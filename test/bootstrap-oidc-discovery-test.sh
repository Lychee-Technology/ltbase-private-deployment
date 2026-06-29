#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-oidc-discovery.sh"

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
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
OIDC_DISCOVERY_PAGES_PROJECT=customer-ltbase-oidc-discovery
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
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
if [[ "${cmd} ${sub}" == "api repos/customer-org/customer-ltbase" ]]; then
  printf 'NOISY_GH_STDERR repo metadata success\n' >&2
  printf '{"default_branch":"main","private":false}'
  exit 0
fi
printf 'NOISY_GH_STDOUT generic success\n'
printf 'NOISY_GH_STDERR generic success\n' >&2
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
printf 'NOISY_AWS_STDOUT generic success\n'
printf 'NOISY_AWS_STDERR generic success\n' >&2
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

dns_lookup_url='https://api.cloudflare.com/client/v4/zones/zone-123/dns_records?name=oidc.customer.example.com'
dns_create_url='https://api.cloudflare.com/client/v4/zones/zone-123/dns_records'
dns_expected_content='customer-ltbase-oidc-discovery.pages.dev'
pages_project_url='https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-oidc-discovery'

if [[ "${method}" == "GET" && "${CURL_GET_EXISTING_PROJECT:-false}" == "true" && "${url}" == "${pages_project_url}" ]]; then
  body='{"success":true,"result":{"name":"customer-ltbase-oidc-discovery"}}'
  status='200'
fi
if [[ "${method}" == "GET" && "${CURL_GET_EXISTING_DOMAIN:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  body='{"success":true,"result":{"name":"oidc.customer.example.com"}}'
  status='200'
fi
if [[ "${method}" == "GET" && "${url}" == "${dns_lookup_url}" ]]; then
  if [[ "${CURL_DNS_CONFLICT_WRONG_CONTENT:-false}" == "true" ]]; then
    body='{"success":true,"result":[{"id":"dns-1","type":"CNAME","name":"oidc.customer.example.com","content":"wrong-target.pages.dev"}]}'
    status='200'
  elif [[ "${CURL_DNS_CONFLICT_WRONG_TYPE:-false}" == "true" ]]; then
    body='{"success":true,"result":[{"id":"dns-1","type":"TXT","name":"oidc.customer.example.com","content":"some-text-value"},{"id":"dns-2","type":"CNAME","name":"other.customer.example.com","content":"customer-ltbase-oidc-discovery.pages.dev"}]}'
    status='200'
  elif [[ "${CURL_DNS_MATCHING_RECORD:-false}" == "true" ]]; then
    body='{"success":true,"result":[{"id":"dns-1","type":"CNAME","name":"oidc.customer.example.com","content":"customer-ltbase-oidc-discovery.pages.dev"}]}'
    status='200'
  else
    body='{"success":true,"result":[]}'
    status='200'
  fi
fi

if [[ "${method}" == "GET" && "${CURL_GET_AUTH_FAILURE:-false}" == "true" && "${url}" == "${pages_project_url}" ]]; then
  body='{"success":false,"errors":[{"message":"auth failure"}]}'
  status='403'
fi
if [[ "${method}" == "GET" && "${CURL_GET_SUCCESS_FALSE:-false}" == "true" && "${url}" == "${pages_project_url}" ]]; then
  body='{"success":false,"errors":[{"message":"project lookup failed"}]}'
  status='200'
fi

if [[ "${method}" == "GET" && "${status}" == '200' && "${CURL_GET_EXISTING_PROJECT:-false}" != "true" && "${CURL_GET_SUCCESS_FALSE:-false}" != "true" && "${url}" == "${pages_project_url}" ]]; then
  status='404'
  body='{"success":false,"errors":[{"message":"not found"}]}'
fi
if [[ "${method}" == "GET" && "${status}" == '200' && "${CURL_GET_EXISTING_DOMAIN:-false}" != "true" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  status='404'
  body='{"success":false,"errors":[{"message":"not found"}]}'
fi

if [[ "${method}" == "POST" && "${url}" == "${dns_create_url}" && "${CURL_FAIL_DNS_POST_SUCCESS:-false}" == "true" ]]; then
  body='{"success":false,"errors":[{"message":"dns create failed"}]}'
  status='200'
fi

if [[ "${method}" == "POST" && "${CURL_TRANSPORT_FAILURE_POST:-false}" == "true" && "${url}" == *"/pages/projects" ]]; then
  printf 'curl: (7) Failed to connect to api.cloudflare.com port 443\n' >&2
  exit 7
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
    printf 'NOISY_CURL_STDERR http code success\n' >&2
    printf '%s' "${status}"
  else
    printf '%s' "${write_out}"
  fi
  exit 0
fi

if [[ "${status}" =~ ^2 ]]; then
  printf 'NOISY_CURL_STDOUT generic success\n'
  printf 'NOISY_CURL_STDERR generic success\n' >&2
  exit 0
fi

exit 22
EOF
chmod +x "${fake_bin}/curl"

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

# ---------- Test 1: fresh bootstrap ----------

if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist" 2>&1)"; then
  fail "expected script to succeed, got: ${output}"
fi

# Should NOT create companion repo
assert_log_not_contains "${log_file}" "gh repo create"
assert_log_not_contains "${log_file}" "gh repo clone"
assert_log_not_contains "${log_file}" "gh repo view"

# Should set variables on deployment repo, not companion repo
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_DOMAIN --repo customer-org/customer-ltbase --body oidc.customer.example.com"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo customer-org/customer-ltbase"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo customer-org/customer-ltbase --body customer-ltbase-oidc-discovery"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_TEMPLATE_REPO --repo customer-org/customer-ltbase --body Lychee-Technology/ltbase-oidc-discovery-template"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_TEMPLATE_REF --repo customer-org/customer-ltbase --body main"
assert_log_not_contains "${log_file}" "gh secret set"
assert_log_not_contains "${log_file}" "gh repo clone"
assert_log_not_contains "${log_file}" "gh repo view"

# Should still manage Pages, domain, DNS, IAM
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-oidc-discovery/domains"

# Pages project must be created as a direct-upload project (no GitHub source block)
pages_create_line="$(grep -F "/pages/projects --data" "${log_file}" || true)"
if [[ -z "${pages_create_line}" ]]; then
  fail "expected a Pages project create POST with a payload"
fi
case "${pages_create_line}" in
  *'"production_branch"'*) ;;
  *) fail "expected production_branch in Pages project create payload" ;;
esac
case "${pages_create_line}" in
  *'"source"'*) fail "Pages project must be created as direct upload (no source block)" ;;
esac
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records?name=oidc.customer.example.com"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records"
assert_log_contains "${log_file}" "aws --profile devo-profile iam create-role --role-name customer-ltbase-oidc-discovery-devo"
assert_log_contains "${log_file}" "aws --profile prod-profile iam create-role --role-name customer-ltbase-oidc-discovery-prod"
assert_log_contains "${log_file}" "aws --profile devo-profile iam put-role-policy --role-name customer-ltbase-oidc-discovery-devo --policy-name LTBaseOIDCDiscoveryAccess"

# Should get deployment repo metadata (not companion repo)
assert_log_contains "${log_file}" "gh api repos/customer-org/customer-ltbase"

# Summary should NOT contain companion repo references
assert_file_contains "${temp_dir}/dist/oidc-discovery.env" "OIDC_DISCOVERY_PAGES_PROJECT=customer-ltbase-oidc-discovery"
assert_file_contains "${temp_dir}/dist/oidc-discovery.env" "OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com"
assert_file_contains "${temp_dir}/dist/oidc-discovery.env" "OIDC_ISSUER_URL_DEVO=https://oidc.customer.example.com/devo"
assert_file_contains "${temp_dir}/dist/oidc-discovery.env" "JWKS_URL_PROD=https://oidc.customer.example.com/prod/.well-known/jwks.json"

# Summary should NOT contain companion repo or repo name
if grep -q "OIDC_DISCOVERY_REPO=" "${temp_dir}/dist/oidc-discovery.env"; then
  fail "summary should not contain OIDC_DISCOVERY_REPO"
fi

# IAM trust policy should reference deployment repo
assert_file_contains "${temp_dir}/dist/oidc-discovery-devo-trust-policy.json" "repo:customer-org/customer-ltbase:ref:refs/heads/main"

# Log messages should no longer mention companion repo
assert_log_not_contains <(printf '%s' "${output}") "[info] Ensuring OIDC discovery repository"
assert_log_contains <(printf '%s' "${output}") "[info] Ensuring Pages project: customer-ltbase-oidc-discovery"
assert_log_contains <(printf '%s' "${output}") "[info] Ensuring Pages domain: oidc.customer.example.com"
assert_log_contains <(printf '%s' "${output}") "[info] Reconciling DNS for OIDC discovery domain: oidc.customer.example.com"
assert_log_contains <(printf '%s' "${output}") "[info] Configuring deployment repository variables for OIDC discovery"
assert_log_contains <(printf '%s' "${output}") "[info] Reconciling OIDC discovery IAM role for stack: devo"

# Should suppress noisy outputs
assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDOUT"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDERR"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_CURL_STDOUT"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_CURL_STDERR"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_AWS_STDOUT"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_AWS_STDERR"

# ---------- Test 2: invalid domain ----------

cat >"${temp_dir}/invalid-domain.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
OIDC_DISCOVERY_DOMAIN=oidc_customer.example.com
OIDC_DISCOVERY_PAGES_PROJECT=customer-ltbase-oidc-discovery
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
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

# ---------- Test 3: Cloudflare POST failure ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_POST_SUCCESS=false "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-failed-post" >"${temp_dir}/cloudflare-failure.log" 2>&1; then
  fail "expected Cloudflare POST success=false response to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-failure.log" "Cloudflare API request failed"

# ---------- Test 4: idempotent rerun (all resources exist) ----------

: >"${log_file}"
if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_EXISTING_PROJECT=true CURL_GET_EXISTING_DOMAIN=true CURL_DNS_MATCHING_RECORD=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-existing" 2>&1)"; then
  fail "expected idempotent rerun to succeed, got: ${output}"
fi

assert_log_not_contains "${log_file}" "gh repo create"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-oidc-discovery/domains --data"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records --data"

# ---------- Test 5: DNS conflict - wrong target ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_DNS_CONFLICT_WRONG_CONTENT=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-dns-conflict-content" >"${temp_dir}/dns-conflict-content.log" 2>&1; then
  fail "expected DNS conflict with wrong content to fail"
fi

assert_log_contains "${temp_dir}/dns-conflict-content.log" "OIDC discovery DNS record already exists with unexpected target"
assert_log_contains "${temp_dir}/dns-conflict-content.log" "wrong-target.pages.dev"

# ---------- Test 6: DNS conflict - wrong type ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_DNS_CONFLICT_WRONG_TYPE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-dns-conflict-type" >"${temp_dir}/dns-conflict-type.log" 2>&1; then
  fail "expected DNS conflict with wrong type to fail"
fi

assert_log_contains "${temp_dir}/dns-conflict-type.log" "OIDC discovery DNS record already exists with unexpected type"
assert_log_contains "${temp_dir}/dns-conflict-type.log" "TXT"

# ---------- Test 7: Cloudflare DNS POST failure ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_DNS_POST_SUCCESS=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-dns-post-failed" >"${temp_dir}/dns-post-failure.log" 2>&1; then
  fail "expected Cloudflare DNS POST success=false response to fail"
fi

assert_log_contains "${temp_dir}/dns-post-failure.log" "Cloudflare API request failed: create DNS CNAME"
assert_log_contains "${temp_dir}/dns-post-failure.log" "dns create failed"

# ---------- Test 8: Cloudflare POST HTTP failure ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_POST_HTTP=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-http-failed-post" >"${temp_dir}/cloudflare-http-failure.log" 2>&1; then
  fail "expected Cloudflare POST HTTP failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-http-failure.log" "create Pages project"
assert_log_contains "${temp_dir}/cloudflare-http-failure.log" "http failure"

# ---------- Test 9: Cloudflare GET auth failure ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_AUTH_FAILURE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-auth-failed-get" >"${temp_dir}/cloudflare-get-auth-failure.log" 2>&1; then
  fail "expected Cloudflare GET auth failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-get-auth-failure.log" "Cloudflare API request failed: get Pages project (HTTP 403)"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"

# ---------- Test 10: Cloudflare POST transport failure ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_TRANSPORT_FAILURE_POST=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-transport-failed-post" >"${temp_dir}/cloudflare-transport-failure-post.log" 2>&1; then
  fail "expected Cloudflare POST transport failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-transport-failure-post.log" "Cloudflare API request failed: create Pages project"
assert_log_contains "${temp_dir}/cloudflare-transport-failure-post.log" "curl: (7) Failed to connect"

# ---------- Test 11: Cloudflare GET success=false ----------

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_SUCCESS_FALSE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-success-false-get" >"${temp_dir}/cloudflare-success-false-get.log" 2>&1; then
  fail "expected Cloudflare GET success=false response to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-success-false-get.log" "Cloudflare API request failed: get Pages project"
assert_log_contains "${temp_dir}/cloudflare-success-false-get.log" "project lookup failed"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"

printf 'PASS: bootstrap-oidc-discovery tests\n'
