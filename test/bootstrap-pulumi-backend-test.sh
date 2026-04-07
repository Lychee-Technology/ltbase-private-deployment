#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-pulumi-backend.sh"

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
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=eu-central-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=345678901234
AWS_ACCOUNT_ID_PROD=210987654321
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_STAGING=staging-profile
AWS_PROFILE_PROD=prod-profile
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/test-deploy-role
AWS_ROLE_ARN_STAGING=arn:aws:iam::345678901234:role/test-staging-role
AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/test-prod-role
EOF

cat >"${fake_bin}/aws" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "\$*" >>"${log_file}"
args=("\$@")
if [[ "\${args[0]:-}" == "--profile" ]]; then
  args=("\${args[@]:2}")
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "s3api head-bucket" ]]; then
  exit 1
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "kms list-aliases" ]]; then
  printf '{"Aliases":[]}'
  exit 0
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "kms create-key" ]]; then
  printf '{"KeyMetadata":{"KeyId":"key-123"}}'
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

  assert_file_contains "${temp_dir}/dist/pulumi-backend.env" "PULUMI_BACKEND_URL=s3://test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/pulumi-backend.env" "PULUMI_SECRETS_PROVIDER_DEVO=awskms://alias/test-pulumi-secrets?region=ap-northeast-1"
  assert_file_contains "${temp_dir}/dist/pulumi-backend.env" "PULUMI_SECRETS_PROVIDER_STAGING=awskms://alias/test-pulumi-secrets?region=eu-central-1"
  assert_file_contains "${temp_dir}/dist/pulumi-backend.env" "PULUMI_SECRETS_PROVIDER_PROD=awskms://alias/test-pulumi-secrets?region=us-west-2"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "kms:Decrypt"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "arn:aws:iam::123456789012:role/test-deploy-role"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "arn:aws:iam::345678901234:role/test-staging-role"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "arn:aws:iam::210987654321:role/test-prod-role"
  assert_log_contains "${log_file}" "aws --profile devo-profile s3api create-bucket --bucket test-pulumi-state --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1"
  assert_log_contains "${log_file}" "aws --profile devo-profile kms create-key --region ap-northeast-1 --description Pulumi secrets for LTBase private deployment --query KeyMetadata.KeyId --output text"
  assert_log_contains "${log_file}" "aws --profile staging-profile kms create-key --region eu-central-1 --description Pulumi secrets for LTBase private deployment --query KeyMetadata.KeyId --output text"
  assert_log_contains "${log_file}" "aws --profile prod-profile kms create-key --region us-west-2 --description Pulumi secrets for LTBase private deployment --query KeyMetadata.KeyId --output text"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-pulumi-backend tests\n'
