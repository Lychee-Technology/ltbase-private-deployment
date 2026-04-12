#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
FORCE="false"
INFRA_DIR="infra"
REPORT_DIR="dist/evaluate-and-continue"
RELEASE_ID=""
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
    --release-id)
      RELEASE_ID="$2"
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

required_vars=(TEMPLATE_REPO GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO_VISIBILITY DEPLOYMENT_REPO_DESCRIPTION DEPLOYMENT_REPO PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS PULUMI_BACKEND_URL LTBASE_RELEASES_REPO LTBASE_RELEASE_ID LTBASE_RELEASES_TOKEN CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID OIDC_DISCOVERY_DOMAIN OIDC_DISCOVERY_TEMPLATE_REPO OIDC_DISCOVERY_REPO OIDC_DISCOVERY_PAGES_PROJECT GEMINI_API_KEY CLOUDFLARE_ZONE_ID GITHUB_ORG GITHUB_REPO GEMINI_MODEL DSQL_PORT DSQL_DB DSQL_USER DSQL_PROJECT_SCHEMA MTLS_TRUSTSTORE_FILE MTLS_TRUSTSTORE_KEY)
bootstrap_env_require_vars "${required_vars[@]}"
while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID AWS_ROLE_NAME AWS_ROLE_ARN PULUMI_SECRETS_PROVIDER API_DOMAIN CONTROL_DOMAIN AUTH_DOMAIN PROJECT_ID AUTH_PROVIDER_CONFIG_FILE OIDC_DISCOVERY_AWS_ROLE_NAME OIDC_DISCOVERY_AWS_ROLE_ARN OIDC_ISSUER_URL JWKS_URL RUNTIME_BUCKET TABLE_NAME
done < <(bootstrap_env_each_stack)

mkdir -p "${REPORT_DIR}"

report_file="${REPORT_DIR}/report.json"
actions_log="${REPORT_DIR}/actions.log"
state_file="${REPORT_DIR}/stack-status.tsv"
oidc_status_file="${REPORT_DIR}/oidc-status.env"
: >"${actions_log}"
: >"${state_file}"
: >"${oidc_status_file}"

run_logged() {
  printf '%s\n' "$*" >>"${actions_log}"
  "$@"
}

json_name_list_contains() {
  local json_input="$1"
  local needle="$2"
  printf '%s' "${json_input}" | python3 -c '
import json
import sys

needle = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(1)

names = {item.get("name", "") for item in json.loads(raw)}
sys.exit(0 if needle in names else 1)
' "${needle}"
}

foundation_present_for_stack() {
  local stack="$1"
  local region account_id role_name provider_arn alias_json

  region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  role_name="$(bootstrap_env_resolve_stack_value AWS_ROLE_NAME "${stack}")"
  provider_arn="arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com"

  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" >/dev/null 2>&1; then
    return 1
  fi
  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    return 1
  fi
  alias_json="$(bootstrap_env_aws_command_for_stack "${stack}" kms list-aliases --region "${region}" --output json)"
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
  bootstrap_env_aws_command_for_stack "${first_stack}" s3api head-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null 2>&1
}

repo_exists() {
  gh repo view "${DEPLOYMENT_REPO}" >/dev/null 2>&1
}

oidc_companion_repo_exists() {
  gh repo view "${OIDC_DISCOVERY_REPO}" >/dev/null 2>&1
}

promotion_environments_present() {
  local promotion_index=0
  local stack
  while IFS= read -r stack; do
    if [[ "${promotion_index}" -gt 0 ]]; then
      if ! gh api "repos/${DEPLOYMENT_REPO}/environments/${stack}" >/dev/null 2>&1; then
        return 1
      fi
    fi
    promotion_index=$((promotion_index + 1))
  done < <(bootstrap_env_each_stack "${PROMOTION_PATH}")
  return 0
}

repo_config_present() {
  local variable_json secret_json stack upper_name

  if ! repo_exists; then
    return 1
  fi

  variable_json="$(gh variable list --repo "${DEPLOYMENT_REPO}" --json name)"
  secret_json="$(gh secret list --repo "${DEPLOYMENT_REPO}" --json name)"

  for required_var in PULUMI_BACKEND_URL LTBASE_RELEASES_REPO LTBASE_RELEASE_ID STACKS PROMOTION_PATH PREVIEW_DEFAULT_STACK; do
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

  if ! promotion_environments_present; then
    return 1
  fi

  return 0
}

oidc_companion_repo_config_present() {
  local variable_json

  if ! oidc_companion_repo_exists; then
    return 1
  fi

  variable_json="$(gh variable list --repo "${OIDC_DISCOVERY_REPO}" --json name)"
  if ! json_name_list_contains "${variable_json}" "OIDC_DISCOVERY_DOMAIN"; then
    return 1
  fi
  if ! json_name_list_contains "${variable_json}" "OIDC_DISCOVERY_STACK_CONFIG"; then
    return 1
  fi

  return 0
}

cloudflare_pages_project_present() {
  curl -fsS \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}" >/dev/null 2>&1
}

cloudflare_pages_domain_present() {
  curl -fsS \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}/domains/${OIDC_DISCOVERY_DOMAIN}" >/dev/null 2>&1
}

cloudflare_oidc_pages_dns_present() {
  local response expected_target

  expected_target="${OIDC_DISCOVERY_PAGES_PROJECT}.pages.dev"
  response="$(curl -fsS \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=CNAME&name=${OIDC_DISCOVERY_DOMAIN}")" || return 1

  printf '%s' "${response}" | python3 -c '
import json
import sys

expected_target = sys.argv[1]
payload = json.load(sys.stdin)
records = payload.get("result") or []

sys.exit(0 if any(
    (record.get("type") or "").upper() == "CNAME"
    and (record.get("name") or "") == sys.argv[2]
    and (record.get("content") or "") == expected_target
    for record in records
) else 1)
' "${expected_target}" "${OIDC_DISCOVERY_DOMAIN}"
}

oidc_discovery_roles_present() {
  local stack role_name
  while IFS= read -r stack; do
    role_name="$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_NAME "${stack}")"
    if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
      return 1
    fi
  done < <(bootstrap_env_each_stack)
  return 0
}

scan_oidc_discovery_state() {
  local repo_present="false"
  local repo_config_present="false"
  local pages_project_present="false"
  local pages_domain_present="false"
  local pages_dns_present="false"
  local roles_present="false"
  local status="needs_oidc_companion"

  if [[ "${SCOPE}" == "foundation" ]]; then
    status="skipped"
  else
    if oidc_companion_repo_exists; then
      repo_present="true"
    fi
    if oidc_companion_repo_config_present; then
      repo_config_present="true"
    fi
    if cloudflare_pages_project_present; then
      pages_project_present="true"
    fi
    if cloudflare_pages_domain_present; then
      pages_domain_present="true"
    fi
    if cloudflare_oidc_pages_dns_present; then
      pages_dns_present="true"
    fi
    if oidc_discovery_roles_present; then
      roles_present="true"
    fi

    if [[ "${repo_present}" == "true" && "${repo_config_present}" == "true" && "${pages_project_present}" == "true" && "${pages_domain_present}" == "true" && "${pages_dns_present}" == "true" && "${roles_present}" == "true" ]]; then
      status="complete"
    fi
  fi

  cat >"${oidc_status_file}" <<EOF
OIDC_DISCOVERY_STATUS=${status}
OIDC_DISCOVERY_REPO_PRESENT=${repo_present}
OIDC_DISCOVERY_REPO_CONFIG_PRESENT=${repo_config_present}
OIDC_DISCOVERY_PAGES_PROJECT_PRESENT=${pages_project_present}
OIDC_DISCOVERY_PAGES_DOMAIN_PRESENT=${pages_domain_present}
OIDC_DISCOVERY_PAGES_DNS_PRESENT=${pages_dns_present}
OIDC_DISCOVERY_ROLES_PRESENT=${roles_present}
EOF
}

stack_bootstrap_present() {
  local stack="$1"
  local stack_env=(env)
  if [[ ! -f "${INFRA_DIR}/Pulumi.${stack}.yaml" ]]; then
    return 1
  fi

  while IFS= read -r token; do
    stack_env+=("${token}")
  done < <(bootstrap_env_stack_runtime_env "${stack}")

  (
    cd "${INFRA_DIR}"
    "${stack_env[@]}" pulumi stack select "${stack}" >/dev/null 2>&1 || exit 1
    "${stack_env[@]}" pulumi config get mtlsTruststoreFile --stack "${stack}" >/dev/null 2>&1 || exit 1
    "${stack_env[@]}" pulumi config get mtlsTruststoreKey --stack "${stack}" >/dev/null 2>&1 || exit 1
  )
}

stack_rollout_status() {
  local stack="$1"
  local dsql_cluster_identifier dsql_endpoint
  local stack_env=(env)

  while IFS= read -r token; do
    stack_env+=("${token}")
  done < <(bootstrap_env_stack_runtime_env "${stack}")

  dsql_cluster_identifier="$(
    (
      cd "${INFRA_DIR}"
      "${stack_env[@]}" pulumi stack output dsqlClusterIdentifier --stack "${stack}" 2>/dev/null
    ) || true
  )"
  if [[ -z "${dsql_cluster_identifier}" ]]; then
    printf 'needs_rollout'
    return 0
  fi

  dsql_endpoint="$(
    (
      cd "${INFRA_DIR}"
      "${stack_env[@]}" pulumi config get dsqlEndpoint --stack "${stack}" 2>/dev/null
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
  local backend_stack backend_env=(env)

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
    backend_stack="$(bootstrap_env_csv_first "${PROMOTION_PATH:-${STACKS}}")"
    while IFS= read -r token; do
      backend_env+=("${token}")
    done < <(bootstrap_env_stack_runtime_env "${backend_stack}")
    "${backend_env[@]}" pulumi login "${PULUMI_BACKEND_URL}" >/dev/null 2>&1 || true
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

  scan_oidc_discovery_state
}

write_report() {
  python3 - "${state_file}" "${oidc_status_file}" "${report_file}" "${DEPLOYMENT_REPO}" "${OIDC_DISCOVERY_REPO}" "${OIDC_DISCOVERY_PAGES_PROJECT}" "${OIDC_DISCOVERY_DOMAIN}" "${STACKS}" "${PROMOTION_PATH}" "${SCOPE}" <<'PY'
import json
import os
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
oidc_state_path = Path(sys.argv[2])
report_path = Path(sys.argv[3])
deployment_repo = sys.argv[4]
oidc_repo = sys.argv[5]
oidc_pages_project = sys.argv[6]
oidc_domain = sys.argv[7]
stacks = [item for item in sys.argv[8].split(",") if item]
promotion_path = [item for item in sys.argv[9].split(",") if item]
scope = sys.argv[10]

items = []
with state_path.open() as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        stack, status = line.split("\t", 1)
        items.append({"stack": stack, "status": status})

oidc_values = {}
with oidc_state_path.open() as handle:
    for line in handle:
        line = line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        oidc_values[key] = value

report = {
    "deploymentRepo": deployment_repo,
    "oidcDiscovery": {
        "repo": oidc_repo,
        "pagesProject": oidc_pages_project,
        "domain": oidc_domain,
        "status": oidc_values.get("OIDC_DISCOVERY_STATUS", "needs_oidc_companion"),
        "repoPresent": oidc_values.get("OIDC_DISCOVERY_REPO_PRESENT", "false") == "true",
        "repoConfigPresent": oidc_values.get("OIDC_DISCOVERY_REPO_CONFIG_PRESENT", "false") == "true",
        "pagesProjectPresent": oidc_values.get("OIDC_DISCOVERY_PAGES_PROJECT_PRESENT", "false") == "true",
        "pagesDomainPresent": oidc_values.get("OIDC_DISCOVERY_PAGES_DOMAIN_PRESENT", "false") == "true",
        "pagesDnsPresent": oidc_values.get("OIDC_DISCOVERY_PAGES_DNS_PRESENT", "false") == "true",
        "rolesPresent": oidc_values.get("OIDC_DISCOVERY_ROLES_PRESENT", "false") == "true",
    },
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
  # shellcheck disable=SC1090
  source "${oidc_status_file}"
  if [[ "${OIDC_DISCOVERY_STATUS}" != "complete" && "${OIDC_DISCOVERY_STATUS}" != "skipped" ]]; then
    return 0
  fi
  return 1
}

run_force_actions() {
  local needs_foundation="false"
  local needs_repo="false"
  local needs_oidc_companion="false"
  local has_dsql_reconcile="false"
  local has_needs_rollout="false"
  local first_needs_rollout_stack=""
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
      needs_dsql_reconcile)
        has_dsql_reconcile="true"
        ;;
      needs_rollout)
        has_needs_rollout="true"
        if [[ -z "${first_needs_rollout_stack}" ]]; then
          first_needs_rollout_stack="${stack}"
        fi
        ;;
    esac
  done <"${state_file}"
  # shellcheck disable=SC1090
  source "${oidc_status_file}"
  if [[ "${OIDC_DISCOVERY_STATUS}" != "complete" && "${OIDC_DISCOVERY_STATUS}" != "skipped" ]]; then
    needs_oidc_companion="true"
  fi

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

  # Bug #21: repair missing promotion environments
  if repo_exists && ! promotion_environments_present; then
    local promotion_index=0
    while IFS= read -r stack; do
      if [[ "${promotion_index}" -gt 0 ]]; then
        if ! gh api "repos/${DEPLOYMENT_REPO}/environments/${stack}" >/dev/null 2>&1; then
          run_logged gh api "repos/${DEPLOYMENT_REPO}/environments/${stack}" --method PUT
        fi
      fi
      promotion_index=$((promotion_index + 1))
    done < <(bootstrap_env_each_stack "${PROMOTION_PATH}")
  fi

  if [[ "${needs_oidc_companion}" == "true" && "${SCOPE}" != "foundation" ]]; then
    run_logged "${script_dir}/bootstrap-oidc-discovery-companion.sh" --env-file "${ENV_FILE}"
  fi

  # Bug #20: reconcile DSQL endpoints for stacks that have a cluster but no endpoint set
  if [[ "${has_dsql_reconcile}" == "true" && "${SCOPE}" != "foundation" ]]; then
    while IFS=$'\t' read -r stack status; do
      if [[ "${status}" == "needs_dsql_reconcile" ]]; then
        run_logged "${script_dir}/reconcile-managed-dsql-endpoint.sh" --env-file "${ENV_FILE}" --stack "${stack}" --infra-dir "${INFRA_DIR}"
      fi
    done <"${state_file}"
  fi

  # Bug #20: resume rollout from the first incomplete stack instead of starting over
  if [[ "${has_needs_rollout}" == "true" && -n "${RELEASE_ID}" && "${SCOPE}" != "foundation" ]]; then
    run_logged gh workflow run rollout-hop.yml --repo "${DEPLOYMENT_REPO}" \
      -f release_id="${RELEASE_ID}" \
      -f target_stack="${first_needs_rollout_stack}" \
      -f continue_chain=true
  elif [[ -n "${RELEASE_ID}" && "${SCOPE}" != "foundation" ]]; then
    run_logged gh workflow run rollout.yml --repo "${DEPLOYMENT_REPO}" -f release_id="${RELEASE_ID}"
  fi
}

scan_state
write_report

while IFS=$'\t' read -r stack status; do
  printf '%s: %s\n' "${stack}" "${status}"
done <"${state_file}"
# shellcheck disable=SC1090
source "${oidc_status_file}"
printf 'oidc-discovery: %s\n' "${OIDC_DISCOVERY_STATUS}"
printf 'report: %s\n' "${report_file}"

if [[ "${FORCE}" == "true" ]]; then
  run_force_actions
  exit 0
fi

if has_non_complete_status; then
  exit 2
fi

exit 0
