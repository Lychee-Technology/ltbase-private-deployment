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

bootstrap_env_require_vars PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS
while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID AWS_ROLE_ARN
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"

backend_stack="$(bootstrap_env_csv_first "${PROMOTION_PATH:-${STACKS}}")"
backend_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${backend_stack}")"

if ! bootstrap_env_aws_command_for_stack "${backend_stack}" s3api head-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null 2>&1; then
  if [[ "${backend_region}" == "us-east-1" ]]; then
    bootstrap_env_aws_command_for_stack "${backend_stack}" s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null
  else
    bootstrap_env_aws_command_for_stack "${backend_stack}" s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" --region "${backend_region}" --create-bucket-configuration "LocationConstraint=${backend_region}" >/dev/null
  fi
fi

bootstrap_env_aws_command_for_stack "${backend_stack}" s3api put-bucket-versioning --bucket "${PULUMI_STATE_BUCKET}" --versioning-configuration Status=Enabled >/dev/null
bootstrap_env_aws_command_for_stack "${backend_stack}" s3api put-bucket-encryption --bucket "${PULUMI_STATE_BUCKET}" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
bootstrap_env_aws_command_for_stack "${backend_stack}" s3api put-public-access-block --bucket "${PULUMI_STATE_BUCKET}" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

role_arns_json="$({ while IFS= read -r stack; do printf '%s\n' "$(bootstrap_env_resolve_stack_value AWS_ROLE_ARN "${stack}")"; done < <(bootstrap_env_each_stack); } | python3 -c 'import json, sys; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))')"

pulumi_backend_url="s3://${PULUMI_STATE_BUCKET}"
cat >"${OUTPUT_DIR}/pulumi-backend.env" <<EOF
PULUMI_BACKEND_URL=${pulumi_backend_url}
EOF

while IFS= read -r stack; do
  stack_upper="$(bootstrap_env_stack_upper "${stack}")"
  stack_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  alias_json="$(bootstrap_env_aws_command_for_stack "${stack}" kms list-aliases --region "${stack_region}" --output json)"
  key_id="$(python3 -c 'import json,sys; aliases=json.load(sys.stdin).get("Aliases", []); target="'"${PULUMI_KMS_ALIAS}"'"; match=next((a for a in aliases if a.get("AliasName")==target and a.get("TargetKeyId")), None); print(match.get("TargetKeyId", "") if match else "")' <<<"${alias_json}")"

  if [[ -z "${key_id}" ]]; then
    key_id="$(bootstrap_env_aws_command_for_stack "${stack}" kms create-key --region "${stack_region}" --description "Pulumi secrets for LTBase private deployment" --query 'KeyMetadata.KeyId' --output text)"
    bootstrap_env_aws_command_for_stack "${stack}" kms create-alias --region "${stack_region}" --alias-name "${PULUMI_KMS_ALIAS}" --target-key-id "${key_id}" >/dev/null
  fi

  printf 'PULUMI_SECRETS_PROVIDER_%s=awskms://%s?region=%s\n' "${stack_upper}" "${PULUMI_KMS_ALIAS}" "${stack_region}" >>"${OUTPUT_DIR}/pulumi-backend.env"
done < <(bootstrap_env_each_stack)

cat >"${OUTPUT_DIR}/pulumi-kms-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDeployRoleUseOfPulumiSecretsKey",
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

printf 'PULUMI_BACKEND_URL=%s\n' "${pulumi_backend_url}"
while IFS= read -r stack; do
  stack_upper="$(bootstrap_env_stack_upper "${stack}")"
  provider_value="$(bootstrap_env_resolve_stack_value PULUMI_SECRETS_PROVIDER "${stack}")"
  printf 'PULUMI_SECRETS_PROVIDER_%s=%s\n' "${stack_upper}" "${provider_value}"
done < <(bootstrap_env_each_stack)
