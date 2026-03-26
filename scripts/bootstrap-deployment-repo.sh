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

# shellcheck disable=SC1090
source "${ENV_FILE}"

required_vars=(DEPLOYMENT_REPO AWS_REGION PULUMI_BACKEND_URL PULUMI_SECRETS_PROVIDER LTBASE_RELEASES_REPO LTBASE_RELEASE_ID AWS_ROLE_ARN_DEVO AWS_ROLE_ARN_PROD LTBASE_RELEASES_TOKEN CLOUDFLARE_API_TOKEN GEMINI_API_KEY API_DOMAIN CONTROL_DOMAIN AUTH_DOMAIN CLOUDFLARE_ZONE_ID OIDC_ISSUER_URL JWKS_URL RUNTIME_BUCKET TABLE_NAME GITHUB_ORG GITHUB_REPO GEMINI_MODEL DSQL_PORT DSQL_DB DSQL_USER DSQL_PROJECT_SCHEMA)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

gh variable set AWS_REGION --repo "${DEPLOYMENT_REPO}" --body "${AWS_REGION}"
gh variable set PULUMI_BACKEND_URL --repo "${DEPLOYMENT_REPO}" --body "${PULUMI_BACKEND_URL}"
gh variable set PULUMI_SECRETS_PROVIDER --repo "${DEPLOYMENT_REPO}" --body "${PULUMI_SECRETS_PROVIDER}"
gh variable set LTBASE_RELEASES_REPO --repo "${DEPLOYMENT_REPO}" --body "${LTBASE_RELEASES_REPO}"
gh variable set LTBASE_RELEASE_ID --repo "${DEPLOYMENT_REPO}" --body "${LTBASE_RELEASE_ID}"

gh secret set AWS_ROLE_ARN_DEVO --repo "${DEPLOYMENT_REPO}" --body "${AWS_ROLE_ARN_DEVO}"
gh secret set AWS_ROLE_ARN_PROD --repo "${DEPLOYMENT_REPO}" --body "${AWS_ROLE_ARN_PROD}"
gh secret set LTBASE_RELEASES_TOKEN --repo "${DEPLOYMENT_REPO}" --body "${LTBASE_RELEASES_TOKEN}"
gh secret set CLOUDFLARE_API_TOKEN --repo "${DEPLOYMENT_REPO}" --body "${CLOUDFLARE_API_TOKEN}"

pulumi login "${PULUMI_BACKEND_URL}"
if ! pulumi stack select "${STACK}" >/dev/null 2>&1; then
  pulumi stack init "${STACK}" --secrets-provider "${PULUMI_SECRETS_PROVIDER}"
fi

pushd "${INFRA_DIR}" >/dev/null
pulumi config set awsRegion "${AWS_REGION}" --stack "${STACK}"
pulumi config set runtimeBucket "${RUNTIME_BUCKET}" --stack "${STACK}"
pulumi config set tableName "${TABLE_NAME}" --stack "${STACK}"
pulumi config set apiDomain "${API_DOMAIN}" --stack "${STACK}"
pulumi config set controlPlaneDomain "${CONTROL_DOMAIN}" --stack "${STACK}"
pulumi config set authDomain "${AUTH_DOMAIN}" --stack "${STACK}"
pulumi config set cloudflareZoneId "${CLOUDFLARE_ZONE_ID}" --stack "${STACK}"
pulumi config set oidcIssuerUrl "${OIDC_ISSUER_URL}" --stack "${STACK}"
pulumi config set jwksUrl "${JWKS_URL}" --stack "${STACK}"
pulumi config set githubOrg "${GITHUB_ORG}" --stack "${STACK}"
pulumi config set githubRepo "${GITHUB_REPO}" --stack "${STACK}"
pulumi config set releaseId "${LTBASE_RELEASE_ID}" --stack "${STACK}"
pulumi config set dsqlPort "${DSQL_PORT}" --stack "${STACK}"
pulumi config set dsqlDB "${DSQL_DB}" --stack "${STACK}"
pulumi config set dsqlUser "${DSQL_USER}" --stack "${STACK}"
pulumi config set dsqlProjectSchema "${DSQL_PROJECT_SCHEMA}" --stack "${STACK}"
pulumi config set geminiModel "${GEMINI_MODEL}" --stack "${STACK}"
pulumi config set --secret geminiApiKey "${GEMINI_API_KEY}" --stack "${STACK}"
popd >/dev/null
