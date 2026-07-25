#!/usr/bin/env bash
#
# Master orchestrator for provisioning a production-ready Debian 12
# (Bookworm, x86_64) server. Run this as root on a fresh droplet:
#
#   cp .env.example .env && vim .env
#   sudo ./install.sh
#
# Each stage lives in scripts/NN-*.sh, is idempotent (safe to re-run),
# and logs to /var/log/echo-protocol/provision.log. Re-running install.sh
# after a failure resumes; completed stages are skipped via markers in
# /var/lib/echo-protocol/markers (see scripts/lib/common.sh).
#
# Run a single stage directly if you only need to redo one piece:
#   sudo ./scripts/10-docker.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/scripts/lib/common.sh"

require_root

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
else
  die ".env not found. Run: cp .env.example .env && vim .env"
fi

STAGES=(
  00-bootstrap.sh
  01-ssh-hardening.sh
  02-firewall.sh
  03-fail2ban.sh
  04-apparmor.sh
  05-kernel-hardening.sh
  06-core-utilities.sh
  07-python.sh
  08-node.sh
  09-go-rust-java.sh
  10-docker.sh
  11-databases.sh
  12-nginx-certbot.sh
  13-media-ai-tools.sh
  14-monitoring-logging.sh
  15-git-config.sh
  16-automation-cron.sh
  99-validate.sh
)

log "Starting provisioning run. Stages: ${#STAGES[@]}"
for stage in "${STAGES[@]}"; do
  step "Stage: ${stage}"
  bash "${ROOT_DIR}/scripts/${stage}"
done

step "Provisioning complete."
log "Review /var/log/echo-protocol/provision.log and docs/VALIDATION-CHECKLIST.md for a manual sanity pass."
