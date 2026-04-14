#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
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

required_vars=(TEMPLATE_REPO GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO_VISIBILITY DEPLOYMENT_REPO_DESCRIPTION DEPLOYMENT_REPO)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

visibility_flag="--private"
if [[ "${DEPLOYMENT_REPO_VISIBILITY}" == "public" ]]; then
  visibility_flag="--public"
fi

expected_private="true"
if [[ "${DEPLOYMENT_REPO_VISIBILITY}" == "public" ]]; then
  expected_private="false"
fi

bootstrap_env_info "Ensuring deployment repository: ${DEPLOYMENT_REPO}"
repo_view_output=""
repo_view_error_file="$(mktemp)"
if gh repo view "${DEPLOYMENT_REPO}" >/dev/null 2>"${repo_view_error_file}"; then
  rm -f "${repo_view_error_file}"
  capture_stdout_quiet actual_private gh api "repos/${DEPLOYMENT_REPO}" --jq '.private'
  if [[ "${actual_private}" != "${expected_private}" ]]; then
    echo "existing repository visibility mismatch for ${DEPLOYMENT_REPO}: expected ${DEPLOYMENT_REPO_VISIBILITY}" >&2
    exit 1
  fi
else
  repo_view_output="$(<"${repo_view_error_file}")"
  rm -f "${repo_view_error_file}"
  if github_repo_missing "${repo_view_output}"; then
    bootstrap_env_run_quiet gh repo create "${DEPLOYMENT_REPO}" --template "${TEMPLATE_REPO}" "${visibility_flag}" --description "${DEPLOYMENT_REPO_DESCRIPTION}" --clone=false
  else
    printf 'GitHub repo lookup failed: %s\n' "${DEPLOYMENT_REPO}" >&2
    printf '%s\n' "${repo_view_output}" >&2
    exit 1
  fi
fi

promotion_index=0
while IFS= read -r stack; do
  if [[ "${promotion_index}" -gt 0 ]]; then
    bootstrap_env_info "Ensuring protected deployment environment: ${stack}"
    bootstrap_env_run_quiet gh api "repos/${DEPLOYMENT_REPO}/environments/${stack}" --method PUT
  fi
  promotion_index=$((promotion_index + 1))
done < <(bootstrap_env_each_stack "${PROMOTION_PATH}")

if [[ "${promotion_index}" -eq 0 && -n "${PROD_ENVIRONMENT_NAME:-}" ]]; then
  bootstrap_env_info "Ensuring protected deployment environment: ${PROD_ENVIRONMENT_NAME}"
  bootstrap_env_run_quiet gh api "repos/${DEPLOYMENT_REPO}/environments/${PROD_ENVIRONMENT_NAME}" --method PUT
fi
