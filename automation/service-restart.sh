#!/usr/bin/env bash
# Safely restarts a systemd service or a docker-compose service,
# logging before/after status so a bad restart is visible immediately.
#
# Usage:
#   sudo ~/scripts/automation/service-restart.sh systemd nginx
#   sudo ~/scripts/automation/service-restart.sh compose /home/deploy/docker/myapp web
set -euo pipefail
LOG_TAG="service-restart"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
die()  { echo "[$(date '+%F %T')] [${LOG_TAG}] ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ $# -ge 2 ]] || die "Usage: service-restart.sh systemd <unit> | service-restart.sh compose <project-dir> <service>"

MODE="$1"

case "$MODE" in
  systemd)
    UNIT="$2"
    log "Status before restart:"
    systemctl status "$UNIT" --no-pager -l | head -n5 || true
    log "Restarting ${UNIT}"
    systemctl restart "$UNIT"
    sleep 2
    if systemctl is-active --quiet "$UNIT"; then
      log "${UNIT} restarted successfully."
    else
      die "${UNIT} failed to come back up. journalctl -u ${UNIT} -n 50"
    fi
    ;;
  compose)
    PROJECT_DIR="$2"
    SERVICE="${3:-}"
    [[ -d "$PROJECT_DIR" ]] || die "No such directory: ${PROJECT_DIR}"
    cd "$PROJECT_DIR"
    log "Restarting ${SERVICE:-<all services>} in ${PROJECT_DIR}"
    docker compose restart ${SERVICE}
    sleep 2
    docker compose ps
    ;;
  *)
    die "Unknown mode '${MODE}'. Expected 'systemd' or 'compose'."
    ;;
esac
