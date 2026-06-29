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

# ---------- checkout and generate step ----------

assert_file_contains "${WORKFLOW_PATH}" "actions/checkout@v6"

assert_file_contains "${WORKFLOW_PATH}" "./scripts/build-discovery.sh"

# ---------- removed template checkout dependencies ----------

assert_file_not_contains "${WORKFLOW_PATH}" "OIDC_DISCOVERY_TEMPLATE_REPO"
assert_file_not_contains "${WORKFLOW_PATH}" "OIDC_DISCOVERY_TEMPLATE_REF"
assert_file_not_contains "${WORKFLOW_PATH}" "path: oidc-template"
assert_file_not_contains "${WORKFLOW_PATH}" "working-directory: oidc-template"

# ---------- target stack support ----------

assert_file_contains "${WORKFLOW_PATH}" 'default: "all"'
assert_file_contains "${WORKFLOW_PATH}" "TARGET_STACK: \${{ inputs.target_stack }}"

# ---------- Cloudflare Pages direct upload ----------

assert_file_contains "${WORKFLOW_PATH}" "cloudflare/wrangler-action@v3"
assert_file_contains "${WORKFLOW_PATH}" "pages deploy"

printf 'PASS: publish-oidc-discovery-workflow tests\n'
