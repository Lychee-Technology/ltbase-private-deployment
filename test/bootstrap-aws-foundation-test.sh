#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-aws-foundation.sh"

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

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}"
touch "${log_file}"

cat >"${temp_dir}/.env" <<'EOF'
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/ltbase-deploy-devo
AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
EOF

cat >"${fake_bin}/aws" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "kms create-key" ]]; then
  printf 'key-123\n'
  exit 0
fi
if [[ "\$1 \$2" == "iam create-role" ]]; then
  printf '{"Role":{"Arn":"arn:aws:iam::123456789012:role/generated"}}'
  exit 0
fi
exit 0
EOF
chmod +x "${fake_bin}/aws"

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when implemented, got: ${output}"
  fi

  assert_log_contains "${log_file}" "aws iam create-open-id-connect-provider"
  assert_log_contains "${log_file}" "aws iam create-role --role-name ltbase-deploy-devo"
  assert_log_contains "${log_file}" "aws iam create-role --role-name ltbase-deploy-prod"
  assert_log_contains "${log_file}" "aws s3api create-bucket --bucket test-pulumi-state --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1"
  assert_file_contains "${temp_dir}/dist/foundation.env" "AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/ltbase-deploy-devo"
  assert_file_contains "${temp_dir}/dist/foundation.env" "AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/ltbase-deploy-prod"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-aws-foundation tests\n'
