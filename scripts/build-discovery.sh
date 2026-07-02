#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
#   OIDC_DISCOVERY_DOMAIN        – custom domain for discovery documents
#   OIDC_DISCOVERY_STACK_CONFIG  – JSON mapping stack name -> {aws_region, aws_role_arn, kms_auth_key_alias}
#   OIDC_DISCOVERY_OUTPUT_DIR    – directory to write generated files into
# Optional:
#   TARGET_STACKS                – CSV of stack names (e.g. "devo,prod"). Takes
#                                  precedence over TARGET_STACK when set. Used to
#                                  publish a promotion-path prefix in one run.
#   TARGET_STACK                 – "all" (default) or a specific stack name.
#                                  Ignored when TARGET_STACKS is set.
#
# When a stack's authservice signing KMS key does not exist yet (the alias
# returns NotFoundException), this script publishes a PLACEHOLDER JWKS backed by
# an ephemeral throwaway RSA key instead of failing. This keeps the discovery
# endpoint valid so API Gateway can create its JWT authorizer during the stack's
# first rollout; the real KMS-backed key is published afterward.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATE_JWKS="${SCRIPT_DIR}/generate-jwks.py"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

# Generate an ephemeral throwaway RSA public key as base64-encoded DER
# SubjectPublicKeyInfo. Used as a PLACEHOLDER when a stack's KMS signing key
# does not exist yet. The private key is discarded, so the placeholder cannot be
# used to mint tokens; it exists only to keep the discovery endpoint well-formed
# until the real KMS-backed key is published after rollout.
generate_placeholder_public_key_b64() {
  command -v openssl >/dev/null 2>&1 || fail "openssl is required to generate a placeholder discovery key"
  local der_b64
  der_b64="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null \
    | openssl pkey -pubout -outform DER 2>/dev/null \
    | base64 \
    | tr -d '\n')" || fail "Failed to generate placeholder RSA key with openssl"
  [[ -n "${der_b64}" ]] || fail "Placeholder RSA key generation produced no output"
  printf '%s' "${der_b64}"
}

# --- validate required vars ---

[[ -n "${OIDC_DISCOVERY_DOMAIN:-}" ]]       || fail "OIDC_DISCOVERY_DOMAIN is not set"
[[ -n "${OIDC_DISCOVERY_STACK_CONFIG:-}" ]] || fail "OIDC_DISCOVERY_STACK_CONFIG is not set"
[[ -n "${OIDC_DISCOVERY_OUTPUT_DIR:-}" ]]   || fail "OIDC_DISCOVERY_OUTPUT_DIR is not set"

if ! echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -e 'type == "object"' >/dev/null 2>&1; then
  fail "OIDC_DISCOVERY_STACK_CONFIG must be a valid JSON object"
fi

TARGET_STACK="${TARGET_STACK:-all}"
TARGET_STACKS="${TARGET_STACKS:-}"

# --- determine stacks ---

if [[ -n "${TARGET_STACKS}" ]]; then
  # CSV selection (promotion-path prefix). Takes precedence over TARGET_STACK.
  stacks=()
  IFS=',' read -r -a target_stacks_list <<<"${TARGET_STACKS}"
  for raw_stack in "${target_stacks_list[@]}"; do
    stack="${raw_stack//[[:space:]]/}"
    [[ -n "${stack}" ]] || continue
    if ! echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -e --arg s "${stack}" '.[$s]' >/dev/null 2>&1; then
      fail "Stack '${stack}' not found in OIDC_DISCOVERY_STACK_CONFIG"
    fi
    stacks+=("${stack}")
  done
  if [[ "${#stacks[@]}" -eq 0 ]]; then
    fail "TARGET_STACKS did not resolve to any stack names"
  fi
elif [[ "${TARGET_STACK}" == "all" ]]; then
  stacks=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    stacks+=("${line}")
  done < <(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r 'keys[]')
else
  if ! echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -e --arg s "${TARGET_STACK}" '.[$s]' >/dev/null 2>&1; then
    fail "Stack '${TARGET_STACK}' not found in OIDC_DISCOVERY_STACK_CONFIG"
  fi
  stacks=("${TARGET_STACK}")
fi

for stack in "${stacks[@]}"; do
  if [[ ! "${stack}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    fail "Invalid stack name '${stack}' in OIDC_DISCOVERY_STACK_CONFIG"
  fi
done

# --- generate per-stack documents ---
#
# This script is generation-only: it writes the configured stacks into a fresh
# output dir. Reconciling repo state (pruning stacks that are no longer
# configured) is the publishing workflow's responsibility, since only the
# workflow has the committed repo to compare against.

mkdir -p "${OIDC_DISCOVERY_OUTPUT_DIR}"

current_stack_manifest="$(mktemp)"
trap 'rm -f "${current_stack_manifest}"' EXIT

for stack in "${stacks[@]}"; do
  echo "Generating discovery documents for ${stack}"

  aws_region=$(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r --arg s "${stack}" '.[$s].aws_region')
  aws_role_arn=$(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r --arg s "${stack}" '.[$s].aws_role_arn')
  kms_alias=$(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r --arg s "${stack}" '.[$s].kms_auth_key_alias')

  # Each missing JSON key yields the literal string "null" from jq -r; reject it
  # before it flows into AWS calls as a bogus --role-arn / --key-id argument.
  [[ -n "${aws_region}" && "${aws_region}" != "null" ]] \
    || fail "Stack '${stack}' is missing required field 'aws_region' in OIDC_DISCOVERY_STACK_CONFIG"
  [[ -n "${aws_role_arn}" && "${aws_role_arn}" != "null" ]] \
    || fail "Stack '${stack}' is missing required field 'aws_role_arn' in OIDC_DISCOVERY_STACK_CONFIG"
  [[ -n "${kms_alias}" && "${kms_alias}" != "null" ]] \
    || fail "Stack '${stack}' is missing required field 'kms_auth_key_alias' in OIDC_DISCOVERY_STACK_CONFIG"

  # Obtain a fresh GitHub OIDC token and assume the stack IAM role.
  oidc_token_response=$(curl -sS -f \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com") || fail "Failed to obtain GitHub OIDC token"

  oidc_token=$(echo "${oidc_token_response}" | jq -r '.value')
  if [[ -z "${oidc_token}" || "${oidc_token}" == "null" ]]; then
    fail "GitHub OIDC token value is empty"
  fi

  creds=$(AWS_DEFAULT_REGION="${aws_region}" aws sts assume-role-with-web-identity \
    --role-arn "${aws_role_arn}" \
    --role-session-name "oidc-discovery-${stack}" \
    --web-identity-token "${oidc_token}" \
    --duration-seconds 900 \
    --output json) || fail "Failed to assume role ${aws_role_arn}"

  # Split assignment from export so set -e catches a failed jq.
  AWS_ACCESS_KEY_ID=$(echo "${creds}" | jq -r '.Credentials.AccessKeyId'); export AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.Credentials.SecretAccessKey'); export AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN=$(echo "${creds}" | jq -r '.Credentials.SessionToken'); export AWS_SESSION_TOKEN
  export AWS_DEFAULT_REGION="${aws_region}"

  # Fetch the RSA public key from KMS. When the signing key does not exist yet
  # (NotFoundException), fall back to a PLACEHOLDER key so the discovery endpoint
  # stays valid for API Gateway authorizer creation during the first rollout.
  kms_stderr="$(mktemp)"
  if public_key_json=$(aws kms get-public-key --key-id "${kms_alias}" --output json 2>"${kms_stderr}"); then
    rm -f "${kms_stderr}"
    public_key_b64=$(echo "${public_key_json}" | jq -r '.PublicKey')
    key_id=$(echo "${public_key_json}" | jq -r '.KeyId')

    if [[ -z "${public_key_b64}" || "${public_key_b64}" == "null" ]]; then
      fail "KMS get-public-key returned no PublicKey for ${kms_alias}"
    fi
    if [[ -z "${key_id}" || "${key_id}" == "null" ]]; then
      fail "KMS get-public-key returned no KeyId for ${kms_alias}"
    fi
  else
    kms_error="$(<"${kms_stderr}")"
    rm -f "${kms_stderr}"
    if [[ "${kms_error}" == *"NotFoundException"* ]]; then
      echo "WARNING: KMS key ${kms_alias} not found for ${stack}; publishing PLACEHOLDER JWKS (replaced after rollout)" >&2
      public_key_b64="$(generate_placeholder_public_key_b64)"
      key_id="placeholder"
    else
      [[ -n "${kms_error}" ]] && printf '%s\n' "${kms_error}" >&2
      fail "Failed to get KMS public key for ${kms_alias}"
    fi
  fi

  # Generate JWKS.
  mkdir -p "${OIDC_DISCOVERY_OUTPUT_DIR}/${stack}/.well-known"
  python3 "${GENERATE_JWKS}" \
    --public-key-b64 "${public_key_b64}" \
    --key-id "${key_id}" \
    > "${OIDC_DISCOVERY_OUTPUT_DIR}/${stack}/.well-known/jwks.json"

  # Generate openid-configuration.
  python3 -c "
import json, sys
domain = sys.argv[1]
stack = sys.argv[2]
print(json.dumps({
    'issuer': f'https://{domain}/{stack}',
    'jwks_uri': f'https://{domain}/{stack}/.well-known/jwks.json',
    'response_types_supported': ['id_token'],
    'subject_types_supported': ['public'],
    'id_token_signing_alg_values_supported': ['RS256'],
}, indent=2))" "${OIDC_DISCOVERY_DOMAIN}" "${stack}" \
    > "${OIDC_DISCOVERY_OUTPUT_DIR}/${stack}/.well-known/openid-configuration"

  echo "Published: ${stack}/.well-known/jwks.json"
  echo "Published: ${stack}/.well-known/openid-configuration"

  printf '%s\n' "${stack}" >> "${current_stack_manifest}"

  # Clear per-stack credentials.
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION
done

# --- generate _headers ---

headers_file="${OIDC_DISCOVERY_OUTPUT_DIR}/_headers"
: > "${headers_file}"

while IFS= read -r stack; do
  [[ -n "${stack}" ]] || continue
  printf '/%s/.well-known/openid-configuration\n  Content-Type: application/json; charset=utf-8\n\n/%s/.well-known/jwks.json\n  Content-Type: application/json; charset=utf-8\n\n' \
    "${stack}" "${stack}" >> "${headers_file}"
done < "${current_stack_manifest}"
