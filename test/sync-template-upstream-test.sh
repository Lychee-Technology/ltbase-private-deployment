#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/sync-template-upstream.sh"

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

restore_optional_file() {
  local backup_path="$1"
  local target_path="$2"

  if [[ -f "${backup_path}" ]]; then
    mkdir -p "$(dirname "${target_path}")"
    /bin/cp "${backup_path}" "${target_path}"
  else
    rm -f "${target_path}"
  fi
}

temp_dir="$(mktemp -d)"
provenance_path="${ROOT_DIR}/__ref__/template-provenance.json"
original_provenance="${temp_dir}/template-provenance.original.json"
/bin/cp "${provenance_path}" "${original_provenance}"
trap '/bin/cp "${original_provenance}" "${provenance_path}"; rm -rf "${temp_dir}"' EXIT
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
    printf 'INSIDE-WORKTREE-NOISE\n' >&2
    exit 0
    ;;
  "status --porcelain")
    printf 'STATUS-NOISE\n' >&2
    if [[ "${SCENARIO:-success}" == "dirty" ]]; then
      printf ' M README.md\n'
    fi
    exit 0
    ;;
  "rev-parse --abbrev-ref HEAD")
    printf 'main\n'
    printf 'BRANCH-NOISE\n' >&2
    exit 0
    ;;
  "remote get-url upstream")
    if [[ "${SCENARIO:-success}" == "url_mismatch" ]]; then
      printf 'https://github.com/example/wrong-template.git\n'
      printf 'REMOTE-GET-NOISE\n' >&2
      exit 0
    fi
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
  "rev-parse upstream/main")
    if [[ "${SCENARIO:-success}" == "upstream_commit_failure" ]]; then
      printf 'upstream commit failed\n' >&2
      exit 23
    fi
    printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf 'UPSTREAM-COMMIT-NOISE\n' >&2
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

  cat >"${fake_bin}/find" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'find %s\n' "$*" >>"${COMMAND_LOG}"
if [[ "$*" == "${TEMP_ROOT}/upstream-checkout/infra -type f" ]]; then
  if [[ "${SCENARIO:-success}" == "find_failure" ]]; then
    printf 'find failed\n' >&2
    exit 31
  fi
  printf 'FIND-NOISE\n' >&2
  if [[ "${SCENARIO:-success}" == "empty_find" ]]; then
    exit 0
  fi
  printf '%s\n' \
    "${TEMP_ROOT}/upstream-checkout/infra/go.mod" \
    "${TEMP_ROOT}/upstream-checkout/infra/go.sum"
  exit 0
fi
exit 1
EOF
  chmod +x "${fake_bin}/find"

  cat >"${fake_bin}/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'shasum %s\n' "$*" >>"${COMMAND_LOG}"
content="$(cat)"
if [[ "${SCENARIO:-success}" == "empty_find" && "${content}" == *$'==  ==\n'* ]]; then
  printf 'malformed fingerprint input\n' >&2
  exit 41
fi
printf 'SHASUM-NOISE\n' >&2
printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  -\n'
EOF
  chmod +x "${fake_bin}/shasum"

  cat >"${fake_bin}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'jq %s\n' "$*" >>"${COMMAND_LOG}"
if [[ "${1:-}" != "-n" ]]; then
  exit 1
fi
printf 'JQ-NOISE\n' >&2
cat <<JSON
{
  "template_repository": "Lychee-Technology/ltbase-private-deployment",
  "template_ref": "main",
  "template_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "build_fingerprint": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "generated_at": "2026-04-13T00:00:00Z",
  "generator": "scripts/sync-template-upstream.sh"
}
JSON
EOF
  chmod +x "${fake_bin}/jq"

  cat >"${fake_bin}/tar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'tar %s\n' "$*" >>"${COMMAND_LOG}"
printf 'TAR-NOISE\n'
printf 'TAR-NOISE\n' >&2
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
  : >"${TEMP_ROOT}/upstream-checkout/.github/workflows/build-infra-binary.yml"
  printf 'module example.com/ltbase\n' >"${TEMP_ROOT}/upstream-checkout/infra/go.mod"
  printf 'sum example\n' >"${TEMP_ROOT}/upstream-checkout/infra/go.sum"
fi
exit 0
EOF
  chmod +x "${fake_bin}/tar"

  cat >"${fake_bin}/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync %s\n' "$*" >>"${COMMAND_LOG}"
printf 'RSYNC-NOISE\n'
printf 'RSYNC-NOISE\n' >&2
src="${@: -2:1}"
dest="${@: -1}"
if [[ "${SCENARIO:-success}" == "preserve_customer_owned_directory" ]]; then
  rm -rf "${dest}/customer-owned"
elif [[ "${SCENARIO:-success}" == "preserve_customer_owned_directory_contents_only" ]]; then
  rm -rf "${dest}/customer-owned"
  mkdir -p "${dest}/customer-owned"
  if [[ -d "${src}/customer-owned" ]]; then
    /bin/cp -R "${src}/customer-owned" "${dest}"
  fi
fi
mkdir -p "${dest}/__ref__"
if [[ -f "${src}/__ref__/template-provenance.json" ]]; then
  /bin/cp "${src}/__ref__/template-provenance.json" "${dest}/__ref__/template-provenance.json"
fi
exit 0
EOF
  chmod +x "${fake_bin}/rsync"

  cat >"${fake_bin}/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cp %s\n' "$*" >>"${COMMAND_LOG}"
/bin/cp "$@"
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
}

run_success_case() {
  local fake_bin="$1"
  local log_file="$2"
  setup_fake_git "${fake_bin}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" "${SCRIPT_PATH}" 2>&1)"; then
    fail "expected script to succeed, got: ${output}"
  fi

  assert_text_contains "${output}" "[info] fetching upstream template from upstream/main"
  assert_text_contains "${output}" "[info] refreshing provenance metadata"
  assert_text_contains "${output}" "[info] syncing template-managed files"
  assert_text_contains "${output}" "synced upstream/main into main"
  assert_text_not_contains "${output}" "INSIDE-WORKTREE-NOISE"
  assert_text_not_contains "${output}" "STATUS-NOISE"
  assert_text_not_contains "${output}" "BRANCH-NOISE"
  assert_text_not_contains "${output}" "REMOTE-ADD-NOISE"
  assert_text_not_contains "${output}" "FETCH-NOISE"
  assert_text_not_contains "${output}" "UPSTREAM-COMMIT-NOISE"
  assert_text_not_contains "${output}" "ARCHIVE-NOISE"
  assert_text_not_contains "${output}" "TAR-NOISE"
  assert_text_not_contains "${output}" "FIND-NOISE"
  assert_text_not_contains "${output}" "SHASUM-NOISE"
  assert_text_not_contains "${output}" "JQ-NOISE"
  assert_text_not_contains "${output}" "RSYNC-NOISE"

  assert_log_contains "${log_file}" "git rev-parse --is-inside-work-tree"
  assert_log_contains "${log_file}" "git status --porcelain"
  assert_log_contains "${log_file}" "git rev-parse --abbrev-ref HEAD"
  assert_log_contains "${log_file}" "git remote get-url upstream"
  assert_log_contains "${log_file}" "git remote add upstream https://github.com/Lychee-Technology/ltbase-private-deployment.git"
  assert_log_contains "${log_file}" "git fetch upstream"
  assert_log_contains "${log_file}" "git rev-parse upstream/main"
  assert_log_contains "${log_file}" "git archive --format=tar --output sync-template-upstream.tar upstream/main"
  assert_log_contains "${log_file}" "tar -xf sync-template-upstream.tar"
  assert_log_contains "${log_file}" "find ${temp_dir}/upstream-checkout/infra -type f"
  assert_log_contains "${log_file}" "shasum -a 256"
  assert_log_contains "${log_file}" "jq -n"
  assert_log_contains "${log_file}" "rsync -a --delete --exclude .git/ --exclude dist/ --exclude .DS_Store --exclude .env --exclude .env.* --exclude infra/Pulumi.*.yaml --exclude scripts/sync-template-upstream.sh --exclude test/sync-template-upstream-test.sh ${temp_dir}/upstream-checkout/ ./"
  assert_log_not_contains "${log_file}" "git merge --no-edit upstream/main"

  if [[ ! -f "${ROOT_DIR}/__ref__/template-provenance.json" ]]; then
    fail "expected provenance file to be written"
  fi

  assert_log_contains "${ROOT_DIR}/__ref__/template-provenance.json" '"template_repository": "Lychee-Technology/ltbase-private-deployment"'
  assert_log_contains "${ROOT_DIR}/__ref__/template-provenance.json" '"template_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
  assert_log_contains "${ROOT_DIR}/__ref__/template-provenance.json" '"build_fingerprint": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"'
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

run_upstream_commit_failure_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="upstream_commit_failure" "${SCRIPT_PATH}" >"${temp_dir}/upstream-commit-failure.out" 2>&1; then
    fail "expected script to fail when upstream commit capture fails"
  fi

  if ! grep -Fq "upstream commit failed" "${temp_dir}/upstream-commit-failure.out"; then
    fail "expected upstream commit capture failure output"
  fi
}

run_find_failure_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="find_failure" "${SCRIPT_PATH}" >"${temp_dir}/find-failure.out" 2>&1; then
    fail "expected script to fail when fingerprint file discovery fails"
  fi

  if ! grep -Fq "find failed" "${temp_dir}/find-failure.out"; then
    fail "expected fingerprint discovery failure output"
  fi
}

run_empty_find_case() {
  local fake_bin="$1"
  setup_fake_git "${fake_bin}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="empty_find" "${SCRIPT_PATH}" 2>&1)"; then
    fail "expected script to succeed when fingerprint discovery is empty, got: ${output}"
  fi

  assert_text_contains "${output}" "synced upstream/main into main"
  assert_text_not_contains "${output}" "find failed"
}

run_preserves_customer_auth_provider_case() {
  local fake_bin="$1"
  local auth_provider_path="${ROOT_DIR}/infra/auth-providers.prod.json"
  local auth_provider_backup="${temp_dir}/auth-providers.prod.json.preserve.backup"
  local original_content='{"providers":[{"name":"customer"}]}'

  setup_fake_git "${fake_bin}"
  rm -f "${auth_provider_backup}"
  if [[ -f "${auth_provider_path}" ]]; then
    /bin/cp "${auth_provider_path}" "${auth_provider_backup}"
  fi
  mkdir -p "${ROOT_DIR}/infra"
  printf '%s\n' "${original_content}" >"${auth_provider_path}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" "${SCRIPT_PATH}" 2>&1)"; then
    restore_optional_file "${auth_provider_backup}" "${auth_provider_path}"
    fail "expected script to preserve customer auth provider file, got: ${output}"
  fi

  assert_text_contains "${output}" "synced upstream/main into main"
  assert_log_contains "${auth_provider_path}" "${original_content}"
  assert_log_contains "${log_file}" "cp ./infra/auth-providers.prod.json ${temp_dir}/upstream-checkout.customer-owned-backup/infra/auth-providers.prod.json"
  assert_log_contains "${log_file}" "cp ${temp_dir}/upstream-checkout.customer-owned-backup/infra/auth-providers.prod.json ./infra/auth-providers.prod.json"
  restore_optional_file "${auth_provider_backup}" "${auth_provider_path}"
}

run_missing_customer_auth_provider_case() {
  local fake_bin="$1"
  local auth_provider_path="${ROOT_DIR}/infra/auth-providers.prod.json"
  local auth_provider_backup="${temp_dir}/auth-providers.prod.json.missing.backup"

  setup_fake_git "${fake_bin}"
  rm -f "${auth_provider_backup}"
  if [[ -f "${auth_provider_path}" ]]; then
    /bin/cp "${auth_provider_path}" "${auth_provider_backup}"
  fi
  rm -f "${auth_provider_path}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" "${SCRIPT_PATH}" 2>&1)"; then
    restore_optional_file "${auth_provider_backup}" "${auth_provider_path}"
    fail "expected script to succeed when customer auth provider file is absent, got: ${output}"
  fi

  assert_text_contains "${output}" "synced upstream/main into main"
  if [[ -e "${auth_provider_path}" ]]; then
    rm -f "${auth_provider_path}"
    restore_optional_file "${auth_provider_backup}" "${auth_provider_path}"
    fail "expected sync to leave missing customer auth provider file absent"
  fi
  restore_optional_file "${auth_provider_backup}" "${auth_provider_path}"
}

run_preserves_customer_owned_directory_case() {
  local fake_bin="$1"
  local schema_dir="${ROOT_DIR}/customer-owned/schemas"
  local schema_path="${schema_dir}/customer-owned.json"
  local original_content='{"schema":"customer-owned"}'

  setup_fake_git "${fake_bin}"
  mkdir -p "${schema_dir}"
  printf '%s\n' "${original_content}" >"${schema_path}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="preserve_customer_owned_directory" "${SCRIPT_PATH}" 2>&1)"; then
    rm -f "${schema_path}"
    fail "expected script to preserve customer-owned directory, got: ${output}"
  fi

  assert_text_contains "${output}" "synced upstream/main into main"
  if [[ ! -f "${schema_path}" ]]; then
    fail "expected sync to restore customer-owned schema file"
  fi
  assert_log_contains "${schema_path}" "${original_content}"
  rm -f "${schema_path}"
}

run_preserves_customer_owned_directory_contents_case() {
  local fake_bin="$1"
  local schema_dir="${ROOT_DIR}/customer-owned/schemas"
  local schema_path="${schema_dir}/customer-owned-contents.json"
  local nested_schema_path="${ROOT_DIR}/customer-owned/customer-owned/schemas/customer-owned-contents.json"
  local original_content='{"schema":"customer-owned-contents"}'

  setup_fake_git "${fake_bin}"
  rm -rf "${ROOT_DIR}/customer-owned/customer-owned"
  mkdir -p "${schema_dir}"
  printf '%s\n' "${original_content}" >"${schema_path}"

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" SCENARIO="preserve_customer_owned_directory_contents_only" "${SCRIPT_PATH}" 2>&1)"; then
    rm -f "${schema_path}"
    fail "expected script to preserve customer-owned directory contents, got: ${output}"
  fi

  assert_text_contains "${output}" "synced upstream/main into main"
  if [[ ! -f "${schema_path}" ]]; then
    fail "expected sync to restore customer-owned schema file in place"
  fi
  if [[ -e "${nested_schema_path}" ]]; then
    rm -f "${schema_path}"
    fail "expected sync to avoid nesting restored customer-owned data"
  fi
  assert_log_contains "${schema_path}" "${original_content}"
  rm -f "${schema_path}"
}

run_without_bootstrap_env_case() {
  local fake_bin="$1"
  local backup_path="${ROOT_DIR}/scripts/lib/bootstrap-env.sh.test-backup"
  setup_fake_git "${fake_bin}"

  mv "${ROOT_DIR}/scripts/lib/bootstrap-env.sh" "${backup_path}"
  trap 'mv "${backup_path}" "${ROOT_DIR}/scripts/lib/bootstrap-env.sh"; /bin/cp "${original_provenance}" "${provenance_path}"; rm -rf "${temp_dir}"' EXIT

  if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" TEMP_ROOT="${temp_dir}" "${SCRIPT_PATH}" 2>&1)"; then
    fail "expected script to stay runnable without bootstrap-env.sh, got: ${output}"
  fi

  assert_text_contains "${output}" "[info] fetching upstream template from upstream/main"
  assert_text_contains "${output}" "synced upstream/main into main"

  mv "${backup_path}" "${ROOT_DIR}/scripts/lib/bootstrap-env.sh"
  trap '/bin/cp "${original_provenance}" "${provenance_path}"; rm -rf "${temp_dir}"' EXIT
}

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

success_bin="${temp_dir}/success-bin"
dirty_bin="${temp_dir}/dirty-bin"
url_mismatch_bin="${temp_dir}/url-mismatch-bin"
upstream_commit_failure_bin="${temp_dir}/upstream-commit-failure-bin"
find_failure_bin="${temp_dir}/find-failure-bin"
empty_find_bin="${temp_dir}/empty-find-bin"
self_contained_bin="${temp_dir}/self-contained-bin"
preserve_auth_provider_bin="${temp_dir}/preserve-auth-provider-bin"
missing_auth_provider_bin="${temp_dir}/missing-auth-provider-bin"
preserve_customer_owned_directory_bin="${temp_dir}/preserve-customer-owned-directory-bin"
preserve_customer_owned_directory_contents_bin="${temp_dir}/preserve-customer-owned-directory-contents-bin"

run_success_case "${success_bin}" "${log_file}"
run_dirty_tree_case "${dirty_bin}"
run_url_mismatch_case "${url_mismatch_bin}"
run_upstream_commit_failure_case "${upstream_commit_failure_bin}"
run_find_failure_case "${find_failure_bin}"
run_empty_find_case "${empty_find_bin}"
run_without_bootstrap_env_case "${self_contained_bin}"
run_preserves_customer_auth_provider_case "${preserve_auth_provider_bin}"
run_missing_customer_auth_provider_case "${missing_auth_provider_bin}"
run_preserves_customer_owned_directory_case "${preserve_customer_owned_directory_bin}"
run_preserves_customer_owned_directory_contents_case "${preserve_customer_owned_directory_contents_bin}"

printf 'PASS: sync-template-upstream tests\n'
