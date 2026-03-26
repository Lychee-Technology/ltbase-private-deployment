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

required_vars=(AWS_REGION AWS_ACCOUNT_ID PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS AWS_ROLE_ARN_DEVO)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}"

if ! aws s3api head-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null 2>&1; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null
  else
    aws s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" --region "${AWS_REGION}" --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
fi

aws s3api put-bucket-versioning --bucket "${PULUMI_STATE_BUCKET}" --versioning-configuration Status=Enabled >/dev/null
aws s3api put-bucket-encryption --bucket "${PULUMI_STATE_BUCKET}" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
aws s3api put-public-access-block --bucket "${PULUMI_STATE_BUCKET}" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

alias_json="$(aws kms list-aliases --region "${AWS_REGION}" --output json)"
key_id="$(python3 -c 'import json,sys; aliases=json.load(sys.stdin).get("Aliases", []); target="'"${PULUMI_KMS_ALIAS}"'"; match=next((a for a in aliases if a.get("AliasName")==target and a.get("TargetKeyId")), None); print(match.get("TargetKeyId", "") if match else "")' <<<"${alias_json}")"

if [[ -z "${key_id}" ]]; then
  key_id="$(aws kms create-key --region "${AWS_REGION}" --description "Pulumi secrets for LTBase private deployment" --query 'KeyMetadata.KeyId' --output text)"
  aws kms create-alias --region "${AWS_REGION}" --alias-name "${PULUMI_KMS_ALIAS}" --target-key-id "${key_id}" >/dev/null
fi

pulumi_backend_url="s3://${PULUMI_STATE_BUCKET}"
pulumi_secrets_provider="awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION}"

cat >"${OUTPUT_DIR}/pulumi-backend.env" <<EOF
PULUMI_BACKEND_URL=${pulumi_backend_url}
PULUMI_SECRETS_PROVIDER=${pulumi_secrets_provider}
EOF

cat >"${OUTPUT_DIR}/pulumi-kms-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDeployRoleUseOfPulumiSecretsKey",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${AWS_ROLE_ARN_DEVO}"
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

printf 'PULUMI_BACKEND_URL=%s\n' "${pulumi_backend_url}"
printf 'PULUMI_SECRETS_PROVIDER=%s\n' "${pulumi_secrets_provider}"
