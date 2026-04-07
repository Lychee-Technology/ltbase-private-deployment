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

selected_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${STACK}")"

resolve_dsql_cluster_identifier() {
  pulumi stack output dsqlClusterIdentifier --stack "${STACK}" 2>/dev/null
}

clear_managed_dsql_endpoint() {
  pulumi config rm dsqlEndpoint --stack "${STACK}" >/dev/null 2>&1 || true
}

pulumi login "${PULUMI_BACKEND_URL}"
pushd "${INFRA_DIR}" >/dev/null
pulumi stack select "${STACK}" >/dev/null

dsql_cluster_identifier="$(resolve_dsql_cluster_identifier || true)"
if [[ -z "${dsql_cluster_identifier}" ]]; then
  clear_managed_dsql_endpoint
  echo "failed to resolve dsqlClusterIdentifier for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

if ! dsql_endpoint="$(bootstrap_env_aws_command_for_stack "${STACK}" dsql get-cluster --identifier "${dsql_cluster_identifier}" --region "${selected_region}" --query endpoint --output text)"; then
  clear_managed_dsql_endpoint
  echo "failed to resolve managed DSQL endpoint for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

if [[ -z "${dsql_endpoint}" || "${dsql_endpoint}" == "None" || "${dsql_endpoint}" == "null" ]]; then
  clear_managed_dsql_endpoint
  echo "managed DSQL endpoint was empty for stack ${STACK}" >&2
  popd >/dev/null
  exit 1
fi

pulumi config set dsqlEndpoint "${dsql_endpoint}" --stack "${STACK}"
popd >/dev/null
