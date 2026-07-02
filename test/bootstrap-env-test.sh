#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB_PATH="${ROOT_DIR}/scripts/lib/bootstrap-env.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected [${expected}], got [${actual}]"
  fi
}

assert_file_eq() {
  local expected="$1"
  local path="$2"
  local message="$3"
  local actual
  actual="$(<"${path}")"
  assert_eq "${expected}" "${actual}" "${message}"
}

source "${LIB_PATH}"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

stdout_file="${temp_dir}/stdout"
stderr_file="${temp_dir}/stderr"

bootstrap_env_info 'hello world' >"${stdout_file}" 2>"${stderr_file}"
assert_file_eq '[info] hello world' "${stdout_file}" 'bootstrap_env_info should write info logs to stdout'
assert_file_eq '' "${stderr_file}" 'bootstrap_env_info should not write to stderr'

: >"${stdout_file}"
: >"${stderr_file}"
bootstrap_env_run_quiet bash -c 'printf "visible stdout\n"; printf "visible stderr\n" >&2' >"${stdout_file}" 2>"${stderr_file}"
assert_file_eq '' "${stdout_file}" 'bootstrap_env_run_quiet should suppress stdout on success'
assert_file_eq '' "${stderr_file}" 'bootstrap_env_run_quiet should suppress stderr on success'

: >"${stdout_file}"
: >"${stderr_file}"
set +e
bootstrap_env_run_quiet bash -c 'printf "failed stdout\n"; printf "failed stderr\n" >&2; exit 23' >"${stdout_file}" 2>"${stderr_file}"
status=$?
set -e
assert_eq '23' "${status}" 'bootstrap_env_run_quiet should preserve failing exit status'
assert_file_eq '' "${stdout_file}" 'bootstrap_env_run_quiet should not replay output to stdout on failure'
assert_file_eq $'failed stdout\nfailed stderr' "${stderr_file}" 'bootstrap_env_run_quiet should replay combined output to stderr on failure'

captured=''
: >"${stdout_file}"
: >"${stderr_file}"
bootstrap_env_capture_quiet captured bash -c 'printf "captured stdout\n"; printf "captured stderr\n" >&2' >"${stdout_file}" 2>"${stderr_file}"
assert_eq $'captured stdout\ncaptured stderr' "${captured}" 'bootstrap_env_capture_quiet should capture combined output on success'
assert_file_eq '' "${stdout_file}" 'bootstrap_env_capture_quiet should stay silent on success stdout'
assert_file_eq '' "${stderr_file}" 'bootstrap_env_capture_quiet should stay silent on success stderr'

captured='unchanged'
: >"${stdout_file}"
: >"${stderr_file}"
set +e
bootstrap_env_capture_quiet captured bash -c 'printf "capture failed stdout\n"; printf "capture failed stderr\n" >&2; exit 17' >"${stdout_file}" 2>"${stderr_file}"
status=$?
set -e
assert_eq '17' "${status}" 'bootstrap_env_capture_quiet should preserve failing exit status'
assert_eq 'unchanged' "${captured}" 'bootstrap_env_capture_quiet should not overwrite the destination variable on failure'
assert_file_eq '' "${stdout_file}" 'bootstrap_env_capture_quiet should not replay output to stdout on failure'
assert_file_eq $'capture failed stdout\ncapture failed stderr' "${stderr_file}" 'bootstrap_env_capture_quiet should replay combined output to stderr on failure'

# ---------- derivation regression: no OIDC_DISCOVERY_TEMPLATE_* defaults ----------

env_file="${temp_dir}/test-env"
cat >"${env_file}" <<'ENVEOF'
STACKS=devo
PROMOTION_PATH=devo
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
PULUMI_STATE_BUCKET=test-bucket
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
ENVEOF

bootstrap_env_load "${env_file}"

if [[ -n "${OIDC_DISCOVERY_TEMPLATE_REPO:-}" ]]; then
  fail "OIDC_DISCOVERY_TEMPLATE_REPO should not be derived by bootstrap_env_load"
fi
if [[ -n "${OIDC_DISCOVERY_TEMPLATE_REF:-}" ]]; then
  fail "OIDC_DISCOVERY_TEMPLATE_REF should not be derived by bootstrap_env_load"
fi
if [[ "${OIDC_DISCOVERY_PAGES_PROJECT:-}" != "customer-ltbase-oidc-discovery" ]]; then
  fail "OIDC_DISCOVERY_PAGES_PROJECT should still be derived: expected customer-ltbase-oidc-discovery, got ${OIDC_DISCOVERY_PAGES_PROJECT:-}"
fi

# ---------- constant defaults derived when unset ----------

assert_eq 'Lychee-Technology/ltbase-private-deployment' "${TEMPLATE_REPO:-}" 'TEMPLATE_REPO should default'
assert_eq 'private' "${DEPLOYMENT_REPO_VISIBILITY:-}" 'DEPLOYMENT_REPO_VISIBILITY should default'
assert_eq 'Customer LTBase deployment repo' "${DEPLOYMENT_REPO_DESCRIPTION:-}" 'DEPLOYMENT_REPO_DESCRIPTION should default'
assert_eq 'alias/ltbase-pulumi-secrets' "${PULUMI_KMS_ALIAS:-}" 'PULUMI_KMS_ALIAS should default'
assert_eq 'Lychee-Technology/ltbase-releases' "${LTBASE_RELEASES_REPO:-}" 'LTBASE_RELEASES_REPO should default'
assert_eq 'infra/certs/cloudflare-origin-pull-ca.pem' "${MTLS_TRUSTSTORE_FILE:-}" 'MTLS_TRUSTSTORE_FILE should default'
assert_eq 'mtls/cloudflare-origin-pull-ca.pem' "${MTLS_TRUSTSTORE_KEY:-}" 'MTLS_TRUSTSTORE_KEY should default'
assert_eq 'gemini-3.1-flash-lite' "${GEMINI_MODEL:-}" 'GEMINI_MODEL should default'
assert_eq '5432' "${DSQL_PORT:-}" 'DSQL_PORT should default'
assert_eq 'postgres' "${DSQL_DB:-}" 'DSQL_DB should default'
assert_eq 'admin' "${DSQL_USER:-}" 'DSQL_USER should default'
assert_eq 'ltbase' "${DSQL_PROJECT_SCHEMA:-}" 'DSQL_PROJECT_SCHEMA should default'

# ---------- per-stack defaults derived when unset ----------

assert_eq 'ltbase-deploy-devo' "${AWS_ROLE_NAME_DEVO:-}" 'AWS_ROLE_NAME_DEVO should default to ltbase-deploy-devo'
assert_eq 'arn:aws:iam::123456789012:role/ltbase-deploy-devo' "${AWS_ROLE_ARN_DEVO:-}" 'AWS_ROLE_ARN_DEVO should derive from default role name'
assert_eq 'infra/auth-providers.devo.json' "${AUTH_PROVIDER_CONFIG_FILE_DEVO:-}" 'AUTH_PROVIDER_CONFIG_FILE_DEVO should default'

# ---------- explicit values win over defaults ----------

# Derived exports persist in this shell across loads; clear the ones this case
# re-derives so we exercise a fresh derivation from the override file.
unset AWS_ROLE_ARN_DEVO AWS_ROLE_NAME_DEVO PULUMI_KMS_ALIAS GEMINI_MODEL

override_env="${temp_dir}/override-env"
cat >"${override_env}" <<'ENVEOF'
STACKS=devo
PROMOTION_PATH=devo
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
PULUMI_STATE_BUCKET=test-bucket
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=custom-role
PULUMI_KMS_ALIAS=alias/custom
GEMINI_MODEL=gemini-custom
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
ENVEOF

bootstrap_env_load "${override_env}"

assert_eq 'custom-role' "${AWS_ROLE_NAME_DEVO:-}" 'explicit AWS_ROLE_NAME_DEVO should win'
assert_eq 'arn:aws:iam::123456789012:role/custom-role' "${AWS_ROLE_ARN_DEVO:-}" 'AWS_ROLE_ARN_DEVO should use explicit role name'
assert_eq 'alias/custom' "${PULUMI_KMS_ALIAS:-}" 'explicit PULUMI_KMS_ALIAS should win'
assert_eq 'gemini-custom' "${GEMINI_MODEL:-}" 'explicit GEMINI_MODEL should win'

# ---------- caller ARN to IAM role ARN conversion ----------

assert_eq 'arn:aws:iam::210987654321:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_Admin_abc123' \
  "$(bootstrap_env_iam_role_arn_from_caller_arn 'arn:aws:sts::210987654321:assumed-role/AWSReservedSSO_Admin_abc123/alice' 'us-west-2')" \
  'SSO assumed-role should map to reserved SSO role path'
assert_eq 'arn:aws:iam::111111111111:role/MyRole' \
  "$(bootstrap_env_iam_role_arn_from_caller_arn 'arn:aws:sts::111111111111:assumed-role/MyRole/session' '')" \
  'plain assumed-role should drop session'
assert_eq 'arn:aws:iam::111111111111:role/Foo' \
  "$(bootstrap_env_iam_role_arn_from_caller_arn 'arn:aws:iam::111111111111:role/Foo' '')" \
  'iam role ARN should pass through'
assert_eq '' \
  "$(bootstrap_env_iam_role_arn_from_caller_arn 'arn:aws:iam::111111111111:user/bob' '')" \
  'iam user ARN should yield empty'
assert_eq '' \
  "$(bootstrap_env_iam_role_arn_from_caller_arn 'arn:aws:sts::210987654321:assumed-role/AWSReservedSSO_Admin_abc123/alice' '')" \
  'SSO assumed-role with unknown sso_region must yield empty, never the plain role form'

# ---------- SSO region resolution for a profile ----------

fake_bin="${temp_dir}/bin"
mkdir -p "${fake_bin}"
cat >"${fake_bin}/aws" <<'FAKEEOF'
#!/usr/bin/env bash
case "$*" in
  *"configure get sso_region"*)
    if [[ -n "${FAKE_SSO_REGION:-}" ]]; then printf '%s\n' "${FAKE_SSO_REGION}"; exit 0; fi
    exit 1
    ;;
  *"configure get sso_session"*)
    if [[ -n "${FAKE_SSO_SESSION:-}" ]]; then printf '%s\n' "${FAKE_SSO_SESSION}"; exit 0; fi
    exit 1
    ;;
  *"sts get-caller-identity"*)
    if [[ -n "${FAKE_CALLER_ARN:-}" ]]; then printf '%s\n' "${FAKE_CALLER_ARN}"; exit 0; fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
FAKEEOF
chmod +x "${fake_bin}/aws"

aws_config_file="${temp_dir}/aws-config"
cat >"${aws_config_file}" <<'CONFEOF'
[profile session-profile]
sso_session = test-session

[sso-session test-session]
sso_region = eu-west-1
sso_start_url = https://example.awsapps.com/start
CONFEOF

assert_eq 'us-west-2' \
  "$(PATH="${fake_bin}:${PATH}" FAKE_SSO_REGION=us-west-2 bootstrap_env_sso_region_for_profile legacy-profile)" \
  'legacy profile-level sso_region should win'
assert_eq 'eu-west-1' \
  "$(PATH="${fake_bin}:${PATH}" FAKE_SSO_SESSION=test-session AWS_CONFIG_FILE="${aws_config_file}" bootstrap_env_sso_region_for_profile session-profile)" \
  'sso-session config section should provide the region when the profile lacks sso_region'
assert_eq '' \
  "$(PATH="${fake_bin}:${PATH}" bootstrap_env_sso_region_for_profile unknown-profile)" \
  'unresolvable profile should yield empty without failing'

# ---------- backend principal derivation from AWS_PROFILE_<STACK> ----------

sso_caller_arn='arn:aws:sts::123456789012:assumed-role/AWSReservedSSO_Admin_abc123/alice'
AWS_PROFILE_DEVO='fake-profile'

unset PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS
: >"${stdout_file}"
: >"${stderr_file}"
PATH="${fake_bin}:${PATH}" FAKE_CALLER_ARN="${sso_caller_arn}" FAKE_SSO_REGION=us-west-2 \
  bootstrap_env_derive_backend_principals_from_profiles >"${stdout_file}" 2>"${stderr_file}"
assert_eq 'arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_Admin_abc123' \
  "${PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS:-}" \
  'derivation should append the reserved SSO role ARN'
if ! grep -q 'Derived Pulumi backend principal for stack devo' "${stdout_file}"; then
  fail 'derivation should log the derived principal'
fi

unset PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS
: >"${stderr_file}"
PATH="${fake_bin}:${PATH}" FAKE_CALLER_ARN="${sso_caller_arn}" \
  bootstrap_env_derive_backend_principals_from_profiles >/dev/null 2>"${stderr_file}"
assert_eq '' "${PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS:-}" \
  'SSO caller with unresolvable region must be skipped, not added in the malformed plain form'
if ! grep -q '\[warn\].*PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS' "${stderr_file}"; then
  fail 'skipped SSO caller should warn about the manual fallback'
fi

unset AWS_PROFILE_DEVO

# ---------- CSV splitting must not glob-expand entries ----------

glob_probe="$(cd "${temp_dir}" && bootstrap_env_each_stack '*')"
assert_eq '*' "${glob_probe}" 'bootstrap_env_each_stack should not glob-expand entries'

glob_json="$(cd "${temp_dir}" && PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS='*' STACKS=devo bootstrap_env_pulumi_backend_principal_arns_json)"
if [[ "${glob_json}" != *'"*"'* ]]; then
  fail "principal ARNs JSON should keep a literal * entry, got [${glob_json}]"
fi

printf 'PASS: bootstrap-env tests\n'
