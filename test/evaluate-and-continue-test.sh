#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/evaluate-and-continue.sh"

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
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
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

write_env() {
  local path="$1"
  cat >"${path}" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=us-east-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_STAGING=staging-profile
AWS_PROFILE_PROD=prod-profile
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_STAGING=ltbase-deploy-staging
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PULUMI_BACKEND_URL=s3://test-pulumi-state
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
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
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
}

write_env_without_mtls() {
  local path="$1"
  cat >"${path}" <<'EOF'
STACKS=devo,staging,prod
PROMOTION_PATH=devo,staging,prod
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_STAGING=us-east-1
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_STAGING=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_STAGING=staging-profile
AWS_PROFILE_PROD=prod-profile
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
AWS_ROLE_NAME_STAGING=ltbase-deploy-staging
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
PULUMI_BACKEND_URL=s3://test-pulumi-state
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
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CLOUDFLARE_ACCOUNT_ID=cf-account-123
GEMINI_MODEL=gemini-3.1-flash-lite
DSQL_PORT=5432
DSQL_DB=postgres
DSQL_USER=admin
DSQL_PROJECT_SCHEMA=ltbase
GEMINI_API_KEY=test-gemini-key
CLOUDFLARE_API_TOKEN=test-cloudflare-token
LTBASE_RELEASES_TOKEN=test-release-token
EOF
}

setup_fake_bin() {
  local fake_bin="$1"
  local log_file="$2"

  mkdir -p "${fake_bin}"

  cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"${COMMAND_LOG}"
cmd="${1:-}"
sub="${2:-}"
if [[ "${cmd} ${sub}" == "repo view" ]]; then
  if [[ "${SCENARIO}" == "repo_config_missing" || "${SCENARIO}" == "bootstrap_force" ]]; then
    printf 'GraphQL: Could not resolve to a Repository with the name %s.\n' "${3:-unknown}" >&2
    exit 1
  fi
  if [[ "${3:-}" == "customer-org/customer-ltbase-oidc-discovery" && "${SCENARIO}" == "oidc_companion_missing" ]]; then
    printf 'GraphQL: Could not resolve to a Repository with the name %s.\n' "${3}" >&2
    exit 1
  fi
  exit 0
fi
if [[ "${cmd}" == "api" ]]; then
  url="${2:-}"
  method="GET"
  for arg in "$@"; do
    if [[ "${arg}" == "--method" ]]; then
      shift_next="true"
    elif [[ "${shift_next:-}" == "true" ]]; then
      method="${arg}"
      shift_next=""
    fi
  done
  # Check for method in positional args
  local_args=("$@")
  for i in "${!local_args[@]}"; do
    if [[ "${local_args[$i]}" == "--method" && -n "${local_args[$((i + 1))]:-}" ]]; then
      method="${local_args[$((i + 1))]}"
    fi
  done
  # Environment check/create
  if [[ "${url}" == *"/environments/"* ]]; then
    if [[ "${SCENARIO}" == "envs_missing" && "${method}" == "GET" ]]; then
      exit 1
    fi
    if [[ "${method}" == "PUT" ]]; then
      printf '{"name":"env-created"}\n'
      exit 0
    fi
    exit 0
  fi
  if [[ "${url}" == "repos/customer-org/customer-ltbase-oidc-discovery" ]]; then
    printf '{"default_branch":"main","private":false}\n'
    exit 0
  fi
  exit 0
fi
if [[ "${cmd} ${sub}" == "variable list" ]]; then
  if [[ "${4:-}" == "customer-org/customer-ltbase-oidc-discovery" ]]; then
    if [[ "${SCENARIO}" == "oidc_companion_missing" ]]; then
      printf '[]'
    else
      printf '[{"name":"OIDC_DISCOVERY_DOMAIN"},{"name":"OIDC_DISCOVERY_STACK_CONFIG"}]'
    fi
    exit 0
  fi
  if [[ "${SCENARIO}" == "repo_config_missing" ]]; then
    printf '[]'
  elif [[ "${SCENARIO}" == "repo_topology_missing" ]]; then
    printf '[{"name":"AWS_REGION_DEVO"},{"name":"AWS_REGION_STAGING"},{"name":"AWS_REGION_PROD"},{"name":"PULUMI_BACKEND_URL"},{"name":"PULUMI_SECRETS_PROVIDER_DEVO"},{"name":"PULUMI_SECRETS_PROVIDER_STAGING"},{"name":"PULUMI_SECRETS_PROVIDER_PROD"},{"name":"LTBASE_RELEASES_REPO"},{"name":"LTBASE_RELEASE_ID"}]'
  else
    printf '[{"name":"AWS_REGION_DEVO"},{"name":"AWS_REGION_STAGING"},{"name":"AWS_REGION_PROD"},{"name":"PULUMI_BACKEND_URL"},{"name":"PULUMI_SECRETS_PROVIDER_DEVO"},{"name":"PULUMI_SECRETS_PROVIDER_STAGING"},{"name":"PULUMI_SECRETS_PROVIDER_PROD"},{"name":"LTBASE_RELEASES_REPO"},{"name":"LTBASE_RELEASE_ID"},{"name":"STACKS"},{"name":"PROMOTION_PATH"},{"name":"PREVIEW_DEFAULT_STACK"}]'
  fi
  exit 0
fi
if [[ "${cmd} ${sub}" == "secret list" ]]; then
  if [[ "${4:-}" == "customer-org/customer-ltbase-oidc-discovery" ]]; then
    printf '[]'
    exit 0
  fi
  if [[ "${SCENARIO}" == "repo_config_missing" ]]; then
    printf '[]'
  else
    printf '[{"name":"AWS_ROLE_ARN_DEVO"},{"name":"AWS_ROLE_ARN_STAGING"},{"name":"AWS_ROLE_ARN_PROD"},{"name":"LTBASE_RELEASES_TOKEN"},{"name":"CLOUDFLARE_API_TOKEN"}]'
  fi
  exit 0
fi
if [[ "${cmd} ${sub}" == "workflow run" ]]; then
  printf 'NOISY_GH_STDOUT workflow success\n'
  printf 'NOISY_GH_STDERR workflow success\n' >&2
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
command_key="${args[0]:-} ${args[1]:-}"
case "${SCENARIO}:${command_key}" in
  foundation_missing:iam\ get-open-id-connect-provider|foundation_missing:iam\ get-role)
    exit 255
    ;;
  foundation_missing:s3api\ head-bucket)
    exit 1
    ;;
  foundation_missing:kms\ list-aliases)
    printf 'NOISY_AWS_STDERR kms list success\n' >&2
    printf '{"Aliases":[]}'
    exit 0
    ;;
  bootstrap_force:iam\ get-open-id-connect-provider|bootstrap_force:iam\ get-role)
    exit 255
    ;;
  bootstrap_force:s3api\ head-bucket)
    exit 1
    ;;
  bootstrap_force:kms\ list-aliases)
    printf 'NOISY_AWS_STDERR kms list success\n' >&2
    printf '{"Aliases":[]}'
    exit 0
    ;;
  oidc_companion_missing:iam\ get-role)
    if printf '%s\n' "$*" | grep -Fq 'oidc-discovery'; then
      exit 255
    fi
    exit 0
    ;;
  bootstrap_force:kms\ create-key)
    printf 'NOISY_AWS_STDERR kms create success\n' >&2
    printf 'key-123\n'
    exit 0
    ;;
  *:kms\ list-aliases)
    printf 'NOISY_AWS_STDERR kms list success\n' >&2
    printf '{"Aliases":[{"AliasName":"alias/test-pulumi-secrets","TargetKeyId":"key-123"}]}'
    exit 0
    ;;
  *:dsql\ get-cluster)
    printf 'NOISY_AWS_STDOUT dsql success\n'
    printf 'NOISY_AWS_STDERR dsql success\n' >&2
    printf 'managed.%s.endpoint.example.com\n' "${STACK_HINT:-devo}"
    exit 0
    ;;
esac
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
output_file=""
write_format=""
args=("$@")
index=0
while [[ ${index} -lt ${#args[@]} ]]; do
  case "${args[${index}]}" in
    -X)
      method="${args[$((index + 1))]}"
      index=$((index + 2))
      ;;
    -o)
      output_file="${args[$((index + 1))]}"
      index=$((index + 2))
      ;;
    -w)
      write_format="${args[$((index + 1))]}"
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
if [[ "${SCENARIO}" == "oidc_companion_missing" && "${method}" == "GET" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  printf 'NOISY_CURL_STDERR expected missing project\n' >&2
  exit 22
fi
if [[ "${SCENARIO}" == "oidc_companion_missing" && "${method}" == "GET" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  printf 'NOISY_CURL_STDERR expected missing domain\n' >&2
  exit 22
fi
if [[ "${SCENARIO}" == "oidc_project_success_false" && "${method}" == "GET" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery" ]]; then
  if [[ -n "${output_file}" ]]; then
    printf '{"success":false,"errors":[{"message":"project state unavailable"}]}' >"${output_file}"
  else
    printf '{"success":false,"errors":[{"message":"project state unavailable"}]}'
  fi
  if [[ "${write_format}" == "%{http_code}" ]]; then
    printf 'NOISY_CURL_STDERR http code success\n' >&2
    printf '200'
  fi
  printf 'NOISY_CURL_STDOUT generic success\n'
  printf 'NOISY_CURL_STDERR generic success\n' >&2
  exit 0
fi
if [[ "${SCENARIO}" == "oidc_domain_success_false" && "${method}" == "GET" && "${url}" == *"/pages/projects/customer-ltbase-oidc-discovery/domains/oidc.customer.example.com" ]]; then
  if [[ -n "${output_file}" ]]; then
    printf '{"success":false,"errors":[{"message":"domain state unavailable"}]}' >"${output_file}"
  else
    printf '{"success":false,"errors":[{"message":"domain state unavailable"}]}'
  fi
  if [[ "${write_format}" == "%{http_code}" ]]; then
    printf 'NOISY_CURL_STDERR http code success\n' >&2
    printf '200'
  fi
  printf 'NOISY_CURL_STDOUT generic success\n'
  printf 'NOISY_CURL_STDERR generic success\n' >&2
  exit 0
fi
if [[ "${SCENARIO}" == "oidc_dns_success_false" && "${method}" == "GET" && "${url}" == *"/zones/zone-123/dns_records?type=CNAME&name=oidc.customer.example.com" ]]; then
  if [[ -n "${output_file}" ]]; then
    printf '{"success":false,"errors":[{"message":"dns state unavailable"}]}' >"${output_file}"
  else
    printf '{"success":false,"errors":[{"message":"dns state unavailable"}]}'
  fi
  if [[ "${write_format}" == "%{http_code}" ]]; then
    printf 'NOISY_CURL_STDERR http code success\n' >&2
    printf '200'
  fi
  printf 'NOISY_CURL_STDOUT generic success\n'
  printf 'NOISY_CURL_STDERR generic success\n' >&2
  exit 0
fi
if [[ "${SCENARIO}" == "oidc_missing_dns" && "${method}" == "GET" && "${url}" == *"/zones/zone-123/dns_records?type=CNAME&name=oidc.customer.example.com" ]]; then
  if [[ -n "${output_file}" ]]; then
    printf '{"success":true,"result":[]}' >"${output_file}"
  else
    printf '{"success":true,"result":[]}'
  fi
  if [[ "${write_format}" == "%{http_code}" ]]; then
    printf 'NOISY_CURL_STDERR http code success\n' >&2
    printf '200'
  fi
  printf 'NOISY_CURL_STDOUT generic success\n'
  printf 'NOISY_CURL_STDERR generic success\n' >&2
  exit 0
fi
if [[ -n "${output_file}" ]]; then
  printf '{"success":true}' >"${output_file}"
else
  printf '{"success":true}'
fi
if [[ "${write_format}" == "%{http_code}" ]]; then
  printf 'NOISY_CURL_STDERR http code success\n' >&2
  printf '200'
fi
printf 'NOISY_CURL_STDOUT generic success\n'
printf 'NOISY_CURL_STDERR generic success\n' >&2
EOF
  chmod +x "${fake_bin}/curl"

  cat >"${fake_bin}/pulumi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'AWS_REGION=%s AWS_DEFAULT_REGION=%s AWS_PROFILE=%s pulumi %s\n' "${AWS_REGION:-}" "${AWS_DEFAULT_REGION:-}" "${AWS_PROFILE:-}" "$*" >>"${COMMAND_LOG}"

stack_name() {
  local previous=""
  for arg in "$@"; do
    if [[ "${previous}" == "--stack" ]]; then
      printf '%s' "${arg}"
      return 0
    fi
    previous="${arg}"
  done
  printf '%s' "${STACK_HINT:-devo}"
}

if [[ "${1:-}" == "login" ]]; then
  printf 'NOISY_PULUMI_STDOUT login success\n'
  printf 'NOISY_PULUMI_STDERR login success\n' >&2
  exit 0
fi
if [[ "${1:-} ${2:-}" == "stack select" ]]; then
  if [[ "${SCENARIO}" == "bootstrap_force" ]]; then
    printf 'error: no stack named %s found\n' "$(stack_name "$@")" >&2
    exit 1
  fi
  exit 0
fi
if [[ "${1:-} ${2:-}" == "stack init" ]]; then
  printf 'NOISY_PULUMI_STDOUT stack init success\n'
  printf 'NOISY_PULUMI_STDERR stack init success\n' >&2
  exit 0
fi
if [[ "${1:-} ${2:-} ${3:-} ${4:-}" == "stack output dsqlClusterIdentifier --stack" ]]; then
  current_stack="$(stack_name "$@")"
  case "${SCENARIO}:${current_stack}" in
    rollout_mix:devo)
      exit 1
      ;;
    rollout_mix:staging|rollout_mix:prod)
      printf 'cluster-%s\n' "${current_stack}"
      exit 0
      ;;
  esac
  exit 1
fi
if [[ "${1:-} ${2:-} ${3:-} ${4:-}" == "config get dsqlEndpoint --stack" ]]; then
  current_stack="$(stack_name "$@")"
  case "${SCENARIO}:${current_stack}" in
    rollout_mix:prod)
      printf 'managed.prod.endpoint.example.com\n'
      exit 0
      ;;
    rollout_mix:staging)
      exit 1
      ;;
  esac
  exit 1
fi
if [[ "${1:-} ${2:-} ${3:-} ${4:-}" == "config get mtlsTruststoreFile --stack" ]]; then
  if [[ "${SCENARIO}" == "missing_mtls_stack_config" ]]; then
    exit 1
  fi
  printf 'infra/certs/cloudflare-origin-pull-ca.pem\n'
  exit 0
fi
if [[ "${1:-} ${2:-} ${3:-} ${4:-}" == "config get mtlsTruststoreKey --stack" ]]; then
  if [[ "${SCENARIO}" == "missing_mtls_stack_config" ]]; then
    exit 1
  fi
  printf 'mtls/cloudflare-origin-pull-ca.pem\n'
  exit 0
fi
if [[ "${1:-} ${2:-}" == "config set" || "${1:-} ${2:-}" == "config rm" ]]; then
  printf 'NOISY_PULUMI_STDOUT config success\n'
  printf 'NOISY_PULUMI_STDERR config success\n' >&2
  exit 0
fi
printf 'NOISY_PULUMI_STDOUT generic success\n'
printf 'NOISY_PULUMI_STDERR generic success\n' >&2
exit 0
EOF
  chmod +x "${fake_bin}/pulumi"

  : >"${log_file}"
}

run_expect_exit_code() {
  local expected="$1"
  shift
  set +e
  "$@"
  local status=$?
  set -e
  if [[ "${status}" -ne "${expected}" ]]; then
    fail "expected exit code ${expected}, got ${status}"
  fi
}

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

mkdir -p "${temp_dir}/infra"
for stack in devo staging prod; do
  cat >"${temp_dir}/infra/Pulumi.${stack}.yaml" <<EOF
config:
  ltbase-infra:awsRegion: test
EOF
done

write_env "${temp_dir}/.env"
setup_fake_bin "${temp_dir}/bin" "${temp_dir}/commands.log"

write_env_without_mtls "${temp_dir}/missing-mtls.env"

run_expect_exit_code 1 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="rollout_mix" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/missing-mtls.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-missing-mtls-env"

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="foundation_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-foundation"

assert_file_contains "${temp_dir}/report-foundation/report.json" '"deploymentRepo": "customer-org/customer-ltbase"'
assert_file_contains "${temp_dir}/report-foundation/report.json" '"status": "needs_foundation"'

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="repo_config_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-repo"

assert_file_contains "${temp_dir}/report-repo/report.json" '"status": "needs_repo_config"'

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="repo_topology_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-topology-missing"

assert_file_contains "${temp_dir}/report-topology-missing/report.json" '"status": "needs_repo_config"'

rm -f "${temp_dir}/infra/Pulumi.devo.yaml" "${temp_dir}/infra/Pulumi.staging.yaml" "${temp_dir}/infra/Pulumi.prod.yaml"
run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="rollout_mix" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-stack"

assert_file_contains "${temp_dir}/report-stack/report.json" '"status": "needs_stack_bootstrap"'

for stack in devo staging prod; do
  cat >"${temp_dir}/infra/Pulumi.${stack}.yaml" <<EOF
config:
  ltbase-infra:awsRegion: test
EOF
done

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="rollout_mix" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-rollout"

assert_file_contains "${temp_dir}/report-rollout/report.json" '"stack": "devo"'
assert_file_contains "${temp_dir}/report-rollout/report.json" '"status": "needs_rollout"'
assert_file_contains "${temp_dir}/report-rollout/report.json" '"stack": "staging"'
assert_file_contains "${temp_dir}/report-rollout/report.json" '"status": "needs_dsql_reconcile"'
assert_file_contains "${temp_dir}/report-rollout/report.json" '"stack": "prod"'
assert_file_contains "${temp_dir}/report-rollout/report.json" '"status": "complete"'
assert_log_contains "${temp_dir}/commands.log" "AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1 AWS_PROFILE=devo-profile pulumi login s3://test-pulumi-state"
assert_log_contains "${temp_dir}/commands.log" "AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1 AWS_PROFILE=devo-profile pulumi stack select devo"
assert_log_contains "${temp_dir}/commands.log" "AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 AWS_PROFILE=staging-profile pulumi stack select staging"
assert_log_contains "${temp_dir}/commands.log" "AWS_REGION=us-west-2 AWS_DEFAULT_REGION=us-west-2 AWS_PROFILE=prod-profile pulumi stack select prod"

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="missing_mtls_stack_config" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-missing-mtls-stack-config"

assert_file_contains "${temp_dir}/report-missing-mtls-stack-config/report.json" '"status": "needs_stack_bootstrap"'

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="oidc_companion_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-oidc"

assert_file_contains "${temp_dir}/report-oidc/report.json" '"oidcDiscovery"'
assert_file_contains "${temp_dir}/report-oidc/report.json" '"status": "needs_oidc_companion"'

oidc_missing_output="$(env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="oidc_companion_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-oidc-quiet" 2>&1 || true)"

assert_log_not_contains <(printf '%s' "${oidc_missing_output}") "NOISY_CURL_STDERR expected missing project"
assert_log_not_contains <(printf '%s' "${oidc_missing_output}") "NOISY_CURL_STDERR expected missing domain"

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="oidc_missing_dns" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-oidc-missing-dns"

assert_file_contains "${temp_dir}/report-oidc-missing-dns/report.json" '"status": "needs_oidc_companion"'
assert_file_contains "${temp_dir}/report-oidc-missing-dns/report.json" '"pagesDnsPresent": false'

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="oidc_project_success_false" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-oidc-project-success-false"

assert_file_contains "${temp_dir}/report-oidc-project-success-false/report.json" '"status": "needs_oidc_companion"'
assert_file_contains "${temp_dir}/report-oidc-project-success-false/report.json" '"pagesProjectPresent": false'

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="oidc_domain_success_false" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-oidc-domain-success-false"

assert_file_contains "${temp_dir}/report-oidc-domain-success-false/report.json" '"status": "needs_oidc_companion"'
assert_file_contains "${temp_dir}/report-oidc-domain-success-false/report.json" '"pagesDomainPresent": false'

run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="oidc_dns_success_false" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-oidc-dns-success-false"

assert_file_contains "${temp_dir}/report-oidc-dns-success-false/report.json" '"status": "needs_oidc_companion"'
assert_file_contains "${temp_dir}/report-oidc-dns-success-false/report.json" '"pagesDnsPresent": false'

rm -rf "${temp_dir}/infra"
mkdir -p "${temp_dir}/infra"
run_expect_exit_code 0 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="bootstrap_force" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --scope bootstrap --force --release-id v9.9.9 --report-dir "${temp_dir}/report-force"

assert_log_contains "${temp_dir}/commands.log" "gh repo create customer-org/customer-ltbase"
assert_log_contains "${temp_dir}/commands.log" "aws --profile devo-profile iam create-open-id-connect-provider"
assert_log_contains "${temp_dir}/commands.log" "aws --profile prod-profile iam create-open-id-connect-provider"
assert_log_contains "${temp_dir}/commands.log" "gh repo create customer-org/customer-ltbase-oidc-discovery"
assert_log_contains "${temp_dir}/commands.log" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"
assert_log_contains "${temp_dir}/commands.log" "pulumi stack init devo --secrets-provider awskms://alias/test-pulumi-secrets?region=ap-northeast-1"
assert_log_contains "${temp_dir}/commands.log" "pulumi stack init staging --secrets-provider awskms://alias/test-pulumi-secrets?region=us-east-1"
assert_log_contains "${temp_dir}/commands.log" "pulumi stack init prod --secrets-provider awskms://alias/test-pulumi-secrets?region=us-west-2"
assert_log_contains "${temp_dir}/commands.log" "gh workflow run rollout.yml --repo customer-org/customer-ltbase -f release_id=v9.9.9"

# Bug #20: force mode with rollout_mix should reconcile DSQL and resume rollout via rollout-hop
for stack in devo staging prod; do
  cat >"${temp_dir}/infra/Pulumi.${stack}.yaml" <<EOF
config:
  ltbase-infra:awsRegion: test
EOF
done

: >"${temp_dir}/commands.log"
force_rollout_output="$(env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="rollout_mix" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-force-rollout" --force --release-id v2.0.0 2>&1)"

# Should call reconcile for staging (needs_dsql_reconcile)
assert_log_contains "${temp_dir}/report-force-rollout/actions.log" "reconcile-managed-dsql-endpoint.sh --env-file ${temp_dir}/.env --stack staging --infra-dir ${temp_dir}/infra"
# Should dispatch rollout-hop.yml for devo (first needs_rollout stack), NOT rollout.yml
assert_log_contains "${temp_dir}/report-force-rollout/actions.log" "gh workflow run rollout-hop.yml --repo customer-org/customer-ltbase -f release_id=v2.0.0 -f target_stack=devo -f continue_chain=true"
assert_log_contains <(printf '%s' "${force_rollout_output}") "[info] Reconciling managed DSQL endpoint: staging"
assert_log_contains <(printf '%s' "${force_rollout_output}") "[info] Dispatching rollout workflow: rollout-hop.yml"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_GH_STDOUT"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_GH_STDERR"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_AWS_STDOUT"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_AWS_STDERR"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_CURL_STDOUT"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_CURL_STDERR"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_PULUMI_STDOUT"
assert_log_not_contains <(printf '%s' "${force_rollout_output}") "NOISY_PULUMI_STDERR"
# Should NOT dispatch rollout.yml
if grep -Fq "gh workflow run rollout.yml" "${temp_dir}/report-force-rollout/actions.log"; then
  fail "force mode with needs_rollout should dispatch rollout-hop.yml, not rollout.yml"
fi

# Bug #21: force mode should repair missing promotion environments
: >"${temp_dir}/commands.log"
run_expect_exit_code 0 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="envs_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-force-envs" --force --release-id v3.0.0

# Should create missing promotion environments (staging and prod, not devo which is first)
assert_log_contains "${temp_dir}/report-force-envs/actions.log" "gh api repos/customer-org/customer-ltbase/environments/staging --method PUT"
assert_log_contains "${temp_dir}/report-force-envs/actions.log" "gh api repos/customer-org/customer-ltbase/environments/prod --method PUT"

# Bug #21: envs_missing should be detected as non-complete by repo_config_present
: >"${temp_dir}/commands.log"
run_expect_exit_code 2 env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="envs_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-envs-detect"

assert_file_contains "${temp_dir}/report-envs-detect/report.json" '"status": "needs_repo_config"'

force_output="$(env \
  PATH="${temp_dir}/bin:$PATH" \
  COMMAND_LOG="${temp_dir}/commands.log" \
  SCENARIO="envs_missing" \
  "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --infra-dir "${temp_dir}/infra" --report-dir "${temp_dir}/report-force-envs-quiet" --force --release-id v4.0.0 2>&1)"

assert_log_contains <(printf '%s' "${force_output}") "[info] Ensuring protected deployment environment: staging"
assert_log_contains <(printf '%s' "${force_output}") "[info] Dispatching rollout workflow: rollout.yml"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_GH_STDOUT"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_GH_STDERR"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_AWS_STDOUT"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_AWS_STDERR"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_CURL_STDOUT"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_CURL_STDERR"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_PULUMI_STDOUT"
assert_log_not_contains <(printf '%s' "${force_output}") "NOISY_PULUMI_STDERR"

printf 'PASS: evaluate-and-continue tests\n'
