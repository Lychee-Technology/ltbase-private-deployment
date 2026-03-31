#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-oidc-discovery-companion.sh"

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
trap 'rm -rf "${temp_dir}"' EXIT
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}"
touch "${log_file}"

cat >"${temp_dir}/.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_PROD=prod-profile
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
CLOUDFLARE_API_TOKEN=test-cloudflare-token
EOF

cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"${COMMAND_LOG}"
cmd="${1:-}"
sub="${2:-}"
if [[ "${cmd} ${sub}" == "repo view" ]]; then
  exit 1
fi
if [[ "${cmd} ${sub}" == "api repos/customer-org/customer-ltbase-oidc-discovery" ]]; then
  printf '{"default_branch":"main"}'
  exit 0
fi
exit 0
EOF
chmod +x "${fake_bin}/gh"

cat >"${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "$*" >>"${COMMAND_LOG}"
args=("$@")
if [[ "${args[0]:-}" == "--profile" ]]; then
  args=("${args[@]:2}")
fi
if [[ "${args[0]:-} ${args[1]:-}" == "iam get-role" ]]; then
  exit 255
fi
exit 0
EOF
chmod +x "${fake_bin}/aws"

cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >>"${COMMAND_LOG}"
method="GET"
url=""
args=("$@")
index=0
while [[ ${index} -lt ${#args[@]} ]]; do
  case "${args[${index}]}" in
    -X)
      method="${args[$((index + 1))]}"
      index=$((index + 2))
      ;;
    http*)
      url="${args[${index}]}"
      index=$((index + 1))
      ;;
    *)
      index=$((index + 1))
      ;;
  esac
done

if [[ "${method}" == "GET" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  exit 22
fi
if [[ "${method}" == "GET" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  exit 22
fi

printf '{"success":true}'
EOF
chmod +x "${fake_bin}/curl"

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist" 2>&1)"; then
  fail "expected script to succeed, got: ${output}"
fi

assert_log_contains "${log_file}" "gh repo create customer-org/customer-ltbase-oidc-discovery --template Lychee-Technology/ltbase-oidc-discovery-template --private --description LTBase OIDC discovery companion for customer-ltbase --clone=false"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-oidc-discovery/domains"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_DOMAIN --repo customer-org/customer-ltbase-oidc-discovery --body oidc.customer.example.com"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo customer-org/customer-ltbase-oidc-discovery --body {\"devo\":{\"aws_region\":\"ap-northeast-1\",\"aws_role_arn\":\"arn:aws:iam::123456789012:role/customer-ltbase-oidc-discovery-devo\",\"kms_auth_key_alias\":\"alias/ltbase-infra-devo-authservice\"},\"prod\":{\"aws_region\":\"us-west-2\",\"aws_role_arn\":\"arn:aws:iam::210987654321:role/customer-ltbase-oidc-discovery-prod\",\"kms_auth_key_alias\":\"alias/ltbase-infra-prod-authservice\"}}"
assert_log_contains "${log_file}" "aws --profile devo-profile iam create-role --role-name customer-ltbase-oidc-discovery-devo"
assert_log_contains "${log_file}" "aws --profile prod-profile iam create-role --role-name customer-ltbase-oidc-discovery-prod"
assert_log_contains "${log_file}" "aws --profile devo-profile iam put-role-policy --role-name customer-ltbase-oidc-discovery-devo --policy-name LTBaseOIDCDiscoveryAccess"
assert_log_contains "${log_file}" "aws --profile prod-profile iam put-role-policy --role-name customer-ltbase-oidc-discovery-prod --policy-name LTBaseOIDCDiscoveryAccess"

assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "OIDC_DISCOVERY_REPO=customer-org/customer-ltbase-oidc-discovery"
assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "OIDC_DISCOVERY_PAGES_PROJECT=customer-ltbase-oidc-discovery"
assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "OIDC_ISSUER_URL_DEVO=https://oidc.customer.example.com/devo"
assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "JWKS_URL_PROD=https://oidc.customer.example.com/prod/.well-known/jwks.json"

printf 'PASS: bootstrap-oidc-discovery-companion tests\n'
