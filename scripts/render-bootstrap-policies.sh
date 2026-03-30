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

required_vars=(GITHUB_OWNER DEPLOYMENT_REPO_NAME DEPLOYMENT_REPO AWS_REGION_DEVO AWS_REGION_PROD AWS_ACCOUNT_ID_DEVO AWS_ACCOUNT_ID_PROD AWS_ROLE_NAME_DEVO AWS_ROLE_NAME_PROD AWS_ROLE_ARN_DEVO AWS_ROLE_ARN_PROD PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}"

devo_provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID_DEVO}:oidc-provider/token.actions.githubusercontent.com"
prod_provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID_PROD}:oidc-provider/token.actions.githubusercontent.com"
devo_provider_url="awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION_DEVO}"
prod_provider_url="awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION_PROD}"

cat >"${OUTPUT_DIR}/devo-trust-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${devo_provider_arn}"
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
            "repo:${DEPLOYMENT_REPO}:pull_request"
          ]
        }
      }
    }
  ]
}
EOF

cat >"${OUTPUT_DIR}/prod-trust-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${prod_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${DEPLOYMENT_REPO}:ref:refs/heads/main",
            "repo:${DEPLOYMENT_REPO}:ref:refs/heads/release/*"
          ]
        }
      }
    }
  ]
}
EOF

for target in devo prod; do
  if [[ "${target}" == "devo" ]]; then
    role_arn="${AWS_ROLE_ARN_DEVO}"
  else
    role_arn="${AWS_ROLE_ARN_PROD}"
  fi
  cat >"${OUTPUT_DIR}/${target}-role-policy.json" <<EOF
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
      "Resource": "${role_arn}"
    }
  ]
}
EOF
done

cat >"${OUTPUT_DIR}/pulumi-kms-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDeployRolesUseOfPulumiSecretsKey",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "${AWS_ROLE_ARN_DEVO}",
          "${AWS_ROLE_ARN_PROD}"
        ]
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

cat >"${OUTPUT_DIR}/bootstrap-summary.env" <<EOF
DEPLOYMENT_REPO=${DEPLOYMENT_REPO}
PULUMI_BACKEND_URL=s3://${PULUMI_STATE_BUCKET}
PULUMI_SECRETS_PROVIDER_DEVO=${devo_provider_url}
PULUMI_SECRETS_PROVIDER_PROD=${prod_provider_url}
AWS_ROLE_ARN_DEVO=${AWS_ROLE_ARN_DEVO}
AWS_ROLE_ARN_PROD=${AWS_ROLE_ARN_PROD}
EOF
