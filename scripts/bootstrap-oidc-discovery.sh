#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
OUTPUT_DIR="dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ENV_FILE}" ]]; then
  echo "--env-file is required" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/bootstrap-env.sh"
bootstrap_env_load "${ENV_FILE}"

capture_stdout_quiet() {
  local destination_var="$1"
  local output command_status stderr_file
  shift

  stderr_file="$(mktemp)"
  if output="$("$@" 2>"${stderr_file}")"; then
    rm -f "${stderr_file}"
    printf -v "${destination_var}" '%s' "${output}"
    return 0
  else
    command_status=$?
  fi

  if [[ -s "${stderr_file}" ]]; then
    cat "${stderr_file}" >&2
  fi
  rm -f "${stderr_file}"
  return "${command_status}"
}

required_vars=(GITHUB_OWNER DEPLOYMENT_REPO_NAME OIDC_DISCOVERY_DOMAIN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID OIDC_DISCOVERY_PAGES_PROJECT)
bootstrap_env_require_vars "${required_vars[@]}"

if ! python3 -c 'import re, sys; domain = sys.argv[1]; label = r"(?!-)[a-z0-9-]{1,63}(?<!-)"; pattern = rf"^{label}(\.{label})+$"; sys.exit(0 if re.fullmatch(pattern, domain.lower()) else 1)' "${OIDC_DISCOVERY_DOMAIN}"; then
  printf 'OIDC_DISCOVERY_DOMAIN is invalid: %s\n' "${OIDC_DISCOVERY_DOMAIN}" >&2
  printf 'Use a valid DNS hostname with letters, digits, and hyphens only. Underscores are not allowed.\n' >&2
  exit 1
fi

while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID OIDC_DISCOVERY_AWS_ROLE_NAME OIDC_DISCOVERY_AWS_ROLE_ARN OIDC_ISSUER_URL JWKS_URL
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"

oidc_discovery_summary="${OUTPUT_DIR}/oidc-discovery.env"
oidc_stack_config="$(bootstrap_env_oidc_discovery_stack_config_json)"

cloudflare_headers=(
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
  -H "Content-Type: application/json"
)

cloudflare_require_success() {
  local action="$1"
  local response="$2"

  if ! python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)

sys.exit(0 if payload.get("success") is True else 1)
' <<<"${response}"
  then
    printf 'Cloudflare API request failed: %s\n' "${action}" >&2
    printf '%s\n' "${response}" >&2
    exit 1
  fi
}

cloudflare_get_exists() {
  local action="$1"
  local url="$2"
  local response_file status response curl_status

  response_file="$(mktemp)"
  if capture_stdout_quiet status curl -sS -o "${response_file}" -w '%{http_code}' "${cloudflare_headers[@]}" "${url}"; then
    :
  else
    curl_status=$?
    response="$(<"${response_file}")"
    rm -f "${response_file}"
    printf 'Cloudflare API request failed: %s\n' "${action}" >&2
    if [[ -n "${response}" ]]; then
      printf '%s\n' "${response}" >&2
    fi
    exit "${curl_status}"
  fi
  response="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ "${status}" =~ ^2 ]]; then
    cloudflare_require_success "${action}" "${response}"
    return 0
  fi

  if [[ "${status}" == "404" ]]; then
    return 1
  fi

  printf 'Cloudflare API request failed: %s (HTTP %s)\n' "${action}" "${status}" >&2
  if [[ -n "${response}" ]]; then
    printf '%s\n' "${response}" >&2
  fi
  exit 1
}

cloudflare_post() {
  local action="$1"
  local url="$2"
  local payload="$3"
  local response_file status response curl_status

  response_file="$(mktemp)"
  if capture_stdout_quiet status curl -sS -o "${response_file}" -w '%{http_code}' -X POST "${cloudflare_headers[@]}" "${url}" --data "${payload}"; then
    :
  else
    curl_status=$?
    response="$(<"${response_file}")"
    rm -f "${response_file}"
    printf 'Cloudflare API request failed: %s\n' "${action}" >&2
    if [[ -n "${response}" ]]; then
      printf '%s\n' "${response}" >&2
    fi
    exit "${curl_status}"
  fi
  response="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ ! "${status}" =~ ^2 ]]; then
    printf 'Cloudflare API request failed: %s (HTTP %s)\n' "${action}" "${status}" >&2
    if [[ -n "${response}" ]]; then
      printf '%s\n' "${response}" >&2
    fi
    exit 1
  fi

  cloudflare_require_success "${action}" "${response}"
}

cloudflare_get_json() {
  local action="$1"
  local url="$2"
  local response_file status response curl_status

  response_file="$(mktemp)"
  if capture_stdout_quiet status curl -sS -o "${response_file}" -w '%{http_code}' "${cloudflare_headers[@]}" "${url}"; then
    :
  else
    curl_status=$?
    response="$(<"${response_file}")"
    rm -f "${response_file}"
    printf 'Cloudflare API request failed: %s\n' "${action}" >&2
    if [[ -n "${response}" ]]; then
      printf '%s\n' "${response}" >&2
    fi
    exit "${curl_status}"
  fi
  response="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ ! "${status}" =~ ^2 ]]; then
    printf 'Cloudflare API request failed: %s (HTTP %s)\n' "${action}" "${status}" >&2
    if [[ -n "${response}" ]]; then
      printf '%s\n' "${response}" >&2
    fi
    exit 1
  fi

  cloudflare_require_success "${action}" "${response}"
  printf '%s' "${response}"
}

ensure_oidc_discovery_dns_record() {
  local dns_lookup_response record_state

  dns_lookup_response="$(cloudflare_get_json "get DNS records" "${dns_lookup_url}")"
  record_state="$(printf '%s' "${dns_lookup_response}" | python3 -c '
import json
import sys

name = sys.argv[1]
target = sys.argv[2]
payload = json.load(sys.stdin)
records = [record for record in (payload.get("result") or []) if (record.get("name") or "") == name]

if not records:
    print("missing")
    sys.exit(0)

for record in records:
    record_type = (record.get("type") or "").upper()
    record_content = record.get("content") or ""

    if record_type != "CNAME":
        print(f"conflict_type:{record_type}")
        sys.exit(0)

    if record_content == target:
        print("matching")
        sys.exit(0)

    print(f"conflict_target:{record_content}")
    sys.exit(0)

print("missing")
' "${OIDC_DISCOVERY_DOMAIN}" "${oidc_pages_target}")"

  case "${record_state}" in
    missing)
      local dns_payload
      dns_payload="$(python3 - "${OIDC_DISCOVERY_DOMAIN}" "${oidc_pages_target}" <<'PY'
import json
import sys

print(json.dumps({
    "type": "CNAME",
    "name": sys.argv[1],
    "content": sys.argv[2],
    "proxied": False,
    "ttl": 1,
}, separators=(",", ":")))
PY
)"
      cloudflare_post "create DNS CNAME" "${dns_records_url}" "${dns_payload}"
      ;;
    matching)
      ;;
    conflict_type:*)
      printf 'OIDC discovery DNS record already exists with unexpected type: %s\n' "${record_state#conflict_type:}" >&2
      exit 1
      ;;
    conflict_target:*)
      printf 'OIDC discovery DNS record already exists with unexpected target: %s\n' "${record_state#conflict_target:}" >&2
      exit 1
      ;;
    *)
      printf 'Unable to determine OIDC discovery DNS state\n' >&2
      exit 1
      ;;
  esac
}

pages_project_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}"
pages_projects_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects"
pages_domain_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}/domains/${OIDC_DISCOVERY_DOMAIN}"
pages_domains_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}/domains"
oidc_pages_target="${OIDC_DISCOVERY_PAGES_PROJECT}.pages.dev"
dns_records_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
dns_lookup_url="${dns_records_url}?name=${OIDC_DISCOVERY_DOMAIN}"

capture_stdout_quiet repo_metadata gh api "repos/${DEPLOYMENT_REPO}"
default_branch="$(python3 -c 'import json, sys; data = json.load(sys.stdin); print(data.get("default_branch", "main"))' <<<"${repo_metadata}"
)"

bootstrap_env_info "Ensuring Pages project: ${OIDC_DISCOVERY_PAGES_PROJECT}"
if ! cloudflare_get_exists "get Pages project" "${pages_project_url}"; then
  project_payload="$(python3 - "${OIDC_DISCOVERY_PAGES_PROJECT}" "${default_branch}" <<'PY'
import json
import sys

print(json.dumps({
    "name": sys.argv[1],
    "production_branch": sys.argv[2],
}, separators=(",", ":")))
PY
)"
  cloudflare_post "create Pages project" "${pages_projects_url}" "${project_payload}"
fi

bootstrap_env_info "Ensuring Pages domain: ${OIDC_DISCOVERY_DOMAIN}"
if ! cloudflare_get_exists "get Pages custom domain" "${pages_domain_url}"; then
  domain_payload="$(python3 - "${OIDC_DISCOVERY_DOMAIN}" <<'PY'
import json
import sys

print(json.dumps({"name": sys.argv[1]}, separators=(",", ":")))
PY
)"
  cloudflare_post "create Pages custom domain" "${pages_domains_url}" "${domain_payload}"
fi

bootstrap_env_info "Reconciling DNS for OIDC discovery domain: ${OIDC_DISCOVERY_DOMAIN}"
ensure_oidc_discovery_dns_record

bootstrap_env_info "Configuring deployment repository variables for OIDC discovery"
bootstrap_env_run_quiet gh variable set OIDC_DISCOVERY_DOMAIN --repo "${DEPLOYMENT_REPO}" --body "${OIDC_DISCOVERY_DOMAIN}"
bootstrap_env_run_quiet gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo "${DEPLOYMENT_REPO}" --body "${oidc_stack_config}"
bootstrap_env_run_quiet gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo "${DEPLOYMENT_REPO}" --body "${OIDC_DISCOVERY_PAGES_PROJECT}"
create_or_update_discovery_role() {
  local stack="$1"
  local upper_name account_id region role_name role_arn provider_arn
  local trust_policy_path role_policy_path

  bootstrap_env_require_aws_credentials_for_stack "${stack}"

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  role_name="$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_NAME "${stack}")"
  role_arn="$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_ARN "${stack}")"
  provider_arn="arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com"
  trust_policy_path="${OUTPUT_DIR}/oidc-discovery-${stack}-trust-policy.json"
  role_policy_path="${OUTPUT_DIR}/oidc-discovery-${stack}-role-policy.json"

  cat >"${trust_policy_path}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${DEPLOYMENT_REPO}:ref:refs/heads/${default_branch}"
          ]
        }
      }
    }
  ]
}
EOF

  cat >"${role_policy_path}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:GetPublicKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  bootstrap_env_info "Reconciling OIDC discovery IAM role for stack: ${stack}"
  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" >/dev/null 2>&1; then
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
  fi

  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam create-role --role-name "${role_name}" --assume-role-policy-document "file://${trust_policy_path}"
  fi

  bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam update-assume-role-policy --role-name "${role_name}" --policy-document "file://${trust_policy_path}"
  bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam put-role-policy --role-name "${role_name}" --policy-name LTBaseOIDCDiscoveryAccess --policy-document "file://${role_policy_path}"

  cat >>"${oidc_discovery_summary}" <<EOF
OIDC_DISCOVERY_AWS_ROLE_ARN_${upper_name}=${role_arn}
EOF
}

: >"${oidc_discovery_summary}"
cat >>"${oidc_discovery_summary}" <<EOF
OIDC_DISCOVERY_PAGES_PROJECT=${OIDC_DISCOVERY_PAGES_PROJECT}
OIDC_DISCOVERY_DOMAIN=${OIDC_DISCOVERY_DOMAIN}
EOF

while IFS= read -r stack; do
  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  create_or_update_discovery_role "${stack}"
  cat >>"${oidc_discovery_summary}" <<EOF
OIDC_ISSUER_URL_${upper_name}=$(bootstrap_env_resolve_stack_value OIDC_ISSUER_URL "${stack}")
JWKS_URL_${upper_name}=$(bootstrap_env_resolve_stack_value JWKS_URL "${stack}")
EOF
done < <(bootstrap_env_each_stack)
