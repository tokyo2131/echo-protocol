# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`echo-protocol` is infrastructure-as-code for provisioning a Debian 12
(Bookworm) server — it does not contain an application. Running
`install.sh` against a fresh droplet turns it into a hardened host ready
for Docker workloads, PostgreSQL/Redis, an Nginx/Certbot reverse proxy,
and automated backups/monitoring. There is no build step, no test
suite, and no runtime dependency graph in the usual sense — the
"product" is the set of shell scripts, config files, and systemd units
themselves, applied idempotently to a live host over SSH.

Claude Code sessions working in this repo cannot execute these scripts
against a real server (no SSH/DigitalOcean credentials in typical
sessions) — treat changes here as code review + static reasoning, not
something to verify by running `install.sh` end-to-end, unless a real
target host and credentials are explicitly available in the session.

## Commands

```
# Syntax-check a script without running it
bash -n scripts/10-docker.sh

# Lint (if shellcheck is available in the environment)
shellcheck scripts/*.sh scripts/lib/*.sh automation/*.sh

# Run the full provisioning pipeline (root, on the target host, after
# cp .env.example .env && editing it)
sudo ./install.sh

# Run a single stage (idempotent — safe to re-run)
sudo ./scripts/10-docker.sh

# Post-install verification (safe to re-run any time, e.g. after reboot)
sudo ./scripts/99-validate.sh

# Run one automation task manually (on the target host, after stage 16)
sudo ~/scripts/automation/backup-run.sh
sudo ~/scripts/automation/health-check.sh
```

There's no `npm test`/`make`/CI config in this repo — correctness is
established by `scripts/99-validate.sh` (checks the result of
provisioning) and the manual checklist in
`docs/VALIDATION-CHECKLIST.md`, run against a real host.

## Architecture

Full detail lives in `docs/ARCHITECTURE.md` and `docs/DIRECTORY-STRUCTURE.md`
— read those before making non-trivial changes. The short version:

- **`install.sh`** sources `.env`, then runs `scripts/00-bootstrap.sh`
  through `scripts/99-validate.sh` in numeric order. Each stage is a
  standalone, idempotent, `set -euo pipefail` script that can also be
  run directly (`sudo ./scripts/NN-name.sh`) to redo just that piece.
- **`scripts/lib/common.sh`** is sourced by every `scripts/*.sh` stage
  (not by `automation/*.sh` — see below) and provides `log`/`warn`/
  `err`/`die`, `require_root`, `require_env`, and marker-file helpers
  (`mark_done`/`skip_if_done`) written to `/var/lib/echo-protocol/markers/`.
- **`config/`** holds static config files installed verbatim (or with a
  handful of `sed` placeholder substitutions, e.g. Nginx vhost
  templates) by the corresponding stage script. If you're changing
  behavior, the actual file that lands on the server is almost always
  in `config/`, not inlined in the stage script — check there first.
- **`automation/*.sh`** are deliberately *not* wired to
  `scripts/lib/common.sh`. They get copied standalone to
  `~<admin>/scripts/automation/` on the target host by
  `scripts/16-automation-cron.sh` and must keep working independent of
  whether this repo checkout still exists on disk — each defines its
  own minimal inline `log`/`warn`/`die` and reads shared config from
  `/etc/echo-protocol/automation.env` (root-only, generated from `.env`
  at provisioning time) rather than sourcing anything from this repo.
  Keep that independence when editing them — don't add a `source
  ../scripts/lib/common.sh` line.
- **`systemd/*.service` / `*.timer`** contain a literal
  `__ADMIN_USER__` placeholder, substituted by `scripts/16-automation-cron.sh`
  at install time (not a systemd template unit — plain `sed`).
- **Two separate SSH identities** exist and are easy to conflate: the
  key in `ADMIN_SSH_PUBKEY` (`.env`) is for logging *into* the server
  (installed by stage 00); the key at `~<admin>/.ssh/id_ed25519_git`
  is generated *on* the server by stage 15 for outbound git auth *to*
  GitHub/GitLab. See `docs/SSH.md` / `docs/GIT.md`.
- **Database placement**: stage 11 installs PostgreSQL/Redis/SQLite
  directly on the host (`listen_addresses = 'localhost'`, password-only
  auth) for shared tooling. The intended pattern for actual application
  data is a per-project Postgres/Redis pair as sibling Docker containers
  (`docker/docker-compose.example.yml`), not the host-level instances —
  don't assume an app should connect to the host Postgres unless that's
  explicitly what's being built.
- **Architecture**: every stage runs on amd64 or arm64. Stages that fetch
  prebuilt binaries from upstream GitHub releases instead of apt
  (`scripts/06-core-utilities.sh` for eza/zoxide/fastfetch,
  `scripts/09-go-rust-java.sh` for Go) must call `detect_arch`
  (`scripts/lib/common.sh`) and use `$RUST_TARGET_ARCH`/`$GO_ARCH`/
  `$FASTFETCH_ARCH`/`$DPKG_ARCH` in the asset pattern/URL rather than
  hardcoding `x86_64`/`amd64` — this is what lets `install.sh` run
  unmodified on Oracle Cloud's free arm64 Ampere A1 tier
  (`docs/ORACLE-FREE-TIER.md`, `cloud/oracle/`).
- **Nginx vhosts** are rendered from a single template
  (`config/nginx/reverse-proxy.conf.template`) via placeholder
  substitution in `scripts/12-nginx-certbot.sh`'s `render_vhost`
  function — adding a new proxied domain means adding a
  `render_vhost` call there (or rendering the template manually), not
  writing a new vhost file from scratch.

## Conventions to follow when editing

- Every `scripts/*.sh` stage: `set -euo pipefail`, source
  `scripts/lib/common.sh` via the `ROOT_DIR="$(cd "$(dirname
  "${BASH_SOURCE[0]}")/.." && pwd)"` pattern (works whether invoked via
  `install.sh` or directly), `require_root`, `require_env` for any
  `.env` variable it depends on, end with `mark_done "NN-name"`.
- Every `automation/*.sh` script: `set -euo pipefail`, its own inline
  `log`/`warn`/`die`, source `/etc/echo-protocol/automation.env` if
  present, provide sane fallback defaults for every var it reads (these
  run unattended via systemd timers — a missing/stale config file
  should degrade, not crash silently in a way nobody sees).
- Secrets go in `.env` (gitignored) or the generated
  `/etc/echo-protocol/automation.env` (root-only, `600`) — never
  hardcoded in a script or committed to `config/`.
- New apt packages: prefer Debian's own repos; only reach for an
  upstream GitHub release / vendor repo (as `scripts/06-core-utilities.sh`
  does for `eza`/`zoxide`/`fastfetch`, or `scripts/10-docker.sh` does for
  Docker itself) when Bookworm genuinely doesn't ship it — note that
  choice in a comment when it's not obvious why.
- Reverse-proxied services bind to `127.0.0.1:<port>`, never
  `0.0.0.0:<port>` — UFW only ever opens 22/80/443, so anything a
  container publishes on all interfaces is reachable from the internet
  regardless of what UFW says.
