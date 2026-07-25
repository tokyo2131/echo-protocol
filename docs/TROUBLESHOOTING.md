# Troubleshooting

## Locked out over SSH

If you've disabled password auth and lost the key, you're not getting
back in over SSH — use your DigitalOcean droplet's web console
(Recovery Console in the control panel) to log in as root on the local
console (not subject to `sshd` restrictions) and either restore a key
into `~<admin>/.ssh/authorized_keys` or temporarily re-enable password
auth by removing `/etc/ssh/sshd_config.d/99-hardening.conf` and
`systemctl restart ssh`.

## `install.sh` fails partway through

It's safe to fix the underlying issue and re-run — `install.sh` re-runs
every stage from the top, and each stage is idempotent, so completed
work isn't redone destructively. To retry just the failing stage:
`sudo ./scripts/<NN-name>.sh`. Check `/var/log/echo-protocol/provision.log`
for the full history of a run.

## `.env` variable errors ("Required environment variable ... is not set")

Every stage that needs config calls `require_env VAR_NAME`
(`scripts/lib/common.sh`) and dies with this message if it's missing.
Copy `.env.example` to `.env` and fill in every value — placeholder
values like `change-me-...` will "work" (script won't error) but you
should replace them with real generated secrets
(`openssl rand -base64 32`) before this touches production traffic.

## `apt-cache show python3.12` reports nothing / falls back to 3.11

`scripts/07-python.sh` enables `bookworm-backports` and prefers 3.12
from there, but falls back to the distro-default 3.11 if the mirror in
use hasn't caught up. Not an error — check with `python3 --version`
after the stage runs; re-run the stage later if you specifically need
3.12 and the fallback fired.

## Certbot fails to issue a certificate

Almost always DNS: the domain isn't pointing at this droplet's IP yet.
`scripts/12-nginx-certbot.sh` treats this as best-effort and warns
rather than failing the whole run. Once DNS propagates:

```
sudo certbot --nginx -d <domain>
```

Check propagation with `dig +short <domain>` from outside the network
and compare against the droplet's public IP.

## Docker commands need `sudo` even after `usermod -aG docker`

Group membership changes don't apply to already-open shell sessions —
log out and back in (or `newgrp docker` in the current shell) after
`scripts/10-docker.sh` runs.

## A service is enabled but `systemctl is-active` shows it down

```
journalctl -u <service> -n 100 --no-pager
systemctl status <service>
```

For Nginx specifically, `nginx -t` catches most config errors before
they'd prevent a restart — run it after any manual edit to
`/etc/nginx/`.

## Disk filling up

`automation/health-check.sh` warns at 80% and treats 90%+ as critical
(tune `DISK_WARN_PCT`/`DISK_CRIT_PCT` in `/etc/echo-protocol/automation.env`).
Common causes, in order of likelihood on this stack: unrotated Docker
container logs (shouldn't happen — `daemon.json` caps them, but a
container started before that config landed won't retroactively apply
it, so recreate long-running containers after provisioning), unpruned
Docker images/build cache (`sudo ~/scripts/automation/docker-cleanup.sh`),
accumulated local backups past `BACKUP_RETENTION_DAYS`
(`backup-run.sh` prunes on its own schedule, not on demand — run it
manually to force a prune early), or journald exceeding its configured
cap (shouldn't happen given `SystemMaxUse=1G` in
`config/journald/persistent.conf`, but `journalctl --disk-usage`
confirms).

## Redis: "NOAUTH Authentication required"

Expected — `requirepass` is set. Pass the password:
`redis-cli -a "$REDIS_PASSWORD" <command>`, or read it from
`/etc/echo-protocol/automation.env` (root-only) if you don't have it
handy from `.env` anymore.

## Fail2Ban banned an IP you need (yourself, mid-testing)

```
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip <ip>
```

## GPU-related: `cuda-detect.sh` finds nothing

Expected on a standard droplet — this repo targets a CPU-only 4vCPU/8GB
host. The script exists for if/when you resize onto a GPU-enabled plan;
see its own output for next steps once a GPU is actually present.
