# Database Administration

## Two places databases can live

- **Host-level** (`scripts/11-databases.sh`): PostgreSQL, Redis, SQLite
  installed directly on the server, for shared tooling or anything you
  deliberately want outside a container.
- **Per-project containers** (`docker/docker-compose.example.yml`): the
  default pattern for actual application databases — isolated,
  disposable, backed up as Docker volumes (`docs/DOCKER.md`).

This document covers the host-level instances.

## PostgreSQL

- Config: `/etc/postgresql/<version>/main/`
- `listen_addresses = 'localhost'` — not reachable off-host; connect via
  SSH tunnel or from `127.0.0.1` only. Containers that need it must use
  `network_mode: host` or `extra_hosts`/`host.docker.internal` — the
  more common pattern is to just run Postgres as a sibling container per
  project instead (see `docs/DOCKER.md`).
- `password_encryption = scram-sha-256`, and `pg_hba.conf`'s `local`/
  `host 127.0.0.1`/`host ::1` entries are rewritten from
  `peer`/`md5` to `scram-sha-256` — stronger password hashing, no
  plaintext-equivalent MD5.
- An application role/database (`POSTGRES_APP_USER`/`POSTGRES_APP_DB`
  from `.env`) is created idempotently on every run — safe to change the
  password in `.env` and re-run stage 11 to rotate it.

Common admin tasks:

```
sudo -u postgres psql                       # interactive shell
sudo -u postgres psql -c "\l"                # list databases
sudo -u postgres psql -c "\du"               # list roles
sudo -u postgres psql -d <db> -c "\dt"       # list tables in a db
```

## Redis

- Config: `/etc/redis/redis.conf`
- `bind 127.0.0.1 -::1` — localhost only
- `requirepass` set from `.env`'s `REDIS_PASSWORD`
- `FLUSHALL`/`FLUSHDB`/`DEBUG` renamed to `""` (disabled) to prevent
  accidental or malicious full-database wipes from a compromised client;
  `CONFIG` is deliberately left enabled since monitoring exporters (e.g.
  `redis_exporter`) rely on `CONFIG GET`.
- `supervised systemd` — Redis notifies systemd on startup instead of
  systemd guessing based on the forked PID.

```
redis-cli -a "$REDIS_PASSWORD" ping
redis-cli -a "$REDIS_PASSWORD" info server
```

## SQLite

No daemon, no auth model — `sqlite3` is just installed as a CLI for
ad-hoc inspection of `.sqlite`/`.db` files used by apps/scripts. Each
application owns its own SQLite file's location and permissions.

## Backups / restores

See `docs/BACKUP-RESTORE.md` — `automation/backup-postgres.sh` dumps
every non-template database individually (`pg_dump -Fc`, custom format)
plus a `pg_dumpall --globals-only` for roles; `automation/backup-redis.sh`
triggers a synchronous `BGSAVE` and copies the resulting RDB file.
