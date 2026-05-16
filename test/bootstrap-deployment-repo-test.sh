#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-deployment-repo.sh"

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

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}" "${temp_dir}/infra"
touch "${log_file}"

cat >"${temp_dir}/.env" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
GITHUB_OWNER=Lychee-Technology
DEPLOYMENT_REPO_NAME=ltbase-private-deployment
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=us-east-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=123456789012
AWS_ACCOUNT_ID_PROD=123456789012
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_STAGING=staging-profile
AWS_PROFILE_PROD=prod-profile
AWS_ROLE_NAME_DEVO=test-deploy-role
AWS_ROLE_NAME_STAGING=test-staging-role
AWS_ROLE_NAME_PROD=test-prod-role
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases
LTBASE_RELEASE_ID=v1.0.0
LTBASE_RELEASES_TOKEN=test-release-token
CLOUDFLARE_API_TOKEN=test-cloudflare-token
GEMINI_API_KEY=test-gemini-key
API_DOMAIN_DEVO=api.devo.example.com
API_DOMAIN_STAGING=api.staging.example.com
API_DOMAIN_PROD=api.example.com
CONTROL_DOMAIN_DEVO=control.devo.example.com
CONTROL_DOMAIN_STAGING=control.staging.example.com
CONTROL_DOMAIN_PROD=control.example.com
AUTH_DOMAIN_DEVO=auth.devo.example.com
AUTH_DOMAIN_STAGING=auth.staging.example.com
AUTH_DOMAIN_PROD=auth.example.com
PROJECT_ID=33333333-3333-4333-8333-333333333333
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
AUTH_PROVIDER_CONFIG_FILE_STAGING=infra/auth-providers.staging.json
AUTH_PROVIDER_CONFIG_FILE_PROD=infra/auth-providers.prod.json
CLOUDFLARE_ZONE_ID=zone-123
OIDC_ISSUER_URL_DEVO=https://issuer.example.com/devo
OIDC_ISSUER_URL_STAGING=https://issuer.example.com/staging
OIDC_ISSUER_URL_PROD=https://issuer.example.com/prod
JWKS_URL_DEVO=https://issuer.example.com/devo/jwks.json
JWKS_URL_STAGING=https://issuer.example.com/staging/jwks.json
JWKS_URL_PROD=https://issuer.example.com/prod/jwks.json
GEMINI_MODEL=gemini-3.1-flash-lite
DSQL_PORT=5432
DSQL_DB=postgres
DSQL_USER=admin
DSQL_PROJECT_SCHEMA=ltbase
MTLS_TRUSTSTORE_FILE=infra/certs/cloudflare-origin-pull-ca.pem
MTLS_TRUSTSTORE_KEY=mtls/cloudflare-origin-pull-ca.pem
EOF

cat >"${fake_bin}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'NOISY GH STDOUT %s\n' "\$*"
printf 'NOISY GH STDERR %s\n' "\$*" >&2
printf 'gh %s\n' "\$*" >>"${log_file}"
if [[ "\${GH_FAIL_FIRST:-0}" == "1" ]]; then
  exit 1
fi
EOF
chmod +x "${fake_bin}/gh"

cat >"${fake_bin}/pulumi" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'NOISY PULUMI STDOUT %s\n' "\$*"
printf 'NOISY PULUMI STDERR %s\n' "\$*" >&2
printf 'PWD=%s AWS_REGION=%s AWS_DEFAULT_REGION=%s AWS_PROFILE=%s pulumi %s\n' "\$PWD" "\${AWS_REGION:-}" "\${AWS_DEFAULT_REGION:-}" "\${AWS_PROFILE:-}" "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "stack select" ]]; then
  case "\${PULUMI_STACK_SELECT_MODE:-missing}" in
    missing)
      printf 'error: no stack named %s found\n' "\${3:-}" >&2
      exit 1
      ;;
    unexpected)
      printf 'error: backend unavailable\n' >&2
      exit 1
      ;;
    existing)
      exit 0
      ;;
  esac
fi
if [[ "\${PULUMI_FAIL_COMMAND:-}" == "\$*" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "${fake_bin}/pulumi"

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack prod --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when implemented, got: ${output}"
  fi

  assert_log_contains <(printf '%s' "${output}") "[info] configuring repository variables and secrets for Lychee-Technology/ltbase-private-deployment"
  assert_log_contains <(printf '%s' "${output}") "[info] configuring Pulumi stack prod"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY GH STDOUT"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY GH STDERR"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY PULUMI STDOUT"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY PULUMI STDERR"

  assert_log_contains "${log_file}" "gh variable set AWS_REGION_DEVO --repo Lychee-Technology/ltbase-private-deployment --body ap-northeast-1"
  assert_log_contains "${log_file}" "gh variable set AWS_REGION_STAGING --repo Lychee-Technology/ltbase-private-deployment --body us-east-1"
  assert_log_contains "${log_file}" "gh variable set AWS_REGION_PROD --repo Lychee-Technology/ltbase-private-deployment --body us-west-2"
  assert_log_contains "${log_file}" "gh variable set SCHEMA_BUCKET_DEVO --repo Lychee-Technology/ltbase-private-deployment --body ltbase-private-deployment-schema-devo"
  assert_log_contains "${log_file}" "gh variable set SCHEMA_BUCKET_STAGING --repo Lychee-Technology/ltbase-private-deployment --body ltbase-private-deployment-schema-staging"
  assert_log_contains "${log_file}" "gh variable set SCHEMA_BUCKET_PROD --repo Lychee-Technology/ltbase-private-deployment --body ltbase-private-deployment-schema-prod"
  assert_log_contains "${log_file}" "gh variable set STACKS --repo Lychee-Technology/ltbase-private-deployment --body devo,staging,prod"
  assert_log_contains "${log_file}" "gh variable set PROMOTION_PATH --repo Lychee-Technology/ltbase-private-deployment --body devo,staging,prod"
  assert_log_contains "${log_file}" "gh variable set PREVIEW_DEFAULT_STACK --repo Lychee-Technology/ltbase-private-deployment --body devo"
  assert_log_contains "${log_file}" "gh secret set AWS_ROLE_ARN_DEVO --repo Lychee-Technology/ltbase-private-deployment --body arn:aws:iam::123456789012:role/test-deploy-role"
  assert_log_contains "${log_file}" "gh secret set AWS_ROLE_ARN_STAGING --repo Lychee-Technology/ltbase-private-deployment --body arn:aws:iam::123456789012:role/test-staging-role"
  assert_log_contains "${log_file}" "gh secret set AWS_ROLE_ARN_PROD --repo Lychee-Technology/ltbase-private-deployment --body arn:aws:iam::123456789012:role/test-prod-role"
  assert_log_contains "${log_file}" "AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1 AWS_PROFILE=devo-profile pulumi login s3://test-pulumi-state"
  assert_log_contains "${log_file}" "PWD=${temp_dir}/infra AWS_REGION=us-west-2 AWS_DEFAULT_REGION=us-west-2 AWS_PROFILE=prod-profile pulumi stack init prod --secrets-provider awskms://alias/test-pulumi-secrets?region=us-west-2"
  assert_log_contains "${log_file}" "pulumi config set runtimeBucket ltbase-private-deployment-runtime-prod --stack prod"
  assert_log_contains "${log_file}" "pulumi config set schemaBucket ltbase-private-deployment-schema-prod --stack prod"
  assert_log_contains "${log_file}" "pulumi config set apiDomain api.example.com --stack prod"
  assert_log_contains "${log_file}" "pulumi config set projectId 33333333-3333-4333-8333-333333333333 --stack prod"
  assert_log_contains "${log_file}" "pulumi config set authProviderConfigFile infra/auth-providers.prod.json --stack prod"
  assert_log_contains "${log_file}" "pulumi config set oidcIssuerUrl https://issuer.example.com/prod --stack prod"
  assert_log_contains "${log_file}" "pulumi config set deploymentAwsAccountId 123456789012 --stack prod"
  assert_log_contains "${log_file}" "pulumi config set githubOidcProviderArn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com --stack prod"
  assert_log_contains "${log_file}" "pulumi config set tableName ltbase-private-deployment-prod --stack prod"
  assert_log_contains "${log_file}" "pulumi config set mtlsTruststoreFile infra/certs/cloudflare-origin-pull-ca.pem --stack prod"
  assert_log_contains "${log_file}" "pulumi config set mtlsTruststoreKey mtls/cloudflare-origin-pull-ca.pem --stack prod"
  assert_log_contains "${log_file}" "pulumi config set dsqlDB postgres --stack prod"
  assert_log_contains "${log_file}" "pulumi config set dsqlUser admin --stack prod"
  assert_log_contains "${log_file}" "pulumi config set --secret geminiApiKey test-gemini-key --stack prod"
  assert_log_not_contains "${log_file}" "pulumi stack output dsqlClusterIdentifier"
  assert_log_not_contains "${log_file}" "pulumi up --stack prod --yes --skip-preview"
  assert_log_not_contains "${log_file}" "pulumi config set dsqlEndpoint"
  assert_log_not_contains "${log_file}" "aws dsql get-cluster"

  if output="$(GH_FAIL_FIRST=1 PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack prod --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to fail when gh fails"
  fi

  first_output_line="$(printf '%s\n' "${output}" | sed -n '1p')"
  assert_equals "[info] configuring repository variables and secrets for Lychee-Technology/ltbase-private-deployment" "${first_output_line}"
  assert_log_contains <(printf '%s' "${output}") "NOISY GH STDOUT variable set AWS_REGION_DEVO --repo Lychee-Technology/ltbase-private-deployment --body ap-northeast-1"
  assert_log_contains <(printf '%s' "${output}") "NOISY GH STDERR variable set AWS_REGION_DEVO --repo Lychee-Technology/ltbase-private-deployment --body ap-northeast-1"

  if output="$(PULUMI_FAIL_COMMAND="config set schemaBucket ltbase-private-deployment-schema-prod --stack prod" PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack prod --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to fail when pulumi fails"
  fi

  assert_log_contains <(printf '%s' "${output}") "[info] configuring Pulumi stack prod"
  assert_log_contains <(printf '%s' "${output}") "NOISY PULUMI STDOUT config set schemaBucket ltbase-private-deployment-schema-prod --stack prod"
  assert_log_contains <(printf '%s' "${output}") "NOISY PULUMI STDERR config set schemaBucket ltbase-private-deployment-schema-prod --stack prod"

  : >"${log_file}"
  if ! output="$(PULUMI_STACK_SELECT_MODE=existing PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack prod --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when stack already exists, got: ${output}"
  fi

  assert_log_contains <(printf '%s' "${output}") "[info] configuring Pulumi stack prod"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY PULUMI STDOUT"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY PULUMI STDERR"
  assert_log_contains "${log_file}" "pulumi stack select prod"
  assert_log_not_contains "${log_file}" "pulumi stack init prod --secrets-provider awskms://alias/test-pulumi-secrets?region=us-west-2"

  : >"${log_file}"
  if output="$(PULUMI_STACK_SELECT_MODE=unexpected PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack prod --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to fail when stack select fails unexpectedly"
  fi

  assert_log_contains <(printf '%s' "${output}") "[info] configuring Pulumi stack prod"
  assert_log_contains <(printf '%s' "${output}") "NOISY PULUMI STDOUT stack select prod"
  assert_log_contains <(printf '%s' "${output}") "NOISY PULUMI STDERR stack select prod"
  assert_log_contains <(printf '%s' "${output}") "error: backend unavailable"
  assert_log_not_contains "${log_file}" "pulumi stack init prod --secrets-provider awskms://alias/test-pulumi-secrets?region=us-west-2"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-deployment-repo tests\n'
