#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-controlplane-ui-companion.sh"

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
trap 'rm -rf "${temp_dir}"' EXIT
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}"
mkdir -p "${temp_dir}/infra"
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
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
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
CLOUDFLARE_API_TOKEN=test-cloudflare-token
EOF

cat >"${temp_dir}/infra/auth-providers.devo.json" <<'EOF'
{
  "providers": [
    {
      "name": "firebase-google",
      "issuer": "https://securetoken.google.com/firebase-project-devo",
      "audiences": ["firebase-project-devo"],
      "enable_login": true,
      "enable_id_binding": true
    },
    {
      "name": "supabase-google",
      "issuer": "https://devo-project.supabase.co/auth/v1",
      "audiences": ["authenticated"],
      "enable_login": true,
      "enable_id_binding": true
    }
  ]
}
EOF

cat >"${temp_dir}/infra/auth-providers.prod.json" <<'EOF'
{
  "providers": [
    {
      "name": "firebase-google",
      "issuer": "https://securetoken.google.com/firebase-project-prod",
      "audiences": ["firebase-project-prod"],
      "enable_login": true,
      "enable_id_binding": true
    },
    {
      "name": "supabase-google",
      "issuer": "https://prod-project.supabase.co/auth/v1",
      "audiences": ["authenticated"],
      "enable_login": true,
      "enable_id_binding": true
    }
  ]
}
EOF

cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"${COMMAND_LOG}"
cmd="${1:-}"
sub="${2:-}"
if [[ "${cmd} ${sub}" == "repo view" ]]; then
  if [[ "${GH_REPO_VIEW_EXISTS:-false}" == "true" ]]; then
    printf 'NOISY_GH_STDOUT repo view success\n'
    printf 'NOISY_GH_STDERR repo view success\n' >&2
    printf 'customer-org/customer-ltbase-controlplane-ui\n'
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
    printf 'GraphQL: Could not resolve to a Repository with the name customer-org/customer-ltbase-controlplane-ui.\n' >&2
    exit 1
  fi
  exit 1
fi
if [[ "${cmd} ${sub}" == "api repos/customer-org/customer-ltbase-controlplane-ui" ]]; then
  printf 'NOISY_GH_STDERR repo metadata success\n' >&2
  printf '{"default_branch":"main","private":false}'
  exit 0
fi
if [[ "${cmd} ${sub}" == "api repos/customer-org/customer-ltbase" ]]; then
  printf 'NOISY_GH_STDERR deployment repo metadata success\n' >&2
  printf '{"default_branch":"main","private":false}'
  exit 0
fi
if [[ "${cmd} ${sub}" == "repo clone" ]]; then
  dest="${4:-}"
  mkdir -p "${dest}"
  if [[ "${dest}" == *"/companion" ]]; then
    mkdir -p "${dest}/.git"
    if [[ "${GH_EXISTING_REPO_HAS_DIFF:-false}" == "true" ]]; then
      printf 'existing repo\n' >"${dest}/README.md"
    else
      printf 'template repo\n' >"${dest}/README.md"
    fi
  elif [[ "${dest}" == *"/template" ]]; then
    printf 'template repo\n' >"${dest}/README.md"
  else
    printf 'template checkout\n' >"${dest}/README.md"
  fi
  printf 'NOISY_GH_STDOUT repo clone success\n'
  printf 'NOISY_GH_STDERR repo clone success\n' >&2
  exit 0
fi
printf 'NOISY_GH_STDOUT generic success\n'
printf 'NOISY_GH_STDERR generic success\n' >&2
exit 0
EOF
chmod +x "${fake_bin}/gh"

cat >"${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"${COMMAND_LOG}"
repo_dir=""
args=("$@")
if [[ "${args[0]:-}" == "-C" ]]; then
  repo_dir="${args[1]}"
  args=("${args[@]:2}")
fi
if [[ "${args[0]:-}" == "diff" && "${args[1]:-}" == "--quiet" ]]; then
  if [[ "${GH_EXISTING_REPO_HAS_DIFF:-false}" == "true" ]]; then
    exit 1
  fi
  exit 0
fi
if [[ "${args[0]:-}" == "add" ]]; then
  exit 0
fi
if [[ "${args[0]:-}" == "commit" ]]; then
  printf 'commit:%s\n' "${repo_dir}" >>"${COMMAND_LOG}"
  exit 0
fi
if [[ "${args[0]:-}" == "push" ]]; then
  printf 'push:%s\n' "${repo_dir}" >>"${COMMAND_LOG}"
  exit 0
fi
exit 0
EOF
chmod +x "${fake_bin}/git"

cat >"${fake_bin}/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync %s\n' "$*" >>"${COMMAND_LOG}"
src="${@: -2:1}"
dest="${@: -1}"
cp -R "${src}/." "${dest}/"
exit 0
EOF
chmod +x "${fake_bin}/rsync"

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

dns_lookup_url='https://api.cloudflare.com/client/v4/zones/zone-123/dns_records?name=admin.customer.example.com'
dns_create_url='https://api.cloudflare.com/client/v4/zones/zone-123/dns_records'

if [[ "${method}" == "GET" && "${CURL_GET_EXISTING_PROJECT:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-controlplane-ui" ]]; then
  body='{"success":true,"result":{"name":"customer-ltbase-controlplane-ui"}}'
  status='200'
fi
if [[ "${method}" == "GET" && "${CURL_GET_EXISTING_DOMAIN:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-controlplane-ui/domains/admin.customer.example.com" ]]; then
  body='{"success":true,"result":{"name":"admin.customer.example.com"}}'
  status='200'
fi
if [[ "${method}" == "GET" && "${url}" == "${dns_lookup_url}" ]]; then
  if [[ "${CURL_DNS_CONFLICT_WRONG_CONTENT:-false}" == "true" ]]; then
    body='{"success":true,"result":[{"id":"dns-1","type":"CNAME","name":"admin.customer.example.com","content":"wrong-target.pages.dev"}]}'
    status='200'
  elif [[ "${CURL_DNS_CONFLICT_WRONG_TYPE:-false}" == "true" ]]; then
    body='{"success":true,"result":[{"id":"dns-1","type":"TXT","name":"admin.customer.example.com","content":"some-text-value"}]}'
    status='200'
  elif [[ "${CURL_DNS_MATCHING_RECORD:-false}" == "true" ]]; then
    body='{"success":true,"result":[{"id":"dns-1","type":"CNAME","name":"admin.customer.example.com","content":"customer-ltbase-controlplane-ui.pages.dev"}]}'
    status='200'
  else
    body='{"success":true,"result":[]}'
    status='200'
  fi
fi
if [[ "${method}" == "GET" && "${CURL_GET_AUTH_FAILURE:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-controlplane-ui" ]]; then
  body='{"success":false,"errors":[{"message":"auth failure"}]}'
  status='403'
fi
if [[ "${method}" == "GET" && "${CURL_GET_SUCCESS_FALSE:-false}" == "true" && "${url}" == *"/pages/projects/customer-ltbase-controlplane-ui" ]]; then
  body='{"success":false,"errors":[{"message":"project lookup failed"}]}'
  status='200'
fi
if [[ "${method}" == "GET" && "${status}" == '200' && "${CURL_GET_EXISTING_PROJECT:-false}" != "true" && "${CURL_GET_SUCCESS_FALSE:-false}" != "true" && "${url}" == *"/pages/projects/customer-ltbase-controlplane-ui" ]]; then
  status='404'
  body='{"success":false,"errors":[{"message":"not found"}]}'
fi
if [[ "${method}" == "GET" && "${status}" == '200' && "${CURL_GET_EXISTING_DOMAIN:-false}" != "true" && "${url}" == *"/pages/projects/customer-ltbase-controlplane-ui/domains/admin.customer.example.com" ]]; then
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

if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist" 2>&1)"; then
  fail "expected script to succeed, got: ${output}"
fi

assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-controlplane-ui/domains"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records?name=admin.customer.example.com"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records"
assert_log_contains "${log_file}" '"production_branch":"main"'
assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase-controlplane-ui"
assert_log_not_contains "${log_file}" "gh variable set CONTROLPLANE_UI_DOMAIN --repo customer-org/customer-ltbase-controlplane-ui --body admin.customer.example.com"
assert_log_not_contains "${log_file}" "gh variable set CONTROLPLANE_UI_STACK_CONFIG --repo customer-org/customer-ltbase-controlplane-ui"
assert_log_not_contains "${log_file}" "gh variable set CLOUDFLARE_ACCOUNT_ID --repo customer-org/customer-ltbase-controlplane-ui --body cf-account-123"
assert_log_not_contains "${log_file}" "gh variable set CONTROLPLANE_UI_PAGES_PROJECT --repo customer-org/customer-ltbase-controlplane-ui --body customer-ltbase-controlplane-ui"
assert_log_not_contains "${log_file}" "gh secret set CLOUDFLARE_API_TOKEN --repo customer-org/customer-ltbase-controlplane-ui --body test-cloudflare-token"
assert_log_not_contains "${log_file}" "gh workflow run publish-pages.yml --repo customer-org/customer-ltbase-controlplane-ui"

assert_file_contains "${temp_dir}/dist/controlplane-ui-companion.env" "CONTROLPLANE_UI_PAGES_PROJECT=customer-ltbase-controlplane-ui"
assert_file_contains "${temp_dir}/dist/controlplane-ui-companion.env" "CONTROLPLANE_UI_DOMAIN=admin.customer.example.com"
assert_file_contains "${temp_dir}/dist/controlplane-ui-companion.env" "CONTROLPLANE_UI_STACK_CONFIG={\"stacks\":[{\"key\":\"devo\""

assert_log_contains <(printf '%s' "${output}") "[info] Ensuring Control Plane UI Pages project: customer-ltbase-controlplane-ui"
assert_log_contains <(printf '%s' "${output}") "[info] Ensuring Pages project: customer-ltbase-controlplane-ui"
assert_log_contains <(printf '%s' "${output}") "[info] Ensuring Pages domain: admin.customer.example.com"
assert_log_contains <(printf '%s' "${output}") "[info] Reconciling DNS for Control Plane UI domain: admin.customer.example.com"
assert_log_not_contains <(printf '%s' "${output}") "[info] Configuring companion repository variables and secrets"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDOUT"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_GH_STDERR"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_CURL_STDOUT"
assert_log_not_contains <(printf '%s' "${output}") "NOISY_CURL_STDERR"

cat >"${temp_dir}/firebase-only.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
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
SUPABASE_URL_DEVO=
SUPABASE_ANON_KEY_DEVO=
FIREBASE_API_KEY_PROD=public-firebase-key-prod
FIREBASE_PROJECT_ID_PROD=firebase-project-prod
SUPABASE_URL_PROD=
SUPABASE_ANON_KEY_PROD=
CLOUDFLARE_API_TOKEN=test-cloudflare-token
EOF

: >"${log_file}"
if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/firebase-only.env" --output-dir "${temp_dir}/dist-firebase-only" 2>&1)"; then
  fail "expected Firebase-only auth config to succeed, got: ${output}"
fi

assert_file_contains "${temp_dir}/dist-firebase-only/controlplane-ui-companion.env" '"type":"firebase"'
assert_file_not_contains "${temp_dir}/dist-firebase-only/controlplane-ui-companion.env" '"type":"supabase"'

cat >"${temp_dir}/missing-provider-config.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/missing-auth-providers.devo.json
API_DOMAIN_DEVO=api.devo.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
FIREBASE_API_KEY_DEVO=public-firebase-key-devo
FIREBASE_PROJECT_ID_DEVO=firebase-project-devo
SUPABASE_URL_DEVO=https://devo-project.supabase.co
SUPABASE_ANON_KEY_DEVO=public-supabase-key-devo
CLOUDFLARE_API_TOKEN=test-cloudflare-token
EOF

: >"${log_file}"
if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/missing-provider-config.env" --output-dir "${temp_dir}/dist-missing-provider-config" 2>&1)"; then
  fail "expected missing auth provider config to fall back to default provider names, got: ${output}"
fi

assert_log_not_contains "${log_file}" "gh variable set CONTROLPLANE_UI_STACK_CONFIG --repo customer-org/customer-ltbase-controlplane-ui"

cat >"${temp_dir}/partial-supabase.env" <<'EOF'
STACKS=devo
PROMOTION_PATH=devo
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
API_DOMAIN_DEVO=api.devo.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
FIREBASE_API_KEY_DEVO=public-firebase-key-devo
FIREBASE_PROJECT_ID_DEVO=firebase-project-devo
SUPABASE_URL_DEVO=https://devo-project.supabase.co
SUPABASE_ANON_KEY_DEVO=
CLOUDFLARE_API_TOKEN=test-cloudflare-token
EOF

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/partial-supabase.env" --output-dir "${temp_dir}/dist-partial-supabase" >"${temp_dir}/partial-supabase.log" 2>&1; then
  fail "expected partial Supabase auth config to fail"
fi

assert_log_contains "${temp_dir}/partial-supabase.log" "Supabase control plane UI config for stack devo must include both SUPABASE_URL_DEVO and SUPABASE_ANON_KEY_DEVO"

cat >"${temp_dir}/invalid-domain.env" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
CONTROLPLANE_UI_DOMAIN=admin_customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
CLOUDFLARE_ZONE_ID=zone-123
PROJECT_ID=11111111-1111-4111-8111-111111111111
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
CLOUDFLARE_API_TOKEN=test-cloudflare-token
EOF

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${SCRIPT_PATH}" --env-file "${temp_dir}/invalid-domain.env" --output-dir "${temp_dir}/dist-invalid" >"${temp_dir}/invalid-domain.log" 2>&1; then
  fail "expected invalid Control Plane UI domain to fail"
fi

assert_log_contains "${temp_dir}/invalid-domain.log" "CONTROLPLANE_UI_DOMAIN is invalid"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_POST_SUCCESS=false "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-failed-post" >"${temp_dir}/cloudflare-failure.log" 2>&1; then
  fail "expected Cloudflare POST success=false response to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-failure.log" "Cloudflare API request failed"

: >"${log_file}"
if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_EXISTING_PROJECT=true CURL_GET_EXISTING_DOMAIN=true CURL_DNS_MATCHING_RECORD=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-existing" 2>&1)"; then
  fail "expected idempotent rerun to succeed, got: ${output}"
fi

assert_log_not_contains "${log_file}" "gh repo create customer-org/customer-ltbase-controlplane-ui --template Lychee-Technology/ltbase-controlplane-ui --private --description LTBase Control Plane UI companion for customer-ltbase --clone=false"
assert_log_not_contains "${log_file}" "gh repo clone customer-org/customer-ltbase-controlplane-ui"
assert_log_not_contains "${log_file}" "gh repo clone Lychee-Technology/ltbase-controlplane-ui"
assert_log_not_contains "${log_file}" "rsync -a --exclude=.git"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects/customer-ltbase-controlplane-ui/domains --data"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records --data"
assert_log_not_contains "${log_file}" " add -A"
assert_log_not_contains "${log_file}" " commit -m Sync from template Lychee-Technology/ltbase-controlplane-ui"
assert_log_not_contains "${log_file}" " push"
assert_log_not_contains "${log_file}" "gh variable set CONTROLPLANE_UI_PAGES_PROJECT --repo customer-org/customer-ltbase-controlplane-ui --body customer-ltbase-controlplane-ui"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_DNS_CONFLICT_WRONG_CONTENT=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-dns-conflict-content" >"${temp_dir}/dns-conflict-content.log" 2>&1; then
  fail "expected DNS conflict with wrong content to fail"
fi

assert_log_contains "${temp_dir}/dns-conflict-content.log" "Control Plane UI DNS record already exists with unexpected target"
assert_log_contains "${temp_dir}/dns-conflict-content.log" "wrong-target.pages.dev"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_DNS_CONFLICT_WRONG_TYPE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-dns-conflict-type" >"${temp_dir}/dns-conflict-type.log" 2>&1; then
  fail "expected DNS conflict with wrong type to fail"
fi

assert_log_contains "${temp_dir}/dns-conflict-type.log" "Control Plane UI DNS record already exists with unexpected type"
assert_log_contains "${temp_dir}/dns-conflict-type.log" "TXT"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_DNS_POST_SUCCESS=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-dns-post-failed" >"${temp_dir}/dns-post-failure.log" 2>&1; then
  fail "expected Cloudflare DNS POST success=false response to fail"
fi

assert_log_contains "${temp_dir}/dns-post-failure.log" "Cloudflare API request failed: create DNS CNAME"
assert_log_contains "${temp_dir}/dns-post-failure.log" "dns create failed"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_FAIL_POST_HTTP=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-http-failed-post" >"${temp_dir}/cloudflare-http-failure.log" 2>&1; then
  fail "expected Cloudflare POST HTTP failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-http-failure.log" "create Pages project"
assert_log_contains "${temp_dir}/cloudflare-http-failure.log" "http failure"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_AUTH_FAILURE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-auth-failed-get" >"${temp_dir}/cloudflare-get-auth-failure.log" 2>&1; then
  fail "expected Cloudflare GET auth failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-get-auth-failure.log" "Cloudflare API request failed: get Pages project (HTTP 403)"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_TRANSPORT_FAILURE_POST=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-transport-failed-post" >"${temp_dir}/cloudflare-transport-failure-post.log" 2>&1; then
  fail "expected Cloudflare POST transport failure to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-transport-failure-post.log" "Cloudflare API request failed: create Pages project"
assert_log_contains "${temp_dir}/cloudflare-transport-failure-post.log" "curl: (7) Failed to connect"

: >"${log_file}"
if PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" CURL_GET_SUCCESS_FALSE=true "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist-success-false-get" >"${temp_dir}/cloudflare-success-false-get.log" 2>&1; then
  fail "expected Cloudflare GET success=false response to fail"
fi

assert_log_contains "${temp_dir}/cloudflare-success-false-get.log" "Cloudflare API request failed: get Pages project"
assert_log_contains "${temp_dir}/cloudflare-success-false-get.log" "project lookup failed"
assert_log_not_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects --data"

printf 'PASS: bootstrap-controlplane-ui-companion tests\n'
