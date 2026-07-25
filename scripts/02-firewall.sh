#!/usr/bin/env bash
# Stage 02: UFW — default-deny, only 22/80/443 exposed.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root

SSH_PORT="${SSH_PORT:-22}"

step "Install UFW"
apt_install ufw

step "Configure default policy: deny incoming, allow outgoing"
ufw default deny incoming
ufw default allow outgoing

step "Allow SSH (${SSH_PORT}/tcp), HTTP (80/tcp), HTTPS (443/tcp)"
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

step "Enable IPv6 support in UFW"
sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw

step "Enable rate limiting on SSH (extra layer on top of Fail2Ban)"
ufw limit "${SSH_PORT}/tcp"

step "Enable UFW"
ufw --force enable
systemctl enable ufw

ufw status verbose | tee -a "$LOG_FILE"

mark_done "02-firewall"
log "Stage 02 complete. Only ${SSH_PORT}/tcp, 80/tcp, 443/tcp are reachable from outside."
