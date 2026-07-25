# Security Hardening Checklist

Flat checklist form of `docs/SECURITY.md` — tick through after a fresh
`install.sh` run, or periodically as a review.

## OS / patching
- [ ] `apt list --upgradable` is empty (or only held-back packages you
      expect)
- [ ] `systemctl is-enabled unattended-upgrades` → `enabled`
- [ ] `cat /var/run/reboot-required` doesn't exist, or you've scheduled
      a reboot for it

## SSH
- [ ] `PermitRootLogin no`, `PasswordAuthentication no`,
      `PermitEmptyPasswords no` all present in
      `/etc/ssh/sshd_config.d/99-hardening.conf`
- [ ] `passwd -S root` shows `L` (locked)
- [ ] Only an Ed25519 host key exists: `ls /etc/ssh/ssh_host_*` shows
      no `rsa`/`ecdsa`/`dsa` files
- [ ] `sshd -T | grep -i ciphers` matches the restricted set in
      `config/ssh/sshd_hardening.conf`
- [ ] You can log in with a key from a fresh session (see
      `docs/VALIDATION-CHECKLIST.md`)

## Firewall / IPS
- [ ] `sudo ufw status verbose` shows default deny (incoming), and only
      22(or `SSH_PORT`)/80/443 allowed
- [ ] `sudo fail2ban-client status` lists the `sshd` jail as active
- [ ] From a test client, 3+ failed SSH logins result in that IP being
      banned (`fail2ban-client status sshd`)

## Mandatory access control
- [ ] `sudo apparmor_status` shows profiles in enforce mode, not
      complain
- [ ] `systemctl is-active apparmor` → `active`

## Kernel / network
- [ ] `sysctl net.ipv4.tcp_syncookies` → `1`
- [ ] `sysctl kernel.kptr_restrict` → `2`
- [ ] `sysctl net.ipv4.conf.all.accept_redirects` → `0`
- [ ] `sysctl net.ipv4.ip_forward` → `0` on the host profile itself
      (Docker sets this to `1` at runtime when it creates its bridge
      network — that's expected and not a regression of this setting)

## TLS
- [ ] `curl -I https://<domain>` shows `strict-transport-security` in
      the response headers
- [ ] SSL Labs (or `nmap --script ssl-enum-ciphers`) shows no TLS 1.0/1.1
      support
- [ ] `sudo certbot certificates` shows valid, non-expiring-soon certs
- [ ] `systemctl is-enabled certbot.timer` → `enabled`

## Application / containers
- [ ] `docker ps --format '{{.Ports}}'` shows no `0.0.0.0:` bindings for
      app/db containers — only `127.0.0.1:`
- [ ] `cat /etc/docker/daemon.json` includes `no-new-privileges: true`
- [ ] Secrets (`POSTGRES_APP_PASSWORD`, `REDIS_PASSWORD`, etc.) in
      `.env` are generated values, not the `change-me-...` placeholders

## Database access
- [ ] `sudo -u postgres psql -c "SHOW listen_addresses;"` → `localhost`
- [ ] `redis-cli -a "$REDIS_PASSWORD" ping` → `PONG`; without `-a`, the
      command is rejected with `NOAUTH`
- [ ] `redis-cli -a "$REDIS_PASSWORD" FLUSHALL` is rejected (renamed
      command)

## Secrets hygiene
- [ ] `.env` is in `.gitignore` and was never committed
      (`git log --all --full-history -- .env` is empty)
- [ ] `/etc/echo-protocol/automation.env` is mode `600`, owned by `root`
- [ ] No secrets appear in `/var/log/echo-protocol/provision.log`
      (review after first run — the provisioning scripts avoid echoing
      secret values, but double-check after any local edits)

## Backups
- [ ] `sudo ~/scripts/automation/backup-run.sh` completes with exit 0
- [ ] A restore has actually been tested (see
      `docs/VALIDATION-CHECKLIST.md`) — an unverified backup is a
      liability, not a control
- [ ] `BACKUP_OFFSITE_RCLONE_REMOTE` is configured if surviving total
      droplet loss matters to you (local-only backups don't)
