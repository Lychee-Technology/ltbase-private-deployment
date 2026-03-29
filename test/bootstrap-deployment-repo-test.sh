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

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}" "${temp_dir}/infra"
touch "${log_file}"

cat >"${temp_dir}/.env" <<'EOF'
DEPLOYMENT_REPO=Lychee-Technology/ltbase-private-deployment
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
PULUMI_BACKEND_URL=s3://test-pulumi-state
PULUMI_SECRETS_PROVIDER_DEVO=awskms://alias/test-pulumi-secrets?region=ap-northeast-1
PULUMI_SECRETS_PROVIDER_PROD=awskms://alias/test-pulumi-secrets?region=us-west-2
LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases
LTBASE_RELEASE_ID=v1.0.0
AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/test-deploy-role
AWS_ROLE_ARN_PROD=arn:aws:iam::123456789012:role/test-prod-role
LTBASE_RELEASES_TOKEN=test-release-token
CLOUDFLARE_API_TOKEN=test-cloudflare-token
GEMINI_API_KEY=test-gemini-key
API_DOMAIN=api.devo.example.com
CONTROL_DOMAIN=control.devo.example.com
AUTH_DOMAIN=auth.devo.example.com
CLOUDFLARE_ZONE_ID=zone-123
OIDC_ISSUER_URL=https://issuer.example.com
JWKS_URL=https://issuer.example.com/jwks.json
RUNTIME_BUCKET=runtime-bucket
TABLE_NAME=ltbase-devo
GITHUB_ORG=Lychee-Technology
GITHUB_REPO=ltbase-private-deployment
GEMINI_MODEL=gemini-3-flash-preview
DSQL_PORT=5432
DSQL_DB=postgres
DSQL_USER=admin
DSQL_PROJECT_SCHEMA=ltbase
EOF

cat >"${fake_bin}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "\$*" >>"${log_file}"
EOF
chmod +x "${fake_bin}/gh"

cat >"${fake_bin}/pulumi" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'pulumi %s\n' "\$*" >>"${log_file}"
if [[ "\$1 \$2" == "stack select" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "${fake_bin}/pulumi"

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when implemented, got: ${output}"
  fi

  assert_log_contains "${log_file}" "gh variable set AWS_REGION_DEVO --repo Lychee-Technology/ltbase-private-deployment --body ap-northeast-1"
  assert_log_contains "${log_file}" "gh variable set AWS_REGION_PROD --repo Lychee-Technology/ltbase-private-deployment --body us-west-2"
  assert_log_contains "${log_file}" "gh secret set AWS_ROLE_ARN_DEVO --repo Lychee-Technology/ltbase-private-deployment --body arn:aws:iam::123456789012:role/test-deploy-role"
  assert_log_contains "${log_file}" "pulumi stack init devo --secrets-provider awskms://alias/test-pulumi-secrets?region=ap-northeast-1"
  assert_log_contains "${log_file}" "pulumi config set runtimeBucket runtime-bucket --stack devo"
  assert_log_contains "${log_file}" "pulumi config set dsqlDB postgres --stack devo"
  assert_log_contains "${log_file}" "pulumi config set dsqlUser admin --stack devo"
  assert_log_contains "${log_file}" "pulumi config set --secret geminiApiKey test-gemini-key --stack devo"
  assert_log_not_contains "${log_file}" "pulumi stack output dsqlClusterIdentifier"
  assert_log_not_contains "${log_file}" "pulumi up --stack devo --yes --skip-preview"
  assert_log_not_contains "${log_file}" "pulumi config set dsqlEndpoint"
  assert_log_not_contains "${log_file}" "aws dsql get-cluster"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-deployment-repo tests\n'
