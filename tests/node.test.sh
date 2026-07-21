#!/usr/bin/env bash

set -Eeuo pipefail

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

  cat > "${mock_bin}/sudo" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "${HOME}/sudo-calls.log"
if [[ "${1:-}" == "-n" ]]; then shift; fi
if [[ "${1:-}" == "-v" ]]; then exit 0; fi
if [[ "${1:-}" == "env" ]]; then
  shift
  while [[ "${1:-}" == *=* ]]; do shift; done
fi
exec "$@"
MOCK

  cat > "${mock_bin}/apt-get" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

  cat > "${mock_bin}/id" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then printf '1000\n'; else exec /usr/bin/id "$@"; fi
MOCK

  chmod +x "${mock_bin}"/*
}

create_fake_nvm() {
  local home="$1"
  mkdir -p "${home}/.nvm"

  cat > "${home}/.nvm/nvm.sh" <<'NVM'
nvm() {
  printf '%s\n' "$*" >> "${HOME}/nvm-calls.log"
  case "${1:-}" in
    --version)
      printf '0.40.4\n'
      ;;
    install|use)
      mkdir -p "${HOME}/.nvm/current/bin"
      cat > "${HOME}/.nvm/current/bin/node" <<'NODE'
#!/usr/bin/env bash
printf 'v24.0.0\n'
NODE
      cat > "${HOME}/.nvm/current/bin/npm" <<'NPM'
#!/usr/bin/env bash
printf '11.0.0\n'
NPM
      cat > "${HOME}/.nvm/current/bin/corepack" <<'COREPACK'
#!/usr/bin/env bash
exit 0
COREPACK
      chmod +x "${HOME}/.nvm/current/bin"/*
      export PATH="${HOME}/.nvm/current/bin:${PATH}"
      ;;
    alias) ;;
    *) return 0 ;;
  esac
}
NVM
}

assert_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual
  actual="$(grep -c -F "${pattern}" "${file}" || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Expected ${expected} occurrence(s) of '${pattern}' in ${file}, found ${actual}." >&2
    exit 1
  fi
}

test_idempotent_node_setup() {
  local test_root="${TEMP_ROOT}/success"
  local mock_bin="${test_root}/bin"
  local home="${test_root}/home"

  mkdir -p "${home}"
  create_mocks "${mock_bin}"
  create_fake_nvm "${home}"
  printf 'export PRESERVED_BASH=1\n' > "${home}/.bashrc"
  printf 'export PRESERVED_ZSH=1\n' > "${home}/.zshrc"

  PATH="${mock_bin}:${PATH}" HOME="${home}" bash "${PROJECT_ROOT}/install-node.sh"
  PATH="${mock_bin}:${PATH}" HOME="${home}" bash "${PROJECT_ROOT}/install-node.sh"

  assert_count 1 '# >>> env-setup nvm >>>' "${home}/.bashrc"
  assert_count 1 '# <<< env-setup nvm <<<' "${home}/.bashrc"
  assert_count 1 '# >>> env-setup nvm >>>' "${home}/.zshrc"
  assert_count 1 '# <<< env-setup nvm <<<' "${home}/.zshrc"
  assert_count 1 'export PRESERVED_BASH=1' "${home}/.bashrc"
  assert_count 1 'export PRESERVED_ZSH=1' "${home}/.zshrc"
  assert_count 2 'install --lts --latest-npm' "${home}/nvm-calls.log"
  assert_count 2 'alias default lts/*' "${home}/nvm-calls.log"

  test "$(find "${home}/.env-setup/backups" -type f -name '.bashrc-*.bak' | wc -l)" -ge 2
  test "$(find "${home}/.env-setup/backups" -type f -name '.zshrc-*.bak' | wc -l)" -ge 2
}

test_incomplete_block_is_rejected_without_changes() {
  local test_root="${TEMP_ROOT}/incomplete"
  local mock_bin="${test_root}/bin"
  local home="${test_root}/home"
  local before

  mkdir -p "${home}"
  create_mocks "${mock_bin}"
  create_fake_nvm "${home}"
  cat > "${home}/.bashrc" <<'PROFILE'
export BEFORE_BLOCK=1
# >>> env-setup nvm >>>
export AFTER_START_MUST_SURVIVE=1
PROFILE
  before="$(cat "${home}/.bashrc")"

  if PATH="${mock_bin}:${PATH}" HOME="${home}" bash "${PROJECT_ROOT}/install-node.sh"; then
    echo 'Expected an incomplete managed block to fail.' >&2
    exit 1
  fi

  test "$(cat "${home}/.bashrc")" = "${before}"
  test ! -f "${home}/sudo-calls.log"
}

test_noninteractive_uses_non_prompting_sudo() {
  local test_root="${TEMP_ROOT}/noninteractive"
  local mock_bin="${test_root}/bin"
  local home="${test_root}/home"

  mkdir -p "${home}"
  create_mocks "${mock_bin}"
  create_fake_nvm "${home}"

  ENV_SETUP_NONINTERACTIVE=1 PATH="${mock_bin}:${PATH}" HOME="${home}" \
    bash "${PROJECT_ROOT}/install-node.sh"

  grep -Fxq -- '-n -v' "${home}/sudo-calls.log"
  grep -Fxq -- '-n apt-get update' "${home}/sudo-calls.log"
}

test_idempotent_node_setup
test_incomplete_block_is_rejected_without_changes
test_noninteractive_uses_non_prompting_sudo

echo "Node setup tests passed."
