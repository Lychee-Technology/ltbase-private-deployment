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

# shellcheck disable=SC1090
source "${ENV_FILE}"

required_vars=(DEPLOYMENT_REPO AWS_REGION_DEVO AWS_REGION_PROD AWS_ACCOUNT_ID_DEVO AWS_ACCOUNT_ID_PROD AWS_ROLE_NAME_DEVO AWS_ROLE_NAME_PROD PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

if [[ "${AWS_ACCOUNT_ID_DEVO}" != "${AWS_ACCOUNT_ID_PROD}" ]]; then
  if [[ -z "${AWS_PROFILE_DEVO:-}" || -z "${AWS_PROFILE_PROD:-}" ]]; then
    echo "AWS_PROFILE_DEVO and AWS_PROFILE_PROD are required when AWS_ACCOUNT_ID_DEVO and AWS_ACCOUNT_ID_PROD differ" >&2
    exit 1
  fi
fi

mkdir -p "${OUTPUT_DIR}"

devo_provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID_DEVO}:oidc-provider/token.actions.githubusercontent.com"
prod_provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID_PROD}:oidc-provider/token.actions.githubusercontent.com"

devo_profile_args=()
prod_profile_args=()
if [[ -n "${AWS_PROFILE_DEVO:-}" ]]; then
  devo_profile_args=(--profile "${AWS_PROFILE_DEVO}")
fi
if [[ -n "${AWS_PROFILE_PROD:-}" ]]; then
  prod_profile_args=(--profile "${AWS_PROFILE_PROD}")
fi

pulumi_backend_url="s3://${PULUMI_STATE_BUCKET}"
pulumi_secrets_provider_devo="awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION_DEVO}"
pulumi_secrets_provider_prod="awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION_PROD}"
devo_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID_DEVO}:role/${AWS_ROLE_NAME_DEVO}"
prod_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID_PROD}:role/${AWS_ROLE_NAME_PROD}"

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

cat >"${OUTPUT_DIR}/devo-role-policy.json" <<EOF
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
      "Action": "iam:PassRole",
      "Resource": "${devo_role_arn}"
    }
  ]
}
EOF

cat >"${OUTPUT_DIR}/prod-role-policy.json" <<EOF
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
      "Action": "iam:PassRole",
      "Resource": "${prod_role_arn}"
    }
  ]
}
EOF

if ! aws "${devo_profile_args[@]}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${devo_provider_arn}" >/dev/null 2>&1; then
  aws "${devo_profile_args[@]}" iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com >/dev/null
fi

if [[ "${AWS_ACCOUNT_ID_DEVO}" != "${AWS_ACCOUNT_ID_PROD}" ]]; then
  if ! aws "${prod_profile_args[@]}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${prod_provider_arn}" >/dev/null 2>&1; then
    aws "${prod_profile_args[@]}" iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com >/dev/null
  fi
fi

if ! aws "${devo_profile_args[@]}" iam get-role --role-name "${AWS_ROLE_NAME_DEVO}" >/dev/null 2>&1; then
  aws "${devo_profile_args[@]}" iam create-role --role-name "${AWS_ROLE_NAME_DEVO}" --assume-role-policy-document "file://${OUTPUT_DIR}/devo-trust-policy.json" >/dev/null
fi
if ! aws "${prod_profile_args[@]}" iam get-role --role-name "${AWS_ROLE_NAME_PROD}" >/dev/null 2>&1; then
  aws "${prod_profile_args[@]}" iam create-role --role-name "${AWS_ROLE_NAME_PROD}" --assume-role-policy-document "file://${OUTPUT_DIR}/prod-trust-policy.json" >/dev/null
fi

aws "${devo_profile_args[@]}" iam update-assume-role-policy --role-name "${AWS_ROLE_NAME_DEVO}" --policy-document "file://${OUTPUT_DIR}/devo-trust-policy.json" >/dev/null
aws "${prod_profile_args[@]}" iam update-assume-role-policy --role-name "${AWS_ROLE_NAME_PROD}" --policy-document "file://${OUTPUT_DIR}/prod-trust-policy.json" >/dev/null
aws "${devo_profile_args[@]}" iam put-role-policy --role-name "${AWS_ROLE_NAME_DEVO}" --policy-name LTBaseDeploymentAccess --policy-document "file://${OUTPUT_DIR}/devo-role-policy.json" >/dev/null
aws "${prod_profile_args[@]}" iam put-role-policy --role-name "${AWS_ROLE_NAME_PROD}" --policy-name LTBaseDeploymentAccess --policy-document "file://${OUTPUT_DIR}/prod-role-policy.json" >/dev/null

if ! aws s3api head-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null 2>&1; then
  if [[ "${AWS_REGION_DEVO}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null
  else
    aws s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" --region "${AWS_REGION_DEVO}" --create-bucket-configuration "LocationConstraint=${AWS_REGION_DEVO}" >/dev/null
  fi
fi

aws s3api put-bucket-versioning --bucket "${PULUMI_STATE_BUCKET}" --versioning-configuration Status=Enabled >/dev/null
aws s3api put-bucket-encryption --bucket "${PULUMI_STATE_BUCKET}" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
aws s3api put-public-access-block --bucket "${PULUMI_STATE_BUCKET}" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

alias_json_devo="$(aws "${devo_profile_args[@]}" kms list-aliases --region "${AWS_REGION_DEVO}" --output json)"
devo_key_id="$(python3 -c 'import json,sys; aliases=json.load(sys.stdin).get("Aliases", []); target="'"${PULUMI_KMS_ALIAS}"'"; match=next((a for a in aliases if a.get("AliasName")==target and a.get("TargetKeyId")), None); print(match.get("TargetKeyId", "") if match else "")' <<<"${alias_json_devo}")"

if [[ -z "${devo_key_id}" ]]; then
  devo_key_id="$(aws "${devo_profile_args[@]}" kms create-key --region "${AWS_REGION_DEVO}" --description "Pulumi secrets for LTBase private deployment" --query 'KeyMetadata.KeyId' --output text)"
  aws "${devo_profile_args[@]}" kms create-alias --region "${AWS_REGION_DEVO}" --alias-name "${PULUMI_KMS_ALIAS}" --target-key-id "${devo_key_id}" >/dev/null
fi

alias_json_prod="$(aws "${prod_profile_args[@]}" kms list-aliases --region "${AWS_REGION_PROD}" --output json)"
prod_key_id="$(python3 -c 'import json,sys; aliases=json.load(sys.stdin).get("Aliases", []); target="'"${PULUMI_KMS_ALIAS}"'"; match=next((a for a in aliases if a.get("AliasName")==target and a.get("TargetKeyId")), None); print(match.get("TargetKeyId", "") if match else "")' <<<"${alias_json_prod}")"

if [[ -z "${prod_key_id}" ]]; then
  prod_key_id="$(aws "${prod_profile_args[@]}" kms create-key --region "${AWS_REGION_PROD}" --description "Pulumi secrets for LTBase private deployment" --query 'KeyMetadata.KeyId' --output text)"
  aws "${prod_profile_args[@]}" kms create-alias --region "${AWS_REGION_PROD}" --alias-name "${PULUMI_KMS_ALIAS}" --target-key-id "${prod_key_id}" >/dev/null
fi

cat >"${OUTPUT_DIR}/foundation.env" <<EOF
AWS_ROLE_ARN_DEVO=${devo_role_arn}
AWS_ROLE_ARN_PROD=${prod_role_arn}
PULUMI_BACKEND_URL=${pulumi_backend_url}
PULUMI_SECRETS_PROVIDER_DEVO=${pulumi_secrets_provider_devo}
PULUMI_SECRETS_PROVIDER_PROD=${pulumi_secrets_provider_prod}
EOF
