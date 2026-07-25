#!/usr/bin/env bash
# Stage 13: media tooling (FFmpeg, ImageMagick) and AI-development
# support (Git LFS init, GitHub CLI). CUDA detection lives in
# automation/cuda-detect.sh (installed to ~/scripts by stage 16) since
# it's a runtime check, not something to run once during provisioning —
# useful if this droplet is ever resized onto a GPU-enabled plan.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER

step "Install media tooling"
apt_install ffmpeg imagemagick

step "Install GitHub CLI"
if ! command -v gh &>/dev/null; then
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt_update
  apt_install gh
fi

step "Initialise Git LFS for ${ADMIN_USER}"
sudo -u "$ADMIN_USER" -H git lfs install --skip-repo

gh --version | tee -a "$LOG_FILE"
ffmpeg -version | head -n1 | tee -a "$LOG_FILE"
convert -version | head -n1 | tee -a "$LOG_FILE"

mark_done "13-media-ai-tools"
log "Stage 13 complete."
