#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-all.sh"

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
repo_copy="${temp_dir}/repo"
log_file="${temp_dir}/commands.log"
mkdir -p "${repo_copy}" "${temp_dir}/infra"
touch "${log_file}"

cp -R "${ROOT_DIR}/." "${repo_copy}"

create_stub() {
  local name="$1"
  cat >"${repo_copy}/scripts/${name}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'NOISY STDOUT from ${name}\n'
printf 'NOISY STDERR from ${name}\n' >&2
printf '%s %s\n' '${name}' "\$*" >>"${log_file}"
if [[ "\${FAIL_SCRIPT:-}" == "${name}" ]]; then
  exit 1
fi
EOF
  chmod +x "${repo_copy}/scripts/${name}"
}

cat >"${temp_dir}/.env" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=us-east-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_STAGING=ltbase-deploy-staging
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases
LTBASE_RELEASE_ID=v1.0.0
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
GEMINI_API_KEY=test-gemini-key
CLOUDFLARE_API_TOKEN=test-cloudflare-token
LTBASE_RELEASES_TOKEN=test-release-token
EOF

for name in render-bootstrap-policies.sh create-deployment-repo.sh bootstrap-aws-foundation.sh bootstrap-oidc-discovery-companion.sh bootstrap-deployment-repo.sh reconcile-managed-dsql-endpoint.sh; do
  create_stub "${name}"
done

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$("${repo_copy}/scripts/bootstrap-all.sh" --env-file "${temp_dir}/.env" --mode apply --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected orchestrator to succeed when implemented, got: ${output}"
  fi

  assert_log_contains <(printf '%s' "${output}") "[info] ensuring deployment repository"
  assert_log_contains <(printf '%s' "${output}") "[info] rendering bootstrap policies"
  assert_log_contains <(printf '%s' "${output}") "[info] bootstrapping AWS foundation"
  assert_log_contains <(printf '%s' "${output}") "[info] ensuring OIDC discovery companion"
  assert_log_contains <(printf '%s' "${output}") "[info] configuring stack devo"
  assert_log_contains <(printf '%s' "${output}") "[info] configuring stack staging"
  assert_log_contains <(printf '%s' "${output}") "[info] configuring stack prod"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY STDOUT"
  assert_log_not_contains <(printf '%s' "${output}") "NOISY STDERR"

  assert_log_contains "${log_file}" "create-deployment-repo.sh --env-file ${temp_dir}/.env"
  assert_log_contains "${log_file}" "render-bootstrap-policies.sh --env-file ${temp_dir}/.env"
  assert_log_contains "${log_file}" "bootstrap-aws-foundation.sh --env-file ${temp_dir}/.env"
  assert_log_contains "${log_file}" "bootstrap-oidc-discovery-companion.sh --env-file ${temp_dir}/.env"
  assert_log_contains "${log_file}" "bootstrap-deployment-repo.sh --env-file ${temp_dir}/.env --stack devo --infra-dir ${temp_dir}/infra"
  assert_log_contains "${log_file}" "bootstrap-deployment-repo.sh --env-file ${temp_dir}/.env --stack staging --infra-dir ${temp_dir}/infra"
  assert_log_contains "${log_file}" "bootstrap-deployment-repo.sh --env-file ${temp_dir}/.env --stack prod --infra-dir ${temp_dir}/infra"
  assert_log_not_contains "${log_file}" "reconcile-managed-dsql-endpoint.sh --env-file ${temp_dir}/.env --stack devo --infra-dir ${temp_dir}/infra"
  assert_log_not_contains "${log_file}" "reconcile-managed-dsql-endpoint.sh --env-file ${temp_dir}/.env --stack staging --infra-dir ${temp_dir}/infra"
  assert_log_not_contains "${log_file}" "reconcile-managed-dsql-endpoint.sh --env-file ${temp_dir}/.env --stack prod --infra-dir ${temp_dir}/infra"

  if output="$(FAIL_SCRIPT="bootstrap-aws-foundation.sh" "${repo_copy}/scripts/bootstrap-all.sh" --env-file "${temp_dir}/.env" --mode apply --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected orchestrator to fail when a child script fails"
  fi

  assert_log_contains <(printf '%s' "${output}") "[info] bootstrapping AWS foundation"
  assert_log_contains <(printf '%s' "${output}") "NOISY STDOUT from bootstrap-aws-foundation.sh"
  assert_log_contains <(printf '%s' "${output}") "NOISY STDERR from bootstrap-aws-foundation.sh"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-all tests\n'
