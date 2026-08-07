#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/ and automation/.
# Not meant to be executed directly.

set -euo pipefail

# --- auto-load .env -----------------------------------------------------
# install.sh sources .env itself before invoking a stage as a subprocess,
# so its exported vars are already present by the time this runs there.
# But docs (README.md, docs/MAINTENANCE.md) also document running a
# stage directly — "sudo ./scripts/10-docker.sh" — and without this,
# that path fails on the first require_env call since nothing ever
# sourced .env. Idempotent either way: re-sourcing already-exported vars
# here is harmless.
_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_COMMON_SH_DIR}/../.." && pwd)"
if [[ -f "${_REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${_REPO_ROOT}/.env"
  set +a
fi
unset _COMMON_SH_DIR _REPO_ROOT

# --- logging -----------------------------------------------------------
LOG_DIR="${LOG_DIR:-/var/log/echo-protocol}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/provision.log}"

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

log()  { printf '[%s] [INFO]  %s\n'  "$(_ts)" "$*" | tee -a "$LOG_FILE" ; }
warn() { printf '[%s] [WARN]  %s\n'  "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2 ; }
err()  { printf '[%s] [ERROR] %s\n'  "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2 ; }
die()  { err "$*"; exit 1; }

step() { printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*" | tee -a "$LOG_FILE" ; }

# --- guards --------------------------------------------------------------
require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)."
}

require_env() {
  local var="$1"
  [[ -n "${!var:-}" ]] || die "Required environment variable '${var}' is not set. Copy .env.example to .env and edit it."
}

# --- idempotency helpers -------------------------------------------------
# Marks a provisioning step as done so re-running install.sh is a no-op
# for steps that already succeeded. Steps that are naturally idempotent
# (apt install, systemctl enable, etc.) don't strictly need this, but it
# keeps re-runs fast and makes "what has run" auditable.
MARKER_DIR="${MARKER_DIR:-/var/lib/echo-protocol/markers}"

step_done() {
  local name="$1"
  [[ -f "${MARKER_DIR}/${name}" ]]
}

mark_done() {
  local name="$1"
  mkdir -p "$MARKER_DIR"
  date -u +%Y-%m-%dT%H:%M:%SZ > "${MARKER_DIR}/${name}"
}

skip_if_done() {
  local name="$1"
  if step_done "$name"; then
    log "Skipping '${name}' (already completed on $(cat "${MARKER_DIR}/${name}"))."
    return 0
  fi
  return 1
}

# Ubuntu's needrestart package prompts interactively ("which services
# should be restarted?") on certain installs/upgrades — independent of
# DEBIAN_FRONTEND=noninteractive, which does NOT suppress it. Left
# unset, this hangs any apt operation indefinitely in a non-interactive
# session (confirmed live: install.sh hung here on a real run). 'a'
# means restart automatically without asking. Exported globally here
# since plenty of stages call apt-get directly (upgrade, dist-upgrade,
# remove) rather than only through apt_install below.
export NEEDRESTART_MODE=a

# --- run as the admin user ------------------------------------------------
# `sudo -u` alone does NOT change the working directory — it inherits
# wherever the calling script's cwd is. Confirmed live: install.sh run
# from ~ubuntu/echo-protocol (the pre-existing cloud-init user's home,
# since that's naturally where the repo gets cloned before the admin
# user even exists), and the newly-created admin user has no permission
# to even stat into ubuntu's home directory — every bare `sudo -u
# "$ADMIN_USER"` call failed with "Permission denied", regardless of
# what the actual command was.
#
# The obvious fix, `sudo --chdir`, is itself blocked: sudo >=1.9.13
# (what Ubuntu 24.04 ships) refuses `-D`/`--chdir` unless the sudoers
# policy has an explicit CWD= spec granting it, which the default
# sudoers file doesn't ("sudo: you are not permitted to use the -D
# option with ..." — confirmed live). So instead of asking sudo to
# change directory, let the shell that's already running as the admin
# user cd itself once it's there — that only needs permission on the
# admin user's own home, which they have.
sudo_admin() {
  require_env ADMIN_USER
  sudo -u "$ADMIN_USER" -H bash -c 'cd "$HOME" && exec "$@"' _ "$@"
}

# --- package helpers -------------------------------------------------------
apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update() {
  DEBIAN_FRONTEND=noninteractive apt-get update -y
}

pkg_installed() {
  dpkg -s "$1" &>/dev/null
}

# --- architecture helpers ------------------------------------------------
# This repo targets amd64 (x86_64) and arm64 (e.g. Oracle Cloud's Ampere A1
# "Always Free" shape) — apt packages are multi-arch already, but a few
# stages fetch prebuilt binaries straight from upstream GitHub releases,
# which name their assets per-arch differently. Stages that do so should
# set these once near the top and use them in asset_pattern/URLs instead
# of hardcoding an architecture.
detect_arch() {
  DPKG_ARCH=$(dpkg --print-architecture)   # "amd64" | "arm64"
  case "$DPKG_ARCH" in
    amd64) RUST_TARGET_ARCH="x86_64";  GO_ARCH="amd64"; FASTFETCH_ARCH="amd64" ;;
    arm64) RUST_TARGET_ARCH="aarch64"; GO_ARCH="arm64"; FASTFETCH_ARCH="aarch64" ;;
    *) die "Unsupported architecture '${DPKG_ARCH}' — this repo supports amd64 and arm64 only." ;;
  esac
  export DPKG_ARCH RUST_TARGET_ARCH GO_ARCH FASTFETCH_ARCH
}

# --- OS helpers ------------------------------------------------------
# Primary target is Debian 12 (Bookworm). Ubuntu 24.04 LTS (Noble) is
# supported as a fallback for hosts where Debian isn't offered as a
# platform image (this has been observed for Oracle Cloud's A1.Flex
# shape in some regions/tenancies) — apt/systemd/UFW are the same
# across both, but a handful of things genuinely differ per-distro
# (backports repo naming, unattended-upgrades' security-pocket origin
# match, Docker's per-distro apt repo path). Stages that touch any of
# those should call detect_os and branch on $DISTRO_ID rather than
# hardcoding "debian".
detect_os() {
  . /etc/os-release
  DISTRO_ID="$ID"                 # "debian" | "ubuntu"
  DISTRO_CODENAME="$VERSION_CODENAME"   # "bookworm" | "noble"
  case "$DISTRO_ID" in
    debian|ubuntu) ;;
    *) die "Unsupported distro '${DISTRO_ID}' — this repo supports Debian and Ubuntu only." ;;
  esac
  export DISTRO_ID DISTRO_CODENAME
}

# --- misc --------------------------------------------------------------
confirm_or_die() {
  # Used by destructive automation scripts (restore.sh) when run interactively.
  local prompt="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "${prompt} [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted by user."
}

mkdir -p "$LOG_DIR"
