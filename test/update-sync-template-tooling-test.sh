#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/update-sync-template-tooling.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_text_contains() {
  local text="$1"
  local needle="$2"
  if [[ "${text}" != *"${needle}"* ]]; then
    fail "expected output to contain: ${needle}"
  fi
}

assert_text_not_contains() {
  local text="$1"
  local needle="$2"
  if [[ "${text}" == *"${needle}"* ]]; then
    fail "expected output to not contain: ${needle}"
  fi
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

setup_fake_bin() {
  local fake_bin="$1"

  mkdir -p "${fake_bin}"

  cat >"${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"${COMMAND_LOG}"

case "$*" in
  "rev-parse --is-inside-work-tree")
    printf 'true\n'
    printf 'INSIDE-WORKTREE-NOISE\n' >&2
    exit 0
    ;;
  "status --porcelain")
    printf 'STATUS-NOISE\n' >&2
    if [[ "${SCENARIO:-success}" == "status_failure" ]]; then
      printf 'status failed\n' >&2
      exit 17
    fi
    printf '\n'
    exit 0
    ;;
  "rev-parse --abbrev-ref HEAD")
    printf 'main\n'
    printf 'BRANCH-NOISE\n' >&2
    exit 0
    ;;
  "remote get-url upstream")
    exit 2
    ;;
  "remote add upstream https://github.com/Lychee-Technology/ltbase-private-deployment.git")
    printf 'REMOTE-ADD-NOISE\n'
    printf 'REMOTE-ADD-NOISE\n' >&2
    exit 0
    ;;
  "fetch upstream")
    printf 'FETCH-NOISE\n'
    printf 'FETCH-NOISE\n' >&2
    exit 0
    ;;
  "archive --format=tar --output sync-template-upstream.tar upstream/main")
    printf 'ARCHIVE-NOISE\n'
    printf 'ARCHIVE-NOISE\n' >&2
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
printf 'TAR-NOISE\n'
printf 'TAR-NOISE\n' >&2
if [[ "$*" == "-xf sync-template-upstream.tar -C ${TEMP_ROOT}/upstream-checkout" ]]; then
  mkdir -p "${TEMP_ROOT}/upstream-checkout/scripts" "${TEMP_ROOT}/upstream-checkout/test"
  : >"${TEMP_ROOT}/upstream-checkout/scripts/sync-template-upstream.sh"
  : >"${TEMP_ROOT}/upstream-checkout/test/sync-template-upstream-test.sh"
fi
exit 0
EOF
  chmod +x "${fake_bin}/tar"

  cat >"${fake_bin}/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cp %s\n' "$*" >>"${COMMAND_LOG}"
printf 'CP-NOISE\n'
printf 'CP-NOISE\n' >&2
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
path="${TEMP_ROOT}/mktemp-file.$$.$RANDOM"
: >"${path}"
printf '%s\n' "${path}"
exit 0
exit 1
EOF
  chmod +x "${fake_bin}/mktemp"

  cat >"${fake_bin}/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync %s\n' "$*" >>"${COMMAND_LOG}"
exit 0
EOF
  chmod +x "${fake_bin}/rsync"
}

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

fake_bin="${temp_dir}/bin"
setup_fake_bin "${fake_bin}"

if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" "${SCRIPT_PATH}" 2>&1)"; then
  fail "expected script to succeed, got: ${output}"
fi

assert_text_contains "${output}" "[info] fetching upstream template from upstream/main"
assert_text_contains "${output}" "[info] updating local sync helper files"
assert_text_contains "${output}" "updated sync tooling from upstream/main"
assert_text_not_contains "${output}" "INSIDE-WORKTREE-NOISE"
assert_text_not_contains "${output}" "STATUS-NOISE"
assert_text_not_contains "${output}" "BRANCH-NOISE"
assert_text_not_contains "${output}" "REMOTE-ADD-NOISE"
assert_text_not_contains "${output}" "FETCH-NOISE"
assert_text_not_contains "${output}" "ARCHIVE-NOISE"
assert_text_not_contains "${output}" "TAR-NOISE"
assert_text_not_contains "${output}" "CP-NOISE"

assert_log_contains "${log_file}" "git rev-parse --is-inside-work-tree"
assert_log_contains "${log_file}" "git status --porcelain"
assert_log_contains "${log_file}" "git rev-parse --abbrev-ref HEAD"
assert_log_contains "${log_file}" "git remote get-url upstream"
assert_log_contains "${log_file}" "git remote add upstream https://github.com/Lychee-Technology/ltbase-private-deployment.git"
assert_log_contains "${log_file}" "git fetch upstream"
assert_log_contains "${log_file}" "git archive --format=tar --output sync-template-upstream.tar upstream/main"
assert_log_contains "${log_file}" "tar -xf sync-template-upstream.tar -C ${temp_dir}/upstream-checkout"
assert_log_contains "${log_file}" "cp ${temp_dir}/upstream-checkout/scripts/sync-template-upstream.sh ${ROOT_DIR}/scripts/sync-template-upstream.sh"
assert_log_contains "${log_file}" "cp ${temp_dir}/upstream-checkout/test/sync-template-upstream-test.sh ${ROOT_DIR}/test/sync-template-upstream-test.sh"
assert_log_not_contains "${log_file}" "rsync "

status_failure_out="${temp_dir}/status-failure.out"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="status_failure" "${SCRIPT_PATH}" >"${status_failure_out}" 2>&1; then
  fail "expected script to fail when git status capture fails"
fi

assert_log_contains "${status_failure_out}" "status failed"

printf 'PASS: update-sync-template-tooling tests\n'
