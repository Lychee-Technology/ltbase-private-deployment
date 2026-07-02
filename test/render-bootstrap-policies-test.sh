#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/render-bootstrap-policies.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
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

cat >"${temp_dir}/.env" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=eu-central-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=345678901234
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_STAGING=ltbase-deploy-staging
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/ltbase-deploy-devo
AWS_ROLE_ARN_STAGING=arn:aws:iam::345678901234:role/ltbase-deploy-staging
AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
EOF

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$("${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when implemented, got: ${output}"
  fi

  assert_file_contains "${temp_dir}/dist/devo-trust-policy.json" "token.actions.githubusercontent.com"
  assert_file_contains "${temp_dir}/dist/devo-trust-policy.json" "repo:customer-org/customer-ltbase"
  assert_file_contains "${temp_dir}/dist/staging-trust-policy.json" "arn:aws:iam::345678901234:oidc-provider/token.actions.githubusercontent.com"
  assert_file_contains "${temp_dir}/dist/prod-trust-policy.json" "arn:aws:iam::210987654321:oidc-provider/token.actions.githubusercontent.com"
  assert_file_contains "${temp_dir}/dist/devo-role-policy.json" "arn:aws:s3:::test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/staging-role-policy.json" "arn:aws:iam::345678901234:role/ltbase-deploy-staging"
  assert_file_contains "${temp_dir}/dist/prod-role-policy.json" "kms:Decrypt"
  assert_file_contains "${temp_dir}/dist/devo-role-policy.json" "\"Action\": \"*\""
  assert_file_contains "${temp_dir}/dist/devo-role-policy.json" "\"Resource\": \"*\""
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "iam:CreateOpenIDConnectProvider"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "arn:aws:iam::123456789012:role/ltbase-deploy-devo"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "kms:CreateAlias"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "kms:Encrypt"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "kms:Decrypt"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-devo-policy.json" "kms:GenerateDataKey"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-staging-policy.json" "arn:aws:iam::345678901234:role/ltbase-deploy-staging"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-prod-policy.json" "arn:aws:iam::210987654321:role/ltbase-deploy-prod"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "arn:aws:s3:::test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "s3:CreateBucket"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "s3:PutBucketVersioning"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "s3:GetObject"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "s3:PutObject"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "arn:aws:s3:::test-pulumi-state/*"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "s3:GetBucketPolicy"
  assert_file_contains "${temp_dir}/dist/bootstrap-operator-first-stack-s3-policy.json" "s3:PutBucketPolicy"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "arn:aws:s3:::test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "arn:aws:s3:::test-pulumi-state/*"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "arn:aws:iam::123456789012:role/ltbase-deploy-devo"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "arn:aws:iam::345678901234:role/ltbase-deploy-staging"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "arn:aws:iam::210987654321:role/ltbase-deploy-prod"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "s3:ListBucket"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "s3:PutObject"
  assert_file_contains "${temp_dir}/dist/pulumi-backend-bucket-policy.json" "s3:DeleteObject"
  assert_file_contains "${temp_dir}/dist/bootstrap-summary.env" "PULUMI_SECRETS_PROVIDER_DEVO=awskms://alias/test-pulumi-secrets?region=ap-northeast-1"
  assert_file_contains "${temp_dir}/dist/bootstrap-summary.env" "PULUMI_SECRETS_PROVIDER_STAGING=awskms://alias/test-pulumi-secrets?region=eu-central-1"
  assert_file_contains "${temp_dir}/dist/bootstrap-summary.env" "PULUMI_SECRETS_PROVIDER_PROD=awskms://alias/test-pulumi-secrets?region=us-west-2"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

cat >"${temp_dir}/derived-arns.env" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=eu-central-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=345678901234
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_STAGING=ltbase-deploy-staging
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
EOF

if ! output="$("${SCRIPT_PATH}" --env-file "${temp_dir}/derived-arns.env" --output-dir "${temp_dir}/dist-derived" 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected script to derive AWS role ARNs, got: ${output}"
fi

assert_file_contains "${temp_dir}/dist-derived/bootstrap-summary.env" "AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/ltbase-deploy-devo"
assert_file_contains "${temp_dir}/dist-derived/bootstrap-summary.env" "AWS_ROLE_ARN_STAGING=arn:aws:iam::345678901234:role/ltbase-deploy-staging"
assert_file_contains "${temp_dir}/dist-derived/bootstrap-summary.env" "AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/ltbase-deploy-prod"

cat >"${temp_dir}/single-stack.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
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

if ! output="$("${SCRIPT_PATH}" --env-file "${temp_dir}/single-stack.env" --output-dir "${temp_dir}/dist-single" 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected script to ignore non-active stack ARN requirements, got: ${output}"
fi

assert_file_contains "${temp_dir}/dist-single/bootstrap-summary.env" "AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/ltbase-deploy-devo"
assert_file_not_contains "${temp_dir}/dist-single/bootstrap-summary.env" "AWS_ROLE_ARN_PROD="

cat >"${temp_dir}/extra-principals.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS=arn:aws:iam::210987654321:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_Admin_abc123
EOF

if ! output="$("${SCRIPT_PATH}" --env-file "${temp_dir}/extra-principals.env" --output-dir "${temp_dir}/dist-extra" 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected script to accept extra backend principals, got: ${output}"
fi

assert_file_contains "${temp_dir}/dist-extra/pulumi-backend-bucket-policy.json" "arn:aws:iam::123456789012:role/ltbase-deploy-devo"
assert_file_contains "${temp_dir}/dist-extra/pulumi-backend-bucket-policy.json" "arn:aws:iam::210987654321:role/ltbase-deploy-prod"
assert_file_contains "${temp_dir}/dist-extra/pulumi-backend-bucket-policy.json" "arn:aws:iam::210987654321:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_Admin_abc123"

# The rendered backend bucket policy must include the operator identities that
# bootstrap-aws-foundation.sh derives from AWS_PROFILE_<STACK> at apply time,
# so a manually reviewed/applied policy matches the bootstrap-applied one.
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}"
touch "${log_file}"

cat >"${fake_bin}/aws" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "\$*" >>"${log_file}"
if [[ "\$*" == *"sts get-caller-identity"* && "\$*" == *"--query Arn"* ]]; then
  if [[ "\${AWS_BEHAVIOR:-}" == "sts-unavailable" ]]; then
    exit 254
  fi
  printf 'arn:aws:sts::999999999999:assumed-role/AWSReservedSSO_Admin_test/alice\n'
  exit 0
fi
if [[ "\$*" == *"configure get sso_region"* ]]; then
  printf 'us-west-2\n'
  exit 0
fi
exit 1
EOF
chmod +x "${fake_bin}/aws"

cat >"${temp_dir}/profile-principals.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
DEPLOYMENT_REPO=customer-org/customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
AWS_PROFILE_PROD=prod-profile
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
EOF

if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/profile-principals.env" --output-dir "${temp_dir}/dist-profile" 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected script to derive profile-based backend principals, got: ${output}"
fi

assert_file_contains "${temp_dir}/dist-profile/pulumi-backend-bucket-policy.json" "arn:aws:iam::123456789012:role/ltbase-deploy-devo"
assert_file_contains "${temp_dir}/dist-profile/pulumi-backend-bucket-policy.json" "arn:aws:iam::210987654321:role/ltbase-deploy-prod"
assert_file_contains "${temp_dir}/dist-profile/pulumi-backend-bucket-policy.json" "arn:aws:iam::999999999999:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_Admin_test"
if ! printf '%s' "${output}" | grep -Fq "Derived Pulumi backend principal for stack prod"; then
  rm -rf "${temp_dir}"
  fail "expected render output to note the derived principal, got: ${output}"
fi

# Rendering must stay usable without live AWS credentials: unresolvable
# profiles are skipped and the policy keeps only the stack deploy roles.
if ! output="$(PATH="${fake_bin}:$PATH" AWS_BEHAVIOR=sts-unavailable "${SCRIPT_PATH}" --env-file "${temp_dir}/profile-principals.env" --output-dir "${temp_dir}/dist-nocreds" 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected script to tolerate unavailable AWS credentials, got: ${output}"
fi

assert_file_contains "${temp_dir}/dist-nocreds/pulumi-backend-bucket-policy.json" "arn:aws:iam::123456789012:role/ltbase-deploy-devo"
assert_file_contains "${temp_dir}/dist-nocreds/pulumi-backend-bucket-policy.json" "arn:aws:iam::210987654321:role/ltbase-deploy-prod"
assert_file_not_contains "${temp_dir}/dist-nocreds/pulumi-backend-bucket-policy.json" "AWSReservedSSO_Admin_test"

rm -rf "${temp_dir}"
printf 'PASS: render-bootstrap-policies tests\n'
