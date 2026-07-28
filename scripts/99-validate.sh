#!/usr/bin/env bash
# Stage 99: post-install validation. Checks every component installed
# by stages 00-16 and reports PASS/FAIL/WARN per item. Safe to re-run
# any time (e.g. after a reboot) to confirm the server is still healthy.
# Non-zero exit if any check fails. See also docs/VALIDATION-CHECKLIST.md
# for the manual (non-scriptable) checks — e.g. "reboot and confirm
# everything comes back".
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
WARN=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; WARN=$((WARN+1)); }

check_cmd() {
  local label="$1" cmd="$2"
  if command -v "$cmd" &>/dev/null; then ok "$label ($("$cmd" --version 2>&1 | head -n1 | tr -d '\n'))"; else bad "$label: '$cmd' not found"; fi
}

check_service() {
  local label="$1" svc="$2"
  if ! systemctl list-unit-files "${svc}.service" &>/dev/null && ! systemctl list-unit-files "${svc}.socket" &>/dev/null; then
    warn "$label: unit not installed"
    return
  fi
  if systemctl is-enabled --quiet "$svc" 2>/dev/null && systemctl is-active --quiet "$svc"; then
    ok "$label: enabled + active"
  elif systemctl is-active --quiet "$svc"; then
    warn "$label: active but not enabled at boot"
  else
    bad "$label: not active"
  fi
}

check_timer() {
  local label="$1" timer="$2"
  if systemctl is-enabled --quiet "$timer" 2>/dev/null; then
    ok "$label: enabled"
  else
    bad "$label: not enabled"
  fi
}

echo "== SSH =="
check_service "sshd" ssh
grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null \
  && ok "Password authentication disabled" || bad "Password authentication not confirmed disabled"
grep -q '^PermitRootLogin no' /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null \
  && ok "Root login disabled" || bad "Root login not confirmed disabled"

echo "== Firewall / intrusion prevention =="
check_cmd "UFW" ufw
ufw status 2>/dev/null | grep -q "Status: active" && ok "UFW active" || bad "UFW not active"
check_service "Fail2Ban" fail2ban
check_service "AppArmor" apparmor
command -v aa-status &>/dev/null && aa-status --enabled &>/dev/null && ok "AppArmor enforcing profiles present" || warn "AppArmor status inconclusive"

echo "== Automatic updates =="
systemctl is-enabled --quiet unattended-upgrades 2>/dev/null && ok "unattended-upgrades enabled" || bad "unattended-upgrades not enabled"

echo "== Languages / runtimes =="
check_cmd "Git" git
check_cmd "Git LFS" git-lfs
check_cmd "Python" python3
check_cmd "Node.js" node
check_cmd "npm" npm
check_cmd "pnpm" pnpm
check_cmd "Yarn" yarn
[[ -x /usr/local/go/bin/go ]] && ok "Go ($(/usr/local/go/bin/go version))" || bad "Go not found at /usr/local/go/bin/go"
check_cmd "Java" java

echo "== Docker =="
check_cmd "Docker" docker
docker compose version &>/dev/null && ok "Docker Compose plugin" || bad "Docker Compose plugin missing"
check_service "Docker" docker

echo "== Databases =="
check_cmd "PostgreSQL client" psql
check_service "PostgreSQL" postgresql
check_cmd "Redis" redis-cli
check_service "Redis" redis-server
check_cmd "SQLite" sqlite3

echo "== Web / TLS =="
check_cmd "Nginx" nginx
check_service "Nginx" nginx
check_cmd "Certbot" certbot
check_timer "Certbot renewal timer" certbot.timer

echo "== Monitoring / logging =="
check_cmd "Glances" glances
check_cmd "htop" htop
check_cmd "btop" btop
grep -q '^Storage=persistent' /etc/systemd/journald.conf.d/persistent.conf 2>/dev/null \
  && ok "journald persistent storage configured" || bad "journald persistent storage not configured"
[[ -f /etc/logrotate.d/echo-protocol ]] && ok "logrotate policy installed" || bad "logrotate policy missing"

echo "== Backups =="
check_timer "backup.timer" backup.timer
check_timer "health-check.timer" health-check.timer
check_timer "maintenance.timer" maintenance.timer
[[ -x "/home/${ADMIN_USER:-deploy}/scripts/automation/backup-run.sh" ]] \
  && ok "backup-run.sh installed" || bad "backup-run.sh not found in ~/scripts/automation"

echo "== Directory structure =="
for d in projects ruflo docker scripts logs backups downloads tmp; do
  [[ -d "/home/${ADMIN_USER:-deploy}/${d}" ]] && ok "~/${d} exists" || bad "~/${d} missing"
done

echo
echo "== Summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed =="
[[ $FAIL -eq 0 ]] || exit 1
