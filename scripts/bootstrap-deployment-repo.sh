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

if ! bootstrap_env_has_stack "${STACK}"; then
  echo "unknown stack: ${STACK}" >&2
  exit 1
fi

required_vars=(DEPLOYMENT_REPO PULUMI_BACKEND_URL LTBASE_RELEASES_REPO LTBASE_RELEASE_ID LTBASE_RELEASES_TOKEN CLOUDFLARE_API_TOKEN GEMINI_API_KEY CLOUDFLARE_ZONE_ID GITHUB_ORG GITHUB_REPO GEMINI_MODEL DSQL_PORT DSQL_DB DSQL_USER DSQL_PROJECT_SCHEMA MTLS_TRUSTSTORE_FILE MTLS_TRUSTSTORE_KEY)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

if ! bootstrap_env_require_stack_values "${STACK}" AWS_REGION AWS_ROLE_ARN PULUMI_SECRETS_PROVIDER API_DOMAIN CONTROL_DOMAIN AUTH_DOMAIN PROJECT_ID AUTH_PROVIDER_CONFIG_FILE OIDC_ISSUER_URL JWKS_URL RUNTIME_BUCKET TABLE_NAME; then
  exit 1
fi

bootstrap_env_info "configuring repository variables and secrets for ${DEPLOYMENT_REPO}"
while IFS= read -r target_stack; do
  target_upper="$(bootstrap_env_stack_upper "${target_stack}")"
  target_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${target_stack}")"
  target_secrets_provider="$(bootstrap_env_resolve_stack_value PULUMI_SECRETS_PROVIDER "${target_stack}")"
  target_role_arn="$(bootstrap_env_resolve_stack_value AWS_ROLE_ARN "${target_stack}")"

  bootstrap_env_run_quiet gh variable set "AWS_REGION_${target_upper}" --repo "${DEPLOYMENT_REPO}" --body "${target_region}"
  bootstrap_env_run_quiet gh variable set "PULUMI_SECRETS_PROVIDER_${target_upper}" --repo "${DEPLOYMENT_REPO}" --body "${target_secrets_provider}"
  bootstrap_env_run_quiet gh secret set "AWS_ROLE_ARN_${target_upper}" --repo "${DEPLOYMENT_REPO}" --body "${target_role_arn}"
done < <(bootstrap_env_each_stack)

bootstrap_env_run_quiet gh variable set PULUMI_BACKEND_URL --repo "${DEPLOYMENT_REPO}" --body "${PULUMI_BACKEND_URL}"
bootstrap_env_run_quiet gh variable set LTBASE_RELEASES_REPO --repo "${DEPLOYMENT_REPO}" --body "${LTBASE_RELEASES_REPO}"
bootstrap_env_run_quiet gh variable set LTBASE_RELEASE_ID --repo "${DEPLOYMENT_REPO}" --body "${LTBASE_RELEASE_ID}"
bootstrap_env_run_quiet gh variable set STACKS --repo "${DEPLOYMENT_REPO}" --body "${STACKS}"
bootstrap_env_run_quiet gh variable set PROMOTION_PATH --repo "${DEPLOYMENT_REPO}" --body "${PROMOTION_PATH}"
bootstrap_env_run_quiet gh variable set PREVIEW_DEFAULT_STACK --repo "${DEPLOYMENT_REPO}" --body "${PREVIEW_DEFAULT_STACK}"

bootstrap_env_run_quiet gh secret set LTBASE_RELEASES_TOKEN --repo "${DEPLOYMENT_REPO}" --body "${LTBASE_RELEASES_TOKEN}"
bootstrap_env_run_quiet gh secret set CLOUDFLARE_API_TOKEN --repo "${DEPLOYMENT_REPO}" --body "${CLOUDFLARE_API_TOKEN}"

selected_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${STACK}")"
backend_stack="$(bootstrap_env_csv_first "${PROMOTION_PATH:-${STACKS}}")"
backend_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${backend_stack}")"
selected_secrets_provider="$(bootstrap_env_resolve_stack_value PULUMI_SECRETS_PROVIDER "${STACK}")"
selected_runtime_bucket="$(bootstrap_env_resolve_stack_value RUNTIME_BUCKET "${STACK}")"
selected_table_name="$(bootstrap_env_resolve_stack_value TABLE_NAME "${STACK}")"
selected_api_domain="$(bootstrap_env_resolve_stack_value API_DOMAIN "${STACK}")"
selected_control_domain="$(bootstrap_env_resolve_stack_value CONTROL_DOMAIN "${STACK}")"
selected_auth_domain="$(bootstrap_env_resolve_stack_value AUTH_DOMAIN "${STACK}")"
selected_project_id="$(bootstrap_env_resolve_stack_value PROJECT_ID "${STACK}")"
selected_auth_provider_config_file="$(bootstrap_env_resolve_stack_value AUTH_PROVIDER_CONFIG_FILE "${STACK}")"
selected_oidc_issuer_url="$(bootstrap_env_resolve_stack_value OIDC_ISSUER_URL "${STACK}")"
selected_jwks_url="$(bootstrap_env_resolve_stack_value JWKS_URL "${STACK}")"
selected_account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${STACK}")"
selected_github_oidc_provider_arn="arn:aws:iam::${selected_account_id}:oidc-provider/token.actions.githubusercontent.com"

backend_env=(env)
while IFS= read -r token; do
  backend_env+=("${token}")
done < <(bootstrap_env_stack_runtime_env "${backend_stack}")

stack_env=(env)
while IFS= read -r token; do
  stack_env+=("${token}")
done < <(bootstrap_env_stack_runtime_env "${STACK}")

pushd "${INFRA_DIR}" >/dev/null
bootstrap_env_info "configuring Pulumi stack ${STACK}"
bootstrap_env_run_quiet "${backend_env[@]}" pulumi login "${PULUMI_BACKEND_URL}"
stack_select_output=""
if stack_select_output="$("${stack_env[@]}" pulumi stack select "${STACK}" 2>&1)"; then
  :
else
  stack_select_status=$?
  if [[ "${stack_select_output}" == *"no stack named"*"found"* ]]; then
    bootstrap_env_run_quiet "${stack_env[@]}" pulumi stack init "${STACK}" --secrets-provider "${selected_secrets_provider}"
  else
    if [[ -n "${stack_select_output}" ]]; then
      printf '%s\n' "${stack_select_output}" >&2
    fi
    exit "${stack_select_status}"
  fi
fi
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set awsRegion "${selected_region}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set runtimeBucket "${selected_runtime_bucket}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set tableName "${selected_table_name}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set mtlsTruststoreFile "${MTLS_TRUSTSTORE_FILE}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set mtlsTruststoreKey "${MTLS_TRUSTSTORE_KEY}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set apiDomain "${selected_api_domain}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set controlPlaneDomain "${selected_control_domain}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set authDomain "${selected_auth_domain}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set projectId "${selected_project_id}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set authProviderConfigFile "${selected_auth_provider_config_file}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set cloudflareZoneId "${CLOUDFLARE_ZONE_ID}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set oidcIssuerUrl "${selected_oidc_issuer_url}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set jwksUrl "${selected_jwks_url}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set githubOidcProviderArn "${selected_github_oidc_provider_arn}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set githubOrg "${GITHUB_ORG}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set githubRepo "${GITHUB_REPO}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set releaseId "${LTBASE_RELEASE_ID}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set dsqlPort "${DSQL_PORT}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set dsqlDB "${DSQL_DB}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set dsqlUser "${DSQL_USER}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set dsqlProjectSchema "${DSQL_PROJECT_SCHEMA}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set geminiModel "${GEMINI_MODEL}" --stack "${STACK}"
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set --secret geminiApiKey "${GEMINI_API_KEY}" --stack "${STACK}"
popd >/dev/null
