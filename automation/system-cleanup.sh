#!/usr/bin/env bash
# General host cleanup: apt cache, journal vacuum, stale files under
# ~/tmp and /tmp. Complements docker-cleanup.sh (container-side) and
# backup-run.sh's own retention pruning (backup-side).
set -euo pipefail
LOG_TAG="system-cleanup"
log() { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }
ADMIN_USER="${ADMIN_USER:-deploy}"

log "Cleaning apt cache"
apt-get clean

log "Vacuuming journald logs to 500M / 30 days"
journalctl --vacuum-size=500M
journalctl --vacuum-time=30d

log "Removing files older than 7 days from /tmp and ~${ADMIN_USER}/tmp"
find /tmp -mindepth 1 -mtime +7 -delete 2>/dev/null || true
find "/home/${ADMIN_USER}/tmp" -mindepth 1 -mtime +7 -delete 2>/dev/null || true

log "Removing files older than 30 days from ~${ADMIN_USER}/downloads"
find "/home/${ADMIN_USER}/downloads" -mindepth 1 -mtime +30 -delete 2>/dev/null || true

log "System cleanup complete."
df -h / | tee -a /dev/null
