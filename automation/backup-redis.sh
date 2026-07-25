#!/usr/bin/env bash
# Triggers a synchronous Redis save (BGSAVE + wait) and copies the
# resulting RDB snapshot to ${BACKUP_ROOT}/redis/<timestamp>/.
set -euo pipefail
LOG_TAG="$(basename "$0" .sh)"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
TIMESTAMP="${BACKUP_TIMESTAMP:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
DEST="${BACKUP_ROOT}/redis/${TIMESTAMP}"

command -v redis-cli &>/dev/null || { warn "Redis not installed, skipping."; exit 0; }
systemctl is-active --quiet redis-server || { warn "Redis not running, skipping."; exit 0; }

REDIS_AUTH=()
[[ -n "${REDIS_PASSWORD:-}" ]] && REDIS_AUTH=(-a "$REDIS_PASSWORD" --no-auth-warning)

install -d -m 750 "$DEST"

LAST_SAVE_BEFORE=$(redis-cli "${REDIS_AUTH[@]}" LASTSAVE)
redis-cli "${REDIS_AUTH[@]}" BGSAVE >/dev/null
log "BGSAVE triggered, waiting for completion..."
for _ in $(seq 1 60); do
  LAST_SAVE_NOW=$(redis-cli "${REDIS_AUTH[@]}" LASTSAVE)
  [[ "$LAST_SAVE_NOW" != "$LAST_SAVE_BEFORE" ]] && break
  sleep 1
done

RDB_PATH=$(redis-cli "${REDIS_AUTH[@]}" CONFIG GET dir | tail -n1)/$(redis-cli "${REDIS_AUTH[@]}" CONFIG GET dbfilename | tail -n1)
if [[ -f "$RDB_PATH" ]]; then
  gzip -c "$RDB_PATH" > "${DEST}/dump.rdb.gz"
  log "Redis backup complete: ${DEST}/dump.rdb.gz"
else
  warn "Could not locate RDB file at ${RDB_PATH}"
fi
