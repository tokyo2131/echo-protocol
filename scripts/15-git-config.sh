#!/usr/bin/env bash
# Stage 15: Git global configuration, Git LFS, and a dedicated outbound
# SSH keypair for authenticating to GitHub/GitLab (separate from the
# inbound admin login key set up in stage 00).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER
require_env GIT_USER_NAME
require_env GIT_USER_EMAIL

ADMIN_HOME="/home/${ADMIN_USER}"
RUN_AS() { sudo -u "$ADMIN_USER" -H bash -c "$*"; }

step "Configure global Git identity and defaults for ${ADMIN_USER}"
RUN_AS "git config --global user.name '${GIT_USER_NAME}'"
RUN_AS "git config --global user.email '${GIT_USER_EMAIL}'"
RUN_AS "git config --global init.defaultBranch main"
RUN_AS "git config --global pull.rebase false"
RUN_AS "git config --global core.editor vim"
RUN_AS "git config --global credential.helper store"

step "Ensure Git LFS is initialised (also done in stage 13, safe to repeat)"
RUN_AS "git lfs install --skip-repo"

step "Generate a dedicated outbound Git SSH keypair (github.com / gitlab.com auth)"
GIT_KEY="${ADMIN_HOME}/.ssh/id_ed25519_git"
if [[ ! -f "$GIT_KEY" ]]; then
  sudo -u "$ADMIN_USER" -H ssh-keygen -t ed25519 -f "$GIT_KEY" -N "" -C "${GIT_USER_EMAIL}"
else
  log "Outbound git SSH key already exists at ${GIT_KEY}."
fi

step "Pin known_hosts and wire the key up for github.com/gitlab.com"
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "${ADMIN_HOME}/.ssh"
SSH_CONFIG="${ADMIN_HOME}/.ssh/config"
touch "$SSH_CONFIG"
if ! grep -q "^Host github.com$" "$SSH_CONFIG" 2>/dev/null; then
  cat >>"$SSH_CONFIG" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile ${GIT_KEY}
    IdentitiesOnly yes

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ${GIT_KEY}
    IdentitiesOnly yes
EOF
fi
chmod 600 "$SSH_CONFIG"
chown "$ADMIN_USER:$ADMIN_USER" "$SSH_CONFIG"
sudo -u "$ADMIN_USER" -H ssh-keyscan -t ed25519 github.com gitlab.com >> "${ADMIN_HOME}/.ssh/known_hosts" 2>/dev/null || true
chown "$ADMIN_USER:$ADMIN_USER" "${ADMIN_HOME}/.ssh/known_hosts"

step "Public key to register with GitHub/GitLab (Settings -> SSH keys)"
cat "${GIT_KEY}.pub" | tee -a "$LOG_FILE"

mark_done "15-git-config"
log "Stage 15 complete. Add the printed public key to your Git hosting account(s) before pulling/pushing over SSH."
