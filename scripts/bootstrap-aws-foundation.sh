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

capture_stdout_quiet() {
  local destination_var="$1"
  local output command_status stderr_file
  shift

  stderr_file="$(mktemp)"
  if output="$("$@" 2>"${stderr_file}")"; then
    rm -f "${stderr_file}"
    printf -v "${destination_var}" '%s' "${output}"
    return 0
  fi

  command_status=$?
  if [[ -s "${stderr_file}" ]]; then
    cat "${stderr_file}" >&2
  fi
  rm -f "${stderr_file}"
  return "${command_status}"
}

required_vars=(DEPLOYMENT_REPO AWS_REGION_DEVO AWS_REGION_PROD AWS_ACCOUNT_ID_DEVO AWS_ACCOUNT_ID_PROD AWS_ROLE_NAME_DEVO AWS_ROLE_NAME_PROD PULUMI_STATE_BUCKET PULUMI_KMS_ALIAS)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
done

while IFS= read -r stack; do
  bootstrap_env_require_stack_values "${stack}" AWS_REGION AWS_ACCOUNT_ID AWS_ROLE_NAME
done < <(bootstrap_env_each_stack)

while IFS= read -r stack; do
  stack_account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  if [[ "${stack_account_id}" != "${AWS_ACCOUNT_ID_DEVO}" ]]; then
    stack_upper="$(bootstrap_env_stack_upper "${stack}")"
    profile_name="AWS_PROFILE_${stack_upper}"
    if [[ -z "${!profile_name:-}" ]]; then
      echo "AWS profile is required for stack ${stack} when its AWS account differs from the first stack account" >&2
      exit 1
    fi
  fi
done < <(bootstrap_env_each_stack)

mkdir -p "${OUTPUT_DIR}"
summary_path="${OUTPUT_DIR}/foundation.env"
cat >"${summary_path}" <<EOF
PULUMI_BACKEND_URL=s3://${PULUMI_STATE_BUCKET}
EOF

first_stack="$(bootstrap_env_csv_first "${PROMOTION_PATH:-${STACKS}}")"
first_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${first_stack}")"

while IFS= read -r stack; do
  bootstrap_env_info "Validating AWS credentials for stack: ${stack}"
  bootstrap_env_require_aws_credentials_for_stack "${stack}"
  stack_upper="$(bootstrap_env_stack_upper "${stack}")"
  stack_region="$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")"
  stack_account_id="$(bootstrap_env_resolve_stack_value AWS_ACCOUNT_ID "${stack}")"
  stack_role_name="$(bootstrap_env_resolve_stack_value AWS_ROLE_NAME "${stack}")"
  stack_role_arn="$(bootstrap_env_resolve_stack_value AWS_ROLE_ARN "${stack}")"
  provider_arn="arn:aws:iam::${stack_account_id}:oidc-provider/token.actions.githubusercontent.com"
  trust_policy_path="${OUTPUT_DIR}/${stack}-trust-policy.json"
  role_policy_path="${OUTPUT_DIR}/${stack}-role-policy.json"

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

  cat >"${role_policy_path}" <<EOF
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

  bootstrap_env_info "Reconciling IAM and KMS resources for stack: ${stack}"
  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" >/dev/null 2>&1; then
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
  fi

  if ! bootstrap_env_aws_command_for_stack "${stack}" iam get-role --role-name "${stack_role_name}" >/dev/null 2>&1; then
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam create-role --role-name "${stack_role_name}" --assume-role-policy-document "file://${trust_policy_path}"
  fi

  bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam update-assume-role-policy --role-name "${stack_role_name}" --policy-document "file://${trust_policy_path}"
  bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam put-role-policy --role-name "${stack_role_name}" --policy-name LTBaseDeploymentAccess --policy-document "file://${role_policy_path}"

  capture_stdout_quiet alias_json bootstrap_env_aws_command_for_stack "${stack}" kms list-aliases --region "${stack_region}" --output json
  key_id="$(python3 -c 'import json,sys; aliases=json.load(sys.stdin).get("Aliases", []); target="'"${PULUMI_KMS_ALIAS}"'"; match=next((a for a in aliases if a.get("AliasName")==target and a.get("TargetKeyId")), None); print(match.get("TargetKeyId", "") if match else "")' <<<"${alias_json}")"

  if [[ -z "${key_id}" ]]; then
    capture_stdout_quiet key_id bootstrap_env_aws_command_for_stack "${stack}" kms create-key --region "${stack_region}" --description "Pulumi secrets for LTBase private deployment" --query 'KeyMetadata.KeyId' --output text
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" kms create-alias --region "${stack_region}" --alias-name "${PULUMI_KMS_ALIAS}" --target-key-id "${key_id}"
  fi

  printf 'AWS_ROLE_ARN_%s=%s\n' "${stack_upper}" "${stack_role_arn}" >>"${summary_path}"
  printf 'PULUMI_SECRETS_PROVIDER_%s=awskms://%s?region=%s\n' "${stack_upper}" "${PULUMI_KMS_ALIAS}" "${stack_region}" >>"${summary_path}"
done < <(bootstrap_env_each_stack)

bootstrap_env_info "Ensuring shared Pulumi state bucket: ${PULUMI_STATE_BUCKET}"
if ! bootstrap_env_aws_command_for_stack "${first_stack}" s3api head-bucket --bucket "${PULUMI_STATE_BUCKET}" >/dev/null 2>&1; then
  if [[ "${first_region}" == "us-east-1" ]]; then
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${first_stack}" s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}"
  else
    bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${first_stack}" s3api create-bucket --bucket "${PULUMI_STATE_BUCKET}" --region "${first_region}" --create-bucket-configuration "LocationConstraint=${first_region}"
  fi
fi

bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${first_stack}" s3api put-bucket-versioning --bucket "${PULUMI_STATE_BUCKET}" --versioning-configuration Status=Enabled
bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${first_stack}" s3api put-bucket-encryption --bucket "${PULUMI_STATE_BUCKET}" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${first_stack}" s3api put-public-access-block --bucket "${PULUMI_STATE_BUCKET}" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
