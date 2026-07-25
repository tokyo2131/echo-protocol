#!/usr/bin/env bash
# Stage 14: monitoring tooling (Glances, plus the htop/btop already
# installed in stage 06) and persistent, rotated logging.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root

step "Install Glances (CPU/mem/disk/net overview + optional web UI)"
apt_install glances

step "Configure persistent journald logging"
install -d /etc/systemd/journald.conf.d
install -m 644 "${ROOT_DIR}/config/journald/persistent.conf" /etc/systemd/journald.conf.d/persistent.conf
systemctl restart systemd-journald

step "Install logrotate policy for provisioning/app logs"
apt_install logrotate
install -m 644 "${ROOT_DIR}/config/logrotate/echo-protocol" /etc/logrotate.d/echo-protocol
logrotate -d /etc/logrotate.d/echo-protocol >/dev/null # dry-run syntax check

log "Monitoring: run 'glances' interactively, or 'glances -w' for the web UI on :61208."
log "Disk/CPU/mem/net are also covered by htop/btop/iotop/iftop/ncdu (stage 06)."
log "automation/health-check.sh (stage 16) turns these into an automated, alerting check."

mark_done "14-monitoring-logging"
log "Stage 14 complete."
