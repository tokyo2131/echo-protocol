#!/usr/bin/env bash
# Stage 06: core CLI utilities. Packages available in Debian 12 (Bookworm)
# main repos are installed via apt; a few modern tools that Bookworm
# doesn't ship (eza, zoxide, fastfetch) are installed from upstream
# GitHub releases, pinned to the latest tagged release at install time.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
detect_arch
log "Architecture: ${DPKG_ARCH} (Rust target: ${RUST_TARGET_ARCH}, fastfetch: ${FASTFETCH_ARCH})"

step "Install apt-packaged utilities"
apt_update
apt_install \
  git git-lfs curl wget jq zip unzip tree rsync tmux screen vim nano \
  htop btop ncdu iotop iftop \
  build-essential software-properties-common ca-certificates gnupg \
  ripgrep fd-find fzf bat

step "Symlink Debian-renamed binaries to their upstream names"
ln -sf "$(command -v fdfind)" /usr/local/bin/fd
ln -sf "$(command -v batcat)" /usr/local/bin/bat

# --- helper: install latest GitHub release binary tarball -----------------
install_github_release() {
  local repo="$1" asset_pattern="$2" binary_name="$3"
  if command -v "$binary_name" &>/dev/null; then
    log "${binary_name} already installed, skipping."
    return
  fi
  local tag url tmp release_json
  release_json=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")
  tag=$(jq -r .tag_name <<<"$release_json")
  # --arg passes asset_pattern as a jq string value rather than
  # interpolating it into the program text — avoids fights between
  # bash's backslash-escaping and jq's own JSON-string-escaping rules
  # (a literal "\." in the interpolated form is not a valid jq string
  # escape and fails to parse).
  url=$(jq -r --arg pattern "$asset_pattern" \
    '.assets[] | select(.name | test($pattern)) | .browser_download_url' \
    <<<"$release_json" | head -n1)
  [[ -n "$url" && "$url" != "null" ]] || { warn "Could not resolve release asset for ${repo} (${asset_pattern}); skipping."; return; }
  tmp=$(mktemp -d)
  log "Installing ${binary_name} ${tag} from ${repo}"
  curl -fsSL "$url" -o "${tmp}/asset"
  if [[ "$url" == *.tar.gz ]]; then
    tar -xzf "${tmp}/asset" -C "$tmp"
  elif [[ "$url" == *.zip ]]; then
    unzip -q "${tmp}/asset" -d "$tmp"
  fi
  local found
  found=$(find "$tmp" -maxdepth 3 -type f -name "$binary_name" | head -n1)
  if [[ -z "$found" ]]; then
    warn "Could not locate ${binary_name} binary inside downloaded asset; skipping."
  else
    install -m 755 "$found" "/usr/local/bin/${binary_name}"
  fi
  rm -rf "$tmp"
}

step "Install eza (modern ls replacement) from upstream release"
install_github_release "eza-community/eza" "eza_${RUST_TARGET_ARCH}-unknown-linux-gnu\\.tar\\.gz$" "eza"

step "Install zoxide (smarter cd) from upstream release"
install_github_release "ajeetdsouza/zoxide" "zoxide-.*-${RUST_TARGET_ARCH}-unknown-linux-musl\\.tar\\.gz$" "zoxide"

step "Install fastfetch (system info banner) from upstream release"
install_github_release "fastfetch-cli/fastfetch" "fastfetch-linux-${FASTFETCH_ARCH}\\.tar\\.gz$" "fastfetch"

step "Enable zoxide and useful aliases for interactive shells"
cat >/etc/profile.d/echo-protocol-aliases.sh <<'EOF'
# Managed by echo-protocol scripts/06-core-utilities.sh
if command -v eza &>/dev/null; then
  alias ls='eza --group-directories-first'
  alias ll='eza -lah --group-directories-first'
fi
if command -v bat &>/dev/null; then
  alias cat='bat --paging=never'
fi
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
fi
EOF
chmod 644 /etc/profile.d/echo-protocol-aliases.sh

mark_done "06-core-utilities"
log "Stage 06 complete."
