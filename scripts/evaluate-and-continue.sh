#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
FORCE="false"
INFRA_DIR="infra"
REPORT_DIR="dist/evaluate-and-continue"
SCOPE="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --infra-dir)
      INFRA_DIR="$2"
      shift 2
      ;;
    --report-dir)
      REPORT_DIR="$2"
      shift 2
      ;;
    --scope)
      SCOPE="$2"
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

case "${SCOPE}" in
  foundation|bootstrap|all)
    ;;
  *)
    echo "unsupported scope: ${SCOPE}" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/bootstrap-env.sh"
bootstrap_env_load "${ENV_FILE}"

required_vars=(TEMPLATE_REPO GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO_VISIBILITY DEPLOYMENT_REPO_DESCRIPTION DEPLOYMENT_REPO PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS PULUMI_BACKEND_URL LTBASE_RELEASES_REPO LTBASE_RELEASE_ID LTBASE_RELEASES_TOKEN CLOUDFLARE_API_TOKEN GEMINI_API_KEY CLOUDFLARE_ZONE_ID GITHUB_ORG GITHUB_REPO GEMINI_MODEL DSQL_PORT DSQL_DB DSQL_USER DSQL_PROJECT_SCHEMA)
bootstrap_env_require_vars "${required_vars[@]}"
while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID AWS_ROLE_NAME AWS_ROLE_ARN PULUMI_SECRETS_PROVIDER API_DOMAIN CONTROL_DOMAIN AUTH_DOMAIN OIDC_ISSUER_URL JWKS_URL RUNTIME_BUCKET TABLE_NAME
done < <(bootstrap_env_each_stack)

mkdir -p "${REPORT_DIR}"

report_file="${REPORT_DIR}/report.json"
actions_log="${REPORT_DIR}/actions.log"
state_file="${REPORT_DIR}/stack-status.tsv"
: >"${actions_log}"
: >"${state_file}"

run_logged() {
  printf '%s\n' "$*" >>"${actions_log}"
  "$@"
}

json_name_list_contains() {
  local json_input="$1"
  local needle="$2"
  python3 - "${needle}" <<'PY' <<<"${json_input}"
import json
import sys

needle = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(1)

names = {item.get("name", "") for item in json.loads(raw)}
sys.exit(0 if needle in names else 1)
PY
}

aws_command_for_stack() {
  local stack="$1"
  shift
  local command=(aws)
  while IFS= read -r token; do
    command+=("${token}")
  done < <(bootstrap_env_stack_profile_args "${stack}")
  command+=("$@")
  "${command[@]}"
}

foundation_present_for_stack() {
  local stack="$1"
  local region account_id role_name provider_arn alias_json

  region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  role_name="$(bootstrap_env_resolve_stack_value AWS_ROLE_NAME "${stack}")"
  provider_arn="arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com"

  if ! aws_command_for_stack "${stack}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" >/dev/null 2>&1; then
    return 1
  fi
  if ! aws_command_for_stack "${stack}" iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    return 1
  fi
  alias_json="$(aws_command_for_stack "${stack}" kms list-aliases --region "${region}" --output json)"
  python3 - "${PULUMI_KMS_ALIAS}" <<'PY' <<<"${alias_json}"
import json
import sys

target = sys.argv[1]
aliases = json.load(sys.stdin).get("Aliases", [])
sys.exit(0 if any(item.get("AliasName") == target and item.get("TargetKeyId") for item in aliases) else 1)
PY
}

shared_foundation_present() {
  local first_stack
  first_stack="$(bootstrap_env_csv_first "${STACKS}")"
  if [[ -z "${first_stack}" ]]; then
    return 1
  fi
  aws_command_for_stack "${first_stack}" s3api head-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null 2>&1
}

repo_exists() {
  gh repo view "${DEPLOYMENT_REPO}" >/dev/null 2>&1
}

repo_config_present() {
  local variable_json secret_json stack upper_name

  if ! repo_exists; then
    return 1
  fi

  variable_json="$(gh variable list --repo "${DEPLOYMENT_REPO}" --json name)"
  secret_json="$(gh secret list --repo "${DEPLOYMENT_REPO}" --json name)"

  for required_var in PULUMI_BACKEND_URL LTBASE_RELEASES_REPO LTBASE_RELEASE_ID; do
    if ! json_name_list_contains "${variable_json}" "${required_var}"; then
      return 1
    fi
  done

  for required_secret in LTBASE_RELEASES_TOKEN CLOUDFLARE_API_TOKEN; do
    if ! json_name_list_contains "${secret_json}" "${required_secret}"; then
      return 1
    fi
  done

  while IFS= read -r stack; do
    upper_name="$(bootstrap_env_stack_upper "${stack}")"
    if ! json_name_list_contains "${variable_json}" "AWS_REGION_${upper_name}"; then
      return 1
    fi
    if ! json_name_list_contains "${variable_json}" "PULUMI_SECRETS_PROVIDER_${upper_name}"; then
      return 1
    fi
    if ! json_name_list_contains "${secret_json}" "AWS_ROLE_ARN_${upper_name}"; then
      return 1
    fi
  done < <(bootstrap_env_each_stack)

  return 0
}

stack_bootstrap_present() {
  local stack="$1"
  if [[ ! -f "${INFRA_DIR}/Pulumi.${stack}.yaml" ]]; then
    return 1
  fi

  (
    cd "${INFRA_DIR}"
    pulumi stack select "${stack}" >/dev/null 2>&1
  )
}

stack_rollout_status() {
  local stack="$1"
  local dsql_cluster_identifier dsql_endpoint

  dsql_cluster_identifier="$(
    (
      cd "${INFRA_DIR}"
      pulumi stack output dsqlClusterIdentifier --stack "${stack}" 2>/dev/null
    ) || true
  )"
  if [[ -z "${dsql_cluster_identifier}" ]]; then
    printf 'needs_rollout'
    return 0
  fi

  dsql_endpoint="$(
    (
      cd "${INFRA_DIR}"
      pulumi config get dsqlEndpoint --stack "${stack}" 2>/dev/null
    ) || true
  )"
  if [[ -z "${dsql_endpoint}" ]]; then
    printf 'needs_dsql_reconcile'
    return 0
  fi

  printf 'complete'
}

scan_state() {
  local repo_present repo_config_ok shared_foundation_ok stack foundation_ok status rollout_status

  if repo_exists; then
    repo_present="true"
  else
    repo_present="false"
  fi

  if repo_config_present; then
    repo_config_ok="true"
  else
    repo_config_ok="false"
  fi

  if shared_foundation_present; then
    shared_foundation_ok="true"
  else
    shared_foundation_ok="false"
  fi

  if [[ "${SCOPE}" != "foundation" ]]; then
    pulumi login "${PULUMI_BACKEND_URL}" >/dev/null 2>&1 || true
  fi

  while IFS= read -r stack; do
    foundation_ok="false"
    status="needs_foundation"

    if [[ "${shared_foundation_ok}" == "true" ]] && foundation_present_for_stack "${stack}" >/dev/null 2>&1; then
      foundation_ok="true"
      status="needs_repo_config"
    fi

    if [[ "${foundation_ok}" == "true" && "${repo_present}" == "true" && "${repo_config_ok}" == "true" ]]; then
      status="needs_stack_bootstrap"
      if stack_bootstrap_present "${stack}"; then
        if [[ "${SCOPE}" == "bootstrap" ]]; then
          status="complete"
        elif [[ "${SCOPE}" == "all" ]]; then
          rollout_status="$(stack_rollout_status "${stack}")"
          status="${rollout_status}"
        else
          status="complete"
        fi
      fi
    fi

    printf '%s\t%s\n' "${stack}" "${status}" >>"${state_file}"
  done < <(bootstrap_env_each_stack)
}

write_report() {
  python3 - "${state_file}" "${report_file}" "${DEPLOYMENT_REPO}" "${STACKS}" "${PROMOTION_PATH}" "${SCOPE}" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
deployment_repo = sys.argv[3]
stacks = [item for item in sys.argv[4].split(",") if item]
promotion_path = [item for item in sys.argv[5].split(",") if item]
scope = sys.argv[6]

items = []
with state_path.open() as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        stack, status = line.split("\t", 1)
        items.append({"stack": stack, "status": status})

report = {
    "deploymentRepo": deployment_repo,
    "scope": scope,
    "stacks": stacks,
    "promotionPath": promotion_path,
    "results": items,
}

report_path.write_text(json.dumps(report, indent=2) + "\n")
PY
}

has_non_complete_status() {
  if grep -Fv $'\tcomplete' "${state_file}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

run_force_actions() {
  local needs_foundation="false"
  local needs_repo="false"
  local stack status

  while IFS=$'\t' read -r stack status; do
    case "${status}" in
      needs_foundation)
        needs_foundation="true"
        needs_repo="true"
        ;;
      needs_repo_config|needs_stack_bootstrap)
        needs_repo="true"
        ;;
    esac
  done <"${state_file}"

  if [[ "${needs_foundation}" == "true" ]]; then
    run_logged "${script_dir}/render-bootstrap-policies.sh" --env-file "${ENV_FILE}"
    run_logged "${script_dir}/bootstrap-aws-foundation.sh" --env-file "${ENV_FILE}"
  fi

  if [[ "${needs_repo}" == "true" ]]; then
    if ! repo_exists; then
      run_logged "${script_dir}/create-deployment-repo.sh" --env-file "${ENV_FILE}"
    fi

    while IFS=$'\t' read -r stack status; do
      case "${status}" in
        needs_foundation|needs_repo_config|needs_stack_bootstrap)
          if [[ "${SCOPE}" != "foundation" ]]; then
            run_logged "${script_dir}/bootstrap-deployment-repo.sh" --env-file "${ENV_FILE}" --stack "${stack}" --infra-dir "${INFRA_DIR}"
          fi
          ;;
      esac
    done <"${state_file}"
  fi
}

scan_state
write_report

while IFS=$'\t' read -r stack status; do
  printf '%s: %s\n' "${stack}" "${status}"
done <"${state_file}"
printf 'report: %s\n' "${report_file}"

if [[ "${FORCE}" == "true" ]]; then
  run_force_actions
  exit 0
fi

if has_non_complete_status; then
  exit 2
fi

exit 0
