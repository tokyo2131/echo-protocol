#!/usr/bin/env bash
# Updates apt package lists, upgrades installed packages, and removes
# packages/kernels no longer needed. Security updates already land
# automatically via unattended-upgrades (stage 00); this script is for
# the full package set, run manually or on a schedule you control.
set -euo pipefail
LOG_TAG="system-update"
log() { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

log "apt-get update"
apt-get update -y

log "apt-get upgrade"
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "apt-get autoremove --purge"
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y

log "apt-get autoclean"
apt-get autoclean -y

if [[ -f /var/run/reboot-required ]]; then
  log "A reboot is required (kernel or core library update). Schedule one when convenient:"
  log "  cat /var/run/reboot-required.pkgs"
fi

log "System update complete."
