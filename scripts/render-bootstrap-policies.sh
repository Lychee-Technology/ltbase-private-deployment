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

required_vars=(GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID AWS_ROLE_NAME AWS_ROLE_ARN
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"
summary_path="${OUTPUT_DIR}/bootstrap-summary.env"
cat >"${summary_path}" <<EOF
DEPLOYMENT_REPO=${DEPLOYMENT_REPO}
PULUMI_BACKEND_URL=s3://${PULUMI_STATE_BUCKET}
EOF

role_arns_json="$({ while IFS= read -r stack; do printf '%s\n' "$(bootstrap_env_resolve_stack_value AWS_ROLE_ARN "${stack}")"; done < <(bootstrap_env_each_stack); } | python3 -c 'import json, sys; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))')"
first_stack="$(bootstrap_env_csv_first "${PROMOTION_PATH:-${STACKS}}")"

while IFS= read -r stack; do
  stack_upper="$(bootstrap_env_stack_upper "${stack}")"
  stack_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  stack_account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  stack_role_arn="$(bootstrap_env_resolve_stack_value AWS_ROLE_ARN "${stack}")"
  stack_role_name="$(bootstrap_env_resolve_stack_value AWS_ROLE_NAME "${stack}")"
  provider_arn="arn:aws:iam::${stack_account_id}:oidc-provider/token.actions.githubusercontent.com"
  stack_operator_policy_path="${OUTPUT_DIR}/bootstrap-operator-${stack}-policy.json"

  discovery_role_name=""
  discovery_role_var="OIDC_DISCOVERY_AWS_ROLE_NAME_${stack_upper}"
  if [[ -n "${!discovery_role_var:-}" ]]; then
    discovery_role_name="$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_NAME "${stack}")"
  fi

  role_resources_json="$({
    printf '%s\n' "arn:aws:iam::${stack_account_id}:role/${stack_role_name}"
    if [[ -n "${discovery_role_name}" ]]; then
      printf '%s\n' "arn:aws:iam::${stack_account_id}:role/${discovery_role_name}"
    fi
  } | python3 -c 'import json, sys; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))')"

  cat >"${OUTPUT_DIR}/${stack}-trust-policy.json" <<EOF
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
            "repo:${DEPLOYMENT_REPO}:ref:refs/heads/main",
            "repo:${DEPLOYMENT_REPO}:ref:refs/heads/feature/*",
            "repo:${DEPLOYMENT_REPO}:ref:refs/heads/release/*",
            "repo:${DEPLOYMENT_REPO}:pull_request"
          ]
        }
      }
    }
  ]
}
EOF

  cat >"${OUTPUT_DIR}/${stack}-role-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${PULUMI_STATE_BUCKET}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${PULUMI_STATE_BUCKET}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "${stack_role_arn}"
    },
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
EOF

  cat >"${stack_operator_policy_path}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateGitHubOidcProvider",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReadGitHubOidcProvider",
      "Effect": "Allow",
      "Action": [
        "iam:GetOpenIDConnectProvider"
      ],
      "Resource": "${provider_arn}"
    },
    {
      "Sid": "CreateBootstrapRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageBootstrapRoles",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": ${role_resources_json}
    },
    {
      "Sid": "ManagePulumiKmsBootstrap",
      "Effect": "Allow",
      "Action": [
        "kms:ListAliases",
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "UsePulumiKmsKey",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  printf 'PULUMI_SECRETS_PROVIDER_%s=awskms://%s?region=%s\n' "${stack_upper}" "${PULUMI_KMS_ALIAS}" "${stack_region}" >>"${summary_path}"
  printf 'AWS_ROLE_ARN_%s=%s\n' "${stack_upper}" "${stack_role_arn}" >>"${summary_path}"
done < <(bootstrap_env_each_stack)

cat >"${OUTPUT_DIR}/bootstrap-operator-first-stack-s3-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManagePulumiStateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:CreateBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock"
      ],
      "Resource": "arn:aws:s3:::${PULUMI_STATE_BUCKET}"
    },
    {
      "Sid": "ManagePulumiStateObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${PULUMI_STATE_BUCKET}/*"
    }
  ]
}
EOF

cat >"${OUTPUT_DIR}/pulumi-kms-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDeployRolesUseOfPulumiSecretsKey",
      "Effect": "Allow",
      "Principal": {
        "AWS": ${role_arns_json}
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF
