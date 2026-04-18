#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/check-cloudflare-mtls.sh"

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

write_env() {
  local path="$1"
  cat >"${path}" <<'EOF'
STACKS=devo,prod
PROMOTION_PATH=devo,prod
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
AWS_REGION_DEVO=ap-northeast-1
AWS_REGION_PROD=us-west-2
AWS_PROFILE_DEVO=devo-profile
AWS_PROFILE_PROD=prod-profile
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
MTLS_TRUSTSTORE_FILE=infra/certs/cloudflare-origin-pull-ca.pem
MTLS_TRUSTSTORE_KEY=mtls/cloudflare-origin-pull-ca.pem
API_DOMAIN_DEVO=api.devo.example.com
API_DOMAIN_PROD=api.example.com
CONTROL_DOMAIN_DEVO=control.devo.example.com
CONTROL_DOMAIN_PROD=control.example.com
AUTH_DOMAIN_DEVO=auth.devo.example.com
AUTH_DOMAIN_PROD=auth.example.com
CLOUDFLARE_ZONE_ID=zone-123
CLOUDFLARE_API_TOKEN=test-cloudflare-token
RUNTIME_BUCKET_DEVO=customer-ltbase-runtime-devo
RUNTIME_BUCKET_PROD=customer-ltbase-runtime-prod
EOF
}

setup_fake_bin() {
  local fake_bin="$1"
  local log_file="$2"

  mkdir -p "${fake_bin}"

  cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

response_file=""
write_format=""
url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o)
      response_file="${args[$((i + 1))]}"
      i=$((i + 1))
      ;;
    -w)
      write_format="${args[$((i + 1))]}"
      i=$((i + 1))
      ;;
    http*)
      url="${args[$i]}"
      ;;
  esac
done

printf 'curl %s\n' "$*" >>"${COMMAND_LOG}"

status="200"
body='{"success":true,"result":{}}'

case "${url}" in
  *"/zones/zone-123/settings/ssl")
    if [[ "${SCENARIO}" == "forbidden-settings" ]]; then
      status="403"
      body='{"success":false,"errors":[{"code":9109,"message":"Unauthorized to access requested resource"}],"messages":[],"result":null}'
    else
      ssl_value="strict"
      if [[ "${SCENARIO}" == "failure" ]]; then
        ssl_value="full"
      fi
      body="{\"success\":true,\"result\":{\"id\":\"ssl\",\"value\":\"${ssl_value}\"}}"
    fi
    ;;
  *"/zones/zone-123/settings/tls_client_auth")
    if [[ "${SCENARIO}" == "forbidden-settings" ]]; then
      status="403"
      body='{"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"messages":[],"result":null}'
    else
      aop_value="on"
      if [[ "${SCENARIO}" == "failure" ]]; then
        aop_value="off"
      fi
      body="{\"success\":true,\"result\":{\"id\":\"tls_client_auth\",\"value\":\"${aop_value}\"}}"
    fi
    ;;
  *"/zones/zone-123/origin_tls_client_auth")
    result='[]'
    if [[ "${SCENARIO}" == "custom-cert" ]]; then
      result='[{"id":"cert-1","enabled":true}]'
    fi
    body="{\"success\":true,\"result\":${result}}"
    ;;
  *"name=api.example.com"*)
    body='{"success":true,"result":[{"name":"api.example.com","proxied":true,"content":"d-api.execute-api.us-west-2.amazonaws.com"}]}'
    ;;
  *"name=auth.example.com"*)
    proxied='true'
    if [[ "${SCENARIO}" == "failure" ]]; then
      proxied='false'
    fi
    body="{\"success\":true,\"result\":[{\"name\":\"auth.example.com\",\"proxied\":${proxied},\"content\":\"d-auth.execute-api.us-west-2.amazonaws.com\"}]}"
    ;;
  *"name=control.example.com"*)
    body='{"success":true,"result":[{"name":"control.example.com","proxied":true,"content":"d-control.execute-api.us-west-2.amazonaws.com"}]}'
    ;;
  *)
    status="404"
    body='{"success":false,"errors":[{"message":"not found"}]}'
    ;;
esac

printf '%s' "${body}" >"${response_file}"
if [[ -n "${write_format}" ]]; then
  printf '%s' "${status}"
fi
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat >"${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'aws %s\n' "$*" >>"${COMMAND_LOG}"

filtered=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --profile|--region|--output|--query|--color|--cli-binary-format)
      i=$((i + 1))
      ;;
    --no-cli-pager)
      ;;
    *)
      filtered+=("${args[$i]}")
      ;;
  esac
done

if [[ "${filtered[0]:-}" == "s3api" && "${filtered[1]:-}" == "head-object" ]]; then
  if [[ "${SCENARIO}" == "failure" ]]; then
    printf 'An error occurred (404) when calling the HeadObject operation: Not Found\n' >&2
    exit 254
  fi
  printf '{"VersionId":"truststore-version-123"}\n'
  exit 0
fi

if [[ "${filtered[0]:-}" == "apigatewayv2" && "${filtered[1]:-}" == "get-domain-name" ]]; then
  domain=""
  for ((i = 0; i < ${#filtered[@]}; i++)); do
    if [[ "${filtered[$i]}" == "--domain-name" ]]; then
      domain="${filtered[$((i + 1))]}"
      break
    fi
  done
  truststore_uri='s3://customer-ltbase-runtime-prod/mtls/cloudflare-origin-pull-ca.pem'
  if [[ "${SCENARIO}" == "failure" && "${domain}" == "control.example.com" ]]; then
    truststore_uri='s3://customer-ltbase-runtime-prod/mtls/unexpected.pem'
  fi
  cat <<JSON
{"DomainName":"${domain}","DomainNameConfigurations":[{"ApiGatewayDomainName":"regional-${domain}","DomainNameStatus":"AVAILABLE"}],"MutualTlsAuthentication":{"TruststoreUri":"${truststore_uri}","TruststoreVersion":"truststore-version-123"}}
JSON
  exit 0
fi

printf 'unexpected aws invocation: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "${fake_bin}/aws"
}

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
env_file="${temp_dir}/.env"
touch "${log_file}"
write_env "${env_file}"
setup_fake_bin "${fake_bin}" "${log_file}"

if output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" SCENARIO=success "${SCRIPT_PATH}" --env-file "${env_file}" --stack prod 2>&1)"; then
  :
else
  rm -rf "${temp_dir}"
  fail "expected success scenario to pass, got: ${output}"
fi

assert_log_contains <(printf '%s' "${output}") "PASS Cloudflare DNS api.example.com is proxied"
assert_log_contains <(printf '%s' "${output}") "PASS Cloudflare SSL mode is Full (strict)"
assert_log_contains <(printf '%s' "${output}") "PASS Cloudflare Authenticated Origin Pulls is enabled"
assert_log_contains <(printf '%s' "${output}") "INFO Cloudflare zone-level AOP certificates: 0 active uploaded certificates"
assert_log_contains <(printf '%s' "${output}") "PASS AWS truststore object exists: s3://customer-ltbase-runtime-prod/mtls/cloudflare-origin-pull-ca.pem"
assert_log_contains <(printf '%s' "${output}") "PASS API Gateway domain api.example.com mutual TLS truststore matches: s3://customer-ltbase-runtime-prod/mtls/cloudflare-origin-pull-ca.pem"
assert_log_not_contains <(printf '%s' "${output}") "FAIL"

if output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" SCENARIO=failure "${SCRIPT_PATH}" --env-file "${env_file}" --stack prod 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected failure scenario to exit non-zero"
fi

assert_log_contains <(printf '%s' "${output}") "FAIL Cloudflare DNS auth.example.com is proxied"
assert_log_contains <(printf '%s' "${output}") "FAIL Cloudflare SSL mode is Full (strict): got full"
assert_log_contains <(printf '%s' "${output}") "FAIL Cloudflare Authenticated Origin Pulls is enabled: got off"
assert_log_contains <(printf '%s' "${output}") "FAIL AWS truststore object exists: s3://customer-ltbase-runtime-prod/mtls/cloudflare-origin-pull-ca.pem"
assert_log_contains <(printf '%s' "${output}") "FAIL API Gateway domain control.example.com mutual TLS truststore matches: got s3://customer-ltbase-runtime-prod/mtls/unexpected.pem"

if output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" SCENARIO=forbidden-settings "${SCRIPT_PATH}" --env-file "${env_file}" --stack prod 2>&1)"; then
  rm -rf "${temp_dir}"
  fail "expected forbidden-settings scenario to exit non-zero"
fi

assert_log_contains <(printf '%s' "${output}") "Cloudflare token may be missing zone settings read permissions required for mTLS audit."
assert_log_contains <(printf '%s' "${output}") "FAIL Cloudflare SSL mode is Full (strict): lookup failed"
assert_log_contains <(printf '%s' "${output}") "FAIL Cloudflare Authenticated Origin Pulls is enabled: lookup failed"

rm -rf "${temp_dir}"
printf 'PASS: check-cloudflare-mtls tests\n'
