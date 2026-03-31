#!/usr/bin/env bash

set -euo pipefail

bootstrap_env_normalize_csv() {
  printf '%s' "${1:-}" | tr -d '[:space:]'
}

bootstrap_env_csv_first() {
  local csv
  csv="$(bootstrap_env_normalize_csv "${1:-}")"
  if [[ "${csv}" == *,* ]]; then
    printf '%s' "${csv%%,*}"
    return 0
  fi
  printf '%s' "${csv}"
}

bootstrap_env_stack_upper() {
  printf '%s' "${1}" | tr '[:lower:]-' '[:upper:]_'
}

bootstrap_env_each_stack() {
  local csv old_ifs
  csv="$(bootstrap_env_normalize_csv "${1:-${STACKS:-devo,prod}}")"
  old_ifs="${IFS}"
  IFS=','
  # shellcheck disable=SC2086
  set -- ${csv}
  IFS="${old_ifs}"
  for stack in "$@"; do
    if [[ -n "${stack}" ]]; then
      printf '%s\n' "${stack}"
    fi
  done
}

bootstrap_env_has_stack() {
  local needle="$1"
  local stack
  while IFS= read -r stack; do
    if [[ "${stack}" == "${needle}" ]]; then
      return 0
    fi
  done < <(bootstrap_env_each_stack)
  return 1
}

bootstrap_env_resolve_stack_value() {
  local base_name="$1"
  local stack="$2"
  local default_value="${3:-}"
  local upper_name specific_name

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  specific_name="${base_name}_${upper_name}"

  if [[ -n "${!specific_name:-}" ]]; then
    printf '%s' "${!specific_name}"
    return 0
  fi
  if [[ -n "${!base_name:-}" ]]; then
    printf '%s' "${!base_name}"
    return 0
  fi
  printf '%s' "${default_value}"
}

bootstrap_env_stack_profile_args() {
  local stack="$1"
  local upper_name profile_var_name

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  profile_var_name="AWS_PROFILE_${upper_name}"

  if [[ -n "${!profile_var_name:-}" ]]; then
    printf '%s\n' "--profile"
    printf '%s\n' "${!profile_var_name}"
  fi
}

bootstrap_env_aws_command_for_stack() {
  local stack="$1"
  shift
  local command=(aws)
  while IFS= read -r token; do
    command+=("${token}")
  done < <(bootstrap_env_stack_profile_args "${stack}")
  command+=("$@")
  "${command[@]}"
}

bootstrap_env_require_vars() {
  local name
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      printf '%s is required\n' "${name}" >&2
      return 1
    fi
  done
}

bootstrap_env_require_stack_values() {
  local stack="$1"
  shift
  local name value upper_name

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  for name in "$@"; do
    value="$(bootstrap_env_resolve_stack_value "${name}" "${stack}")"
    if [[ -z "${value}" ]]; then
      printf '%s_%s or %s is required\n' "${name}" "${upper_name}" "${name}" >&2
      return 1
    fi
  done
}

bootstrap_env_apply_derivations() {
  local stack upper_name region account_id role_name
  local role_arn_var provider_var runtime_bucket_var table_name_var
  local discovery_role_name_var discovery_role_arn_var issuer_var jwks_var

  if [[ -z "${PULUMI_PROJECT:-}" ]]; then
    PULUMI_PROJECT="ltbase-infra"
    export PULUMI_PROJECT
  fi

  if [[ -z "${DEPLOYMENT_REPO:-}" && -n "${GITHUB_OWNER:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
    DEPLOYMENT_REPO="${GITHUB_OWNER}/${DEPLOYMENT_REPO_NAME}"
    export DEPLOYMENT_REPO
  fi
  if [[ -z "${GITHUB_ORG:-}" && -n "${GITHUB_OWNER:-}" ]]; then
    GITHUB_ORG="${GITHUB_OWNER}"
    export GITHUB_ORG
  fi
  if [[ -z "${GITHUB_REPO:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
    GITHUB_REPO="${DEPLOYMENT_REPO_NAME}"
    export GITHUB_REPO
  fi
  if [[ -z "${PULUMI_BACKEND_URL:-}" && -n "${PULUMI_STATE_BUCKET:-}" ]]; then
    PULUMI_BACKEND_URL="s3://${PULUMI_STATE_BUCKET}"
    export PULUMI_BACKEND_URL
  fi
  if [[ -z "${OIDC_DISCOVERY_TEMPLATE_REPO:-}" ]]; then
    OIDC_DISCOVERY_TEMPLATE_REPO="Lychee-Technology/ltbase-oidc-discovery-template"
    export OIDC_DISCOVERY_TEMPLATE_REPO
  fi
  if [[ -z "${OIDC_DISCOVERY_REPO_NAME:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
    OIDC_DISCOVERY_REPO_NAME="${DEPLOYMENT_REPO_NAME}-oidc-discovery"
    export OIDC_DISCOVERY_REPO_NAME
  fi
  if [[ -z "${OIDC_DISCOVERY_REPO:-}" && -n "${GITHUB_OWNER:-}" && -n "${OIDC_DISCOVERY_REPO_NAME:-}" ]]; then
    OIDC_DISCOVERY_REPO="${GITHUB_OWNER}/${OIDC_DISCOVERY_REPO_NAME}"
    export OIDC_DISCOVERY_REPO
  fi
  if [[ -z "${OIDC_DISCOVERY_PAGES_PROJECT:-}" && -n "${OIDC_DISCOVERY_REPO_NAME:-}" ]]; then
    OIDC_DISCOVERY_PAGES_PROJECT="${OIDC_DISCOVERY_REPO_NAME}"
    export OIDC_DISCOVERY_PAGES_PROJECT
  fi

  while IFS= read -r stack; do
    upper_name="$(bootstrap_env_stack_upper "${stack}")"
    region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
    account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
    role_name="$(bootstrap_env_resolve_stack_value AWS_ROLE_NAME "${stack}")"

    role_arn_var="AWS_ROLE_ARN_${upper_name}"
    if [[ -z "${!role_arn_var:-}" && -n "${account_id}" && -n "${role_name}" ]]; then
      printf -v "${role_arn_var}" 'arn:aws:iam::%s:role/%s' "${account_id}" "${role_name}"
      export "${role_arn_var}"
    fi

    provider_var="PULUMI_SECRETS_PROVIDER_${upper_name}"
    if [[ -z "${!provider_var:-}" && -n "${PULUMI_KMS_ALIAS:-}" && -n "${region}" ]]; then
      printf -v "${provider_var}" 'awskms://%s?region=%s' "${PULUMI_KMS_ALIAS}" "${region}"
      export "${provider_var}"
    fi

    runtime_bucket_var="RUNTIME_BUCKET_${upper_name}"
    if [[ -z "${!runtime_bucket_var:-}" && -z "${RUNTIME_BUCKET:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
      printf -v "${runtime_bucket_var}" '%s-runtime-%s' "${DEPLOYMENT_REPO_NAME}" "${stack}"
      export "${runtime_bucket_var}"
    fi

    table_name_var="TABLE_NAME_${upper_name}"
    if [[ -z "${!table_name_var:-}" && -z "${TABLE_NAME:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
      printf -v "${table_name_var}" '%s-%s' "${DEPLOYMENT_REPO_NAME}" "${stack}"
      export "${table_name_var}"
    fi

    discovery_role_name_var="OIDC_DISCOVERY_AWS_ROLE_NAME_${upper_name}"
    if [[ -z "${!discovery_role_name_var:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
      printf -v "${discovery_role_name_var}" '%s-oidc-discovery-%s' "${DEPLOYMENT_REPO_NAME}" "${stack}"
      export "${discovery_role_name_var}"
    fi

    discovery_role_arn_var="OIDC_DISCOVERY_AWS_ROLE_ARN_${upper_name}"
    if [[ -z "${!discovery_role_arn_var:-}" && -n "${account_id}" && -n "${!discovery_role_name_var:-}" ]]; then
      printf -v "${discovery_role_arn_var}" 'arn:aws:iam::%s:role/%s' "${account_id}" "${!discovery_role_name_var}"
      export "${discovery_role_arn_var}"
    fi

    issuer_var="OIDC_ISSUER_URL_${upper_name}"
    if [[ -z "${!issuer_var:-}" && -z "${OIDC_ISSUER_URL:-}" && -n "${OIDC_DISCOVERY_DOMAIN:-}" ]]; then
      printf -v "${issuer_var}" 'https://%s/%s' "${OIDC_DISCOVERY_DOMAIN}" "${stack}"
      export "${issuer_var}"
    fi

    jwks_var="JWKS_URL_${upper_name}"
    if [[ -z "${!jwks_var:-}" && -z "${JWKS_URL:-}" && -n "${OIDC_DISCOVERY_DOMAIN:-}" ]]; then
      printf -v "${jwks_var}" 'https://%s/%s/.well-known/jwks.json' "${OIDC_DISCOVERY_DOMAIN}" "${stack}"
      export "${jwks_var}"
    fi
  done < <(bootstrap_env_each_stack)

  if [[ -z "${PROMOTION_PATH:-}" ]]; then
    PROMOTION_PATH="${STACKS}"
    export PROMOTION_PATH
  fi
  if [[ -z "${PREVIEW_DEFAULT_STACK:-}" ]]; then
    PREVIEW_DEFAULT_STACK="$(bootstrap_env_csv_first "${PROMOTION_PATH}")"
    export PREVIEW_DEFAULT_STACK
  fi
}

bootstrap_env_load() {
  local env_file="$1"
  if [[ ! -f "${env_file}" ]]; then
    printf 'missing env file: %s\n' "${env_file}" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "${env_file}"

  STACKS="$(bootstrap_env_normalize_csv "${STACKS:-devo,prod}")"
  export STACKS

  PROMOTION_PATH="$(bootstrap_env_normalize_csv "${PROMOTION_PATH:-${STACKS}}")"
  export PROMOTION_PATH

  bootstrap_env_apply_derivations
}

bootstrap_env_oidc_discovery_stack_config_json() {
  while IFS= read -r stack; do
    printf '%s\t%s\t%s\t%s\n' \
      "${stack}" \
      "$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")" \
      "$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_ARN "${stack}")" \
      "alias/${PULUMI_PROJECT:-ltbase-infra}-${stack}-authservice"
  done < <(bootstrap_env_each_stack) | python3 -c '
import json
import sys

payload = {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    stack, aws_region, aws_role_arn, kms_auth_key_alias = line.split("\t", 3)
    payload[stack] = {
        "aws_region": aws_region,
        "aws_role_arn": aws_role_arn,
        "kms_auth_key_alias": kms_auth_key_alias,
    }

print(json.dumps(payload, separators=(",", ":")))
'
}
