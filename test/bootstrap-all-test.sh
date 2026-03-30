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
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}" "${temp_dir}/infra"
touch "${log_file}"

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
CLOUDFLARE_ZONE_ID=zone-123
OIDC_ISSUER_URL_DEVO=https://issuer.example.com/devo
OIDC_ISSUER_URL_STAGING=https://issuer.example.com/staging
OIDC_ISSUER_URL_PROD=https://issuer.example.com/prod
JWKS_URL_DEVO=https://issuer.example.com/devo/jwks.json
JWKS_URL_STAGING=https://issuer.example.com/staging/jwks.json
JWKS_URL_PROD=https://issuer.example.com/prod/jwks.json
GEMINI_MODEL=gemini-3-flash-preview
DSQL_PORT=5432
DSQL_DB=postgres
DSQL_USER=admin
DSQL_PROJECT_SCHEMA=ltbase
GEMINI_API_KEY=test-gemini-key
CLOUDFLARE_API_TOKEN=test-cloudflare-token
LTBASE_RELEASES_TOKEN=test-release-token
EOF

for name in render-bootstrap-policies.sh create-deployment-repo.sh bootstrap-aws-foundation.sh bootstrap-oidc-discovery-companion.sh bootstrap-deployment-repo.sh reconcile-managed-dsql-endpoint.sh; do
  cat >"${fake_bin}/${name}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' '${name}' "\$*" >>"${log_file}"
EOF
  chmod +x "${fake_bin}/${name}"
done

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --mode apply --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected orchestrator to succeed when implemented, got: ${output}"
  fi

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
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-all tests\n'
