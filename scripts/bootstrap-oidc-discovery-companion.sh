#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
OUTPUT_DIR="dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
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

required_vars=(GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO_VISIBILITY OIDC_DISCOVERY_DOMAIN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN OIDC_DISCOVERY_TEMPLATE_REPO OIDC_DISCOVERY_REPO_NAME OIDC_DISCOVERY_REPO OIDC_DISCOVERY_PAGES_PROJECT)
bootstrap_env_require_vars "${required_vars[@]}"

if ! python3 -c 'import re, sys; domain = sys.argv[1]; label = r"(?!-)[a-z0-9-]{1,63}(?<!-)"; pattern = rf"^{label}(\.{label})+$"; sys.exit(0 if re.fullmatch(pattern, domain.lower()) else 1)' "${OIDC_DISCOVERY_DOMAIN}"; then
  printf 'OIDC_DISCOVERY_DOMAIN is invalid: %s\n' "${OIDC_DISCOVERY_DOMAIN}" >&2
  printf 'Use a valid DNS hostname with letters, digits, and hyphens only. Underscores are not allowed.\n' >&2
  exit 1
fi

while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID OIDC_DISCOVERY_AWS_ROLE_NAME OIDC_DISCOVERY_AWS_ROLE_ARN OIDC_ISSUER_URL JWKS_URL
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"
companion_summary="${OUTPUT_DIR}/oidc-discovery-companion.env"
oidc_stack_config="$(bootstrap_env_oidc_discovery_stack_config_json)"

visibility_flag="--private"
if [[ "${DEPLOYMENT_REPO_VISIBILITY}" == "public" ]]; then
  visibility_flag="--public"
fi

cloudflare_headers=(
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
  -H "Content-Type: application/json"
)

pages_project_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}"
pages_projects_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects"
pages_domain_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}/domains/${OIDC_DISCOVERY_DOMAIN}"
pages_domains_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}/domains"

if ! gh repo view "${OIDC_DISCOVERY_REPO}" >/dev/null 2>&1; then
  gh repo create "${OIDC_DISCOVERY_REPO}" --template "${OIDC_DISCOVERY_TEMPLATE_REPO}" ${visibility_flag} --description "LTBase OIDC discovery companion for ${DEPLOYMENT_REPO_NAME}" --clone=false
fi

repo_metadata="$(gh api "repos/${OIDC_DISCOVERY_REPO}")"
default_branch="$(python3 -c 'import json, sys; data = json.load(sys.stdin); print(data.get("default_branch", "main"))' <<<"${repo_metadata}"
)"

if ! curl -fsS "${cloudflare_headers[@]}" "${pages_project_url}" >/dev/null 2>&1; then
  project_payload="$(python3 - "${OIDC_DISCOVERY_PAGES_PROJECT}" "${GITHUB_OWNER}" "${OIDC_DISCOVERY_REPO_NAME}" "${default_branch}" <<'PY'
import json
import sys

print(json.dumps({
    "name": sys.argv[1],
    "production_branch": sys.argv[4],
    "source": {
        "type": "github",
        "config": {
            "owner": sys.argv[2],
            "repo_name": sys.argv[3],
            "production_branch": sys.argv[4],
            "preview_deployment_setting": "none",
            "production_deployments_enabled": True,
        },
    },
}, separators=(",", ":")))
PY
)"
  curl -fsS -X POST "${cloudflare_headers[@]}" "${pages_projects_url}" --data "${project_payload}" >/dev/null
fi

if ! curl -fsS "${cloudflare_headers[@]}" "${pages_domain_url}" >/dev/null 2>&1; then
  domain_payload="$(python3 - "${OIDC_DISCOVERY_DOMAIN}" <<'PY'
import json
import sys

print(json.dumps({"name": sys.argv[1]}, separators=(",", ":")))
PY
)"
  curl -fsS -X POST "${cloudflare_headers[@]}" "${pages_domains_url}" --data "${domain_payload}" >/dev/null
fi

gh variable set OIDC_DISCOVERY_DOMAIN --repo "${OIDC_DISCOVERY_REPO}" --body "${OIDC_DISCOVERY_DOMAIN}"
gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo "${OIDC_DISCOVERY_REPO}" --body "${oidc_stack_config}"

create_or_update_discovery_role() {
  local stack="$1"
  local upper_name account_id region role_name role_arn provider_arn
  local trust_policy_path role_policy_path

  bootstrap_env_require_aws_credentials_for_stack "${stack}"

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  role_name="$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_NAME "${stack}")"
  role_arn="$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_ARN "${stack}")"
  provider_arn="arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com"
  trust_policy_path="${OUTPUT_DIR}/oidc-discovery-${stack}-trust-policy.json"
  role_policy_path="${OUTPUT_DIR}/oidc-discovery-${stack}-role-policy.json"

  cat >"${trust_policy_path}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${OIDC_DISCOVERY_REPO}:ref:refs/heads/${default_branch}"
          ]
        }
      }
    }
  ]
}
EOF

  cat >"${role_policy_path}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:GetPublicKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" >/dev/null 2>&1; then
    bootstrap_env_aws_command_for_stack "${stack}" iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com >/dev/null
  fi

  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    bootstrap_env_aws_command_for_stack "${stack}" iam create-role --role-name "${role_name}" --assume-role-policy-document "file://${trust_policy_path}" >/dev/null
  fi

  bootstrap_env_aws_command_for_stack "${stack}" iam update-assume-role-policy --role-name "${role_name}" --policy-document "file://${trust_policy_path}" >/dev/null
  bootstrap_env_aws_command_for_stack "${stack}" iam put-role-policy --role-name "${role_name}" --policy-name LTBaseOIDCDiscoveryAccess --policy-document "file://${role_policy_path}" >/dev/null

  cat >>"${companion_summary}" <<EOF
OIDC_DISCOVERY_AWS_ROLE_ARN_${upper_name}=${role_arn}
EOF
}

: >"${companion_summary}"
cat >>"${companion_summary}" <<EOF
OIDC_DISCOVERY_REPO=${OIDC_DISCOVERY_REPO}
OIDC_DISCOVERY_REPO_NAME=${OIDC_DISCOVERY_REPO_NAME}
OIDC_DISCOVERY_PAGES_PROJECT=${OIDC_DISCOVERY_PAGES_PROJECT}
OIDC_DISCOVERY_DOMAIN=${OIDC_DISCOVERY_DOMAIN}
EOF

while IFS= read -r stack; do
  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  create_or_update_discovery_role "${stack}"
  cat >>"${companion_summary}" <<EOF
OIDC_ISSUER_URL_${upper_name}=$(bootstrap_env_resolve_stack_value OIDC_ISSUER_URL "${stack}")
JWKS_URL_${upper_name}=$(bootstrap_env_resolve_stack_value JWKS_URL "${stack}")
EOF
done < <(bootstrap_env_each_stack)
