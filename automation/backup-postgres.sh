#!/usr/bin/env bash
# Dumps every user database (schema+data, custom format) to
# ${BACKUP_ROOT}/postgres/<timestamp>/. Called by backup-run.sh, or run
# standalone: sudo ~/scripts/automation/backup-postgres.sh
set -euo pipefail
LOG_TAG="$(basename "$0" .sh)"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }
die()  { echo "[$(date '+%F %T')] [${LOG_TAG}] ERROR: $*" >&2; exit 1; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
TIMESTAMP="${BACKUP_TIMESTAMP:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
DEST="${BACKUP_ROOT}/postgres/${TIMESTAMP}"

command -v pg_dump &>/dev/null || { warn "PostgreSQL not installed, skipping."; exit 0; }
systemctl is-active --quiet postgresql || { warn "PostgreSQL not running, skipping."; exit 0; }

install -d -m 750 "$DEST"
log "Dumping all databases to ${DEST}"

DBS=$(sudo -u postgres psql -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;")
for db in $DBS; do
  log "  -> ${db}"
  sudo -u postgres pg_dump -Fc "$db" | gzip > "${DEST}/${db}.dump.gz"
done

# Globals (roles, tablespaces) aren't included in per-db dumps.
sudo -u postgres pg_dumpall --globals-only | gzip > "${DEST}/globals.sql.gz"

chown -R root:root "$DEST"
chmod -R 640 "${DEST}"/*
log "PostgreSQL backup complete: ${DEST}"
