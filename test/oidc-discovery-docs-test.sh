#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Active operator-facing docs (exclude historical superpowers/ plans and specs).
ALL_DOCS=(
  "${ROOT_DIR}/README.md"
  "${ROOT_DIR}/README.zh.md"
  "${ROOT_DIR}/docs/BOOTSTRAP.md"
  "${ROOT_DIR}/docs/BOOTSTRAP.zh.md"
  "${ROOT_DIR}/docs/CUSTOMER_ONBOARDING.md"
  "${ROOT_DIR}/docs/CUSTOMER_ONBOARDING.zh.md"
  "${ROOT_DIR}/docs/onboarding/01-prerequisites.md"
  "${ROOT_DIR}/docs/onboarding/01-prerequisites.zh.md"
  "${ROOT_DIR}/docs/onboarding/02-create-repo-and-clone.md"
  "${ROOT_DIR}/docs/onboarding/02-create-repo-and-clone.zh.md"
  "${ROOT_DIR}/docs/onboarding/03-create-oidc-and-deploy-roles.md"
  "${ROOT_DIR}/docs/onboarding/03-create-oidc-and-deploy-roles.zh.md"
  "${ROOT_DIR}/docs/onboarding/04-prepare-env-file.md"
  "${ROOT_DIR}/docs/onboarding/04-prepare-env-file.zh.md"
  "${ROOT_DIR}/docs/onboarding/05-bootstrap-one-click.md"
  "${ROOT_DIR}/docs/onboarding/05-bootstrap-one-click.zh.md"
  "${ROOT_DIR}/docs/onboarding/06-bootstrap-manual.md"
  "${ROOT_DIR}/docs/onboarding/06-bootstrap-manual.zh.md"
  "${ROOT_DIR}/docs/onboarding/07-first-deploy-and-managed-dsql.md"
  "${ROOT_DIR}/docs/onboarding/07-first-deploy-and-managed-dsql.zh.md"
  "${ROOT_DIR}/docs/onboarding/08-day-2-operations.md"
  "${ROOT_DIR}/docs/onboarding/08-day-2-operations.zh.md"
)

# Docs that explain OIDC discovery setup (EN only)
EN_OIDC_SETUP_DOCS=(
  "${ROOT_DIR}/README.md"
  "${ROOT_DIR}/docs/onboarding/05-bootstrap-one-click.md"
  "${ROOT_DIR}/docs/onboarding/06-bootstrap-manual.md"
)

# Docs that explain OIDC discovery setup (ZH only)
ZH_OIDC_SETUP_DOCS=(
  "${ROOT_DIR}/README.zh.md"
  "${ROOT_DIR}/docs/onboarding/05-bootstrap-one-click.zh.md"
  "${ROOT_DIR}/docs/onboarding/06-bootstrap-manual.zh.md"
)

# Docs that describe .env fields related to OIDC discovery
ENV_DOCS=(
  "${ROOT_DIR}/docs/onboarding/04-prepare-env-file.md"
  "${ROOT_DIR}/docs/onboarding/04-prepare-env-file.zh.md"
)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_no_match_in() {
  local reason="$1"
  local pattern="$2"
  shift 2
  local docs=("$@")
  for doc in "${docs[@]}"; do
    if grep -niF "${pattern}" "${doc}" >/dev/null 2>&1; then
      fail "${reason}: found in ${doc}: $(grep -niF "${pattern}" "${doc}")"
    fi
  done
}

assert_contains_in() {
  local reason="$1"
  local pattern="$2"
  shift 2
  local docs=("$@")
  for doc in "${docs[@]}"; do
    if ! grep -Fiq "${pattern}" "${doc}"; then
      fail "${reason}: pattern [${pattern}] not found in ${doc}"
    fi
  done
}

# ---------- Forbidden patterns: no active operator doc should mention template-repo dependencies ----------

assert_no_match_in "must not mention OIDC_DISCOVERY_TEMPLATE_REPO" 'OIDC_DISCOVERY_TEMPLATE_REPO' "${ALL_DOCS[@]}"
assert_no_match_in "must not mention OIDC_DISCOVERY_TEMPLATE_REF" 'OIDC_DISCOVERY_TEMPLATE_REF' "${ALL_DOCS[@]}"
assert_no_match_in "must not mention ltbase-oidc-discovery-template" 'ltbase-oidc-discovery-template' "${ALL_DOCS[@]}"
assert_no_match_in "must not mention bootstrap-oidc-discovery-companion" 'bootstrap-oidc-discovery-companion' "${ALL_DOCS[@]}"

# ---------- .env docs: must state template repo variables are not needed ----------

assert_no_match_in ".env docs must not mention OIDC_DISCOVERY_TEMPLATE_REPO" 'OIDC_DISCOVERY_TEMPLATE_REPO' "${ENV_DOCS[@]}"
assert_no_match_in ".env docs must not mention OIDC_DISCOVERY_TEMPLATE_REF" 'OIDC_DISCOVERY_TEMPLATE_REF' "${ENV_DOCS[@]}"

# ---------- English OIDC setup docs: must describe the direct-upload model ----------

assert_contains_in "EN OIDC setup docs must mention direct upload or no companion" 'no companion' "${EN_OIDC_SETUP_DOCS[@]}"
assert_contains_in "EN README must mention publish-oidc-discovery.yml" 'publish-oidc-discovery.yml' "${ROOT_DIR}/README.md"

# ---------- Chinese OIDC setup docs: must describe the direct-upload model ----------

for doc in "${ZH_OIDC_SETUP_DOCS[@]}"; do
  if ! grep -Fiq '直接上传' "${doc}" && ! grep -Fiq '无 companion' "${doc}"; then
    fail "ZH OIDC setup doc must mention direct upload (直接上传) or no companion (无 companion): ${doc}"
  fi
done

assert_contains_in "ZH README must mention publish-oidc-discovery.yml" 'publish-oidc-discovery.yml' "${ROOT_DIR}/README.zh.md"

# ---------- Manual bootstrap: OIDC section must explicitly state no companion repo ----------

assert_contains_in "EN manual bootstrap OIDC section must state direct upload" 'direct upload' "${ROOT_DIR}/docs/onboarding/06-bootstrap-manual.md"
assert_contains_in "ZH manual bootstrap OIDC section must state no companion" '无 companion' "${ROOT_DIR}/docs/onboarding/06-bootstrap-manual.zh.md"

printf 'PASS: oidc-discovery-docs tests\n'
