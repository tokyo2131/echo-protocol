# echo-protocol

Provisioning codebase for a production-ready Debian 12 (Bookworm)
server: security hardening, Docker, language runtimes, databases, an
Nginx/Certbot reverse proxy, automated daily backups, and monitoring.
This repo *produces* the server configuration — it doesn't contain an
application. See `docs/ARCHITECTURE.md` for the full picture.

## Quick start

On a fresh Debian 12 x86_64 droplet:

```
git clone <this-repo-url> ~/projects/echo-protocol
cd ~/projects/echo-protocol
cp .env.example .env
vim .env                 # ADMIN_SSH_PUBKEY, domains, DB passwords, etc.
sudo ./install.sh
```

Then, in a **new** terminal (don't close your current session first):

```
ssh -i <your-key> <ADMIN_USER>@<droplet-ip>
```

Confirm everything landed correctly:

```
sudo ./scripts/99-validate.sh
```

## What gets installed

18 idempotent stages (`scripts/00-*.sh` … `scripts/99-validate.sh`),
run in order by `install.sh` or individually. Covers: OS hardening
(SSH, UFW, Fail2Ban, AppArmor, sysctl), Python/Node/Go/Rust/Java,
Docker + Compose, PostgreSQL/Redis/SQLite, Nginx + Let's Encrypt, media
tooling (FFmpeg/ImageMagick), monitoring (Glances + persistent
journald), and a daily-backup/health-check/weekly-maintenance
automation layer via systemd timers. Full list:
`docs/INSTALLED-SOFTWARE.md`.

## Documentation

| | |
|---|---|
| `docs/ARCHITECTURE.md` | How the stages fit together, host vs. container databases, Ruflo's placeholder |
| `docs/DIRECTORY-STRUCTURE.md` | Repo layout and the resulting server layout |
| `docs/INSTALLED-SOFTWARE.md` | What each stage installs |
| `docs/DOCKER.md` | Daemon config, project layout convention, fronting with Nginx |
| `docs/SSH.md` | The two SSH identities, hardening details, changing the port |
| `docs/GIT.md` | Git config, Git LFS, outbound SSH auth to GitHub/GitLab |
| `docs/DATABASE-ADMIN.md` | PostgreSQL/Redis/SQLite administration |
| `docs/BACKUP-RESTORE.md` | What's backed up, retention, offsite sync, restore procedure |
| `docs/SECURITY.md` | Every hardening measure and which stage owns it |
| `docs/SECURITY-HARDENING-CHECKLIST.md` | Flat checklist to tick through |
| `docs/MAINTENANCE.md` | Automated timers + manual maintenance commands |
| `docs/VALIDATION-CHECKLIST.md` | Automated + manual post-install verification |
| `docs/TROUBLESHOOTING.md` | Common failure modes and fixes |

## Automatic deployments for an application

This repo provisions the *server*; deploying an *application* to it is
covered by `docker/docker-compose.example.yml` (project layout
convention) and `examples/github-actions/deploy.yml` (a CI/CD workflow
template — push to `main` in the application's own repo builds and
pushes an image, then SSHes in and runs `docker compose up -d`). See
`docs/MAINTENANCE.md` → "Adding a new Dockerized project" for the full
sequence.
