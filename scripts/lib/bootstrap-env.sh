#!/usr/bin/env bash

set -euo pipefail

bootstrap_env_info() {
  printf '[info] %s\n' "$*"
}

bootstrap_env_run_quiet() {
  local output status

  if output="$("$@" 2>&1)"; then
    return 0
  else
    status=$?
  fi

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" >&2
  fi

  return "${status}"
}

bootstrap_env_capture_quiet() {
  local destination_var="$1"
  local output status
  shift

  if output="$("$@" 2>&1)"; then
    printf -v "${destination_var}" '%s' "${output}"
    return 0
  else
    status=$?
  fi

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" >&2
  fi

  return "${status}"
}

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

bootstrap_env_csv_contains() {
  local csv entry old_ifs noglob_was_on
  csv="$(bootstrap_env_normalize_csv "${1:-}")"
  entry="$(bootstrap_env_normalize_csv "${2:-}")"

  if [[ -z "${csv}" || -z "${entry}" ]]; then
    return 1
  fi

  old_ifs="${IFS}"
  noglob_was_on=0
  if [[ -o noglob ]]; then
    noglob_was_on=1
  fi
  set -f
  IFS=','
  # shellcheck disable=SC2086
  set -- ${csv}
  IFS="${old_ifs}"
  if [[ "${noglob_was_on}" -eq 0 ]]; then
    set +f
  fi
  for value in "$@"; do
    if [[ "${value}" == "${entry}" ]]; then
      return 0
    fi
  done
  return 1
}

bootstrap_env_append_csv_value_once() {
  local csv entry normalized_csv normalized_entry
  csv="${1:-}"
  entry="${2:-}"
  normalized_csv="$(bootstrap_env_normalize_csv "${csv}")"
  normalized_entry="$(bootstrap_env_normalize_csv "${entry}")"

  if [[ -z "${normalized_entry}" ]]; then
    printf '%s' "${normalized_csv}"
    return 0
  fi
  if [[ -z "${normalized_csv}" ]]; then
    printf '%s' "${normalized_entry}"
    return 0
  fi
  if bootstrap_env_csv_contains "${normalized_csv}" '*'; then
    printf '*'
    return 0
  fi
  if bootstrap_env_csv_contains "${normalized_csv}" "${normalized_entry}"; then
    printf '%s' "${normalized_csv}"
    return 0
  fi

  printf '%s,%s' "${normalized_csv}" "${normalized_entry}"
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

bootstrap_env_stack_runtime_env() {
  local stack="$1"
  local upper_name profile_var_name region

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  profile_var_name="AWS_PROFILE_${upper_name}"
  region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"

  printf '%s\n' "AWS_REGION=${region}"
  printf '%s\n' "AWS_DEFAULT_REGION=${region}"
  if [[ -n "${!profile_var_name:-}" ]]; then
    printf '%s\n' "AWS_PROFILE=${!profile_var_name}"
  fi
}

bootstrap_env_require_aws_credentials_for_stack() {
  local stack="$1"
  local upper_name profile_var_name profile_name output status
  local command=(aws)

  while IFS= read -r token; do
    command+=("${token}")
  done < <(bootstrap_env_stack_profile_args "${stack}")

  if output="$("${command[@]}" sts get-caller-identity --output json 2>&1 >/dev/null)"; then
    return 0
  else
    status=$?
  fi

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  profile_var_name="AWS_PROFILE_${upper_name}"
  profile_name="${!profile_var_name:-default credentials}"

  printf 'AWS credentials check failed for stack %s (profile: %s). Refresh the AWS session or fix the configured credentials before rerunning.\n' "${stack}" "${profile_name}" >&2
  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" >&2
  fi

  return "${status}"
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

bootstrap_env_require_controlplane_ui_auth_provider() {
  local stack="$1"
  local upper_name firebase_project_id firebase_api_key supabase_url supabase_anon_key

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  firebase_project_id="$(bootstrap_env_resolve_stack_value FIREBASE_PROJECT_ID "${stack}")"
  firebase_api_key="$(bootstrap_env_resolve_stack_value FIREBASE_API_KEY "${stack}")"
  supabase_url="$(bootstrap_env_resolve_stack_value SUPABASE_URL "${stack}")"
  supabase_anon_key="$(bootstrap_env_resolve_stack_value SUPABASE_ANON_KEY "${stack}")"

  if [[ -n "${firebase_project_id}" || -n "${firebase_api_key}" ]]; then
    if [[ -z "${firebase_project_id}" || -z "${firebase_api_key}" ]]; then
      printf 'Firebase control plane UI config for stack %s must include both FIREBASE_PROJECT_ID_%s and FIREBASE_API_KEY_%s\n' "${stack}" "${upper_name}" "${upper_name}" >&2
      return 1
    fi
  fi

  if [[ -n "${supabase_url}" || -n "${supabase_anon_key}" ]]; then
    if [[ -z "${supabase_url}" || -z "${supabase_anon_key}" ]]; then
      printf 'Supabase control plane UI config for stack %s must include both SUPABASE_URL_%s and SUPABASE_ANON_KEY_%s\n' "${stack}" "${upper_name}" "${upper_name}" >&2
      return 1
    fi
  fi

  if [[ -n "${firebase_project_id}" && -n "${firebase_api_key}" ]]; then
    return 0
  fi

  if [[ -n "${supabase_url}" && -n "${supabase_anon_key}" ]]; then
    return 0
  fi

  printf 'stack %s must configure at least one control plane UI auth provider: Firebase or Supabase\n' "${stack}" >&2
  return 1
}

bootstrap_env_apply_derivations() {
  local stack upper_name region account_id role_name
  local role_arn_var provider_var runtime_bucket_var schema_bucket_var table_name_var
  local discovery_role_name_var discovery_role_arn_var issuer_var jwks_var

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
  if [[ -z "${OIDC_DISCOVERY_PAGES_PROJECT:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
    OIDC_DISCOVERY_PAGES_PROJECT="${DEPLOYMENT_REPO_NAME}-oidc-discovery"
    export OIDC_DISCOVERY_PAGES_PROJECT
  fi
  if [[ -z "${OIDC_DISCOVERY_TEMPLATE_REPO:-}" ]]; then
    OIDC_DISCOVERY_TEMPLATE_REPO="Lychee-Technology/ltbase-oidc-discovery-template"
    export OIDC_DISCOVERY_TEMPLATE_REPO
  fi
  if [[ -z "${OIDC_DISCOVERY_TEMPLATE_REF:-}" ]]; then
    OIDC_DISCOVERY_TEMPLATE_REF="main"
    export OIDC_DISCOVERY_TEMPLATE_REF
  fi
  if [[ -z "${CONTROLPLANE_UI_PAGES_PROJECT:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
    CONTROLPLANE_UI_PAGES_PROJECT="${DEPLOYMENT_REPO_NAME}-controlplane-ui"
    export CONTROLPLANE_UI_PAGES_PROJECT
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

    schema_bucket_var="SCHEMA_BUCKET_${upper_name}"
    if [[ -z "${!schema_bucket_var:-}" && -z "${SCHEMA_BUCKET:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
      printf -v "${schema_bucket_var}" '%s-schema-%s' "${DEPLOYMENT_REPO_NAME}" "${stack}"
      export "${schema_bucket_var}"
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

  BOOTSTRAP_ENV_FILE_DIR="$(cd "$(dirname "${env_file}")" && pwd)"
  export BOOTSTRAP_ENV_FILE_DIR

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
      "alias/ltbase-oidc-discovery-${stack}-authservice"
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

bootstrap_env_controlplane_ui_stack_config_json() {
  while IFS= read -r stack; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${stack}" \
      "$(bootstrap_env_resolve_stack_value PROJECT_ID "${stack}")" \
      "$(bootstrap_env_resolve_stack_value AUTH_DOMAIN "${stack}")" \
      "$(bootstrap_env_resolve_stack_value CONTROL_DOMAIN "${stack}")" \
      "$(bootstrap_env_resolve_stack_value API_DOMAIN "${stack}")" \
      "$(bootstrap_env_resolve_stack_value AUTH_PROVIDER_CONFIG_FILE "${stack}")" \
      "$(bootstrap_env_resolve_stack_value FIREBASE_PROJECT_ID "${stack}")" \
      "$(bootstrap_env_resolve_stack_value FIREBASE_API_KEY "${stack}")" \
      "$(bootstrap_env_resolve_stack_value SUPABASE_URL "${stack}")" \
      "$(bootstrap_env_resolve_stack_value SUPABASE_ANON_KEY "${stack}")"
  done < <(bootstrap_env_each_stack) | python3 -c '
import json
import sys
from pathlib import Path

def label_for_stack(stack: str) -> str:
    return " ".join(part.capitalize() for part in stack.replace("_", "-").split("-"))

def titleize_provider(name: str) -> str:
    return " ".join(part.capitalize() for part in name.replace("_", "-").split("-"))

def load_provider_names(config_path: str, firebase_project_id: str, supabase_url: str):
    config_file = Path(config_path)
    if not config_file.is_absolute():
        config_file = Path(sys.argv[2]) / config_file

    if not config_file.exists():
        return {
            "firebase": "firebase",
            "supabase": "supabase",
        }

    payload = json.loads(config_file.read_text(encoding="utf-8"))
    providers = payload.get("providers")
    if not isinstance(providers, list):
        raise SystemExit(f"auth provider config must contain a providers array: {config_file}")

    firebase_name = None
    supabase_name = None
    firebase_issuer = f"https://securetoken.google.com/{firebase_project_id}"
    supabase_issuer = supabase_url.rstrip("/") + "/auth/v1"

    for provider in providers:
        if not isinstance(provider, dict):
            continue
        name = str(provider.get("name") or "").strip()
        issuer = str(provider.get("issuer") or "").strip().rstrip("/")
        enable_login = bool(provider.get("enable_login"))
        if not name:
            continue
        if not enable_login:
            continue
        if issuer == firebase_issuer and firebase_name is None:
            firebase_name = name
        if issuer == supabase_issuer and supabase_name is None:
            supabase_name = name

    return {
        "firebase": firebase_name or "firebase",
        "supabase": supabase_name or "supabase",
    }

domain = sys.argv[1]
payload = {"stacks": []}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    stack, project_id, auth_domain, control_domain, api_domain, auth_provider_config_file, firebase_project_id, firebase_api_key, supabase_url, supabase_anon_key = line.split("\t", 9)
    provider_names = load_provider_names(auth_provider_config_file, firebase_project_id, supabase_url)
    auth_providers = []
    if firebase_project_id and firebase_api_key:
        auth_providers.append(
            {
                "type": "firebase",
                "name": provider_names["firebase"],
                "label": titleize_provider(provider_names["firebase"]),
                "firebaseProjectId": firebase_project_id,
                "firebaseApiKey": firebase_api_key,
            }
        )
    if supabase_url and supabase_anon_key:
        auth_providers.append(
            {
                "type": "supabase",
                "name": provider_names["supabase"],
                "label": titleize_provider(provider_names["supabase"]),
                "supabaseUrl": supabase_url,
                "supabaseAnonKey": supabase_anon_key,
            }
        )
    payload["stacks"].append(
        {
            "key": stack,
            "label": label_for_stack(stack),
            "projectId": project_id,
            "authBaseUrl": f"https://{auth_domain}",
            "controlPlaneBaseUrl": f"https://{control_domain}",
            "apiBaseUrl": f"https://{api_domain}",
            "oidcClientId": "ltbase-controlplane-ui",
            "redirectUri": f"https://{domain}/auth/callback",
            "authProviders": auth_providers,
        }
    )

print(json.dumps(payload, separators=(",", ":")))
' "${CONTROLPLANE_UI_DOMAIN:-}" "${BOOTSTRAP_ENV_FILE_DIR:-$(pwd)}"
}
