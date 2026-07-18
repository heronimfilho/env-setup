#!/usr/bin/env bash

set -Eeuo pipefail

readonly OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
readonly ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${OH_MY_ZSH_DIR}/custom}"
readonly DRACULA_DIR="${ZSH_CUSTOM_DIR}/themes/dracula"
readonly ZSHRC="${HOME}/.zshrc"
readonly ZSH_BACKUP_DIR="${HOME}/.env-setup/backups"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not run this setup as root." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required." >&2
  exit 1
fi

sudo_command=(sudo)
if [[ "${ENV_SETUP_NONINTERACTIVE:-0}" == "1" ]]; then
  sudo_command+=(-n)
fi

"${sudo_command[@]}" -v

"${sudo_command[@]}" apt-get update
"${sudo_command[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
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

backup_zshrc() {
  if [[ ! -f "${ZSHRC}" ]]; then
    return
  fi

  mkdir -p "${ZSH_BACKUP_DIR}"
  cp "${ZSHRC}" "${ZSH_BACKUP_DIR}/zshrc-$(date +%Y%m%d-%H%M%S)-$$.bak"
}

get_existing_plugins() {
  awk '
    BEGIN { in_plugins = 0 }
    {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)

      if (!in_plugins && line ~ /^[[:space:]]*plugins[[:space:]]*=\(/) {
        in_plugins = 1
        sub(/^[^(]*\(/, "", line)
      }

      if (in_plugins) {
        if (line ~ /\)/) {
          sub(/\).*/, "", line)
          print line
          exit
        }
        print line
      }
    }
  ' "${ZSHRC}"
}

configure_plugins() {
  local existing_plugins
  local plugin
  local plugins_line
  local temporary_file
  local -a merged_plugins=()
  local -a required_plugins=(
    git
    sudo
    extract
    colored-man-pages
    zsh-autosuggestions
    zsh-syntax-highlighting
  )
  declare -A seen_plugins=()

  existing_plugins="$(get_existing_plugins)"
  for plugin in ${existing_plugins}; do
    plugin="${plugin//\"/}"
    plugin="${plugin//\'/}"
    [[ -z "${plugin}" || -n "${seen_plugins[${plugin}]:-}" ]] && continue
    merged_plugins+=("${plugin}")
    seen_plugins["${plugin}"]=1
  done

  for plugin in "${required_plugins[@]}"; do
    [[ -n "${seen_plugins[${plugin}]:-}" ]] && continue
    merged_plugins+=("${plugin}")
    seen_plugins["${plugin}"]=1
  done

  plugins_line="plugins=(${merged_plugins[*]})"
  if grep -Eq '^[[:space:]]*plugins[[:space:]]*=\(' "${ZSHRC}"; then
    temporary_file="$(mktemp)"
    awk -v replacement="${plugins_line}" '
      BEGIN { skipping = 0 }
      {
        if (!skipping && $0 ~ /^[[:space:]]*plugins[[:space:]]*=\(/) {
          print replacement
          if ($0 !~ /\)/) { skipping = 1 }
          next
        }
        if (skipping) {
          if ($0 ~ /\)/) { skipping = 0 }
          next
        }
        print
      }
    ' "${ZSHRC}" > "${temporary_file}"
    cat "${temporary_file}" > "${ZSHRC}"
    rm -f "${temporary_file}"
  else
    printf '\n%s\n' "${plugins_line}" >> "${ZSHRC}"
  fi
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

backup_zshrc

if grep -q '^ZSH_THEME=' "${ZSHRC}"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="dracula"|' "${ZSHRC}"
else
  printf '\nZSH_THEME="dracula"\n' >> "${ZSHRC}"
fi

configure_plugins

zsh_path="$(command -v zsh)"
current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"

if [[ "${current_shell}" != "${zsh_path}" ]]; then
  "${sudo_command[@]}" chsh -s "${zsh_path}" "$(id -un)"
fi

echo "Zsh configured."
echo "Theme: dracula"
echo "Required plugins were added without removing existing plugins."
echo "Open a new WSL session or run: exec zsh"
