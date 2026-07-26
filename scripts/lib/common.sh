#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/ and automation/.
# Not meant to be executed directly.

set -euo pipefail

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
