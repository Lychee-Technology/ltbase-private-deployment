#!/usr/bin/env bash

set -euo pipefail

STACK=""
INFRA_DIR="infra"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      STACK="$2"
      shift 2
      ;;
    --infra-dir)
      INFRA_DIR="$2"
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${STACK}" ]]; then
  printf 'stack is required\n' >&2
  exit 1
fi

stack_file="${INFRA_DIR}/Pulumi.${STACK}.yaml"
display_path="infra/Pulumi.${STACK}.yaml"

if [[ ! -f "${stack_file}" ]]; then
  printf "Missing Pulumi stack file '%s'. Rerun bootstrap-deployment-repo.sh or restore the stack config file.\n" "${display_path}" >&2
  exit 1
fi

required_keys=(
  "ltbase-infra:deploymentAwsAccountId"
  "ltbase-infra:runtimeBucket"
  "ltbase-infra:tableName"
  "ltbase-infra:mtlsTruststoreFile"
  "ltbase-infra:mtlsTruststoreKey"
  "ltbase-infra:apiDomain"
  "ltbase-infra:controlPlaneDomain"
  "ltbase-infra:authDomain"
  "ltbase-infra:projectId"
  "ltbase-infra:authProviderConfigFile"
  "ltbase-infra:cloudflareZoneId"
  "ltbase-infra:oidcIssuerUrl"
  "ltbase-infra:jwksUrl"
  "ltbase-infra:releaseId"
  "ltbase-infra:githubOrg"
  "ltbase-infra:githubRepo"
  "ltbase-infra:githubOidcProviderArn"
  "ltbase-infra:geminiApiKey"
)

for key in "${required_keys[@]}"; do
  if ! grep -Fq "  ${key}:" "${stack_file}"; then
    printf "Missing required Pulumi config key '%s' in %s. Rerun bootstrap-deployment-repo.sh or update the stack config file.\n" "${key}" "${display_path}" >&2
    exit 1
  fi
done
