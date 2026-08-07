#!/usr/bin/env bash
# Stage 12: Nginx reverse proxy + Certbot/Let's Encrypt, with vhosts
# scaffolded for PRIMARY_DOMAIN, RUFLO_DOMAIN, and MCP_CLAUDE_DOMAIN.
# Certificate issuance is best-effort: if DNS doesn't yet point at this
# server (or the domain is still a placeholder), the rendered vhost is
# plain HTTP and stays that way — see
# config/nginx/reverse-proxy.conf.template for why it's deliberately
# not pre-written with a listen-443 block. Re-run this script (it's
# idempotent) once DNS is live to pick up real certificates.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env PRIMARY_DOMAIN
require_env CERTBOT_EMAIL

step "Install Nginx and Certbot"
apt_install nginx certbot python3-certbot-nginx

step "Install hardening snippet"
install -m 644 "${ROOT_DIR}/config/nginx/hardening.conf" /etc/nginx/conf.d/00-hardening.conf
install -d -m 755 /var/www/certbot

# Remove the stock default site so it doesn't shadow our vhosts.
rm -f /etc/nginx/sites-enabled/default

render_vhost() {
  local name="$1" domain="$2" port="$3"
  local out="/etc/nginx/sites-available/${name}.conf"
  sed -e "s/__NAME__/${name}/g" -e "s/__DOMAIN__/${domain}/g" -e "s/__UPSTREAM_PORT__/${port}/g" \
    "${ROOT_DIR}/config/nginx/reverse-proxy.conf.template" > "$out"
  ln -sf "$out" "/etc/nginx/sites-enabled/${name}.conf"
  log "Rendered vhost ${name} -> ${domain} (upstream 127.0.0.1:${port})"
}

step "Render vhosts"
render_vhost "app" "${PRIMARY_DOMAIN}" "3000"
render_vhost "ruflo" "${RUFLO_DOMAIN:-ruflo.${PRIMARY_DOMAIN}}" "3001"
render_vhost "mcp-claude" "${MCP_CLAUDE_DOMAIN:-mcp-claude.${PRIMARY_DOMAIN}}" "8000"

step "Validate and reload Nginx"
nginx -t
systemctl enable nginx
systemctl restart nginx

issue_cert() {
  local domain="$1"
  if [[ -d "/etc/letsencrypt/live/${domain}" ]]; then
    log "Certificate for ${domain} already exists."
    return
  fi
  log "Attempting to issue a Let's Encrypt certificate for ${domain}..."
  if certbot --nginx --non-interactive --agree-tos -m "$CERTBOT_EMAIL" -d "$domain" --redirect; then
    log "Certificate issued for ${domain}."
  else
    warn "Certificate issuance for ${domain} failed (DNS likely not pointing here yet)."
    warn "Re-run: certbot --nginx -d ${domain}   once DNS is live."
  fi
}

step "Issue TLS certificates (best-effort)"
issue_cert "${PRIMARY_DOMAIN}"
issue_cert "${RUFLO_DOMAIN:-ruflo.${PRIMARY_DOMAIN}}"
issue_cert "${MCP_CLAUDE_DOMAIN:-mcp-claude.${PRIMARY_DOMAIN}}"

step "Confirm Certbot auto-renewal timer is enabled"
systemctl enable --now certbot.timer
systemctl list-timers certbot.timer | tee -a "$LOG_FILE"

mark_done "12-nginx-certbot"
log "Stage 12 complete."
