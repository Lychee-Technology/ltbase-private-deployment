#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/bootstrap-pulumi-backend.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
mkdir -p "${fake_bin}"

cat >"${temp_dir}/.env" <<'EOF'
AWS_REGION=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ACCOUNT_ID_PROD=210987654321
PULUMI_STATE_BUCKET=test-pulumi-state
PULUMI_KMS_ALIAS=alias/test-pulumi-secrets
AWS_ROLE_ARN_DEVO=arn:aws:iam::123456789012:role/test-deploy-role
AWS_ROLE_ARN_PROD=arn:aws:iam::210987654321:role/test-prod-role
EOF

cat >"${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "s3api head-bucket" ]]; then
  exit 1
fi
if [[ "$1 $2" == "kms list-aliases" ]]; then
  printf '{"Aliases":[]}'
  exit 0
fi
if [[ "$1 $2" == "kms create-key" ]]; then
  printf '{"KeyMetadata":{"KeyId":"key-123"}}'
  exit 0
fi
exit 0
EOF
chmod +x "${fake_bin}/aws"

if [[ -x "${SCRIPT_PATH}" ]]; then
  if ! output="$(PATH="${fake_bin}:$PATH" "${SCRIPT_PATH}" --env-file "${temp_dir}/.env" --output-dir "${temp_dir}/dist" 2>&1)"; then
    rm -rf "${temp_dir}"
    fail "expected script to succeed when implemented, got: ${output}"
  fi

  assert_file_contains "${temp_dir}/dist/pulumi-backend.env" "PULUMI_BACKEND_URL=s3://test-pulumi-state"
  assert_file_contains "${temp_dir}/dist/pulumi-backend.env" "PULUMI_SECRETS_PROVIDER=awskms://alias/test-pulumi-secrets?region=ap-northeast-1"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "kms:Decrypt"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "arn:aws:iam::123456789012:role/test-deploy-role"
  assert_file_contains "${temp_dir}/dist/pulumi-kms-policy.json" "arn:aws:iam::210987654321:role/test-prod-role"
else
  fail "missing executable script: ${SCRIPT_PATH}"
fi

rm -rf "${temp_dir}"
printf 'PASS: bootstrap-pulumi-backend tests\n'
