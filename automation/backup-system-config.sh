#!/usr/bin/env bash
# Archives the system configuration this repo manages (SSH, firewall,
# Fail2Ban, Nginx, Docker daemon, sysctl, crontabs, systemd units) to
# ${BACKUP_ROOT}/system-config/<timestamp>/ — enough to reconstruct
# host configuration without re-running the full install.
set -euo pipefail
LOG_TAG="$(basename "$0" .sh)"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
TIMESTAMP="${BACKUP_TIMESTAMP:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
DEST="${BACKUP_ROOT}/system-config/${TIMESTAMP}"

install -d -m 750 "$DEST"

PATHS=(
  /etc/ssh/sshd_config.d
  /etc/ufw
  /etc/fail2ban/jail.local
  /etc/nginx
  /etc/docker/daemon.json
  /etc/sysctl.d/99-hardening-performance.conf
  /etc/systemd/journald.conf.d
  /etc/logrotate.d/echo-protocol
  /etc/crontab
  /etc/cron.d
  /var/lib/echo-protocol/markers
  /etc/echo-protocol
)

EXISTING=()
for p in "${PATHS[@]}"; do
  [[ -e "$p" ]] && EXISTING+=("$p")
done

tar -czf "${DEST}/system-config.tar.gz" "${EXISTING[@]}" 2>/dev/null || true
chmod 640 "${DEST}/system-config.tar.gz"
log "System config backup complete: ${DEST}/system-config.tar.gz"
