#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/create-deployment-repo.sh"

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
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}"
touch "${log_file}"

cat >"${temp_dir}/.env" <<'EOF'
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
PROMOTION_PATH=devo,prod
EOF

cat >"${fake_bin}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "\$*" >>"${log_file}"
scenario="\${GH_SCENARIO:-missing}"

if [[ "\${1:-} \${2:-}" == "repo view" ]]; then
  if [[ "\${scenario}" == "missing" ]]; then
    printf 'GraphQL: Could not resolve to a Repository with the name customer-org/customer-ltbase.\n' >&2
    exit 1
  fi
  if [[ "\${scenario}" == "repo-view-error" ]]; then
    printf 'HTTP 500: GitHub service unavailable\n' >&2
    exit 1
  fi
  printf 'NOISY_GH_STDOUT repo view success\n'
  printf 'NOISY_GH_STDERR repo view success\n' >&2
  exit 0
fi

if [[ "\${1:-} \${2:-} \${3:-}" == "api repos/customer-org/customer-ltbase --jq" ]]; then
  if [[ "\${scenario}" == "existing-private" ]]; then
    printf 'NOISY_GH_STDERR repo private lookup success\n' >&2
    printf 'true\n'
    exit 0
  fi
  if [[ "\${scenario}" == "existing-public" ]]; then
    printf 'NOISY_GH_STDERR repo private lookup success\n' >&2
    printf 'false\n'
    exit 0
  fi
fi

printf 'NOISY_GH_STDOUT generic success\n'
printf 'NOISY_GH_STDERR generic success\n' >&2
EOF
chmod +x "${fake_bin}/gh"

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$(PATH="${fake_bin}:$PATH" GH_SCENARIO=missing "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when implemented, got: ${output}"
  fi

  assert_log_contains "${log_file}" "gh repo create customer-org/customer-ltbase --template Lychee-Technology/ltbase-private-deployment --private --description Customer LTBase deployment repo --clone=false"
  assert_log_contains "${log_file}" "gh api repos/customer-org/customer-ltbase/environments/prod --method PUT"
  assert_log_contains <(printf '%s' "${output}") "[info] Ensuring deployment repository: customer-org/customer-ltbase"
  assert_log_contains <(printf '%s' "${output}") "[info] Ensuring protected deployment environment: prod"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDOUT"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDERR"

  : >"${log_file}"
  if ! output="$(PATH="${fake_bin}:$PATH" GH_SCENARIO=existing-private "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected existing repo rerun to succeed, got: ${output}"
  fi

  assert_log_contains "${log_file}" "gh repo view customer-org/customer-ltbase"
  assert_log_contains "${log_file}" "gh api repos/customer-org/customer-ltbase --jq .private"
  assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase --template Lychee-Technology/ltbase-private-deployment --private --description Customer LTBase deployment repo --clone=false"
  assert_log_contains "${log_file}" "gh api repos/customer-org/customer-ltbase/environments/prod --method PUT"
  assert_log_contains <(printf '%s' "${output}") "[info] Ensuring deployment repository: customer-org/customer-ltbase"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDOUT"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDERR"

  : >"${log_file}"
  if output="$(PATH="${fake_bin}:$PATH" GH_SCENARIO=existing-public "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected visibility mismatch to fail"
  fi

  if [[ "${output}" != *"existing repository visibility mismatch"* ]]; then
    rm -rf "${temp_dir}"
    fail "expected mismatch error, got: ${output}"
  fi

  : >"${log_file}"
  if output="$(PATH="${fake_bin}:$PATH" GH_SCENARIO=repo-view-error "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected repo lookup failure to fail"
  fi

  if [[ "${output}" != *"GitHub repo lookup failed"* ]] || [[ "${output}" != *"HTTP 500: GitHub service unavailable"* ]]; then
    rm -rf "${temp_dir}"
    fail "expected repo view failure output, got: ${output}"
  fi
  assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase --template Lychee-Technology/ltbase-private-deployment --private --description Customer LTBase deployment repo --clone=false"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: create-deployment-repo tests\n'
