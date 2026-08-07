# Installed Software

Reference for what each stage installs. See the stage script itself for
exact versions/flags — this is the map, not the source of truth.

| Stage | Installs |
|---|---|
| 00-bootstrap | Full apt upgrade, `unattended-upgrades`, admin user |
| 01-ssh-hardening | `openssh-server` (Ed25519 host key only) |
| 02-firewall | `ufw` |
| 03-fail2ban | `fail2ban` |
| 04-apparmor | `apparmor`, `apparmor-utils`, `apparmor-profiles`, `apparmor-profiles-extra` |
| 05-kernel-hardening | sysctl profile only (no packages); 4G swapfile |
| 06-core-utilities | `git`, `git-lfs`, `curl`, `wget`, `jq`, `zip`, `unzip`, `tree`, `rsync`, `tmux`, `screen`, `vim`, `nano`, `htop`, `btop`, `ncdu`, `iotop`, `iftop`, `build-essential`, `software-properties-common`, `ca-certificates`, `gnupg`, `ripgrep`, `fd-find`, `fzf`, `bat`, plus `eza`/`zoxide`/`fastfetch` from upstream GitHub releases (not in Bookworm's apt repos) |
| 07-python | Python 3.12 (via `bookworm-backports`, falls back to distro 3.11), `pip`, `venv`, `virtualenv`; `pipx`-installed `black`, `ruff`, `pytest`, `ipython`, `jupyterlab` |
| 08-node | Node.js 22.x (NodeSource), `npm`, `pnpm` + `yarn` (via Corepack), global `typescript`, `tsx`, `eslint`, `prettier`, `vite` |
| 09-go-rust-java | Go (latest stable, upstream tarball, `/usr/local/go`), Rust (`rustup`, per-admin-user stable toolchain), `openjdk-21-jdk-headless` |
| 10-docker | Docker Engine, CLI, `containerd.io`, Buildx plugin, Compose plugin (Docker's official apt repo) |
| 11-databases | `postgresql`, `postgresql-contrib`, `redis-server`, `sqlite3` |
| 12-nginx-certbot | `nginx`, `certbot`, `python3-certbot-nginx` |
| 13-media-ai-tools | `ffmpeg`, `imagemagick`, GitHub CLI (`gh`) |
| 14-monitoring-logging | `glances`, `logrotate` |
| 15-git-config | No new packages — configures `git`/Git LFS identity + SSH |
| 16-automation-cron | `rclone` (optional offsite backup sync) |

## Where to look for the authoritative list

```
grep -rhoE 'apt_install [a-z0-9.-]+( [a-z0-9.-]+)*' scripts/ | sort -u
```

## Architecture support

Every stage runs unmodified on amd64 (x86_64) or arm64 (aarch64) —
`scripts/lib/common.sh`'s `detect_arch` resolves the right upstream
release asset for eza/zoxide/fastfetch (stage 06) and Go (stage 09);
apt packages are multi-arch already. See `docs/ORACLE-FREE-TIER.md` for
running on Oracle Cloud's free arm64 (Ampere A1) tier.

## OS support

Debian 12 (Bookworm) is primary; Ubuntu 24.04 LTS (Noble) is also
supported — needed in practice, since Debian isn't offered as a platform
image in every Oracle Cloud region/tenancy. `detect_os` branches the
handful of genuinely distro-specific bits (Python 3.12's repo,
unattended-upgrades' security-pocket match, Docker's apt repo path);
everything else is identical apt packages either way.

## Version policy

- Packages from Debian's apt repos track whatever Bookworm/
  bookworm-backports ships — security-patched automatically by
  `unattended-upgrades`.
- Upstream-sourced tools (eza, zoxide, fastfetch, Docker, Node, Go,
  Rust, GitHub CLI) are pulled from each project's official
  repo/release at install time, so re-running `install.sh` on a new
  droplet gets whatever is current then — expect drift from a droplet
  provisioned months apart. Pin versions explicitly in the relevant
  stage script if you need reproducibility across time instead of
  "latest stable now".
