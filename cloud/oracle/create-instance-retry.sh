#!/usr/bin/env bash
# Creates a Debian 12 (arm64) Ampere A1 Flex instance on Oracle Cloud's
# "Always Free" tier, retrying across availability domains until Oracle
# has capacity. This runs on YOUR machine (or Cloud Shell), not on the
# target server — there is no server yet until this succeeds.
#
# Oracle's free Ampere A1 shape is popular enough that "Out of host
# capacity" is the normal first response, not an error state — retrying
# across ADs and over time is the standard, documented workaround, not a
# hack. This script automates exactly that.
#
# Prerequisites (see docs/ORACLE-FREE-TIER.md):
#   - OCI CLI installed (`bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"`)
#   - `oci setup config` already run once, interactively (generates
#     ~/.oci/config + an API signing key — can't be scripted safely)
#   - cloud/oracle/.env filled in from .env.example
#
# Usage:
#   cp cloud/oracle/.env.example cloud/oracle/.env && vim cloud/oracle/.env
#   ./cloud/oracle/create-instance-retry.sh
#
# On success, prints the instance's public IP — point install.sh's
# ADMIN_SSH_PUBKEY-holding client at it as usual (see README.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG="oracle-create-instance"
log()  { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }
warn() { echo "[$(date '+%F %T')] [${LOG_TAG}] WARN: $*" >&2; }
die()  { echo "[$(date '+%F %T')] [${LOG_TAG}] ERROR: $*" >&2; exit 1; }

[[ -f "${SCRIPT_DIR}/.env" ]] || die "cloud/oracle/.env not found. Run: cp cloud/oracle/.env.example cloud/oracle/.env && vim cloud/oracle/.env"
set -a
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/.env"
set +a

for var in OCI_COMPARTMENT_ID OCI_AVAILABILITY_DOMAINS OCI_SUBNET_ID OCI_IMAGE_ID OCI_SSH_PUBLIC_KEY_FILE; do
  [[ -n "${!var:-}" ]] || die "Required variable '${var}' is not set in cloud/oracle/.env"
done

command -v oci &>/dev/null || die "OCI CLI not found. Install it first — see docs/ORACLE-FREE-TIER.md."
command -v jq &>/dev/null || die "jq not found (apt-get install -y jq / brew install jq)."

OCI_INSTANCE_NAME="${OCI_INSTANCE_NAME:-echo-protocol-server}"
OCI_OCPUS="${OCI_OCPUS:-4}"
OCI_MEMORY_GB="${OCI_MEMORY_GB:-24}"
OCI_BOOT_VOLUME_GB="${OCI_BOOT_VOLUME_GB:-100}"
OCI_RETRY_INTERVAL_SECONDS="${OCI_RETRY_INTERVAL_SECONDS:-60}"
OCI_MAX_ATTEMPTS="${OCI_MAX_ATTEMPTS:-0}"

SSH_KEY_EXPANDED="${OCI_SSH_PUBLIC_KEY_FILE/#\~/$HOME}"
[[ -f "$SSH_KEY_EXPANDED" ]] || die "SSH public key not found at ${SSH_KEY_EXPANDED}"

read -ra ADS <<< "$OCI_AVAILABILITY_DOMAINS"
[[ ${#ADS[@]} -gt 0 ]] || die "OCI_AVAILABILITY_DOMAINS is empty"

log "Target: ${OCI_OCPUS} OCPU / ${OCI_MEMORY_GB}GB RAM / ${OCI_BOOT_VOLUME_GB}GB boot volume, cycling across ${#ADS[@]} AD(s)"

attempt=0
while true; do
  for ad in "${ADS[@]}"; do
    attempt=$((attempt + 1))
    if [[ "$OCI_MAX_ATTEMPTS" -gt 0 && "$attempt" -gt "$OCI_MAX_ATTEMPTS" ]]; then
      die "Reached OCI_MAX_ATTEMPTS (${OCI_MAX_ATTEMPTS}) without success."
    fi
    log "Attempt ${attempt}: launching in ${ad}"

    RESPONSE=$(oci compute instance launch \
      --compartment-id "$OCI_COMPARTMENT_ID" \
      --availability-domain "$ad" \
      --shape "VM.Standard.A1.Flex" \
      --shape-config "{\"ocpus\": ${OCI_OCPUS}, \"memoryInGBs\": ${OCI_MEMORY_GB}}" \
      --display-name "$OCI_INSTANCE_NAME" \
      --image-id "$OCI_IMAGE_ID" \
      --subnet-id "$OCI_SUBNET_ID" \
      --assign-public-ip true \
      --boot-volume-size-in-gbs "$OCI_BOOT_VOLUME_GB" \
      --ssh-authorized-keys-file "$SSH_KEY_EXPANDED" \
      --wait-for-state RUNNING \
      --max-wait-seconds 300 2>&1)
    STATUS=$?

    if [[ $STATUS -eq 0 ]]; then
      INSTANCE_ID=$(echo "$RESPONSE" | jq -r '.data.id // empty')
      [[ -n "$INSTANCE_ID" ]] || die "Launch reported success but no instance id was returned. Raw response:\n${RESPONSE}"
      log "Instance launched: ${INSTANCE_ID}"
      break 2
    fi

    if echo "$RESPONSE" | grep -qiE 'OutOfCapacity|LimitExceeded|Out of host capacity'; then
      warn "${ad}: out of capacity, will retry"
    else
      die "Launch failed with an unexpected error (not a capacity issue) — fix and re-run:\n${RESPONSE}"
    fi
  done
  log "All availability domains exhausted this pass; sleeping ${OCI_RETRY_INTERVAL_SECONDS}s before retrying"
  sleep "$OCI_RETRY_INTERVAL_SECONDS"
done

log "Fetching public IP..."
PUBLIC_IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" --compartment-id "$OCI_COMPARTMENT_ID" \
  | jq -r '.data[0]."public-ip"')

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "null" ]]; then
  warn "Instance is running but no public IP found yet — check the OCI console, or re-run:"
  warn "  oci compute instance list-vnics --instance-id ${INSTANCE_ID} --compartment-id ${OCI_COMPARTMENT_ID}"
else
  log "Instance ${OCI_INSTANCE_NAME} is running at ${PUBLIC_IP}"
  log "Next: ssh into it, clone this repo, cp .env.example .env, fill it in, and run sudo ./install.sh"
  log "  (see README.md 'Quick start' — same steps regardless of which cloud provider gave you the box)"
fi
