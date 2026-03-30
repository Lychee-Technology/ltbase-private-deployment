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

gh repo create "${DEPLOYMENT_REPO}" --template "${TEMPLATE_REPO}" ${visibility_flag} --description "${DEPLOYMENT_REPO_DESCRIPTION}" --clone=false

promotion_index=0
while IFS= read -r stack; do
  if [[ "${promotion_index}" -gt 0 ]]; then
    gh api "repos/${DEPLOYMENT_REPO}/environments/${stack}" --method PUT >/dev/null
  fi
  promotion_index=$((promotion_index + 1))
done < <(bootstrap_env_each_stack "${PROMOTION_PATH}")

if [[ "${promotion_index}" -eq 0 && -n "${PROD_ENVIRONMENT_NAME:-}" ]]; then
  gh api "repos/${DEPLOYMENT_REPO}/environments/${PROD_ENVIRONMENT_NAME}" --method PUT >/dev/null
fi
