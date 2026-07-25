#!/usr/bin/env bash
# Stage 03: Fail2Ban — bans repeat authentication offenders via UFW.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root

step "Install Fail2Ban"
apt_install fail2ban

step "Install jail configuration"
install -m 644 "${ROOT_DIR}/config/fail2ban/jail.local" /etc/fail2ban/jail.local

step "Enable and (re)start Fail2Ban"
systemctl enable fail2ban
systemctl restart fail2ban

sleep 2
fail2ban-client status | tee -a "$LOG_FILE"

mark_done "03-fail2ban"
log "Stage 03 complete."
