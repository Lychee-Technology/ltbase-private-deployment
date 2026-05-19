#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
OUTPUT_PATH=""
STACK_CONFIG_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --output-path)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --stack-config-json)
      STACK_CONFIG_JSON="$2"
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${OUTPUT_PATH}" ]]; then
  printf '--output-path is required\n' >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

if [[ -n "${STACK_CONFIG_JSON}" ]]; then
  printf '%s' "${STACK_CONFIG_JSON}" | jq -c '.' >"${OUTPUT_PATH}"
  exit 0
fi

if [[ -z "${ENV_FILE}" ]]; then
  printf '--env-file is required when --stack-config-json is not provided\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/bootstrap-env.sh"
bootstrap_env_load "${ENV_FILE}"

while IFS= read -r stack; do
  if ! bootstrap_env_require_controlplane_ui_auth_provider "${stack}"; then
    exit 1
  fi
done < <(bootstrap_env_each_stack)

bootstrap_env_controlplane_ui_stack_config_json >"${OUTPUT_PATH}"
