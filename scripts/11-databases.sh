#!/usr/bin/env bash
# Stage 11: PostgreSQL, Redis, SQLite — installed, secured, and set to
# autostart. These are host-level databases for tooling/local dev; most
# application stacks should instead run Postgres/Redis as Docker
# containers per-project (see docker/docker-compose.example.yml) so
# each project gets an isolated, disposable instance. The host-level
# instances here back shared tooling and anything you deliberately want
# outside a container.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env POSTGRES_APP_DB
require_env POSTGRES_APP_USER
require_env POSTGRES_APP_PASSWORD
require_env REDIS_PASSWORD

step "Install PostgreSQL"
apt_install postgresql postgresql-contrib

PG_VERSION=$(psql --version | grep -oP '\d+' | head -n1)
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"

step "Restrict PostgreSQL to localhost and enforce scram-sha-256 auth"
sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'/" "${PG_CONF_DIR}/postgresql.conf"
sed -i "s/^#\?password_encryption.*/password_encryption = scram-sha-256/" "${PG_CONF_DIR}/postgresql.conf"
# Replace md5/trust local-network auth methods with scram-sha-256
sed -i -E 's/^(local\s+all\s+all\s+)peer/\1scram-sha-256/' "${PG_CONF_DIR}/pg_hba.conf"
sed -i -E 's/^(host\s+all\s+all\s+127\.0\.0\.1\/32\s+)md5/\1scram-sha-256/' "${PG_CONF_DIR}/pg_hba.conf"
sed -i -E 's/^(host\s+all\s+all\s+::1\/128\s+)md5/\1scram-sha-256/' "${PG_CONF_DIR}/pg_hba.conf"

step "Enable and restart PostgreSQL"
systemctl enable postgresql
systemctl restart postgresql

step "Create application database/role (idempotent)"
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_APP_USER}') THEN
    CREATE ROLE ${POSTGRES_APP_USER} LOGIN PASSWORD '${POSTGRES_APP_PASSWORD}';
  ELSE
    ALTER ROLE ${POSTGRES_APP_USER} WITH PASSWORD '${POSTGRES_APP_PASSWORD}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${POSTGRES_APP_DB} OWNER ${POSTGRES_APP_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_APP_DB}')\gexec
SQL

step "Install Redis"
apt_install redis-server

step "Secure Redis: bind to localhost, require password, disable dangerous commands"
REDIS_CONF=/etc/redis/redis.conf
sed -i "s/^bind .*/bind 127.0.0.1 -::1/" "$REDIS_CONF"
# | delimiter, not / — REDIS_PASSWORD is base64-generated and can
# legitimately contain a literal "/", which would otherwise be parsed
# as the end of the sed expression (confirmed live: "sed: -e expression
# #1, char 65: unknown option to `s'" whenever a generated password
# happened to contain one).
sed -i "s|^# requirepass .*|requirepass ${REDIS_PASSWORD}|; s|^requirepass .*|requirepass ${REDIS_PASSWORD}|" "$REDIS_CONF"
grep -q '^requirepass' "$REDIS_CONF" || echo "requirepass ${REDIS_PASSWORD}" >> "$REDIS_CONF"
sed -i "s/^supervised .*/supervised systemd/" "$REDIS_CONF"
# FLUSHALL/FLUSHDB/DEBUG disabled outright. CONFIG is left enabled since
# monitoring exporters (e.g. redis_exporter) rely on `CONFIG GET`.
for cmd in FLUSHALL FLUSHDB DEBUG; do
  grep -q "^rename-command ${cmd} \"\"" "$REDIS_CONF" || echo "rename-command ${cmd} \"\"" >> "$REDIS_CONF"
done

step "Enable and restart Redis"
systemctl enable redis-server
systemctl restart redis-server

step "Install SQLite"
apt_install sqlite3

psql --version | tee -a "$LOG_FILE"
redis-server --version | tee -a "$LOG_FILE"
sqlite3 --version | tee -a "$LOG_FILE"

mark_done "11-databases"
log "Stage 11 complete."
