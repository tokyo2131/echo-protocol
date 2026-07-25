#!/usr/bin/env bash
# Orchestrates a full backup run: system config, PostgreSQL, Redis,
# Docker volumes, and project directories, all under one shared
# timestamp, then prunes local backups older than BACKUP_RETENTION_DAYS
# and (optionally) syncs the run offsite via rclone.
#
# Installed by scripts/16-automation-cron.sh and run daily by
# systemd/backup.timer. Run manually with:
#   sudo ~/scripts/automation/backup-run.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG="backup-run"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }
die()  { echo "[$(date '+%F %T')] [${LOG_TAG}] ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
export BACKUP_TIMESTAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"

install -d -m 750 "$BACKUP_ROOT"
log "Starting backup run ${BACKUP_TIMESTAMP} -> ${BACKUP_ROOT}"

FAILURES=0
for script in backup-system-config.sh backup-postgres.sh backup-redis.sh backup-docker-volumes.sh backup-project-dirs.sh; do
  log "Running ${script}"
  if ! bash "${SCRIPT_DIR}/${script}"; then
    warn "${script} failed"
    FAILURES=$((FAILURES + 1))
  fi
done

step_prune() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime "+${BACKUP_RETENTION_DAYS}" -print -exec rm -rf {} \; \
    | sed 's/^/  pruned: /'
}

log "Pruning backups older than ${BACKUP_RETENTION_DAYS} days"
for category in system-config postgres redis docker-volumes project-dirs; do
  step_prune "${BACKUP_ROOT}/${category}"
done

if [[ -n "${BACKUP_OFFSITE_RCLONE_REMOTE:-}" ]] && command -v rclone &>/dev/null; then
  log "Syncing ${BACKUP_ROOT} -> ${BACKUP_OFFSITE_RCLONE_REMOTE}"
  rclone sync "$BACKUP_ROOT" "$BACKUP_OFFSITE_RCLONE_REMOTE" --log-level INFO || warn "Offsite sync failed"
fi

if [[ $FAILURES -gt 0 ]]; then
  die "Backup run ${BACKUP_TIMESTAMP} completed with ${FAILURES} failing step(s). See above."
fi
log "Backup run ${BACKUP_TIMESTAMP} completed successfully."
