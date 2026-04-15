#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/reconcile-project-info.sh"

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
third="\${3:-}"
if [[ "\$1 \$2" == "stack output" && "\${third}" == "projectId" ]]; then
  printf '11111111-1111-4111-8111-111111111111\n'
  exit 0
fi
if [[ "\$1 \$2" == "stack output" && "\${third}" == "apiId" ]]; then
  printf 'api-123456\n'
  exit 0
fi
if [[ "\$1 \$2" == "stack output" && "\${third}" == "apiBaseUrl" ]]; then
  printf 'https://api.example.com\n'
  exit 0
fi
if [[ "\$1 \$2" == "stack output" && "\${third}" == "tableName" ]]; then
  printf 'ltbase-table\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${path}"
}

write_fake_pulumi_missing_output() {
  local path="$1"
  local log_file="$2"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'pulumi %s\n' "\$*" >>"${log_file}"
third="\${3:-}"
if [[ "\$1 \$2" == "stack output" && "\${third}" == "apiId" ]]; then
  printf 'error: no output value named apiId\n' >&2
  exit 1
fi
if [[ "\$1 \$2" == "stack output" && "\${third}" == "projectId" ]]; then
  printf '11111111-1111-4111-8111-111111111111\n'
  exit 0
fi
if [[ "\$1 \$2" == "stack output" && "\${third}" == "apiBaseUrl" ]]; then
  printf 'https://api.example.com\n'
  exit 0
fi
if [[ "\$1 \$2" == "stack output" && "\${third}" == "tableName" ]]; then
  printf 'ltbase-table\n'
  exit 0
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
if [[ "\$1 \$2" == "sts get-caller-identity" || ( "\$1" == "--profile" && "\$3 \$4" == "sts get-caller-identity" ) ]]; then
  printf '{"Account":"123456789012"}\n'
  exit 0
fi
if [[ "\$1 \$2" == "dynamodb put-item" || ( "\$1" == "--profile" && "\$3 \$4" == "dynamodb put-item" ) ]]; then
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
if [[ "\$1 \$2" == "dynamodb put-item" || ( "\$1" == "--profile" && "\$3 \$4" == "dynamodb put-item" ) ]]; then
  printf 'put failed\n' >&2
  exit 1
fi
if [[ "\$1 \$2" == "sts get-caller-identity" || ( "\$1" == "--profile" && "\$3 \$4" == "sts get-caller-identity" ) ]]; then
  printf '{"Account":"123456789012"}\n'
  exit 0
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
  assert_log_contains "${log_file}" "pulumi stack output projectId --stack devo"
  assert_log_contains "${log_file}" "pulumi stack output apiId --stack devo"
  assert_log_contains "${log_file}" "pulumi stack output apiBaseUrl --stack devo"
  assert_log_contains "${log_file}" "pulumi stack output tableName --stack devo"
  assert_log_contains "${log_file}" "aws sts get-caller-identity --query Account --output text"
  assert_log_contains "${log_file}" "aws dynamodb put-item --table-name ltbase-table"
  assert_log_contains "${log_file}" '"PK":{"S":"project#11111111-1111-4111-8111-111111111111"}'
  assert_log_contains "${log_file}" '"api_id":{"S":"api-123456"}'
  assert_log_contains "${log_file}" '"api_base_url":{"S":"https://api.example.com"}'

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
  assert_log_contains "${log_file}" "aws --profile staging-profile sts get-caller-identity --query Account --output text"
  assert_log_contains "${log_file}" "aws --profile staging-profile dynamodb put-item --table-name ltbase-table"

  rm -rf "${temp_dir}"
}

run_missing_output_case() {
  local temp_dir fake_bin log_file output
  temp_dir="$(mktemp -d)"
  fake_bin="${temp_dir}/bin"
  log_file="${temp_dir}/commands.log"
  mkdir -p "${fake_bin}" "${temp_dir}/infra"
  touch "${log_file}"

  write_env_file "${temp_dir}/.env"
  write_fake_pulumi_missing_output "${fake_bin}/pulumi" "${log_file}"
  write_fake_aws_success "${fake_bin}/aws" "${log_file}"

  if output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected reconcile script to fail when an output is missing"
  fi

  assert_log_contains "${log_file}" "pulumi stack output apiId --stack devo"
  assert_log_not_contains "${log_file}" "aws dynamodb put-item"

  rm -rf "${temp_dir}"
}

run_put_failure_case() {
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
    fail "expected reconcile script to fail when put-item fails"
  fi

  assert_log_contains "${log_file}" "aws dynamodb put-item --table-name ltbase-table"

  rm -rf "${temp_dir}"
}

if [[ -x "${SCRIPT_PATH}" ]]; then
  run_success_case
  run_staging_stack_case
  run_missing_output_case
  run_put_failure_case
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

printf 'PASS: reconcile-project-info tests\n'
