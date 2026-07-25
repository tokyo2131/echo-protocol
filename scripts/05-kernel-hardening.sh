#!/usr/bin/env bash
# Stage 05: sysctl hardening + performance tuning, and swap configuration.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root

step "Install hardening/performance sysctl profile"
install -m 644 "${ROOT_DIR}/config/sysctl/99-hardening-performance.conf" \
  /etc/sysctl.d/99-hardening-performance.conf
sysctl --system

step "Configure swap (4G swapfile, low swappiness — RAM-heavy workload prefers page cache)"
SWAP_FILE=/swapfile
SWAP_SIZE_GB=4
if swapon --show=NAME --noheadings | grep -q "^${SWAP_FILE}$"; then
  log "Swap already active on ${SWAP_FILE}, skipping."
elif [[ -f "$SWAP_FILE" ]]; then
  log "${SWAP_FILE} exists but is not active; enabling."
  chmod 600 "$SWAP_FILE"
  swapon "$SWAP_FILE"
else
  fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((SWAP_SIZE_GB * 1024))
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
  swapon "$SWAP_FILE"
fi
if ! grep -q "^${SWAP_FILE} " /etc/fstab 2>/dev/null; then
  echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
fi

step "Set I/O scheduler hint for NVMe (none/mq-deadline are appropriate; NVMe defaults to 'none' already)"
for dev in /sys/block/nvme*n1/queue/scheduler /sys/block/sda/queue/scheduler; do
  [[ -e "$dev" ]] || continue
  log "Scheduler for $(dirname "$(dirname "$dev")"): $(cat "$dev")"
done

mark_done "05-kernel-hardening"
log "Stage 05 complete."
