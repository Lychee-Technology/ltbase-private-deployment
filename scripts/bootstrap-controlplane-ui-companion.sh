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
  fi

  command_status=$?
  if [[ -s "${stderr_file}" ]]; then
    cat "${stderr_file}" >&2
  fi
  rm -f "${stderr_file}"
  return "${command_status}"
}

required_vars=(DEPLOYMENT_REPO_NAME CONTROLPLANE_UI_DOMAIN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID CONTROLPLANE_UI_PAGES_PROJECT)
bootstrap_env_require_vars "${required_vars[@]}"

if ! python3 -c 'import re, sys; domain = sys.argv[1]; label = r"(?!-)[a-z0-9-]{1,63}(?<!-)"; pattern = rf"^{label}(\.{label})+$"; sys.exit(0 if re.fullmatch(pattern, domain.lower()) else 1)' "${CONTROLPLANE_UI_DOMAIN}"; then
  printf 'CONTROLPLANE_UI_DOMAIN is invalid: %s\n' "${CONTROLPLANE_UI_DOMAIN}" >&2
  printf 'Use a valid DNS hostname with letters, digits, and hyphens only. Underscores are not allowed.\n' >&2
  exit 1
fi

while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" PROJECT_ID AUTH_DOMAIN CONTROL_DOMAIN API_DOMAIN AUTH_PROVIDER_CONFIG_FILE
  bootstrap_env_require_controlplane_ui_auth_provider "${stack}"
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"

companion_summary="${OUTPUT_DIR}/controlplane-ui-companion.env"
stack_config="$(bootstrap_env_controlplane_ui_stack_config_json)"

cloudflare_headers=(
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
  -H "Content-Type: application/json"
)

capture_stdout_quiet repo_metadata gh api "repos/${DEPLOYMENT_REPO}"
default_branch="$(python3 -c 'import json, sys; data = json.load(sys.stdin); print(data.get("default_branch", "main"))' <<<"${repo_metadata}"
)"

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

github_repo_missing() {
  local output="$1"

  python3 -c '
import sys

output = sys.stdin.read().lower()
if "could not resolve to a repository" in output:
    sys.exit(0)

if "http 404" in output and "repo" in output:
    sys.exit(0)

if "repository was not found" in output:
    sys.exit(0)

sys.exit(1)
' <<<"${output}"
}

ensure_controlplane_ui_dns_record() {
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
' "${CONTROLPLANE_UI_DOMAIN}" "${pages_target}")"

  case "${record_state}" in
    missing)
      local dns_payload
      dns_payload="$(python3 - "${CONTROLPLANE_UI_DOMAIN}" "${pages_target}" <<'PY'
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
      printf 'Control Plane UI DNS record already exists with unexpected type: %s\n' "${record_state#conflict_type:}" >&2
      exit 1
      ;;
    conflict_target:*)
      printf 'Control Plane UI DNS record already exists with unexpected target: %s\n' "${record_state#conflict_target:}" >&2
      exit 1
      ;;
    *)
      printf 'Unable to determine Control Plane UI DNS state\n' >&2
      exit 1
      ;;
  esac
}

pages_project_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${CONTROLPLANE_UI_PAGES_PROJECT}"
pages_projects_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects"
pages_domain_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${CONTROLPLANE_UI_PAGES_PROJECT}/domains/${CONTROLPLANE_UI_DOMAIN}"
pages_domains_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${CONTROLPLANE_UI_PAGES_PROJECT}/domains"
pages_target="${CONTROLPLANE_UI_PAGES_PROJECT}.pages.dev"
dns_records_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
dns_lookup_url="${dns_records_url}?name=${CONTROLPLANE_UI_DOMAIN}"

bootstrap_env_info "Ensuring Control Plane UI Pages project: ${CONTROLPLANE_UI_PAGES_PROJECT}"

bootstrap_env_info "Ensuring Pages project: ${CONTROLPLANE_UI_PAGES_PROJECT}"
if ! cloudflare_get_exists "get Pages project" "${pages_project_url}"; then
  project_payload="$(python3 - "${CONTROLPLANE_UI_PAGES_PROJECT}" "${default_branch}" <<'PY'
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

bootstrap_env_info "Ensuring Pages domain: ${CONTROLPLANE_UI_DOMAIN}"
if ! cloudflare_get_exists "get Pages custom domain" "${pages_domain_url}"; then
  domain_payload="$(python3 - "${CONTROLPLANE_UI_DOMAIN}" <<'PY'
import json
import sys

print(json.dumps({"name": sys.argv[1]}, separators=(",", ":")))
PY
)"
  cloudflare_post "create Pages custom domain" "${pages_domains_url}" "${domain_payload}"
fi

bootstrap_env_info "Reconciling DNS for Control Plane UI domain: ${CONTROLPLANE_UI_DOMAIN}"
ensure_controlplane_ui_dns_record

: >"${companion_summary}"
cat >>"${companion_summary}" <<EOF
CONTROLPLANE_UI_STACK_CONFIG=${stack_config}
CONTROLPLANE_UI_PAGES_PROJECT=${CONTROLPLANE_UI_PAGES_PROJECT}
CONTROLPLANE_UI_DOMAIN=${CONTROLPLANE_UI_DOMAIN}
EOF
