#!/usr/bin/env bash
# Reclaims disk space from stopped containers, dangling images/networks,
# and build cache. Never touches named volumes (backups own their
# lifecycle — see backup-run.sh / restore.sh) or running containers.
set -euo pipefail
LOG_TAG="docker-cleanup"
log() { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }

command -v docker &>/dev/null || { echo "Docker not installed." >&2; exit 0; }

log "Disk usage before cleanup:"
docker system df

log "Pruning stopped containers"
docker container prune -f

log "Pruning dangling images"
docker image prune -f

log "Pruning unused networks"
docker network prune -f

log "Pruning build cache older than 168h (7d)"
docker builder prune -f --filter "until=168h"

log "Disk usage after cleanup:"
docker system df
