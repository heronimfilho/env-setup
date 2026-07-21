#!/usr/bin/env bash

set -Eeuo pipefail

unset ZSH ZSH_CUSTOM MOCK_GIT_FAIL

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly PROJECT_ROOT TEMP_ROOT

cleanup() {
  rm -rf "${TEMP_ROOT}"
}

trap cleanup EXIT

create_mocks() {
  local mock_bin="$1"

  mkdir -p "${mock_bin}"

  cat > "${mock_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "${HOME}/sudo-calls.log"
if [[ "${1:-}" == "-n" ]]; then shift; fi
if [[ "${1:-}" == "-v" ]]; then
  exit 0
fi

if [[ "${1:-}" == "env" ]]; then
  shift
  while [[ "${1:-}" == *=* ]]; do
    shift
  done
fi

exec "$@"
EOF

  cat > "${mock_bin}/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat > "${mock_bin}/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'INSTALLER'
set -eu
mkdir -p \
  "${HOME}/.oh-my-zsh/custom/plugins" \
  "${HOME}/.oh-my-zsh/custom/themes" \
  "${HOME}/.oh-my-zsh/templates"
touch "${HOME}/.oh-my-zsh/oh-my-zsh.sh"
cat > "${HOME}/.oh-my-zsh/templates/zshrc.zsh-template" <<'ZSHRC'
ZSH_THEME="robbyrussell"
plugins=(git)
ZSHRC
INSTALLER
EOF

  cat > "${mock_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${MOCK_GIT_FAIL:-0}" == "1" ]]; then
  exit 42
fi

if [[ "${1:-}" == "-C" ]]; then
  exit 0
fi

if [[ "${1:-}" == "clone" ]]; then
  target="${@: -1}"
  mkdir -p "${target}/.git"

  if [[ "${target}" == */themes/dracula ]]; then
    touch "${target}/dracula.zsh-theme"
  fi

  exit 0
fi

exit 1
EOF

  cat > "${mock_bin}/id" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -u) printf '1000\n' ;;
  -un) printf 'developer\n' ;;
  *) exit 1 ;;
esac
EOF

  cat > "${mock_bin}/getent" <<'EOF'
#!/usr/bin/env bash
printf 'developer:x:1000:1000::%s:/bin/bash\n' "${HOME}"
EOF

  cat > "${mock_bin}/chsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat > "${mock_bin}/zsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "${mock_bin}"/*
}

run_setup() {
  local mock_bin="$1"
  local home="$2"
  local git_fail="${3:-0}"
  local noninteractive="${4:-0}"

  env \
    -u ZSH \
    -u ZSH_CUSTOM \
    PATH="${mock_bin}:${PATH}" \
    HOME="${home}" \
    MOCK_GIT_FAIL="${git_fail}" \
    ENV_SETUP_NONINTERACTIVE="${noninteractive}" \
    bash "${PROJECT_ROOT}/configure-zsh.sh"
}

assert_line_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual

  actual="$(grep -c -F "${pattern}" "${file}" || true)"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "Expected ${expected} occurrence(s) of '${pattern}', found ${actual}." >&2
    exit 1
  fi
}

test_idempotent_configuration() {
  local test_root="${TEMP_ROOT}/success"
  local mock_bin="${test_root}/bin"
  local home="${test_root}/home"

  mkdir -p "${home}"
  create_mocks "${mock_bin}"

  cat > "${home}/.zshrc" <<'EOF'
ZSH_THEME="agnoster"
plugins=(
  git
  docker
  kubectl # keep this plugin
)
export CUSTOM_SETTING="preserved"
EOF

  run_setup "${mock_bin}" "${home}"
  run_setup "${mock_bin}" "${home}"

  assert_line_count 1 'ZSH_THEME="dracula"' "${home}/.zshrc"
  assert_line_count 1 \
    'plugins=(git docker kubectl sudo extract colored-man-pages zsh-autosuggestions zsh-syntax-highlighting)' \
    "${home}/.zshrc"
  assert_line_count 1 'export CUSTOM_SETTING="preserved"' "${home}/.zshrc"

  test -L "${home}/.oh-my-zsh/custom/themes/dracula.zsh-theme"
  test "$(find "${home}/.env-setup/backups" -type f -name 'zshrc-*.bak' | wc -l)" -ge 1
}

test_noninteractive_uses_non_prompting_sudo() {
  local test_root="${TEMP_ROOT}/noninteractive"
  local mock_bin="${test_root}/bin"
  local home="${test_root}/home"

  mkdir -p "${home}"
  create_mocks "${mock_bin}"
  run_setup "${mock_bin}" "${home}" 0 1

  grep -Fxq -- '-n -v' "${home}/sudo-calls.log"
  grep -Fxq -- '-n apt-get update' "${home}/sudo-calls.log"
}

test_git_failure_is_reported() {
  local test_root="${TEMP_ROOT}/failure"
  local mock_bin="${test_root}/bin"
  local home="${test_root}/home"

  mkdir -p "${home}"
  create_mocks "${mock_bin}"

  if run_setup "${mock_bin}" "${home}" 1; then
    echo "Expected the setup to fail when git clone fails." >&2
    exit 1
  fi
}

test_idempotent_configuration
test_noninteractive_uses_non_prompting_sudo
test_git_failure_is_reported

echo "configure-zsh tests passed."
