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

required_vars=(DEPLOYMENT_REPO AWS_REGION_DEVO AWS_ACCOUNT_ID_DEVO AWS_ACCOUNT_ID_PROD AWS_ROLE_NAME_DEVO AWS_ROLE_NAME_PROD AWS_ROLE_ARN_DEVO AWS_ROLE_ARN_PROD PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}"

aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com >/dev/null || true
aws iam create-role --role-name "${AWS_ROLE_NAME_DEVO}" --assume-role-policy-document file://<(printf '{}') >/dev/null || true
aws iam create-role --role-name "${AWS_ROLE_NAME_PROD}" --assume-role-policy-document file://<(printf '{}') >/dev/null || true

if [[ "${AWS_REGION_DEVO}" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null || true
else
  aws s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" --region "${AWS_REGION_DEVO}" --create-bucket-configuration "LocationConstraint=${AWS_REGION_DEVO}" >/dev/null || true
fi

aws kms create-key --region "${AWS_REGION_DEVO}" --description "Pulumi secrets for LTBase private deployment" --query 'KeyMetadata.KeyId' --output text >/dev/null || true

cat >"${OUTPUT_DIR}/foundation.env" <<EOF
AWS_ROLE_ARN_DEVO=${AWS_ROLE_ARN_DEVO}
AWS_ROLE_ARN_PROD=${AWS_ROLE_ARN_PROD}
PULUMI_BACKEND_URL=s3://${PULUMI_STATE_BUCKET}
EOF
