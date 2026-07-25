# Maintenance Procedures

## Automated (systemd timers, installed by `scripts/16-automation-cron.sh`)

| Timer | Schedule | Runs |
|---|---|---|
| `backup.timer` | Daily 03:00 (±10min jitter) | `automation/backup-run.sh` |
| `health-check.timer` | Every 15 minutes | `automation/health-check.sh` |
| `maintenance.timer` | Weekly, Sunday 04:30 (±15min jitter) | `automation/system-update.sh` → `system-cleanup.sh` → `docker-cleanup.sh` |

Inspect any of them:

```
systemctl status backup.timer
systemctl list-timers 'backup.timer' 'health-check.timer' 'maintenance.timer'
journalctl -u backup.service -n 50
```

Security patches land separately and faster, via
`unattended-upgrades` (daily, not tied to `maintenance.timer` — see
`docs/SECURITY.md`).

## Manual / on-demand

All installed to `~<admin>/scripts/automation/`:

```
sudo ~/scripts/automation/system-update.sh      # full apt upgrade + autoremove
sudo ~/scripts/automation/system-cleanup.sh      # apt cache, journal vacuum, /tmp
sudo ~/scripts/automation/docker-cleanup.sh      # stopped containers, dangling images, build cache
sudo ~/scripts/automation/backup-run.sh          # full backup, out of schedule
sudo ~/scripts/automation/restore.sh <cat> <ts>  # see docs/BACKUP-RESTORE.md
sudo ~/scripts/automation/service-restart.sh systemd nginx
sudo ~/scripts/automation/service-restart.sh compose ~/docker/myapp web
~/scripts/automation/system-info.sh              # no sudo needed; status banner
sudo ~/scripts/automation/health-check.sh        # run the health check immediately
~/scripts/automation/cuda-detect.sh              # check for GPU + driver status
```

## Rebooting

`unattended-upgrades` intentionally does not auto-reboot. Check whether
one's pending:

```
[[ -f /var/run/reboot-required ]] && cat /var/run/reboot-required.pkgs
```

Everything provisioned by this repo is designed to survive a reboot —
every service is `systemctl enable`d, not just started, and Docker
containers use `restart: unless-stopped` — but stage `99-validate.sh` is
the fast way to confirm nothing regressed after one:

```
sudo ./scripts/99-validate.sh
```

## Re-running provisioning

Every stage is idempotent — safe to re-run `install.sh` in full, or a
single `scripts/NN-*.sh`, after changing `.env` or a config template.
Stages record completion in `/var/lib/echo-protocol/markers/` purely for
visibility/logging; re-running does not skip actual work (apt
installs, `systemctl enable`, etc. are naturally idempotent themselves).

## Adding a new Dockerized project

1. `mkdir ~/docker/<project> && cd ~/docker/<project>`
2. Copy `docker/docker-compose.example.yml` and `docker/.env.example` in,
   adjust image/build context and env vars
3. Add a `render_vhost` call in `scripts/12-nginx-certbot.sh` (or render
   `config/nginx/reverse-proxy.conf.template` by hand) for its domain/port
4. `nginx -t && systemctl reload nginx && certbot --nginx -d <domain>`
5. Wire up CI/CD from `examples/github-actions/deploy.yml` in that
   project's own repo, pointing `DEPLOY_PROJECT_DIR` at
   `~/docker/<project>`
