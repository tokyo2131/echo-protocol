#!/usr/bin/env bash
# Stage 00: OS update, unattended-upgrades, admin user, base directory tree.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER
require_env ADMIN_SSH_PUBKEY
detect_os
log "Distro: ${DISTRO_ID} ${DISTRO_CODENAME}"

step "Full system update"
apt_update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
apt_install ca-certificates gnupg lsb-release

step "Configure automatic security updates (unattended-upgrades)"
apt_install unattended-upgrades apt-listchanges
# Clean up the old filename from before this was fixed — APT's conf.d
# parser silently ignores unrecognized extensions like ".local", so it
# was never actually being read.
rm -f /etc/apt/apt.conf.d/50unattended-upgrades.local
if [[ "$DISTRO_ID" == "ubuntu" ]]; then
  # Ubuntu's security pocket sets Origin: Ubuntu with no Debian-style
  # Label field — "${distro_id}:${distro_codename}-security" is the
  # standard pattern Ubuntu's own default config ships with, and
  # unattended-upgrades resolves both placeholders itself from
  # /etc/os-release, so this is portable across Ubuntu releases as-is.
  cat >/etc/apt/apt.conf.d/51unattended-upgrades-echo-protocol <<'EOF'
// Managed by echo-protocol scripts/00-bootstrap.sh
Unattended-Upgrade::Origins-Pattern {
        "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF
else
  cat >/etc/apt/apt.conf.d/51unattended-upgrades-echo-protocol <<'EOF'
// Managed by echo-protocol scripts/00-bootstrap.sh
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF
fi
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

step "Create administrator account (${ADMIN_USER})"
if id "$ADMIN_USER" &>/dev/null; then
  log "User ${ADMIN_USER} already exists, skipping creation."
else
  adduser --disabled-password --gecos "" "$ADMIN_USER"
  usermod -aG sudo "$ADMIN_USER"
  log "Created ${ADMIN_USER} with sudo group membership."
fi

step "Install admin SSH key"
ADMIN_HOME="/home/${ADMIN_USER}"
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "${ADMIN_HOME}/.ssh"
AUTH_KEYS="${ADMIN_HOME}/.ssh/authorized_keys"
touch "$AUTH_KEYS"
if ! grep -qF "$ADMIN_SSH_PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
  echo "$ADMIN_SSH_PUBKEY" >> "$AUTH_KEYS"
fi
chmod 600 "$AUTH_KEYS"
chown "$ADMIN_USER:$ADMIN_USER" "$AUTH_KEYS"

step "Lock root account to SSH-key-only / disable password login"
passwd -l root || true

step "Passwordless sudo for routine automation is intentionally NOT configured"
log "The ${ADMIN_USER} account uses standard sudo (password prompt on the console);"
log "SSH access is key-only per scripts/01-ssh-hardening.sh."

step "Create standard directory structure"
for d in projects ruflo docker scripts logs backups downloads tmp; do
  install -d -m 750 -o "$ADMIN_USER" -g "$ADMIN_USER" "${ADMIN_HOME}/${d}"
done
log "Created: ${ADMIN_HOME}/{projects,ruflo,docker,scripts,logs,backups,downloads,tmp}"

mark_done "00-bootstrap"
log "Stage 00 complete."
