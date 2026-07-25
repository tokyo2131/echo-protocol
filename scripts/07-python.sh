#!/usr/bin/env bash
# Stage 07: Python toolchain. Debian 12 (Bookworm) ships Python 3.11 in
# its main repo; Python 3.12 is available via bookworm-backports. We
# prefer 3.12 and fall back to the in-repo 3.11 if backports is
# unavailable (e.g. a mirror lagging behind). Global CLI tools are
# installed with pipx, since Debian marks the system Python as
# "externally managed" (PEP 668) and `pip install` at system scope is
# deliberately blocked.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER

step "Enable bookworm-backports"
if [[ ! -f /etc/apt/sources.list.d/bookworm-backports.list ]]; then
  echo "deb http://deb.debian.org/debian bookworm-backports main" \
    > /etc/apt/sources.list.d/bookworm-backports.list
fi
apt_update

step "Install Python 3.12 (falls back to distro default python3 if backports lacks it)"
if apt-cache show python3.12 &>/dev/null; then
  apt_install -t bookworm-backports python3.12 python3.12-venv python3.12-dev
  update-alternatives --install /usr/bin/python3 python3 "$(command -v python3.12)" 1
  PY_BIN=python3.12
else
  warn "python3.12 not available from backports on this mirror; using distro python3."
  apt_install python3 python3-venv python3-dev
  PY_BIN=python3
fi
apt_install python3-pip pipx

step "Ensure pipx is on PATH for all users and initialised for ${ADMIN_USER}"
sudo -u "$ADMIN_USER" -H pipx ensurepath || true

step "Install global Python dev tools via pipx (isolated venvs, PEP 668 safe)"
for tool in black ruff pytest ipython jupyterlab; do
  sudo -u "$ADMIN_USER" -H pipx install --force "$tool"
done

step "Confirm wheel/setuptools/virtualenv available for ad-hoc venvs"
"$PY_BIN" -m venv /tmp/echo-protocol-venv-check
/tmp/echo-protocol-venv-check/bin/pip install --upgrade pip wheel setuptools virtualenv >/dev/null
rm -rf /tmp/echo-protocol-venv-check
apt_install python3-virtualenv

"$PY_BIN" --version | tee -a "$LOG_FILE"

mark_done "07-python"
log "Stage 07 complete."
