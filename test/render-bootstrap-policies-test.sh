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

rm -rf "${temp_dir}"
printf 'PASS: render-bootstrap-policies tests\n'
