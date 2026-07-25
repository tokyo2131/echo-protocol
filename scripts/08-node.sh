#!/usr/bin/env bash
# Stage 08: Node.js 22 LTS via NodeSource, npm, pnpm, Yarn, and global
# TypeScript tooling.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
require_root
require_env ADMIN_USER

step "Add NodeSource repository for Node.js 22.x"
if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi

step "Install Node.js"
apt_install nodejs

step "Install pnpm and Yarn via corepack (bundled with Node 22)"
corepack enable
corepack prepare pnpm@latest --activate
corepack prepare yarn@stable --activate

step "Install global TypeScript tooling"
npm install -g typescript tsx eslint prettier vite

node --version | tee -a "$LOG_FILE"
npm --version | tee -a "$LOG_FILE"
pnpm --version | tee -a "$LOG_FILE"
yarn --version | tee -a "$LOG_FILE"

mark_done "08-node"
log "Stage 08 complete."
