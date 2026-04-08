#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-oidc-discovery-companion.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_log_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to not contain: ${needle}"
  fi
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
  if [[ "${GH_REPO_VIEW_EXISTS:-false}" == "true" ]]; then
    printf 'customer-org/customer-ltbase-oidc-discovery\n'
    exit 0
  fi
  if [[ "${GH_REPO_VIEW_ERROR:-false}" == "true" ]]; then
    if [[ "${GH_REPO_VIEW_GENERIC_NOT_FOUND:-false}" == "true" ]]; then
      printf 'HTTP 500: workflow cache not found on upstream service\n' >&2
      exit 1
    fi
    printf 'HTTP 500: GitHub service unavailable\n' >&2
    exit 1
  fi
  if [[ "${GH_REPO_VIEW_NOT_FOUND:-true}" == "true" ]]; then
    printf 'GraphQL: Could not resolve to a Repository with the name customer-org/customer-ltbase-oidc-discovery.\n' >&2
    exit 1
  fi
  exit 1
fi
if [[ "${cmd} ${sub}" == "api repos/customer-org/customer-ltbase-oidc-discovery" ]]; then
  printf '{"default_branch":"main","private":false}'
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
write_out=""
output_file=""
args=("$@")
index=0
while [[ ${index} -lt ${#args[@]} ]]; do
  case "${args[${index}]}" in
    -X)
      method="${args[$((index + 1))]}"
      index=$((index + 2))
      ;;
    -w)
      write_out="${args[$((index + 1))]}"
      index=$((index + 2))
      ;;
    -o)
      output_file="${args[$((index + 1))]}"
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

body='{"success":true}'
status='200'

if [[ "${method}" == "GET" && "${CURL_GET_EXISTING_PROJECT:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  body='{"success":true,"result":{"name":"customer-ltbase-oidc-discovery"}}'
  status='200'
fi
if [[ "${method}" == "GET" && "${CURL_GET_EXISTING_DOMAIN:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  body='{"success":true,"result":{"name":"oidc.customer.example.com"}}'
  status='200'
fi

if [[ "${method}" == "GET" && "${CURL_GET_AUTH_FAILURE:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  body='{"success":false,"errors":[{"message":"auth failure"}]}'
  status='403'
fi
if [[ "${method}" == "GET" && "${CURL_GET_SUCCESS_FALSE:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  body='{"success":false,"errors":[{"message":"project lookup failed"}]}'
  status='200'
fi

if [[ "${method}" == "GET" && "${status}" == '200' && "${CURL_GET_EXISTING_PROJECT:-false}" != "true" && "${CURL_GET_SUCCESS_FALSE:-false}" != "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  status='404'
  body='{"success":false,"errors":[{"message":"not found"}]}'
fi
if [[ "${method}" == "GET" && "${status}" == '200' && "${CURL_GET_EXISTING_DOMAIN:-false}" != "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  status='404'
  body='{"success":false,"errors":[{"message":"not found"}]}'
fi

if [[ "${method}" == "POST" && "${CURL_FAIL_POST_SUCCESS:-true}" == "false" ]]; then
  body='{"success":false,"errors":[{"message":"simulated failure"}]}'
  status='200'
fi

if [[ "${method}" == "POST" && "${CURL_FAIL_POST_HTTP:-false}" == "true" ]]; then
  body='{"success":false,"errors":[{"message":"http failure"}]}'
  status='500'
fi

if [[ -n "${output_file}" ]]; then
  printf '%s' "${body}" >"${output_file}"
else
  printf '%s' "${body}"
fi

if [[ -n "${write_out}" ]]; then
  if [[ "${write_out}" == '%{http_code}' ]]; then
    printf '%s' "${status}"
  else
    printf '%s' "${write_out}"
  fi
  exit 0
fi

if [[ "${status}" =~ ^2 ]]; then
  exit 0
fi

exit 22
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
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo customer-org/customer-ltbase-oidc-discovery --body {\"devo\":{\"aws_region\":\"ap-northeast-1\",\"aws_role_arn\":\"arn:aws:iam::123456789012:role/customer-ltbase-oidc-discovery-devo\",\"kms_auth_key_alias\":\"alias/ltbase-oidc-discovery-devo-authservice\"},\"prod\":{\"aws_region\":\"us-west-2\",\"aws_role_arn\":\"arn:aws:iam::210987654321:role/customer-ltbase-oidc-discovery-prod\",\"kms_auth_key_alias\":\"alias/ltbase-oidc-discovery-prod-authservice\"}}"
assert_log_contains "${log_file}" "gh variable set CLOUDFLARE_ACCOUNT_ID --repo customer-org/customer-ltbase-oidc-discovery --body cf-account-123"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo customer-org/customer-ltbase-oidc-discovery --body customer-ltbase-oidc-discovery"
assert_log_contains "${log_file}" "gh secret set CLOUDFLARE_API_TOKEN --repo customer-org/customer-ltbase-oidc-discovery --body test-cloudflare-token"
assert_log_contains "${log_file}" "aws --profile devo-profile iam create-role --role-name customer-ltbase-oidc-discovery-devo"
assert_log_contains "${log_file}" "aws --profile prod-profile iam create-role --role-name customer-ltbase-oidc-discovery-prod"
assert_log_contains "${log_file}" "aws --profile devo-profile iam put-role-policy --role-name customer-ltbase-oidc-discovery-devo --policy-name LTBaseOIDCDiscoveryAccess"
assert_log_contains "${log_file}" "aws --profile prod-profile iam put-role-policy --role-name customer-ltbase-oidc-discovery-prod --policy-name LTBaseOIDCDiscoveryAccess"

assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "OIDC_DISCOVERY_REPO=customer-org/customer-ltbase-oidc-discovery"
assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "OIDC_DISCOVERY_PAGES_PROJECT=customer-ltbase-oidc-discovery"
assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "OIDC_ISSUER_URL_DEVO=https://oidc.customer.example.com/devo"
assert_file_contains "${temp_dir}/dist/oidc-discovery-companion.env" "JWKS_URL_PROD=https://oidc.customer.example.com/prod/.well-known/jwks.json"

cat >"${temp_dir}/invalid-domain.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc_customer.example.com
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

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/invalid-domain.env" --output-dir "${temp_dir}/dist-invalid" >"${temp_dir}/invalid-domain.log" 2>&1; then
  fail "expected invalid OIDC discovery domain to fail"
fi

assert_log_contains "${temp_dir}/invalid-domain.log" "OIDC_DISCOVERY_DOMAIN is invalid"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_POST_SUCCESS=false "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-failed-post" >"${temp_dir}/cloudflare-failure.log" 2>&1; then
  fail "expected Cloudflare POST success=false response to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-failure.log" "Cloudflare API request failed"

: >"${log_file}"
if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" GH_REPO_VIEW_EXISTS=true GH_REPO_VIEW_NOT_FOUND=false CURL_GET_EXISTING_PROJECT=true CURL_GET_EXISTING_DOMAIN=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-existing" 2>&1)"; then
  fail "expected idempotent rerun to succeed, got: ${output}"
fi

assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase-oidc-discovery --template Lychee-Technology/ltbase-oidc-discovery-template --private --description LTBase OIDC discovery companion for customer-ltbase --clone=false"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-oidc-discovery/domains --data"
assert_log_contains "${log_file}" "gh variable set CLOUDFLARE_ACCOUNT_ID --repo customer-org/customer-ltbase-oidc-discovery --body cf-account-123"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo customer-org/customer-ltbase-oidc-discovery --body customer-ltbase-oidc-discovery"
assert_log_contains "${log_file}" "gh secret set CLOUDFLARE_API_TOKEN --repo customer-org/customer-ltbase-oidc-discovery --body test-cloudflare-token"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" GH_REPO_VIEW_ERROR=true GH_REPO_VIEW_NOT_FOUND=false "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-gh-repo-view-error" >"${temp_dir}/github-repo-view-error.log" 2>&1; then
  fail "expected GitHub repo view error to fail"
fi

assert_log_contains "${temp_dir}/github-repo-view-error.log" "GitHub repo lookup failed"
assert_log_contains "${temp_dir}/github-repo-view-error.log" "HTTP 500: GitHub service unavailable"
assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase-oidc-discovery"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" GH_REPO_VIEW_ERROR=true GH_REPO_VIEW_GENERIC_NOT_FOUND=true GH_REPO_VIEW_NOT_FOUND=false "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-gh-repo-view-not-found-text" >"${temp_dir}/github-repo-view-not-found-text.log" 2>&1; then
  fail "expected non-repo-context not found text to fail"
fi

assert_log_contains "${temp_dir}/github-repo-view-not-found-text.log" "GitHub repo lookup failed"
assert_log_contains "${temp_dir}/github-repo-view-not-found-text.log" "workflow cache not found"
assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase-oidc-discovery"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_POST_HTTP=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-http-failed-post" >"${temp_dir}/cloudflare-http-failure.log" 2>&1; then
  fail "expected Cloudflare POST HTTP failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-http-failure.log" "create Pages project"
assert_log_contains "${temp_dir}/cloudflare-http-failure.log" "http failure"
assert_log_not_contains "${log_file}" "gh variable set CLOUDFLARE_ACCOUNT_ID --repo customer-org/customer-ltbase-oidc-discovery --body cf-account-123"
assert_log_not_contains "${log_file}" "gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo customer-org/customer-ltbase-oidc-discovery --body customer-ltbase-oidc-discovery"
assert_log_not_contains "${log_file}" "gh secret set CLOUDFLARE_API_TOKEN --repo customer-org/customer-ltbase-oidc-discovery --body test-cloudflare-token"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_AUTH_FAILURE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-auth-failed-get" >"${temp_dir}/cloudflare-get-auth-failure.log" 2>&1; then
  fail "expected Cloudflare GET auth failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-get-auth-failure.log" "Cloudflare API request failed: get Pages project (HTTP 403)"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_SUCCESS_FALSE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-success-false-get" >"${temp_dir}/cloudflare-success-false-get.log" 2>&1; then
  fail "expected Cloudflare GET success=false response to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-success-false-get.log" "Cloudflare API request failed: get Pages project"
assert_log_contains "${temp_dir}/cloudflare-success-false-get.log" "project lookup failed"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"

printf 'PASS: bootstrap-oidc-discovery-companion tests\n'
