#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_PATH="${ROOT_DIR}/.github/workflows/publish-oidc-discovery.yml"

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

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
  if grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to not contain: ${needle}"
  fi
}

# ---------- required permissions ----------

assert_file_contains "${WORKFLOW_PATH}" "id-token: write"

# ---------- checkout and delegate to the shared composite action ----------

assert_file_contains "${WORKFLOW_PATH}" "actions/checkout@v6"
assert_file_contains "${WORKFLOW_PATH}" "uses: ./.github/actions/publish-oidc-discovery"

# ---------- removed template checkout dependencies ----------

assert_file_not_contains "${WORKFLOW_PATH}" "OIDC_DISCOVERY_TEMPLATE_REPO"
assert_file_not_contains "${WORKFLOW_PATH}" "OIDC_DISCOVERY_TEMPLATE_REF"
assert_file_not_contains "${WORKFLOW_PATH}" "path: oidc-template"
assert_file_not_contains "${WORKFLOW_PATH}" "working-directory: oidc-template"

# ---------- target stack support (manual recovery keeps the all/single input) ----------

assert_file_contains "${WORKFLOW_PATH}" 'default: "all"'
assert_file_contains "${WORKFLOW_PATH}" "target_stack: \${{ inputs.target_stack }}"
assert_file_contains "${WORKFLOW_PATH}" "target_stacks: \${{ inputs.target_stacks }}"

# ---------- manual recovery: no placeholder opt-in, no readiness poll ----------

assert_file_not_contains "${WORKFLOW_PATH}" "allow_placeholder"
assert_file_contains "${WORKFLOW_PATH}" "wait_for: none"

# ---------- serialized with the rollout-hop publish jobs ----------

assert_file_contains "${WORKFLOW_PATH}" "group: \${{ github.repository }}-oidc-discovery-publish"
assert_file_contains "${WORKFLOW_PATH}" "cancel-in-progress: false"

# ---------- inputs wired to repo vars/secrets ----------

assert_file_contains "${WORKFLOW_PATH}" "oidc_discovery_domain: \${{ vars.OIDC_DISCOVERY_DOMAIN }}"
assert_file_contains "${WORKFLOW_PATH}" "oidc_discovery_stack_config: \${{ vars.OIDC_DISCOVERY_STACK_CONFIG }}"
assert_file_contains "${WORKFLOW_PATH}" "oidc_discovery_pages_project: \${{ vars.OIDC_DISCOVERY_PAGES_PROJECT }}"
assert_file_contains "${WORKFLOW_PATH}" "cloudflare_api_token: \${{ secrets.CLOUDFLARE_API_TOKEN }}"

printf 'PASS: publish-oidc-discovery-workflow tests\n'
