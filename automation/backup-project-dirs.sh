#!/usr/bin/env bash
# Archives ~/projects, ~/ruflo, and ~/docker (excluding heavy,
# regenerable directories) to ${BACKUP_ROOT}/project-dirs/<timestamp>/.
set -euo pipefail
LOG_TAG="$(basename "$0" .sh)"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

ADMIN_USER="${ADMIN_USER:-deploy}"
ADMIN_HOME="/home/${ADMIN_USER}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
TIMESTAMP="${BACKUP_TIMESTAMP:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
DEST="${BACKUP_ROOT}/project-dirs/${TIMESTAMP}"

install -d -m 750 "$DEST"

for dir in projects ruflo docker; do
  src="${ADMIN_HOME}/${dir}"
  [[ -d "$src" ]] || continue
  log "  -> ${dir}"
  tar --exclude='node_modules' --exclude='.venv' --exclude='__pycache__' \
      --exclude='dist' --exclude='.next' --exclude='target' \
      -czf "${DEST}/${dir}.tar.gz" -C "$ADMIN_HOME" "$dir"
done

chmod -R 640 "${DEST}"/* 2>/dev/null || true
log "Project directory backup complete: ${DEST}"
