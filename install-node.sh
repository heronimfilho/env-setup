#!/usr/bin/env bash

set -Eeuo pipefail

readonly ENV_SETUP_NVM_VERSION="${ENV_SETUP_NVM_VERSION:-v0.40.4}"
readonly NVM_BLOCK_START="# >>> env-setup nvm >>>"
readonly NVM_BLOCK_END="# <<< env-setup nvm <<<"
readonly SHELL_BACKUP_DIR="${HOME}/.env-setup/backups"
readonly -a PROFILE_FILES=("${HOME}/.bashrc" "${HOME}/.zshrc")

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

validate_managed_block() {
  local profile_file="$1"
  local start_count=0
  local end_count=0

  [[ -f "${profile_file}" ]] || return 0

  start_count="$(grep -Fxc "${NVM_BLOCK_START}" "${profile_file}" || true)"
  end_count="$(grep -Fxc "${NVM_BLOCK_END}" "${profile_file}" || true)"

  if [[ "${start_count}" -ne "${end_count}" || "${start_count}" -gt 1 ]]; then
    echo "The managed NVM block is incomplete or duplicated in ${profile_file}. Fix the markers before running setup again." >&2
    return 1
  fi
}

backup_profile_file() {
  local profile_file="$1"

  [[ -f "${profile_file}" ]] || return 0
  mkdir -p "${SHELL_BACKUP_DIR}"
  cp "${profile_file}" "${SHELL_BACKUP_DIR}/$(basename "${profile_file}")-$(date +%Y%m%d-%H%M%S)-$$.bak"
}

ensure_nvm_block() {
  local profile_file="$1"
  local temporary_file

  mkdir -p "$(dirname "${profile_file}")"
  touch "${profile_file}"
  backup_profile_file "${profile_file}"
  temporary_file="$(mktemp "${profile_file}.env-setup.XXXXXX")"

  if ! awk -v start="${NVM_BLOCK_START}" -v end="${NVM_BLOCK_END}" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "${profile_file}" > "${temporary_file}"; then
    rm -f "${temporary_file}"
    return 1
  fi

  while [[ -s "${temporary_file}" ]] && [[ "$(tail -n 1 "${temporary_file}")" == "" ]]; do
    sed -i '$d' "${temporary_file}"
  done

  if [[ -s "${temporary_file}" ]]; then
    printf '\n' >> "${temporary_file}"
  fi

  cat >> "${temporary_file}" <<'BLOCK'
# >>> env-setup nvm >>>
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
# <<< env-setup nvm <<<
BLOCK

  chmod --reference="${profile_file}" "${temporary_file}"
  mv -f "${temporary_file}" "${profile_file}"
}

for profile_file in "${PROFILE_FILES[@]}"; do
  validate_managed_block "${profile_file}"
done

sudo_command=(sudo)
if [[ "${ENV_SETUP_NONINTERACTIVE:-0}" == "1" ]]; then
  sudo_command+=(-n)
fi

"${sudo_command[@]}" -v
"${sudo_command[@]}" apt-get update
"${sudo_command[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  git

if [[ -d "${NVM_DIR}/.git" ]]; then
  current_nvm_ref="$(git -C "${NVM_DIR}" describe --tags --exact-match 2>/dev/null || true)"
  if [[ "${current_nvm_ref}" != "${ENV_SETUP_NVM_VERSION}" ]]; then
    echo "Updating NVM to ${ENV_SETUP_NVM_VERSION}..."
    git -C "${NVM_DIR}" fetch --depth 1 origin "tag" "${ENV_SETUP_NVM_VERSION}"
    git -C "${NVM_DIR}" checkout --force "${ENV_SETUP_NVM_VERSION}"
  fi
elif [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
  echo "Installing NVM ${ENV_SETUP_NVM_VERSION}..."
  PROFILE=/dev/null NVM_DIR="${NVM_DIR}" bash -c \
    "$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${ENV_SETUP_NVM_VERSION}/install.sh")"
fi

if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
  echo "NVM installation did not create ${NVM_DIR}/nvm.sh." >&2
  exit 1
fi

for profile_file in "${PROFILE_FILES[@]}"; do
  ensure_nvm_block "${profile_file}"
done

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

echo "NVM: $(nvm --version)"
echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo "Default Node.js alias: lts/*"
