#!/usr/bin/env bash

set -Eeuo pipefail

readonly OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
readonly ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${OH_MY_ZSH_DIR}/custom}"
readonly DRACULA_DIR="${ZSH_CUSTOM_DIR}/themes/dracula"
readonly ZSHRC="${HOME}/.zshrc"

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
  git \
  zsh

if [[ ! -f "${OH_MY_ZSH_DIR}/oh-my-zsh.sh" ]]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
fi

install_or_update_repository() {
  local repository_url="$1"
  local target_directory="$2"

  if [[ -d "${target_directory}/.git" ]]; then
    git -C "${target_directory}" pull --ff-only
    return
  fi

  rm -rf "${target_directory}"
  git clone --depth 1 "${repository_url}" "${target_directory}"
}

install_or_update_repository \
  "https://github.com/dracula/zsh.git" \
  "${DRACULA_DIR}"

ln -sfn \
  "${DRACULA_DIR}/dracula.zsh-theme" \
  "${ZSH_CUSTOM_DIR}/themes/dracula.zsh-theme"

install_or_update_repository \
  "https://github.com/zsh-users/zsh-autosuggestions.git" \
  "${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions"

install_or_update_repository \
  "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
  "${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"

if [[ ! -f "${ZSHRC}" ]]; then
  cp "${OH_MY_ZSH_DIR}/templates/zshrc.zsh-template" "${ZSHRC}"
fi

if grep -q '^ZSH_THEME=' "${ZSHRC}"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="dracula"|' "${ZSHRC}"
else
  printf '\nZSH_THEME="dracula"\n' >> "${ZSHRC}"
fi

plugins_line='plugins=(git sudo extract colored-man-pages zsh-autosuggestions zsh-syntax-highlighting)'

if grep -q '^plugins=(' "${ZSHRC}"; then
  sed -i "s|^plugins=(.*)|${plugins_line}|" "${ZSHRC}"
else
  printf '\n%s\n' "${plugins_line}" >> "${ZSHRC}"
fi

zsh_path="$(command -v zsh)"
current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"

if [[ "${current_shell}" != "${zsh_path}" ]]; then
  sudo chsh -s "${zsh_path}" "$(id -un)"
fi

echo "Zsh configured."
echo "Theme: dracula"
echo "Plugins: git sudo extract colored-man-pages zsh-autosuggestions zsh-syntax-highlighting"
echo "Open a new WSL session or run: exec zsh"
