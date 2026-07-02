#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTION_PATH="${ROOT_DIR}/.github/actions/publish-oidc-discovery/action.yml"

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
  if ! grep -Fq -- "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
  if grep -Fq -- "${needle}" "${path}"; then
    fail "expected ${path} to not contain: ${needle}"
  fi
}

# ---------- composite action shape ----------

assert_file_contains "${ACTION_PATH}" "using: composite"

# ---------- inputs ----------

for input in target_stacks target_stack oidc_discovery_domain \
  oidc_discovery_stack_config oidc_discovery_pages_project \
  cloudflare_account_id cloudflare_api_token allow_placeholder wait_for; do
  assert_file_contains "${ACTION_PATH}" "${input}:"
done

# ---------- generation via build-discovery.sh with prefix support ----------

assert_file_contains "${ACTION_PATH}" "./scripts/build-discovery.sh"
assert_file_contains "${ACTION_PATH}" "TARGET_STACKS: \${{ inputs.target_stacks }}"
assert_file_contains "${ACTION_PATH}" "TARGET_STACK: \${{ inputs.target_stack }}"

# ---------- placeholder fallback is opt-in and defaults off ----------

assert_file_contains "${ACTION_PATH}" "ALLOW_PLACEHOLDER: \${{ inputs.allow_placeholder }}"

# ---------- Cloudflare Pages direct upload ----------

assert_file_contains "${ACTION_PATH}" "cloudflare/wrangler-action@v3"
assert_file_contains "${ACTION_PATH}" "pages deploy"
assert_file_contains "${ACTION_PATH}" "--branch main"

# Composite runs.steps do not support timeout-minutes; its presence fails the
# whole action at load time.
assert_file_not_contains "${ACTION_PATH}" "timeout-minutes:"

# ---------- readiness poll gated on wait_for mode ----------

assert_file_contains "${ACTION_PATH}" "if: \${{ inputs.wait_for != 'none' }}"

# reachable: openid-configuration is served and well-formed.
assert_file_contains "${ACTION_PATH}" 'doc_path=".well-known/openid-configuration"'
assert_file_contains "${ACTION_PATH}" "jq_check='.issuer'"

# real-jwks: jwks.json no longer serves the pre-rollout placeholder key.
assert_file_contains "${ACTION_PATH}" 'doc_path=".well-known/jwks.json"'
assert_file_contains "${ACTION_PATH}" 'all(.kid != "placeholder")'

printf 'PASS: publish-oidc-discovery-action tests\n'
