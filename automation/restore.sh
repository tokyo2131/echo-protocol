#!/usr/bin/env bash
# Restores from a backup produced by backup-run.sh. Destructive —
# requires an explicit --yes flag or an interactive confirmation.
#
# Usage:
#   sudo ~/scripts/automation/restore.sh <category> <timestamp> [--yes]
#   sudo ~/scripts/automation/restore.sh --list <category>
#
# categories: system-config | postgres | redis | docker-volumes | project-dirs
#
# Examples:
#   sudo restore.sh --list postgres
#   sudo restore.sh postgres 2026-07-24T030000Z
set -euo pipefail
LOG_TAG="restore"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }
die()  { echo "[$(date '+%F %T')] [${LOG_TAG}] ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
ADMIN_USER="${ADMIN_USER:-deploy}"
ADMIN_HOME="/home/${ADMIN_USER}"

usage() { grep '^#' "$0" | sed 's/^# \?//; 1,2d'; exit 1; }

[[ $# -ge 1 ]] || usage

if [[ "$1" == "--list" ]]; then
  CATEGORY="${2:-}"
  [[ -n "$CATEGORY" ]] || die "Usage: restore.sh --list <category>"
  ls -1 "${BACKUP_ROOT}/${CATEGORY}" 2>/dev/null || die "No backups found for category '${CATEGORY}'."
  exit 0
fi

CATEGORY="$1"
TIMESTAMP="${2:-}"
ASSUME_YES=0
[[ "${3:-}" == "--yes" ]] && ASSUME_YES=1
SRC="${BACKUP_ROOT}/${CATEGORY}/${TIMESTAMP}"

[[ -n "$TIMESTAMP" ]] || die "Missing timestamp. See: restore.sh --list ${CATEGORY}"
[[ -d "$SRC" ]] || die "No such backup: ${SRC}"

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "This will overwrite current state from ${SRC}. Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted."
}

case "$CATEGORY" in
  postgres)
    confirm
    for dump in "${SRC}"/*.dump.gz; do
      [[ -e "$dump" ]] || continue
      db=$(basename "$dump" .dump.gz)
      log "Restoring database '${db}' from ${dump}"
      sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${db};"
      sudo -u postgres psql -c "CREATE DATABASE ${db};"
      gunzip -c "$dump" | sudo -u postgres pg_restore -d "$db"
    done
    if [[ -f "${SRC}/globals.sql.gz" ]]; then
      log "Restoring global roles"
      gunzip -c "${SRC}/globals.sql.gz" | sudo -u postgres psql
    fi
    ;;
  redis)
    confirm
    [[ -f "${SRC}/dump.rdb.gz" ]] || die "No dump.rdb.gz in ${SRC}"
    systemctl stop redis-server
    RDB_DIR=$(redis-cli CONFIG GET dir 2>/dev/null | tail -n1 || echo /var/lib/redis)
    gunzip -c "${SRC}/dump.rdb.gz" > "${RDB_DIR}/dump.rdb"
    chown redis:redis "${RDB_DIR}/dump.rdb"
    systemctl start redis-server
    log "Redis restored and service restarted."
    ;;
  docker-volumes)
    confirm
    for tarball in "${SRC}"/*.tar.gz; do
      [[ -e "$tarball" ]] || continue
      vol=$(basename "$tarball" .tar.gz)
      log "Restoring Docker volume '${vol}'"
      docker volume inspect "$vol" &>/dev/null || docker volume create "$vol" >/dev/null
      docker run --rm -v "${vol}:/target" -v "${SRC}:/backup" alpine:3 \
        sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar -xzf /backup/${vol}.tar.gz -C /target"
    done
    ;;
  project-dirs)
    confirm
    for tarball in "${SRC}"/*.tar.gz; do
      [[ -e "$tarball" ]] || continue
      log "Restoring $(basename "$tarball" .tar.gz) into ${ADMIN_HOME}"
      tar -xzf "$tarball" -C "$ADMIN_HOME"
      chown -R "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}/$(basename "$tarball" .tar.gz)"
    done
    ;;
  system-config)
    confirm
    warn "system-config restore extracts over /etc and /var/lib/echo-protocol — review the archive first:"
    warn "  tar -tzf ${SRC}/system-config.tar.gz"
    tar -xzf "${SRC}/system-config.tar.gz" -C /
    log "Restart affected services manually: systemctl restart ssh nginx fail2ban docker"
    ;;
  *)
    die "Unknown category '${CATEGORY}'. Expected: system-config|postgres|redis|docker-volumes|project-dirs"
    ;;
esac

log "Restore of '${CATEGORY}' from ${TIMESTAMP} complete."
