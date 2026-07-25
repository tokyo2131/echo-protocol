# Validation Checklist

## Automated

```
sudo ./scripts/99-validate.sh
```

Checks and reports PASS/WARN/FAIL for: sshd config + service, UFW
status, Fail2Ban, AppArmor, unattended-upgrades, every language runtime
(git, git-lfs, python3, node, npm, pnpm, yarn, go, java), Docker +
Compose plugin, PostgreSQL/Redis/SQLite, Nginx + Certbot + renewal
timer, Glances/htop/btop, journald persistence, logrotate policy, the
three automation timers, `backup-run.sh` presence, and the full
`~<admin>/{projects,ruflo,docker,scripts,logs,backups,downloads,tmp}`
directory tree. Exits non-zero if anything FAILs.

## Manual (not scriptable, or judgment calls)

- [ ] **New-session SSH login works** with the admin key *before*
      closing the session that ran `scripts/01-ssh-hardening.sh`
      (see `docs/SSH.md`)
- [ ] `ssh <admin>@<host> 'sudo -n true'` fails (confirms sudo isn't
      passwordless) but `ssh -t <admin>@<host> sudo whoami` succeeds
      with a password prompt
- [ ] From an unauthorized IP, `nmap -Pn <host>` (or similar) shows only
      22/80/443 open
- [ ] Visiting `https://<PRIMARY_DOMAIN>` and
      `https://<RUFLO_DOMAIN>` in a browser shows a valid, trusted
      certificate (not just that Certbot ran without error — DNS has to
      actually be pointed at this droplet first)
- [ ] `sudo -u <admin> docker run hello-world` works without `sudo`
      before that (needs a fresh login after group add)
- [ ] `sudo ~/scripts/automation/backup-run.sh` completes successfully
      and `ls ~/backups/*/*` shows fresh timestamped directories
- [ ] Restore a Postgres backup into a scratch database and confirm data
      integrity — an untested restore path is not a backup
- [ ] **Reboot the droplet** (`sudo reboot`), then after it comes back:
      `sudo ./scripts/99-validate.sh` passes again, and
      `systemctl --failed` shows nothing
- [ ] Trigger `automation/health-check.sh` with a service stopped
      (`systemctl stop nginx`) and confirm the webhook alert fires (if
      `HEALTH_CHECK_WEBHOOK_URL` is configured), then restart the
      service
- [ ] Confirm the printed `id_ed25519_git.pub` (stage 15) is registered
      with GitHub/GitLab and `ssh -T git@github.com` from the server
      succeeds

## Interpreting `99-validate.sh` output

- **FAIL** — something a prior stage should have set up isn't there;
  re-run that stage (see `docs/MAINTENANCE.md` → "Re-running
  provisioning") and re-validate.
- **WARN** — informational (e.g. a systemd unit exists but a check
  couldn't fully confirm its state) rather than a confirmed problem;
  worth a manual look but not necessarily broken.
