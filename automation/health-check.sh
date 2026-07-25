#!/usr/bin/env bash
# Automated health check: disk, memory, load, critical services, and
# TLS certificate expiry. Prints a report and, on any WARN/FAIL, posts
# to HEALTH_CHECK_WEBHOOK_URL (Slack/Discord-compatible incoming
# webhook) if configured. Runs every 15 minutes via
# systemd/health-check.timer.
set -euo pipefail
LOG_TAG="health-check"
log() { echo "[$(date '+%F %T')] [${LOG_TAG}] $*"; }

CONF=/etc/echo-protocol/automation.env
[[ -f "$CONF" ]] && { set -a; source "$CONF"; set +a; }

DISK_WARN_PCT="${DISK_WARN_PCT:-80}"
DISK_CRIT_PCT="${DISK_CRIT_PCT:-90}"
MEM_WARN_PCT="${MEM_WARN_PCT:-85}"
CERT_WARN_DAYS="${CERT_WARN_DAYS:-14}"

ISSUES=()
add_issue() { ISSUES+=("$1"); }

# --- disk ---
DISK_PCT=$(df --output=pcent / | tail -n1 | tr -dc '0-9')
if (( DISK_PCT >= DISK_CRIT_PCT )); then
  add_issue "CRITICAL: root filesystem ${DISK_PCT}% full (threshold ${DISK_CRIT_PCT}%)"
elif (( DISK_PCT >= DISK_WARN_PCT )); then
  add_issue "WARNING: root filesystem ${DISK_PCT}% full (threshold ${DISK_WARN_PCT}%)"
fi

# --- memory ---
MEM_PCT=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}')
if (( MEM_PCT >= MEM_WARN_PCT )); then
  add_issue "WARNING: memory usage at ${MEM_PCT}% (threshold ${MEM_WARN_PCT}%)"
fi

# --- load average vs vCPU count ---
CPU_COUNT=$(nproc)
LOAD_1M=$(awk '{print $1}' /proc/loadavg)
LOAD_OK=$(awk -v load="$LOAD_1M" -v cpus="$CPU_COUNT" 'BEGIN { print (load > cpus * 1.5) ? 0 : 1 }')
if [[ "$LOAD_OK" == "0" ]]; then
  add_issue "WARNING: 1m load average ${LOAD_1M} exceeds 1.5x vCPU count (${CPU_COUNT})"
fi

# --- critical services ---
for svc in ssh nginx docker fail2ban ufw; do
  systemctl list-unit-files "${svc}.service" &>/dev/null || continue
  if ! systemctl is-active --quiet "$svc"; then
    add_issue "CRITICAL: service '${svc}' is not active"
  fi
done
for svc in postgresql redis-server; do
  systemctl list-unit-files "${svc}.service" &>/dev/null || continue
  systemctl is-enabled --quiet "$svc" 2>/dev/null || continue
  if ! systemctl is-active --quiet "$svc"; then
    add_issue "CRITICAL: service '${svc}' is not active"
  fi
done

# --- TLS certificate expiry ---
if command -v certbot &>/dev/null; then
  while IFS= read -r domain_dir; do
    domain=$(basename "$domain_dir")
    cert="${domain_dir}/cert.pem"
    [[ -f "$cert" ]] || continue
    expiry_epoch=$(date -d "$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)" +%s)
    days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))
    if (( days_left <= CERT_WARN_DAYS )); then
      add_issue "WARNING: certificate for ${domain} expires in ${days_left} day(s)"
    fi
  done < <(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# --- report ---
log "Disk: ${DISK_PCT}% | Mem: ${MEM_PCT}% | Load(1m): ${LOAD_1M} / ${CPU_COUNT} vCPU"
if [[ ${#ISSUES[@]} -eq 0 ]]; then
  log "OK: no issues detected."
  exit 0
fi

for issue in "${ISSUES[@]}"; do
  log "$issue"
done

if [[ -n "${HEALTH_CHECK_WEBHOOK_URL:-}" ]]; then
  BODY=$(printf '%s\n' "${ISSUES[@]}")
  HOSTNAME_TXT=$(hostname)
  PAYLOAD=$(jq -n --arg text "Health check on ${HOSTNAME_TXT}:\n${BODY}" '{text: $text}')
  curl -fsS -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$HEALTH_CHECK_WEBHOOK_URL" >/dev/null \
    || log "Failed to deliver webhook alert."
fi

exit 1
