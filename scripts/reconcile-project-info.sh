#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
STACK="devo"
INFRA_DIR="infra"

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
    --infra-dir)
      INFRA_DIR="$2"
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

bootstrap_env_require_vars PULUMI_BACKEND_URL
if ! bootstrap_env_require_stack_values "${STACK}" AWS_REGION; then
  exit 1
fi

resolve_stack_output() {
  local name="$1"
  pulumi stack output "${name}" --stack "${STACK}" 2>/dev/null
}

selected_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${STACK}")"

pulumi login "${PULUMI_BACKEND_URL}"
pushd "${INFRA_DIR}" >/dev/null
pulumi stack select "${STACK}" >/dev/null

project_id="$(resolve_stack_output projectId || true)"
api_id="$(resolve_stack_output apiId || true)"
api_base_url="$(resolve_stack_output apiBaseUrl || true)"
table_name="$(resolve_stack_output tableName || true)"

if [[ -z "${project_id}" || -z "${api_id}" || -z "${api_base_url}" || -z "${table_name}" ]]; then
  echo "failed to resolve project info outputs for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

if ! account_id="$(bootstrap_env_aws_command_for_stack "${STACK}" sts get-caller-identity --query Account --output text)"; then
  echo "failed to resolve AWS account id for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

if [[ -z "${account_id}" || "${account_id}" == "None" || "${account_id}" == "null" ]]; then
  echo "AWS account id was empty for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

item="$(printf '{"PK":{"S":"project#%s"},"SK":{"S":"info"},"account_id":{"S":"%s"},"api_id":{"S":"%s"},"api_base_url":{"S":"%s"}}' "${project_id}" "${account_id}" "${api_id}" "${api_base_url}")"

if ! bootstrap_env_aws_command_for_stack "${STACK}" dynamodb put-item --table-name "${table_name}" --item "${item}" --region "${selected_region}" >/dev/null; then
  echo "failed to write project info for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

popd >/dev/null
