# Docker

## Install

`scripts/10-docker.sh` installs Docker Engine + Compose plugin from
Docker's official apt repository (not Debian's, which lags and used to
ship a differently-named `docker.io` package). The admin user is added
to the `docker` group so `docker`/`docker compose` work without `sudo`
(needs a fresh login or `newgrp docker` to take effect).

## Daemon configuration

`/etc/docker/daemon.json` (from `config/docker/daemon.json`) sets:

- JSON-file log driver capped at 20 MB × 5 files per container (unbounded
  container logs are a classic way to fill the disk)
- `live-restore: true` — containers keep running if the daemon restarts
  (e.g. during a Docker upgrade)
- `userland-proxy: false` — routes container ports natively via iptables
  instead of a slower per-port proxy process
- `no-new-privileges: true` by default for containers
- A custom default bridge address pool (`172.30.0.0/16`) to avoid
  colliding with common corporate VPN ranges

There's no daemon-wide restart policy (Docker doesn't have one) — set
`restart: unless-stopped` per service in each `docker-compose.yml`, as
`docker/docker-compose.example.yml` does.

## Project layout convention

One directory per project under `~/docker/<project>/`, each with its own
`docker-compose.yml` and `.env` (never committed — see that project's
`.gitignore`). Start from `docker/docker-compose.example.yml`, which
demonstrates:

- App container built locally (`build: .`) *or* pulling a prebuilt image
  via an `IMAGE` env var, so the same compose file works for local dev
  and CI-driven deploys (see `examples/github-actions/deploy.yml`)
- Postgres + Redis as sibling containers with named volumes and
  healthchecks, so `depends_on: condition: service_healthy` actually
  waits for them to be ready, not just started
- Ports published as `127.0.0.1:<port>:<port>` — **not** `<port>:<port>`
  — so only Nginx on the same host can reach them; UFW never sees these
  ports because they're never bound to a public interface

## Fronting a project with Nginx/TLS

`scripts/12-nginx-certbot.sh` renders one vhost per domain from
`config/nginx/reverse-proxy.conf.template`, proxying to
`127.0.0.1:<port>`. To add a new project:

1. Add the domain and port to a new `render_vhost` call in
   `scripts/12-nginx-certbot.sh` (or run the equivalent `sed` manually
   for a one-off), or copy the template by hand into
   `/etc/nginx/sites-available/`.
2. `nginx -t && systemctl reload nginx`
3. `certbot --nginx -d <domain>`

**Streaming/long-lived connections**: the shared template's
`proxy_read_timeout 60s` is fine for ordinary request/response APIs, but
`mcp-claude` (an MCP server using streamable-HTTP, which can hold a
connection open for a server-sent-event stream or a long-running tool
call) may need a longer timeout once it has real tools to call. If you
hit connections dropping mid-call, raise `proxy_read_timeout` for that
vhost specifically rather than for every fronted project — don't change
the shared template for one service's needs.

## Backups

Docker named volumes are backed up whole (tar, via a throwaway `alpine`
container bind-mounting the volume read-only — no need to stop the
service) by `automation/backup-docker-volumes.sh`, part of the daily
`backup-run.sh`. See `docs/BACKUP-RESTORE.md`.

## Cleanup

`automation/docker-cleanup.sh` (run weekly by `maintenance.timer`) prunes
stopped containers, dangling images, unused networks, and build cache
older than 7 days. It never touches named volumes or running containers.
