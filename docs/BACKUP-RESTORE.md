# Backup & Restore

## What's backed up, and how often

`systemd/backup.timer` runs `automation/backup-run.sh` daily at 03:00
server time (±10 min jitter), which in turn runs, under one shared
timestamp:

| Script | Covers |
|---|---|
| `backup-system-config.sh` | `/etc/ssh`, `/etc/ufw`, `/etc/fail2ban/jail.local`, `/etc/nginx`, `/etc/docker/daemon.json`, sysctl profile, journald config, logrotate policy, crontabs, `/etc/echo-protocol`, provisioning markers |
| `backup-postgres.sh` | Every non-template database, individually (`pg_dump -Fc`), plus `pg_dumpall --globals-only` for roles |
| `backup-redis.sh` | Synchronous `BGSAVE` + copy of the resulting RDB snapshot |
| `backup-docker-volumes.sh` | Every named Docker volume, tarred via a throwaway `alpine` container (running services are never stopped) |
| `backup-project-dirs.sh` | `~/projects`, `~/ruflo`, `~/docker` (excluding `node_modules`, `.venv`, `__pycache__`, `dist`, `.next`, `target`) |

All land under `BACKUP_ROOT` (default `~<admin>/backups`, overridable in
`.env`), namespaced by category and UTC timestamp:

```
${BACKUP_ROOT}/
├── system-config/2026-07-25T030000Z/system-config.tar.gz
├── postgres/2026-07-25T030000Z/{appdb.dump.gz, globals.sql.gz}
├── redis/2026-07-25T030000Z/dump.rdb.gz
├── docker-volumes/2026-07-25T030000Z/<volume>.tar.gz
└── project-dirs/2026-07-25T030000Z/{projects,ruflo,docker}.tar.gz
```

## Retention

`backup-run.sh` prunes each category's timestamp directories older than
`BACKUP_RETENTION_DAYS` (default 14, set in `.env`) after every run.

## Offsite copy (optional)

Set `BACKUP_OFFSITE_RCLONE_REMOTE` in `.env` (e.g. a `rclone`-configured
DigitalOcean Spaces remote — `rclone config` once, interactively, before
this will work) and `backup-run.sh` syncs `BACKUP_ROOT` there after each
local run. `rclone` itself is installed by `scripts/16-automation-cron.sh`.
Leave it empty to keep backups local-only (still meaningfully protects
against application bugs/bad deploys, but not against total droplet
loss).

## Running a backup manually

```
sudo ~/scripts/automation/backup-run.sh
```

## Restoring

`automation/restore.sh` is the single entry point for all categories.
**It's destructive** (overwrites current state) — it prompts for
confirmation unless you pass `--yes`.

```
# See what's available to restore from:
sudo ~/scripts/automation/restore.sh --list postgres

# Restore:
sudo ~/scripts/automation/restore.sh postgres 2026-07-25T030000Z
sudo ~/scripts/automation/restore.sh redis 2026-07-25T030000Z
sudo ~/scripts/automation/restore.sh docker-volumes 2026-07-25T030000Z
sudo ~/scripts/automation/restore.sh project-dirs 2026-07-25T030000Z
sudo ~/scripts/automation/restore.sh system-config 2026-07-25T030000Z
```

Per category:

- **postgres**: drops and recreates each database named in the backup,
  then `pg_restore`s into it, then replays the globals dump.
- **redis**: stops `redis-server`, overwrites its RDB file, restarts it.
- **docker-volumes**: creates the named volume if it doesn't exist,
  wipes its contents, extracts the archive over it. **Stop containers
  using the volume first** — the restore doesn't do this for you, since
  it doesn't know which compose project(s) reference it.
- **project-dirs**: extracts over the corresponding `~<admin>/<dir>`.
- **system-config**: extracts over `/etc` and `/var/lib/echo-protocol`
  directly — review `tar -tzf <archive>` first, and restart affected
  services afterward (`systemctl restart ssh nginx fail2ban docker`).

## Disaster recovery (losing the whole droplet)

Backups under `BACKUP_ROOT` only survive droplet loss if
`BACKUP_OFFSITE_RCLONE_REMOTE` is configured — a local-only backup is
protection against bad deploys and data corruption, not against the disk
itself disappearing. To rebuild from scratch: provision a fresh Debian
12 droplet, run `install.sh` there, `rclone sync` the offsite backups
down, then run `restore.sh` for each category.
