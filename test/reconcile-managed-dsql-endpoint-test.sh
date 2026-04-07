#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/reconcile-managed-dsql-endpoint.sh"

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

write_env_file() {
  local path="$1"
  cat >"${path}" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
PULUMI_BACKEND_URL=s3://test-pulumi-state
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=eu-central-1
AWS_REGION_PROD=us-west-2
AWS_PROFILE_STAGING=staging-profile
EOF
}

write_fake_pulumi_success() {
  local path="$1"
  local log_file="$2"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'pulumi %s\n' "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "stack output" ]]; then
  printf 'abcdefghijklmnopqrstuvwx12\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${path}"
}

write_fake_pulumi_missing_identifier() {
  local path="$1"
  local log_file="$2"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'pulumi %s\n' "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "stack output" ]]; then
  printf 'error: no output value named dsqlClusterIdentifier\n' >&2
  exit 1
fi
exit 0
EOF
  chmod +x "${path}"
}

write_fake_aws_success() {
  local path="$1"
  local log_file="$2"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "dsql get-cluster" || ( "\$1" == "--profile" && "\$3 \$4" == "dsql get-cluster" ) ]]; then
  printf 'managed.cluster.endpoint.example.com\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${path}"
}

write_fake_aws_failure() {
  local path="$1"
  local log_file="$2"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "dsql get-cluster" || ( "\$1" == "--profile" && "\$3 \$4" == "dsql get-cluster" ) ]]; then
  printf 'lookup failed\n' >&2
  exit 1
fi
exit 0
EOF
  chmod +x "${path}"
}

run_success_case() {
  local temp_dir fake_bin log_file output
  temp_dir="$(mktemp -d)"
  fake_bin="${temp_dir}/bin"
  log_file="${temp_dir}/commands.log"
  mkdir -p "${fake_bin}" "${temp_dir}/infra"
  touch "${log_file}"

  write_env_file "${temp_dir}/.env"
  write_fake_pulumi_success "${fake_bin}/pulumi" "${log_file}"
  write_fake_aws_success "${fake_bin}/aws" "${log_file}"

  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected reconcile script to succeed, got: ${output}"
  fi

  assert_log_contains "${log_file}" "pulumi login s3://test-pulumi-state"
  assert_log_contains "${log_file}" "pulumi stack select devo"
  assert_log_contains "${log_file}" "pulumi stack output dsqlClusterIdentifier --stack devo"
  assert_log_contains "${log_file}" "aws dsql get-cluster --identifier abcdefghijklmnopqrstuvwx12 --region ap-northeast-1 --query endpoint --output text"
  assert_log_contains "${log_file}" "pulumi config set dsqlEndpoint managed.cluster.endpoint.example.com --stack devo"

  rm -rf "${temp_dir}"
}

run_staging_stack_case() {
  local temp_dir fake_bin log_file output
  temp_dir="$(mktemp -d)"
  fake_bin="${temp_dir}/bin"
  log_file="${temp_dir}/commands.log"
  mkdir -p "${fake_bin}" "${temp_dir}/infra"
  touch "${log_file}"

  write_env_file "${temp_dir}/.env"
  write_fake_pulumi_success "${fake_bin}/pulumi" "${log_file}"
  write_fake_aws_success "${fake_bin}/aws" "${log_file}"

  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack staging --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected reconcile script to succeed for staging, got: ${output}"
  fi

  assert_log_contains "${log_file}" "pulumi stack select staging"
  assert_log_contains "${log_file}" "pulumi stack output dsqlClusterIdentifier --stack staging"
  assert_log_contains "${log_file}" "aws --profile staging-profile dsql get-cluster --identifier abcdefghijklmnopqrstuvwx12 --region eu-central-1 --query endpoint --output text"
  assert_log_contains "${log_file}" "pulumi config set dsqlEndpoint managed.cluster.endpoint.example.com --stack staging"

  rm -rf "${temp_dir}"
}

run_missing_identifier_case() {
  local temp_dir fake_bin log_file output
  temp_dir="$(mktemp -d)"
  fake_bin="${temp_dir}/bin"
  log_file="${temp_dir}/commands.log"
  mkdir -p "${fake_bin}" "${temp_dir}/infra"
  touch "${log_file}"

  write_env_file "${temp_dir}/.env"
  write_fake_pulumi_missing_identifier "${fake_bin}/pulumi" "${log_file}"
  write_fake_aws_success "${fake_bin}/aws" "${log_file}"

  if output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected reconcile script to fail when identifier is missing"
  fi

  assert_log_contains "${log_file}" "pulumi config rm dsqlEndpoint --stack devo"
  assert_log_not_contains "${log_file}" "pulumi config set dsqlEndpoint"
  assert_log_not_contains "${log_file}" "aws dsql get-cluster"

  rm -rf "${temp_dir}"
}

run_lookup_failure_case() {
  local temp_dir fake_bin log_file output
  temp_dir="$(mktemp -d)"
  fake_bin="${temp_dir}/bin"
  log_file="${temp_dir}/commands.log"
  mkdir -p "${fake_bin}" "${temp_dir}/infra"
  touch "${log_file}"

  write_env_file "${temp_dir}/.env"
  write_fake_pulumi_success "${fake_bin}/pulumi" "${log_file}"
  write_fake_aws_failure "${fake_bin}/aws" "${log_file}"

  if output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected reconcile script to fail when lookup fails"
  fi

  assert_log_contains "${log_file}" "aws dsql get-cluster --identifier abcdefghijklmnopqrstuvwx12 --region ap-northeast-1 --query endpoint --output text"
  assert_log_contains "${log_file}" "pulumi config rm dsqlEndpoint --stack devo"
  assert_log_not_contains "${log_file}" "pulumi config set dsqlEndpoint"

  rm -rf "${temp_dir}"
}

if [[ -x "${SCRIPT_PATH}" ]]; then
  run_success_case
  run_staging_stack_case
  run_missing_identifier_case
  run_lookup_failure_case
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

printf 'PASS: reconcile-managed-dsql-endpoint tests\n'
