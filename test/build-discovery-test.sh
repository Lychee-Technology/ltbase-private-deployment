#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/scripts/build-discovery.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_dir_contains() {
  local dir="$1"
  local path="$2"
  if [[ ! -e "${dir}/${path}" ]]; then
    fail "expected ${dir}/${path} to exist"
  fi
}

assert_dir_not_contains() {
  local dir="$1"
  local path="$2"
  if [[ -e "${dir}/${path}" ]]; then
    fail "expected ${dir}/${path} to not exist"
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

fake_bin="${temp_dir}/bin"
mkdir -p "${fake_bin}"

# --- fake KMS public key (DER-encoded RSA, generated below) ---
kms_public_key_b64="$(python3 -c '
import base64, struct

# Build a minimal valid DER RSA SubjectPublicKeyInfo by hand.
# SPKI ::= SEQUENCE { AlgorithmIdentifier, BIT STRING { SEQUENCE { INTEGER n, INTEGER e } } }
def der_length(length):
    if length < 0x80:
        return bytes([length])
    elif length < 0x100:
        return bytes([0x81, length])
    else:
        return bytes([0x82, (length >> 8) & 0xFF, length & 0xFF])

# RSA OID 1.2.840.113549.1.1.1 = 2A 86 48 86 F7 0D 01 01 01
rsa_oid = bytes([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
# AlgorithmIdentifier ::= SEQUENCE { OID rsaEncryption, NULL }
null_bytes = bytes([0x05, 0x00])
algo_id_inner = rsa_oid + null_bytes
algo_id = b"\x30" + der_length(len(algo_id_inner)) + algo_id_inner

# RSA public key ::= SEQUENCE { INTEGER modulus, INTEGER exponent }
modulus = bytes(range(256))     # 256-byte fake modulus
exponent = b"\x01\x00\x01"       # 65537

def der_integer(value):
    if value[0] & 0x80:
        value = b"\x00" + value
    return b"\x02" + der_length(len(value)) + value

rsa_key_inner = der_integer(modulus) + der_integer(exponent)
rsa_key = b"\x30" + der_length(len(rsa_key_inner)) + rsa_key_inner

# BIT STRING wrapping RSA key (with 0 unused bits header)
bit_string = b"\x03" + der_length(len(rsa_key) + 1) + b"\x00" + rsa_key

# Full SPKI
spki_inner = algo_id + bit_string
spki = b"\x30" + der_length(len(spki_inner)) + spki_inner

print(base64.b64encode(spki).decode())
')"

# --- fake aws ---
cat >"${fake_bin}/aws" <<'AWSEOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == "kms get-public-key" ]]; then
  printf '{"KeyId":"arn:aws:kms:us-east-1:123456789012:key/test-key-00001","PublicKey":"%s"}\n' "${KMS_PUBLIC_KEY_B64:-}"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "sts assume-role-with-web-identity" ]]; then
  cat <<'EOF'
{"Credentials":{"AccessKeyId":"AKIAIOSFODNN7EXAMPLE","SecretAccessKey":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY","SessionToken":"FQoGZXIvYXdzE..."}}
EOF
  exit 0
fi
printf 'aws unexpected: %s\n' "$*" >&2
exit 1
AWSEOF
chmod +x "${fake_bin}/aws"

# --- fake curl ---
cat >"${fake_bin}/curl" <<'CURLEOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"value":"fake-oidc-token"}\n'
exit 0
CURLEOF
chmod +x "${fake_bin}/curl"

# --- test stack config ---
stack_config='{"devo":{"aws_region":"us-east-1","aws_role_arn":"arn:aws:iam::123456789012:role/ltbase-oidc-devo","kms_auth_key_alias":"alias/ltbase-devo-auth"},"prod":{"aws_region":"us-west-2","aws_role_arn":"arn:aws:iam::210987654321:role/ltbase-oidc-prod","kms_auth_key_alias":"alias/ltbase-prod-auth"}}'

run_build() {
  local output_dir="$1"
  local target_stack="${2:-all}"
  local domain="${3:-oidc.example.com}"

  PATH="${fake_bin}:$PATH" \
    KMS_PUBLIC_KEY_B64="${kms_public_key_b64}" \
    OIDC_DISCOVERY_DOMAIN="${domain}" \
    OIDC_DISCOVERY_STACK_CONFIG="${stack_config}" \
    OIDC_DISCOVERY_OUTPUT_DIR="${output_dir}" \
    TARGET_STACK="${target_stack}" \
    ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-github-token" \
    ACTIONS_ID_TOKEN_REQUEST_URL="https://pipelines.actions.githubusercontent.com/abcdef/" \
    "${BUILD_SCRIPT}" >/dev/null 2>&1
}

# ---------- Test 1: all stacks ----------

output_dir="${temp_dir}/all-stacks"
mkdir -p "${output_dir}"
if ! run_build "${output_dir}" "all"; then
  fail "expected build with all stacks to succeed"
fi

for stack in devo prod; do
  assert_dir_contains "${output_dir}" "${stack}/.well-known/jwks.json"
  assert_dir_contains "${output_dir}" "${stack}/.well-known/openid-configuration"
done

assert_dir_contains "${output_dir}" "_headers"

# ---------- Test 2: single stack ----------

output_dir="${temp_dir}/single-stack"
mkdir -p "${output_dir}"
if ! run_build "${output_dir}" "devo"; then
  fail "expected build with single stack to succeed"
fi

assert_dir_contains "${output_dir}" "devo/.well-known/jwks.json"
assert_dir_contains "${output_dir}" "devo/.well-known/openid-configuration"
assert_dir_not_contains "${output_dir}" "prod"

# ---------- Test 3: generation-only (does not prune unrelated content) ----------
# The script is generation-only; pruning stale stacks is the workflow's job.
# A pre-existing dir not in the config must be left untouched.

output_dir="${temp_dir}/generation-only"
mkdir -p "${output_dir}"
mkdir -p "${output_dir}/stale/.well-known"
: > "${output_dir}/stale/.well-known/jwks.json"
: > "${output_dir}/stale/.well-known/openid-configuration"

if ! run_build "${output_dir}" "all"; then
  fail "expected build to succeed"
fi

assert_dir_contains "${output_dir}" "stale/.well-known/jwks.json"
assert_dir_contains "${output_dir}" "devo/.well-known/jwks.json"
assert_dir_contains "${output_dir}" "prod/.well-known/jwks.json"

# ---------- Test 4: missing required env vars ----------

if OIDC_DISCOVERY_OUTPUT_DIR="${temp_dir}/no-domain" \
   KMS_PUBLIC_KEY_B64="${kms_public_key_b64}" \
   PATH="${fake_bin}:$PATH" \
   "${BUILD_SCRIPT}" 2>/dev/null; then
  fail "expected failure when OIDC_DISCOVERY_DOMAIN is missing"
fi

# ---------- Test 5: invalid JSON config ----------

output_dir="${temp_dir}/bad-config"
mkdir -p "${output_dir}"
if KMS_PUBLIC_KEY_B64="${kms_public_key_b64}" \
   OIDC_DISCOVERY_DOMAIN="oidc.example.com" \
   OIDC_DISCOVERY_STACK_CONFIG="not-json" \
   OIDC_DISCOVERY_OUTPUT_DIR="${output_dir}" \
   ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-github-token" \
   ACTIONS_ID_TOKEN_REQUEST_URL="https://pipelines.actions.githubusercontent.com/abcdef/" \
   PATH="${fake_bin}:$PATH" \
   "${BUILD_SCRIPT}" 2>/dev/null; then
  fail "expected failure with invalid JSON config"
fi

# ---------- Test 6: unknown target stack ----------

output_dir="${temp_dir}/bad-target"
mkdir -p "${output_dir}"
if KMS_PUBLIC_KEY_B64="${kms_public_key_b64}" \
   OIDC_DISCOVERY_DOMAIN="oidc.example.com" \
   OIDC_DISCOVERY_STACK_CONFIG="${stack_config}" \
   OIDC_DISCOVERY_OUTPUT_DIR="${output_dir}" \
   TARGET_STACK="nonexistent" \
   ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-github-token" \
   ACTIONS_ID_TOKEN_REQUEST_URL="https://pipelines.actions.githubusercontent.com/abcdef/" \
   PATH="${fake_bin}:$PATH" \
   "${BUILD_SCRIPT}" 2>/dev/null; then
  fail "expected failure with unknown target stack"
fi

# ---------- Test 6b: stack config missing a required inner field ----------

output_dir="${temp_dir}/missing-field"
mkdir -p "${output_dir}"
missing_field_config='{"devo":{"aws_region":"us-east-1","kms_auth_key_alias":"alias/ltbase-devo-auth"}}'
if KMS_PUBLIC_KEY_B64="${kms_public_key_b64}" \
   OIDC_DISCOVERY_DOMAIN="oidc.example.com" \
   OIDC_DISCOVERY_STACK_CONFIG="${missing_field_config}" \
   OIDC_DISCOVERY_OUTPUT_DIR="${output_dir}" \
   ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-github-token" \
   ACTIONS_ID_TOKEN_REQUEST_URL="https://pipelines.actions.githubusercontent.com/abcdef/" \
   PATH="${fake_bin}:$PATH" \
   "${BUILD_SCRIPT}" 2>/dev/null; then
  fail "expected failure when a stack config entry omits a required field"
fi

# ---------- Test 6c: empty KMS public key ----------
# The fake aws echoes KMS_PUBLIC_KEY_B64 into PublicKey; an empty value must be
# rejected rather than passed on to generate-jwks.py.

output_dir="${temp_dir}/empty-kms-key"
mkdir -p "${output_dir}"
if KMS_PUBLIC_KEY_B64="" \
   OIDC_DISCOVERY_DOMAIN="oidc.example.com" \
   OIDC_DISCOVERY_STACK_CONFIG="${stack_config}" \
   OIDC_DISCOVERY_OUTPUT_DIR="${output_dir}" \
   TARGET_STACK="devo" \
   ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-github-token" \
   ACTIONS_ID_TOKEN_REQUEST_URL="https://pipelines.actions.githubusercontent.com/abcdef/" \
   PATH="${fake_bin}:$PATH" \
   "${BUILD_SCRIPT}" 2>/dev/null; then
  fail "expected failure when KMS returns an empty PublicKey"
fi

# ---------- Test 7: openid-configuration content ----------

output_dir="${temp_dir}/config-content"
mkdir -p "${output_dir}"
run_build "${output_dir}" "devo" "oidc.example.com"

openid_config="${output_dir}/devo/.well-known/openid-configuration"
actual_issuer="$(python3 -c "import json; print(json.load(open('${openid_config}'))['issuer'])")"
expected_issuer="https://oidc.example.com/devo"
if [[ "${actual_issuer}" != "${expected_issuer}" ]]; then
  fail "expected issuer ${expected_issuer}, got ${actual_issuer}"
fi

# ---------- Test 8: _headers content ----------

output_dir="${temp_dir}/headers-content"
mkdir -p "${output_dir}"
run_build "${output_dir}" "devo" "oidc.example.com"

if ! grep -q '/devo/.well-known/openid-configuration' "${output_dir}/_headers"; then
  fail "missing devo openid-configuration header entry"
fi
if ! grep -q 'Content-Type: application/json' "${output_dir}/_headers"; then
  fail "missing Content-Type header in _headers"
fi

printf 'PASS: build-discovery tests\n'
