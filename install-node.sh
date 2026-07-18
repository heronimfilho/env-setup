#!/usr/bin/env bash

set -Eeuo pipefail

readonly ENV_SETUP_NVM_VERSION="${ENV_SETUP_NVM_VERSION:-v0.40.4}"
readonly NVM_BLOCK_START="# >>> env-setup nvm >>>"
readonly NVM_BLOCK_END="# <<< env-setup nvm <<<"

unset NVM_BIN NVM_INC NODE_PATH
export NVM_DIR="${HOME}/.nvm"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not run this setup as root." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required." >&2
  exit 1
fi

sudo -v
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  git

if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
  echo "Installing NVM ${ENV_SETUP_NVM_VERSION}..."
  PROFILE=/dev/null NVM_DIR="${NVM_DIR}" bash -c \
    "$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${ENV_SETUP_NVM_VERSION}/install.sh")"
fi

if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
  echo "NVM installation did not create ${NVM_DIR}/nvm.sh." >&2
  exit 1
fi

ensure_nvm_block() {
  local profile_file="$1"
  local temporary_file

  mkdir -p "$(dirname "${profile_file}")"
  touch "${profile_file}"
  temporary_file="$(mktemp)"

  awk -v start="${NVM_BLOCK_START}" -v end="${NVM_BLOCK_END}" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "${profile_file}" > "${temporary_file}"

  while [[ -s "${temporary_file}" ]] && [[ "$(tail -n 1 "${temporary_file}")" == "" ]]; do
    sed -i '$d' "${temporary_file}"
  done

  cat "${temporary_file}" > "${profile_file}"
  if [[ -s "${profile_file}" ]]; then
    printf '\n' >> "${profile_file}"
  fi

  cat >> "${profile_file}" <<'EOF'
# >>> env-setup nvm >>>
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
# <<< env-setup nvm <<<
EOF

  rm -f "${temporary_file}"
}

ensure_nvm_block "${HOME}/.bashrc"
ensure_nvm_block "${HOME}/.zshrc"

# shellcheck source=/dev/null
source "${NVM_DIR}/nvm.sh"

if ! command -v nvm >/dev/null 2>&1; then
  echo "The nvm command is not available after loading nvm.sh." >&2
  exit 1
fi

echo "Installing the latest Node.js LTS release..."
nvm install --lts --latest-npm
nvm alias default 'lts/*'
nvm use default

if command -v corepack >/dev/null 2>&1; then
  corepack enable
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is not available after installation." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is not available after installation." >&2
  exit 1
fi

echo "NVM ${ENV_SETUP_NVM_VERSION} configured."
echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo "Default Node.js alias: lts/*"
