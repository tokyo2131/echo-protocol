#!/usr/bin/env bash
# Quick system information banner: fastfetch (if installed) plus a
# summary of disk, memory, service, and backup state. Useful on login
# or via `ssh host system-info.sh`.
set -euo pipefail

command -v fastfetch &>/dev/null && fastfetch

echo
echo "== Disk =="
df -h / /home 2>/dev/null

echo
echo "== Memory =="
free -h

echo
echo "== Load =="
uptime

echo
echo "== Key services =="
for svc in ssh ufw fail2ban docker nginx postgresql redis-server; do
  systemctl list-unit-files "${svc}.service" &>/dev/null || continue
  state=$(systemctl is-active "$svc" 2>/dev/null || echo unknown)
  printf '  %-15s %s\n' "$svc" "$state"
done

echo
echo "== Docker =="
if command -v docker &>/dev/null; then
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "  (docker daemon not reachable)"
fi

echo
echo "== Most recent backup run =="
CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/echo-protocol}"
if [[ -d "${BACKUP_ROOT}/system-config" ]]; then
  ls -1t "${BACKUP_ROOT}/system-config" | head -n1
else
  echo "  (no backups yet)"
fi
