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

assert_log_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to not contain: ${needle}"
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
  "archive --format=tar --output sync-template-upstream.tar upstream/main")
    exit 0
    ;;
esac

exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat >"${fake_bin}/tar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'tar %s\n' "$*" >>"${COMMAND_LOG}"
if [[ "$*" == "-xf sync-template-upstream.tar -C ${TEMP_ROOT}/upstream-checkout" ]]; then
  mkdir -p \
    "${TEMP_ROOT}/upstream-checkout/.github/workflows" \
    "${TEMP_ROOT}/upstream-checkout/docs" \
    "${TEMP_ROOT}/upstream-checkout/scripts" \
    "${TEMP_ROOT}/upstream-checkout/test" \
    "${TEMP_ROOT}/upstream-checkout/infra" \
    "${TEMP_ROOT}/upstream-checkout/__ref__"
  : >"${TEMP_ROOT}/upstream-checkout/env.template"
  : >"${TEMP_ROOT}/upstream-checkout/.gitignore"
fi
exit 0
EOF
  chmod +x "${fake_bin}/tar"

  cat >"${fake_bin}/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync %s\n' "$*" >>"${COMMAND_LOG}"
exit 0
EOF
  chmod +x "${fake_bin}/rsync"

  cat >"${fake_bin}/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cp %s\n' "$*" >>"${COMMAND_LOG}"
exit 0
EOF
  chmod +x "${fake_bin}/cp"

  cat >"${fake_bin}/mktemp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-d" ]]; then
  printf '%s\n' "${TEMP_ROOT}/upstream-checkout"
  mkdir -p "${TEMP_ROOT}/upstream-checkout"
  exit 0
fi
exit 1
EOF
  chmod +x "${fake_bin}/mktemp"
}

run_success_case() {
  local fake_bin="$1"
  local log_file="$2"
  setup_fake_git "${fake_bin}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" "${SCRIPT_PATH}" 2>&1)"; then
    fail "expected script to succeed, got: ${output}"
  fi

  assert_log_contains "${log_file}" "git rev-parse --is-inside-work-tree"
  assert_log_contains "${log_file}" "git status --porcelain"
  assert_log_contains "${log_file}" "git rev-parse --abbrev-ref HEAD"
  assert_log_contains "${log_file}" "git remote get-url upstream"
  assert_log_contains "${log_file}" "git remote add upstream https://github.com/Lychee-Technology/ltbase-private-deployment.git"
  assert_log_contains "${log_file}" "git fetch upstream"
  assert_log_contains "${log_file}" "git archive --format=tar --output sync-template-upstream.tar upstream/main"
  assert_log_contains "${log_file}" "tar -xf sync-template-upstream.tar"
  assert_log_contains "${log_file}" "rsync -a --delete --exclude .git/ --exclude dist/ --exclude .DS_Store --exclude .env --exclude .env.* --exclude infra/Pulumi.*.yaml --exclude infra/auth-providers.*.json --exclude scripts/sync-template-upstream.sh --exclude test/sync-template-upstream-test.sh ${temp_dir}/upstream-checkout/ ./"
  assert_log_not_contains "${log_file}" "git merge --no-edit upstream/main"
}

run_dirty_tree_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="dirty" "${SCRIPT_PATH}" >"${temp_dir}/dirty.out" 2>&1; then
    fail "expected script to fail on dirty working tree"
  fi

  if ! grep -Fq "working tree is not clean" "${temp_dir}/dirty.out"; then
    fail "expected dirty tree error output"
  fi
}

run_url_mismatch_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="url_mismatch" "${SCRIPT_PATH}" >"${temp_dir}/url-mismatch.out" 2>&1; then
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
