#!/usr/bin/env bash
# Stage 01: OpenSSH hardening — Ed25519-only host keys, key-only auth,
# restricted ciphers/MACs/KEX, rate limiting, idle timeout, logging.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root

SSH_PORT="${SSH_PORT:-22}"

step "Install OpenSSH server"
apt_install openssh-server

step "Regenerate host keys as Ed25519-only (removes weaker RSA/ECDSA/DSA host keys)"
rm -f /etc/ssh/ssh_host_rsa_key* /etc/ssh/ssh_host_ecdsa_key* /etc/ssh/ssh_host_dsa_key*
if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
fi

step "Install hardened sshd_config.d drop-in"
install -d /etc/ssh/sshd_config.d
install -m 600 "${ROOT_DIR}/config/ssh/sshd_hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf

# Ensure only the Ed25519 host key is offered.
if ! grep -q '^HostKey /etc/ssh/ssh_host_ed25519_key$' /etc/ssh/sshd_config.d/99-hardening.conf; then
  {
    echo ""
    echo "HostKey /etc/ssh/ssh_host_ed25519_key"
  } >> /etc/ssh/sshd_config.d/99-hardening.conf
fi

if [[ "$SSH_PORT" != "22" ]]; then
  echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config.d/99-hardening.conf
  log "SSH port overridden to ${SSH_PORT} — remember to update config/ufw rules and .env before opening a new session."
fi

step "Validate sshd configuration"
# /run/sshd is normally created by systemd when the ssh service starts
# (via the unit's RuntimeDirectory=), but we're checking config syntax
# before ever starting it under our control — without this, `sshd -t`
# fails on a fresh instance with "Missing privilege separation
# directory: /run/sshd" and, under set -e, silently kills the rest of
# this install.
install -d -m 0755 /run/sshd
sshd -t

step "Enable and restart sshd"
systemctl enable ssh
systemctl restart ssh

warn "This stage disables password auth and root login. Confirm you can open a NEW ssh session"
warn "authenticating as the admin user with its key BEFORE closing your current session."

mark_done "01-ssh-hardening"
log "Stage 01 complete."
