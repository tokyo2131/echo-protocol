#!/usr/bin/env bash
# Stage 10: Docker Engine + Compose plugin from Docker's official apt repo.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER
detect_os

step "Remove any conflicting distro Docker packages"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  dpkg -s "$pkg" &>/dev/null && apt-get remove -y "$pkg" || true
done

step "Add Docker's official GPG key and apt repository"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
ARCH=$(dpkg --print-architecture)
cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${DISTRO_CODENAME} stable
EOF

step "Install Docker Engine, CLI, containerd, Buildx, Compose plugin"
apt_update
apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

step "Install daemon.json (log rotation, live-restore, no-new-privileges)"
install -d /etc/docker
install -m 644 "${ROOT_DIR}/config/docker/daemon.json" /etc/docker/daemon.json

step "Enable and start Docker"
systemctl enable docker
systemctl restart docker

step "Allow ${ADMIN_USER} to run Docker without sudo"
getent group docker &>/dev/null || groupadd docker
usermod -aG docker "$ADMIN_USER"
log "${ADMIN_USER} added to the docker group — they must log out/in (or run 'newgrp docker') for it to take effect."

step "Note on container restart policy"
log "daemon.json does not set a global restart policy (Docker has none); set"
log "'restart: unless-stopped' per-service in compose files — see docker/docker-compose.example.yml."

docker version | tee -a "$LOG_FILE"
docker compose version | tee -a "$LOG_FILE"

mark_done "10-docker"
log "Stage 10 complete."
