# Security Configuration

Summary of every hardening measure this repo applies, and which stage
owns it. See `docs/SECURITY-HARDENING-CHECKLIST.md` for a flat
checklist to tick through manually.

## Perimeter

- **UFW** (`scripts/02-firewall.sh`): default-deny inbound, default-allow
  outbound. Only 22 (or `SSH_PORT`), 80, 443 opened. SSH additionally
  rate-limited via `ufw limit`.
- **Fail2Ban** (`scripts/03-fail2ban.sh`, `config/fail2ban/jail.local`):
  bans an IP for 1 hour after 3 failed SSH attempts in 10 minutes
  (`sshd` jail), plus Nginx auth-failure and bot-search jails once Nginx
  is present. Bans enforced via `ufw` (banaction).

## Access

- **No root login, no passwords** (`scripts/00-bootstrap.sh`,
  `scripts/01-ssh-hardening.sh`): root's password is locked
  (`passwd -l root`); SSH allows only the admin user, only via Ed25519
  key. See `docs/SSH.md` for the full cipher/MAC/KEX configuration.
- **Sudo, not passwordless-sudo**: the admin user has standard sudo
  (password-prompted at the console) — deliberately not configured
  passwordless, since that would make a compromised SSH key equivalent
  to root with no additional friction.

## Mandatory access control

- **AppArmor** (`scripts/04-apparmor.sh`): enabled at boot, all shipped
  profiles switched from complain to enforce mode.

## Kernel / network

- **sysctl hardening** (`scripts/05-kernel-hardening.sh`,
  `config/sysctl/99-hardening-performance.conf`): SYN cookies, disabled
  ICMP redirects/source-routing, reverse-path filtering, martian packet
  logging, restricted `kptr`/`dmesg`/`ptrace` access, hardened
  hardlink/symlink/FIFO protections, ASLR at maximum randomization.

## Application-layer

- **TLS** (`scripts/12-nginx-certbot.sh`, `config/nginx/ssl-params.conf`):
  TLSv1.2+ only, modern cipher suites, HSTS, OCSP stapling,
  `X-Content-Type-Options`/`X-Frame-Options`/`Referrer-Policy` headers on
  every vhost. Certificates auto-renew via `certbot.timer`.
- **Docker** (`scripts/10-docker.sh`, `config/docker/daemon.json`):
  `no-new-privileges` by default, app/db ports bound to `127.0.0.1` only
  in the example compose file (never directly internet-reachable — UFW
  doesn't even need to know about them).

## Patching

- **unattended-upgrades** (`scripts/00-bootstrap.sh`): Debian security
  updates applied automatically; `Automatic-Reboot` deliberately left
  `false` so a reboot doesn't happen unattended under a live workload —
  check `/var/run/reboot-required` (surfaced by
  `automation/system-update.sh` and `automation/health-check.sh`
  indirectly via service checks) and reboot on your own schedule.

## Observability of security events

- SSH: `LogLevel VERBOSE`, logged via `AUTH` syslog facility, retained
  by persistent journald (`scripts/14-monitoring-logging.sh`).
- Fail2Ban bans: `fail2ban-client status sshd` for current state;
  `/var/log/fail2ban.log` for history.
- `automation/health-check.sh` alerts (webhook, if configured) on
  service-down conditions for `ssh`/`ufw`/`fail2ban`/`docker`/`nginx`
  among others, and on certificates expiring within
  `CERT_WARN_DAYS` (default 14).

## Threat model notes / deliberate non-goals

- This hardens a single Debian host, not a multi-tenant or
  compliance-regulated environment — there's no SELinux, no FIPS mode,
  no CIS benchmark automation, no intrusion *detection* (only Fail2Ban's
  reactive banning).
- `config/nginx/hardening.conf`'s `limit_req_zone`/`limit_conn_zone`
  define rate-limiting zones but don't apply them anywhere by default —
  opt individual `location` blocks in per-vhost as needed
  (`limit_req zone=general burst=20 nodelay;`); a blanket limit would
  affect every proxied app identically regardless of its actual traffic
  shape.
