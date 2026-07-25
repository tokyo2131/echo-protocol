# SSH

## Two distinct SSH identities — don't conflate them

1. **Inbound admin login** (`scripts/00-bootstrap.sh`): you generate an
   Ed25519 keypair on *your own machine*
   (`ssh-keygen -t ed25519 -C "you@yourhost"`), put the public half in
   `.env` as `ADMIN_SSH_PUBKEY`, and it's installed into
   `~<admin>/.ssh/authorized_keys` on the server. This is how you SSH
   *into* the server.
2. **Outbound Git auth** (`scripts/15-git-config.sh`): a *separate*
   Ed25519 keypair generated *on the server itself*
   (`~<admin>/.ssh/id_ed25519_git`), used only for the server to
   authenticate *to* GitHub/GitLab over SSH. Register the printed public
   key with your Git host — see `docs/GIT.md`.

## Server-side hardening (`scripts/01-ssh-hardening.sh`)

Installed as `/etc/ssh/sshd_config.d/99-hardening.conf`
(`config/ssh/sshd_hardening.conf`):

- `PermitRootLogin no`, `PasswordAuthentication no`,
  `PermitEmptyPasswords no` — key-only, non-root
- Host keys regenerated as Ed25519-only; RSA/ECDSA/DSA host keys deleted
- Restricted `KexAlgorithms`/`Ciphers`/`MACs` to current best-practice
  sets (curve25519/AES-GCM/ChaCha20-Poly1305, ETM MACs)
- `MaxAuthTries 3`, `LoginGraceTime 30` — rate-limits auth attempts
  (Fail2Ban's `sshd` jail adds a second layer: 3 failures bans the
  source IP for 1 hour — see `docs/SECURITY.md`)
- `ClientAliveInterval 300` / `ClientAliveCountMax 2` — idle sessions
  drop after ~10 minutes of no response
- `LogLevel VERBOSE` — logs the key fingerprint used for each login,
  useful for auditing which key authenticated a session
- Forwarding disabled (`X11Forwarding`, `AllowAgentForwarding`,
  `AllowTcpForwarding`, `PermitTunnel` all off) — this host isn't meant
  to be a jump box

## Changing the SSH port

Set `SSH_PORT` in `.env` before running `scripts/01-ssh-hardening.sh`
(or `install.sh`) — it appends a `Port` directive to the hardening
config *and* `scripts/02-firewall.sh` reads the same variable when
opening the UFW rule, so the two stay in sync as long as you set it
before either stage runs. Changing it after the fact means editing both
`/etc/ssh/sshd_config.d/99-hardening.conf` and `ufw` manually — **keep
your current session open** while testing a new port/config in a second
session, so a mistake doesn't lock you out.

## First-login checklist

After `scripts/01-ssh-hardening.sh` runs, password auth and root login
are already off. Before closing your current session:

```
ssh -i <path-to-your-key> <admin-user>@<server-ip>
```

in a **new** terminal, confirm it connects, *then* close the original
session.
