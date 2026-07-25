#!/usr/bin/env bash
# Stage 04: AppArmor — mandatory access control, enforcing mode for
# available profiles (Debian 12 ships AppArmor enabled by default;
# this stage makes sure it's installed, running, and profiles enforced).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root

step "Install AppArmor and utilities"
apt_install apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra

step "Enable AppArmor service"
systemctl enable apparmor
systemctl start apparmor

step "Switch all complain-mode profiles to enforce"
if command -v aa-enforce &>/dev/null; then
  # aa-enforce on the profiles directory enforces every shipped profile;
  # profiles for software not installed are simply inapplicable.
  aa-enforce /etc/apparmor.d/* 2>/dev/null || true
fi

step "AppArmor status"
apparmor_status | tee -a "$LOG_FILE" || true

mark_done "04-apparmor"
log "Stage 04 complete."
