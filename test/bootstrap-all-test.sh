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

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}" "${temp_dir}/infra"
touch "${log_file}"

cat >"${temp_dir}/.env" <<'EOF'
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION=Customer LTBase deployment repo
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
PULUMI_BACKEND_URL=s3://test-pulumi-state
PULUMI_SECRETS_PROVIDER_DEVO=awskms://alias/test-pulumi-secrets?region=ap-northeast-1
PULUMI_SECRETS_PROVIDER_PROD=awskms://alias/test-pulumi-secrets?region=us-west-2
LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases
LTBASE_RELEASE_ID=v1.0.0
API_DOMAIN=api.devo.example.com
CONTROL_DOMAIN=control.devo.example.com
AUTH_DOMAIN=auth.devo.example.com
CLOUDFLARE_ZONE_ID=zone-123
OIDC_ISSUER_URL=https://issuer.example.com
JWKS_URL=https://issuer.example.com/jwks.json
RUNTIME_BUCKET=runtime-bucket
TABLE_NAME=ltbase-devo
GITHUB_ORG=customer-org
GITHUB_REPO=customer-ltbase
GEMINI_MODEL=gemini-3-flash-preview
DSQL_PORT=5432
DSQL_DB=ltbase
DSQL_USER=ltbase
DSQL_PROJECT_SCHEMA=ltbase
GEMINI_API_KEY=test-gemini-key
CLOUDFLARE_API_TOKEN=test-cloudflare-token
LTBASE_RELEASES_TOKEN=test-release-token
EOF

for name in render-bootstrap-policies.sh create-deployment-repo.sh bootstrap-aws-foundation.sh bootstrap-deployment-repo.sh; do
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
  assert_log_contains "${log_file}" "bootstrap-deployment-repo.sh --env-file ${temp_dir}/.env --stack devo --infra-dir ${temp_dir}/infra"
  assert_log_contains "${log_file}" "bootstrap-deployment-repo.sh --env-file ${temp_dir}/.env --stack prod --infra-dir ${temp_dir}/infra"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-all tests\n'
