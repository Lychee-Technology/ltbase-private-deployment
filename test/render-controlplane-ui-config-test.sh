#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/render-controlplane-ui-config.sh"

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
  if ! grep -Fq -- "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
  if grep -Fq -- "${needle}" "${path}"; then
    fail "expected ${path} to not contain: ${needle}"
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

cat >"${temp_dir}/.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
AUTH_PROVIDER_CONFIG_FILE_PROD=infra/auth-providers.prod.json
API_DOMAIN_DEVO=api.devo.customer.example.com
API_DOMAIN_PROD=api.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
CONTROL_DOMAIN_PROD=control.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
AUTH_DOMAIN_PROD=auth.customer.example.com
FIREBASE_API_KEY_DEVO=public-firebase-key-devo
FIREBASE_PROJECT_ID_DEVO=firebase-project-devo
SUPABASE_URL_DEVO=https://devo-project.supabase.co
SUPABASE_ANON_KEY_DEVO=public-supabase-key-devo
FIREBASE_API_KEY_PROD=public-firebase-key-prod
FIREBASE_PROJECT_ID_PROD=firebase-project-prod
SUPABASE_URL_PROD=https://prod-project.supabase.co
SUPABASE_ANON_KEY_PROD=public-supabase-key-prod
EOF

mkdir -p "${temp_dir}/infra"
cat >"${temp_dir}/infra/auth-providers.devo.json" <<'EOF'
{"providers":[{"name":"firebase-google","issuer":"https://securetoken.google.com/firebase-project-devo","enable_login":true},{"name":"supabase-google","issuer":"https://devo-project.supabase.co/auth/v1","enable_login":true}]}
EOF
cat >"${temp_dir}/infra/auth-providers.prod.json" <<'EOF'
{"providers":[{"name":"firebase-google","issuer":"https://securetoken.google.com/firebase-project-prod","enable_login":true},{"name":"supabase-google","issuer":"https://prod-project.supabase.co/auth/v1","enable_login":true}]}
EOF

"${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-path "${temp_dir}/ltbase-controlplane.config.json"

assert_file_contains "${temp_dir}/ltbase-controlplane.config.json" '"redirectUri":"https://admin.customer.example.com/auth/callback"'
assert_file_contains "${temp_dir}/ltbase-controlplane.config.json" '"name":"firebase-google"'
assert_file_contains "${temp_dir}/ltbase-controlplane.config.json" '"name":"supabase-google"'

cat >"${temp_dir}/firebase-only.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
API_DOMAIN_DEVO=api.devo.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
FIREBASE_API_KEY_DEVO=public-firebase-key-devo
FIREBASE_PROJECT_ID_DEVO=firebase-project-devo
SUPABASE_URL_DEVO=
SUPABASE_ANON_KEY_DEVO=
EOF

"${SCRIPT_PATH}" --env-file "${temp_dir}/firebase-only.env" --output-path "${temp_dir}/firebase-only.config.json"

assert_file_contains "${temp_dir}/firebase-only.config.json" '"authProviders":[{"type":"firebase"'
assert_file_contains "${temp_dir}/firebase-only.config.json" '"name":"firebase-google"'
assert_file_not_contains "${temp_dir}/firebase-only.config.json" '"type":"supabase"'

cat >"${temp_dir}/supabase-only.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
API_DOMAIN_DEVO=api.devo.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
FIREBASE_API_KEY_DEVO=
FIREBASE_PROJECT_ID_DEVO=
SUPABASE_URL_DEVO=https://devo-project.supabase.co
SUPABASE_ANON_KEY_DEVO=public-supabase-key-devo
EOF

"${SCRIPT_PATH}" --env-file "${temp_dir}/supabase-only.env" --output-path "${temp_dir}/supabase-only.config.json"

assert_file_contains "${temp_dir}/supabase-only.config.json" '"authProviders":[{"type":"supabase"'
assert_file_contains "${temp_dir}/supabase-only.config.json" '"name":"supabase-google"'
assert_file_not_contains "${temp_dir}/supabase-only.config.json" '"type":"firebase"'

cat >"${temp_dir}/partial-firebase.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
API_DOMAIN_DEVO=api.devo.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
FIREBASE_API_KEY_DEVO=public-firebase-key-devo
FIREBASE_PROJECT_ID_DEVO=
SUPABASE_URL_DEVO=
SUPABASE_ANON_KEY_DEVO=
EOF

if "${SCRIPT_PATH}" --env-file "${temp_dir}/partial-firebase.env" --output-path "${temp_dir}/partial-firebase.config.json" >"${temp_dir}/partial-firebase.stdout" 2>"${temp_dir}/partial-firebase.stderr"; then
  fail "expected standalone renderer to fail for partial Firebase auth config"
fi

assert_file_contains "${temp_dir}/partial-firebase.stderr" "Firebase control plane UI config for stack devo must include both FIREBASE_PROJECT_ID_DEVO and FIREBASE_API_KEY_DEVO"

cat >"${temp_dir}/partial-supabase.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
API_DOMAIN_DEVO=api.devo.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
FIREBASE_API_KEY_DEVO=
FIREBASE_PROJECT_ID_DEVO=
SUPABASE_URL_DEVO=https://devo-project.supabase.co
SUPABASE_ANON_KEY_DEVO=
EOF

if "${SCRIPT_PATH}" --env-file "${temp_dir}/partial-supabase.env" --output-path "${temp_dir}/partial-supabase.config.json" >"${temp_dir}/partial-supabase.stdout" 2>"${temp_dir}/partial-supabase.stderr"; then
  fail "expected standalone renderer to fail for partial Supabase auth config"
fi

assert_file_contains "${temp_dir}/partial-supabase.stderr" "Supabase control plane UI config for stack devo must include both SUPABASE_URL_DEVO and SUPABASE_ANON_KEY_DEVO"

printf 'PASS: render controlplane ui config tests\n'
