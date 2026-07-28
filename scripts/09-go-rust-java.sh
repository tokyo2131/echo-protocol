#!/usr/bin/env bash
# Stage 09: Go (latest stable, upstream tarball), Rust (rustup, per-admin-user),
# OpenJDK 21 (apt).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER
detect_arch

step "Install Go (latest stable) system-wide under /usr/local/go"
GO_LATEST=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)
if [[ -x /usr/local/go/bin/go && "$(/usr/local/go/bin/go version | awk '{print $3}')" == "$GO_LATEST" ]]; then
  log "Go ${GO_LATEST} already installed."
else
  tmp=$(mktemp -d)
  curl -fsSL "https://go.dev/dl/${GO_LATEST}.linux-${GO_ARCH}.tar.gz" -o "${tmp}/go.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "${tmp}/go.tar.gz"
  rm -rf "$tmp"
fi
cat >/etc/profile.d/golang.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
chmod 644 /etc/profile.d/golang.sh
/usr/local/go/bin/go version | tee -a "$LOG_FILE"

step "Install Rust (rustup, stable toolchain) for ${ADMIN_USER}"
ADMIN_HOME="/home/${ADMIN_USER}"
if [[ ! -x "${ADMIN_HOME}/.cargo/bin/rustc" ]]; then
  sudo_admin bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable'
else
  log "Rust already installed for ${ADMIN_USER}."
fi
sudo_admin bash -c "source \$HOME/.cargo/env && rustc --version" | tee -a "$LOG_FILE"

step "Install OpenJDK 21"
apt_install openjdk-21-jdk-headless
java --version | tee -a "$LOG_FILE"

mark_done "09-go-rust-java"
log "Stage 09 complete."
