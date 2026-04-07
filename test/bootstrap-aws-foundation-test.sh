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

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
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
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=eu-central-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=345678901234
AWS_ACCOUNT_ID_PROD=210987654321
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_STAGING=staging-profile
AWS_PROFILE_PROD=prod-profile
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_STAGING=ltbase-deploy-staging
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
EOF

cat >"${fake_bin}/aws" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "\$*" >>"${log_file}"
args=("\$@")
if [[ "\${args[0]:-}" == "--profile" ]]; then
  args=("\${args[@]:2}")
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "iam get-open-id-connect-provider" ]]; then
  exit 255
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "iam get-role" ]]; then
  exit 255
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "s3api head-bucket" ]]; then
  exit 1
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "kms list-aliases" ]]; then
  printf '{"Aliases":[]}'
  exit 0
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "kms create-key" ]]; then
  printf 'key-123\n'
  exit 0
fi
if [[ "\${args[0]:-} \${args[1]:-}" == "iam create-role" ]]; then
  role_name=""
  index=0
  while [[ \$index -lt \${#args[@]} ]]; do
    if [[ "\${args[\$index]}" == "--role-name" ]]; then
      role_name="\${args[\$((index + 1))]}"
      break
    fi
    index=\$((index + 1))
  done
  if [[ "\${role_name}" == "ltbase-deploy-prod" ]]; then
    printf '{"Role":{"Arn":"arn:aws:iam::210987654321:role/ltbase-deploy-prod"}}'
  elif [[ "\${role_name}" == "ltbase-deploy-staging" ]]; then
    printf '{"Role":{"Arn":"arn:aws:iam::345678901234:role/ltbase-deploy-staging"}}'
  else
    printf '{"Role":{"Arn":"arn:aws:iam::123456789012:role/ltbase-deploy-devo"}}'
  fi
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

  assert_log_contains "${log_file}" "aws --profile devo-profile iam create-open-id-connect-provider"
  assert_log_contains "${log_file}" "aws --profile staging-profile iam create-open-id-connect-provider"
  assert_log_contains "${log_file}" "aws --profile prod-profile iam create-open-id-connect-provider"
  assert_log_contains "${log_file}" "aws --profile devo-profile iam create-role --role-name ltbase-deploy-devo"
  assert_log_contains "${log_file}" "aws --profile staging-profile iam create-role --role-name ltbase-deploy-staging"
  assert_log_contains "${log_file}" "aws --profile prod-profile iam create-role --role-name ltbase-deploy-prod"
  assert_log_contains "${log_file}" "aws --profile devo-profile iam put-role-policy --role-name ltbase-deploy-devo --policy-name LTBaseDeploymentAccess"
  assert_log_contains "${log_file}" "aws --profile staging-profile iam put-role-policy --role-name ltbase-deploy-staging --policy-name LTBaseDeploymentAccess"
  assert_log_contains "${log_file}" "aws --profile prod-profile iam put-role-policy --role-name ltbase-deploy-prod --policy-name LTBaseDeploymentAccess"
  assert_log_contains "${log_file}" "aws --profile devo-profile s3api create-bucket --bucket test-pulumi-state --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1"
  assert_log_contains "${log_file}" "aws --profile devo-profile kms create-key --region ap-northeast-1"
  assert_log_contains "${log_file}" "aws --profile staging-profile kms create-key --region eu-central-1"
  assert_log_contains "${log_file}" "aws --profile prod-profile kms create-key --region us-west-2"
  assert_file_contains "${temp_dir}/dist/foundation.env" "AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/ltbase-deploy-devo"
  assert_file_contains "${temp_dir}/dist/foundation.env" "AWS_ROLE_ARN_STAGING=arn:aws:iam::345678901234:role/ltbase-deploy-staging"
  assert_file_contains "${temp_dir}/dist/foundation.env" "AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/ltbase-deploy-prod"
  assert_file_contains "${temp_dir}/dist/foundation.env" "PULUMI_BACKEND_URL=s3://test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/foundation.env" "PULUMI_SECRETS_PROVIDER_DEVO=awskms://alias/test-pulumi-secrets?region=ap-northeast-1"
  assert_file_contains "${temp_dir}/dist/foundation.env" "PULUMI_SECRETS_PROVIDER_STAGING=awskms://alias/test-pulumi-secrets?region=eu-central-1"
  assert_file_contains "${temp_dir}/dist/foundation.env" "PULUMI_SECRETS_PROVIDER_PROD=awskms://alias/test-pulumi-secrets?region=us-west-2"
  assert_file_contains "${temp_dir}/dist/devo-trust-policy.json" "repo:customer-org/customer-ltbase:ref:refs/heads/main"
  assert_file_contains "${temp_dir}/dist/devo-trust-policy.json" "repo:customer-org/customer-ltbase:pull_request"
  assert_file_contains "${temp_dir}/dist/staging-trust-policy.json" "arn:aws:iam::345678901234:oidc-provider/token.actions.githubusercontent.com"
  assert_file_contains "${temp_dir}/dist/staging-role-policy.json" "arn:aws:iam::345678901234:role/ltbase-deploy-staging"
  assert_file_contains "${temp_dir}/dist/prod-trust-policy.json" "repo:customer-org/customer-ltbase:ref:refs/heads/release/*"
  assert_file_contains "${temp_dir}/dist/devo-role-policy.json" "arn:aws:s3:::test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/prod-role-policy.json" "arn:aws:iam::210987654321:role/ltbase-deploy-prod"
  assert_file_not_contains "${temp_dir}/dist/devo-trust-policy.json" "arn:aws:iam::210987654321:oidc-provider"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

cat >"${temp_dir}/missing-profiles.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
EOF

if PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/missing-profiles.env" --output-dir "${temp_dir}/dist-missing" >"${temp_dir}/missing.log" 2>&1; then
  rm -rf "${temp_dir}"
  fail "expected split-account bootstrap to fail without AWS profiles"
fi

assert_log_contains "${temp_dir}/missing.log" "AWS profile is required for stack"

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-aws-foundation tests\n'
