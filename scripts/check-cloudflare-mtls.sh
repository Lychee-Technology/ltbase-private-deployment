#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
STACK="devo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --stack)
      STACK="$2"
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ENV_FILE}" ]]; then
  printf '--env-file is required\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/bootstrap-env.sh"
bootstrap_env_load "${ENV_FILE}"

if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  export CLOUDFLARE_API_TOKEN
fi

if ! bootstrap_env_has_stack "${STACK}"; then
  printf 'unknown stack: %s\n' "${STACK}" >&2
  exit 1
fi

bootstrap_env_require_vars CLOUDFLARE_ZONE_ID CLOUDFLARE_API_TOKEN MTLS_TRUSTSTORE_KEY || exit 1
bootstrap_env_require_stack_values "${STACK}" AWS_REGION API_DOMAIN CONTROL_DOMAIN AUTH_DOMAIN RUNTIME_BUCKET || exit 1

selected_api_domain="$(bootstrap_env_resolve_stack_value API_DOMAIN "${STACK}")"
selected_control_domain="$(bootstrap_env_resolve_stack_value CONTROL_DOMAIN "${STACK}")"
selected_auth_domain="$(bootstrap_env_resolve_stack_value AUTH_DOMAIN "${STACK}")"
selected_runtime_bucket="$(bootstrap_env_resolve_stack_value RUNTIME_BUCKET "${STACK}")"
expected_truststore_uri="s3://${selected_runtime_bucket}/${MTLS_TRUSTSTORE_KEY}"

cloudflare_headers=(
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
  -H "Content-Type: application/json"
)

overall_status=0

pass() {
  printf 'PASS %s\n' "$1"
}

info() {
  printf 'INFO %s\n' "$1"
}

fail_check() {
  printf 'FAIL %s\n' "$1"
  overall_status=1
}

cloudflare_get_json() {
  local url="$1"
  local action="$2"
  local response_file status response success

  response_file="$(mktemp)"
  if ! status="$(curl -sS -o "${response_file}" -w '%{http_code}' "${cloudflare_headers[@]}" "${url}")"; then
    rm -f "${response_file}"
    printf 'Cloudflare API request failed: %s\n' "${action}" >&2
    return 1
  fi

  response="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ "${status}" != "200" ]]; then
    printf 'Cloudflare API request failed: %s (HTTP %s)\n' "${action}" "${status}" >&2
    printf '%s\n' "${response}" >&2
    return 1
  fi

  success="$(printf '%s' "${response}" | jq -r '.success // false')"
  if [[ "${success}" != "true" ]]; then
    printf 'Cloudflare API request failed: %s\n' "${action}" >&2
    printf '%s\n' "${response}" >&2
    return 1
  fi

  printf '%s' "${response}"
}

check_cloudflare_record() {
  local domain="$1"
  local response proxied content

  response="$(cloudflare_get_json "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=CNAME&name=${domain}" "get DNS record ${domain}")" || {
    fail_check "Cloudflare DNS ${domain} lookup"
    return
  }

  proxied="$(printf '%s' "${response}" | jq -r '.result[0].proxied // "missing"')"
  content="$(printf '%s' "${response}" | jq -r '.result[0].content // "missing"')"

  if [[ "${proxied}" == "true" ]]; then
    pass "Cloudflare DNS ${domain} is proxied"
  else
    fail_check "Cloudflare DNS ${domain} is proxied"
  fi

  info "Cloudflare DNS ${domain} target: ${content}"
}

check_cloudflare_ssl_mode() {
  local response value

  response="$(cloudflare_get_json "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/settings/ssl" "get SSL mode")" || {
    fail_check "Cloudflare SSL mode is Full (strict): lookup failed"
    return
  }
  value="$(printf '%s' "${response}" | jq -r '.result.value // "missing"')"

  if [[ "${value}" == "strict" ]]; then
    pass "Cloudflare SSL mode is Full (strict)"
  else
    fail_check "Cloudflare SSL mode is Full (strict): got ${value}"
  fi
}

check_cloudflare_aop() {
  local response value cert_response enabled_count

  response="$(cloudflare_get_json "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/settings/tls_client_auth" "get Authenticated Origin Pulls setting")" || {
    fail_check "Cloudflare Authenticated Origin Pulls is enabled: lookup failed"
    return
  }
  value="$(printf '%s' "${response}" | jq -r '.result.value // "missing"')"

  if [[ "${value}" == "on" ]]; then
    pass "Cloudflare Authenticated Origin Pulls is enabled"
  else
    fail_check "Cloudflare Authenticated Origin Pulls is enabled: got ${value}"
  fi

  cert_response="$(cloudflare_get_json "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/origin_tls_client_auth" "get zone-level AOP certificates")" || {
    fail_check "Cloudflare zone-level AOP certificates lookup"
    return
  }
  enabled_count="$(printf '%s' "${cert_response}" | jq '[.result[] | select(.enabled == true)] | length')"
  info "Cloudflare zone-level AOP certificates: ${enabled_count} active uploaded certificates"
}

check_s3_truststore() {
  if bootstrap_env_aws_command_for_stack "${STACK}" s3api head-object --bucket "${selected_runtime_bucket}" --key "${MTLS_TRUSTSTORE_KEY}" >/dev/null 2>&1; then
    pass "AWS truststore object exists: ${expected_truststore_uri}"
  else
    fail_check "AWS truststore object exists: ${expected_truststore_uri}"
  fi
}

check_apigw_domain() {
  local domain="$1"
  local response truststore_uri truststore_version status

  if ! response="$(bootstrap_env_aws_command_for_stack "${STACK}" apigatewayv2 get-domain-name --domain-name "${domain}" --output json)"; then
    fail_check "API Gateway domain ${domain} lookup"
    return
  fi

  truststore_uri="$(printf '%s' "${response}" | jq -r '.MutualTlsAuthentication.TruststoreUri // "missing"')"
  truststore_version="$(printf '%s' "${response}" | jq -r '.MutualTlsAuthentication.TruststoreVersion // "missing"')"
  status="$(printf '%s' "${response}" | jq -r '.DomainNameConfigurations[0].DomainNameStatus // "missing"')"

  if [[ "${truststore_uri}" == "${expected_truststore_uri}" ]]; then
    pass "API Gateway domain ${domain} mutual TLS truststore matches: ${truststore_uri}"
  else
    fail_check "API Gateway domain ${domain} mutual TLS truststore matches: got ${truststore_uri}"
  fi

  if [[ "${truststore_version}" == "missing" || -z "${truststore_version}" ]]; then
    fail_check "API Gateway domain ${domain} truststore version is present"
  else
    pass "API Gateway domain ${domain} truststore version is present: ${truststore_version}"
  fi

  info "API Gateway domain ${domain} status: ${status}"
}

check_cloudflare_record "${selected_api_domain}"
check_cloudflare_record "${selected_auth_domain}"
check_cloudflare_record "${selected_control_domain}"
check_cloudflare_ssl_mode
check_cloudflare_aop
check_s3_truststore
check_apigw_domain "${selected_api_domain}"
check_apigw_domain "${selected_auth_domain}"
check_apigw_domain "${selected_control_domain}"

exit "${overall_status}"
