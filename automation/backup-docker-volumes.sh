#!/usr/bin/env bash
# Archives every named Docker volume to ${BACKUP_ROOT}/docker-volumes/<timestamp>/
# using a throwaway alpine container that bind-mounts the volume read-only,
# so running containers are never stopped for the backup.
set -euo pipefail
LOG_TAG="$(basename "$0" .sh)"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
TIMESTAMP="${BACKUP_TIMESTAMP:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
DEST="${BACKUP_ROOT}/docker-volumes/${TIMESTAMP}"

command -v docker &>/dev/null || { warn "Docker not installed, skipping."; exit 0; }

VOLUMES=$(docker volume ls -q)
if [[ -z "$VOLUMES" ]]; then
  log "No Docker volumes to back up."
  exit 0
fi

install -d -m 750 "$DEST"
for vol in $VOLUMES; do
  log "  -> ${vol}"
  docker run --rm \
    -v "${vol}:/source:ro" \
    -v "${DEST}:/backup" \
    alpine:3 \
    tar -czf "/backup/${vol}.tar.gz" -C /source . 2>/dev/null || warn "Failed to archive volume ${vol}"
done

chmod -R 640 "${DEST}"/* 2>/dev/null || true
log "Docker volume backup complete: ${DEST}"
