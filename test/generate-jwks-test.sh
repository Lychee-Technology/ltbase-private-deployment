#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATE_SCRIPT="${SCRIPT_DIR}/scripts/generate-jwks.py"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

# --- Setup: generate a test RSA key pair with openssl ---

openssl genrsa -out "${temp_dir}/private.pem" 2048 2>/dev/null
openssl rsa -in "${temp_dir}/private.pem" -pubout -outform DER \
  -out "${temp_dir}/public.der" 2>/dev/null

# Extract expected modulus (uppercase hex, no prefix) via openssl
expected_modulus_hex="$(openssl rsa -in "${temp_dir}/private.pem" \
  -pubout -outform DER 2>/dev/null \
  | openssl rsa -pubin -inform DER -modulus -noout 2>/dev/null \
  | sed 's/Modulus=//')"

# Base64-encode the DER key (single line, portable across macOS/Linux)
public_key_b64="$(base64 < "${temp_dir}/public.der" | tr -d '\n')"

test_key_id="arn:aws:kms:us-west-2:123456789012:key/test-key-id-00001"

# --- Test 1: output is valid JSON ---

if ! output="$(python3 "${GENERATE_SCRIPT}" \
    --public-key-b64 "${public_key_b64}" \
    --key-id "${test_key_id}" 2>&1)"; then
  fail "generate-jwks.py exited non-zero: ${output}"
fi

if ! printf '%s' "${output}" | python3 -m json.tool >/dev/null 2>&1; then
  fail "output is not valid JSON: ${output}"
fi

# --- Test 2: required JWKS fields present with correct values ---

expected_kid="${test_key_id##*/key/}"

if ! python3 - "${expected_kid}" "${expected_modulus_hex}" <<'PYEOF' <<<"${output}"
import json, sys, base64

jwks = json.load(sys.stdin)
expected_kid = sys.argv[1]
expected_hex = sys.argv[2]

assert "keys" in jwks, "missing 'keys'"
assert len(jwks["keys"]) == 1, f"expected 1 key, got {len(jwks['keys'])}"

k = jwks["keys"][0]

assert k["kty"] == "RSA", f"kty={k['kty']}"
assert k["alg"] == "RS256", f"alg={k['alg']}"
assert k["use"] == "sig", f"use={k['use']}"
assert k["kid"] == expected_kid, f"kid={k['kid']}"

for field in ("n", "e"):
    v = k[field]
    assert "=" not in v, f"{field} has base64 padding"
    assert "+" not in v, f"{field} has + (not url-safe)"
    assert "/" not in v, f"{field} has / (not url-safe)"

# Round-trip: decode n and verify modulus matches openssl output
n_padded = k["n"] + "=" * (-len(k["n"]) % 4)
n_bytes = base64.urlsafe_b64decode(n_padded)
n_hex = n_bytes.hex().upper()
assert n_hex == expected_hex.upper(), (
    f"modulus mismatch:\n  got:      {n_hex[:40]}...\n  expected: {expected_hex[:40]}..."
)
PYEOF
then
  fail "field validation failed"
fi

# --- Test 3: different key produces different output ---

openssl genrsa -out "${temp_dir}/private2.pem" 2048 2>/dev/null
openssl rsa -in "${temp_dir}/private2.pem" -pubout -outform DER \
  -out "${temp_dir}/public2.der" 2>/dev/null
public_key_b64_2="$(base64 < "${temp_dir}/public2.der" | tr -d '\n')"

output2="$(python3 "${GENERATE_SCRIPT}" \
  --public-key-b64 "${public_key_b64_2}" \
  --key-id "other-key-id")"

n1="$(printf '%s' "${output}" | python3 -c "import json,sys; print(json.load(sys.stdin)['keys'][0]['n'])")"
n2="$(printf '%s' "${output2}" | python3 -c "import json,sys; print(json.load(sys.stdin)['keys'][0]['n'])")"

if [[ "${n1}" == "${n2}" ]]; then
  fail "two different keys produced the same modulus"
fi

printf 'PASS: generate-jwks tests\n'
