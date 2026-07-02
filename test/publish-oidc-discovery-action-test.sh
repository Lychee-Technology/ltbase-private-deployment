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

# ---------- composite action shape ----------

assert_file_contains "${ACTION_PATH}" "using: composite"

# ---------- inputs ----------

for input in target_stacks target_stack oidc_discovery_domain \
  oidc_discovery_stack_config oidc_discovery_pages_project \
  cloudflare_account_id cloudflare_api_token allow_placeholder wait_for_ready; do
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

# ---------- readiness poll gated on wait_for_ready ----------

assert_file_contains "${ACTION_PATH}" "if: \${{ inputs.wait_for_ready == 'true' }}"
assert_file_contains "${ACTION_PATH}" "/.well-known/openid-configuration"
assert_file_contains "${ACTION_PATH}" "jq -e '.issuer'"

printf 'PASS: publish-oidc-discovery-action tests\n'
