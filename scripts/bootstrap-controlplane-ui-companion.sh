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

required_vars=(GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO_VISIBILITY CONTROLPLANE_UI_DOMAIN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID CONTROLPLANE_UI_TEMPLATE_REPO CONTROLPLANE_UI_REPO_NAME CONTROLPLANE_UI_REPO CONTROLPLANE_UI_PAGES_PROJECT)
bootstrap_env_require_vars "${required_vars[@]}"

if ! python3 -c 'import re, sys; domain = sys.argv[1]; label = r"(?!-)[a-z0-9-]{1,63}(?<!-)"; pattern = rf"^{label}(\.{label})+$"; sys.exit(0 if re.fullmatch(pattern, domain.lower()) else 1)' "${CONTROLPLANE_UI_DOMAIN}"; then
  printf 'CONTROLPLANE_UI_DOMAIN is invalid: %s\n' "${CONTROLPLANE_UI_DOMAIN}" >&2
  printf 'Use a valid DNS hostname with letters, digits, and hyphens only. Underscores are not allowed.\n' >&2
  exit 1
fi

while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" PROJECT_ID AUTH_DOMAIN CONTROL_DOMAIN API_DOMAIN AUTH_PROVIDER_CONFIG_FILE FIREBASE_API_KEY FIREBASE_PROJECT_ID SUPABASE_URL SUPABASE_ANON_KEY
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"

local_code_dir="${OUTPUT_DIR}/${CONTROLPLANE_UI_REPO_NAME}"
bootstrap_env_info "Syncing Control Plane UI template code into ${local_code_dir}"
rm -rf "${local_code_dir}"
bootstrap_env_run_quiet gh repo clone "${CONTROLPLANE_UI_TEMPLATE_REPO}" "${local_code_dir}" -- --depth 1
rm -rf "${local_code_dir}/.git"

companion_summary="${OUTPUT_DIR}/controlplane-ui-companion.env"
stack_config="$(bootstrap_env_controlplane_ui_stack_config_json)"

visibility_flag="--private"
if [[ "${DEPLOYMENT_REPO_VISIBILITY}" == "public" ]]; then
  visibility_flag="--public"
fi

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

bootstrap_env_info "Ensuring Control Plane UI repository: ${CONTROLPLANE_UI_REPO}"
repo_view_output=""
repo_view_error_file="$(mktemp)"
if gh repo view "${CONTROLPLANE_UI_REPO}" >/dev/null 2>"${repo_view_error_file}"; then
  rm -f "${repo_view_error_file}"
  bootstrap_env_info "Companion repo exists, syncing latest template code from ${CONTROLPLANE_UI_TEMPLATE_REPO}"
  sync_tmp="$(mktemp -d)"
  bootstrap_env_run_quiet gh repo clone "${CONTROLPLANE_UI_REPO}" "${sync_tmp}/companion" -- --depth 1
  bootstrap_env_run_quiet gh repo clone "${CONTROLPLANE_UI_TEMPLATE_REPO}" "${sync_tmp}/template" -- --depth 1
  rsync -a --exclude=.git "${sync_tmp}/template/" "${sync_tmp}/companion/"
  if git -C "${sync_tmp}/companion" diff --quiet && git -C "${sync_tmp}/companion" diff --cached --quiet; then
    bootstrap_env_info "Companion repo already up to date"
  else
    git -C "${sync_tmp}/companion" add -A
    git -C "${sync_tmp}/companion" commit -m "Sync from template ${CONTROLPLANE_UI_TEMPLATE_REPO}"
    git -C "${sync_tmp}/companion" push
    bootstrap_env_info "Pushed latest template code to ${CONTROLPLANE_UI_REPO}"
  fi
  rm -rf "${sync_tmp}"
else
  repo_view_output="$(<"${repo_view_error_file}")"
  rm -f "${repo_view_error_file}"
  if github_repo_missing "${repo_view_output}"; then
    bootstrap_env_run_quiet gh repo create "${CONTROLPLANE_UI_REPO}" --template "${CONTROLPLANE_UI_TEMPLATE_REPO}" "${visibility_flag}" --description "LTBase Control Plane UI companion for ${DEPLOYMENT_REPO_NAME}" --clone=false
  else
    printf 'GitHub repo lookup failed: %s\n' "${CONTROLPLANE_UI_REPO}" >&2
    printf '%s\n' "${repo_view_output}" >&2
    exit 1
  fi
fi

capture_stdout_quiet repo_metadata gh api "repos/${CONTROLPLANE_UI_REPO}"
default_branch="$(python3 -c 'import json, sys; data = json.load(sys.stdin); print(data.get("default_branch", "main"))' <<<"${repo_metadata}")"

bootstrap_env_info "Ensuring Pages project: ${CONTROLPLANE_UI_PAGES_PROJECT}"
if ! cloudflare_get_exists "get Pages project" "${pages_project_url}"; then
  project_payload="$(python3 - "${CONTROLPLANE_UI_PAGES_PROJECT}" "${GITHUB_OWNER}" "${CONTROLPLANE_UI_REPO_NAME}" "${default_branch}" <<'PY'
import json
import sys

print(json.dumps({
    "name": sys.argv[1],
    "production_branch": sys.argv[4],
    "source": {
        "type": "github",
        "config": {
            "owner": sys.argv[2],
            "repo_name": sys.argv[3],
            "production_branch": sys.argv[4],
            "preview_deployment_setting": "none",
            "production_deployments_enabled": True,
        },
    },
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

bootstrap_env_info "Configuring companion repository variables and secrets"
bootstrap_env_run_quiet gh variable set CONTROLPLANE_UI_DOMAIN --repo "${CONTROLPLANE_UI_REPO}" --body "${CONTROLPLANE_UI_DOMAIN}"
bootstrap_env_run_quiet gh variable set CONTROLPLANE_UI_STACK_CONFIG --repo "${CONTROLPLANE_UI_REPO}" --body "${stack_config}"
bootstrap_env_run_quiet gh variable set CLOUDFLARE_ACCOUNT_ID --repo "${CONTROLPLANE_UI_REPO}" --body "${CLOUDFLARE_ACCOUNT_ID}"
bootstrap_env_run_quiet gh variable set CONTROLPLANE_UI_PAGES_PROJECT --repo "${CONTROLPLANE_UI_REPO}" --body "${CONTROLPLANE_UI_PAGES_PROJECT}"
bootstrap_env_run_quiet gh secret set CLOUDFLARE_API_TOKEN --repo "${CONTROLPLANE_UI_REPO}" --body "${CLOUDFLARE_API_TOKEN}"
bootstrap_env_run_quiet gh workflow run publish-pages.yml --repo "${CONTROLPLANE_UI_REPO}"

: >"${companion_summary}"
cat >>"${companion_summary}" <<EOF
CONTROLPLANE_UI_REPO=${CONTROLPLANE_UI_REPO}
CONTROLPLANE_UI_REPO_NAME=${CONTROLPLANE_UI_REPO_NAME}
CONTROLPLANE_UI_PAGES_PROJECT=${CONTROLPLANE_UI_PAGES_PROJECT}
CONTROLPLANE_UI_DOMAIN=${CONTROLPLANE_UI_DOMAIN}
EOF
