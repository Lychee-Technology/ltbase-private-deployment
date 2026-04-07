#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/sync-template-upstream.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_log_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
log_file="${temp_dir}/commands.log"
touch "${log_file}"

setup_fake_git() {
  local fake_bin="$1"

  mkdir -p "${fake_bin}"

  cat >"${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"${COMMAND_LOG}"

case "$*" in
  "rev-parse --is-inside-work-tree")
    printf 'true\n'
    exit 0
    ;;
  "status --porcelain")
    if [[ "${SCENARIO:-success}" == "dirty" ]]; then
      printf ' M README.md\n'
    fi
    exit 0
    ;;
  "rev-parse --abbrev-ref HEAD")
    printf 'main\n'
    exit 0
    ;;
  "remote get-url upstream")
    if [[ "${SCENARIO:-success}" == "url_mismatch" ]]; then
      printf 'https://github.com/example/wrong-template.git\n'
      exit 0
    fi
    exit 2
    ;;
  "remote add upstream https://github.com/Lychee-Technology/ltbase-private-deployment.git")
    exit 0
    ;;
  "fetch upstream")
    exit 0
    ;;
  "merge --no-edit upstream/main")
    exit 0
    ;;
esac

exit 0
EOF
  chmod +x "${fake_bin}/git"
}

run_success_case() {
  local fake_bin="$1"
  local log_file="$2"
  setup_fake_git "${fake_bin}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" 2>&1)"; then
    fail "expected script to succeed, got: ${output}"
  fi

  assert_log_contains "${log_file}" "git rev-parse --is-inside-work-tree"
  assert_log_contains "${log_file}" "git status --porcelain"
  assert_log_contains "${log_file}" "git rev-parse --abbrev-ref HEAD"
  assert_log_contains "${log_file}" "git remote get-url upstream"
  assert_log_contains "${log_file}" "git remote add upstream https://github.com/Lychee-Technology/ltbase-private-deployment.git"
  assert_log_contains "${log_file}" "git fetch upstream"
  assert_log_contains "${log_file}" "git merge --no-edit upstream/main"
}

run_dirty_tree_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" SCENARIO="dirty" "${SCRIPT_PATH}" >"${temp_dir}/dirty.out" 2>&1; then
    fail "expected script to fail on dirty working tree"
  fi

  if ! grep -Fq "working tree is not clean" "${temp_dir}/dirty.out"; then
    fail "expected dirty tree error output"
  fi
}

run_url_mismatch_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" SCENARIO="url_mismatch" "${SCRIPT_PATH}" >"${temp_dir}/url-mismatch.out" 2>&1; then
    fail "expected script to fail on upstream URL mismatch"
  fi

  if ! grep -Fq "remote upstream already exists with unexpected URL" "${temp_dir}/url-mismatch.out"; then
    fail "expected upstream URL mismatch error output"
  fi
}

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

success_bin="${temp_dir}/success-bin"
dirty_bin="${temp_dir}/dirty-bin"
url_mismatch_bin="${temp_dir}/url-mismatch-bin"

run_success_case "${success_bin}" "${log_file}"
run_dirty_tree_case "${dirty_bin}"
run_url_mismatch_case "${url_mismatch_bin}"

printf 'PASS: sync-template-upstream tests\n'
