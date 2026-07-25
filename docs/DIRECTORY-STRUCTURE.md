# Directory Structure

## This repo (checked out anywhere, e.g. `~/projects/echo-protocol`)

```
echo-protocol/
├── install.sh                Master orchestrator — runs scripts/ in order
├── .env.example               Copy to .env before running install.sh
├── scripts/
│   ├── lib/common.sh           Shared logging/idempotency helpers
│   ├── 00-bootstrap.sh .. 16-automation-cron.sh   One file per stage
│   └── 99-validate.sh          Post-install checks
├── config/                    Static config files installed verbatim (or
│                               templated) by the scripts/ stages
│   ├── ssh/, fail2ban/, sysctl/, journald/, logrotate/, docker/, nginx/
├── automation/                 Scripts copied to ~/scripts/automation on
│                               the target host; backups, cleanup, health
├── systemd/                   Unit files installed by scripts/16-*.sh
├── docker/                    Example docker-compose stack for app projects
├── examples/github-actions/   Example CI/CD workflow for another repo
└── docs/                      This documentation set
```

## Target host, after provisioning

```
/home/<admin>/                 (ADMIN_USER, default "deploy")
├── projects/                  General-purpose project checkouts
├── ruflo/                     Reserved for the Ruflo project
├── docker/                    One subdirectory per Dockerized project,
│                               each with its own docker-compose.yml
├── scripts/
│   └── automation/             Copied from this repo's automation/ at
│                               provisioning time (backup, cleanup, etc.)
├── logs/                      Free-form app logs (rotated by
│                               /etc/logrotate.d/echo-protocol)
├── backups/                   Default BACKUP_ROOT — see docs/BACKUP-RESTORE.md
├── downloads/                 Scratch space, auto-cleaned after 30 days
└── tmp/                       Scratch space, auto-cleaned after 7 days

/etc/echo-protocol/
└── automation.env             Root-only config the automation/ scripts read

/var/lib/echo-protocol/markers/  Per-stage "already ran" markers (idempotency)
/var/log/echo-protocol/          install.sh / stage script logs
/var/backups/echo-protocol/       Used if BACKUP_ROOT isn't overridden in .env
```

Every directory under `/home/<admin>` is created with mode `750`,
owned by the admin user — group-readable for tooling that runs as a
service account in the same group, but not world-readable.
