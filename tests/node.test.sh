#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEMP_ROOT="$(mktemp -d)"

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
if [[ "${1:-}" == "-v" ]]; then exit 0; fi
if [[ "${1:-}" == "env" ]]; then
  shift
  while [[ "${1:-}" == *=* ]]; do shift; done
fi
exec "$@"
EOF

  cat > "${mock_bin}/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat > "${mock_bin}/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then printf '1000\n'; else exec /usr/bin/id "$@"; fi
EOF

  chmod +x "${mock_bin}"/*
}

create_fake_nvm() {
  local home="$1"
  mkdir -p "${home}/.nvm"

  cat > "${home}/.nvm/nvm.sh" <<'EOF'
nvm() {
  printf '%s\n' "$*" >> "${HOME}/nvm-calls.log"
  case "${1:-}" in
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
EOF
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

  PATH="${mock_bin}:${PATH}" HOME="${home}" bash "${PROJECT_ROOT}/install-node.sh"
  PATH="${mock_bin}:${PATH}" HOME="${home}" bash "${PROJECT_ROOT}/install-node.sh"

  assert_count 1 '# >>> env-setup nvm >>>' "${home}/.bashrc"
  assert_count 1 '# <<< env-setup nvm <<<' "${home}/.bashrc"
  assert_count 1 '# >>> env-setup nvm >>>' "${home}/.zshrc"
  assert_count 1 '# <<< env-setup nvm <<<' "${home}/.zshrc"
  assert_count 2 'install --lts --latest-npm' "${home}/nvm-calls.log"
  assert_count 2 "alias default lts/*" "${home}/nvm-calls.log"
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
test_noninteractive_uses_non_prompting_sudo

echo "Node setup tests passed."
