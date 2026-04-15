#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to not contain: ${needle}"
  fi
}

assert_contains "${ROOT_DIR}/docs/CUSTOMER_ONBOARDING.md" "DSQL_DB=postgres"
assert_contains "${ROOT_DIR}/docs/CUSTOMER_ONBOARDING.md" "DSQL_USER=admin"
assert_not_contains "${ROOT_DIR}/docs/CUSTOMER_ONBOARDING.md" "DSQL_DB=ltbase"
assert_not_contains "${ROOT_DIR}/docs/CUSTOMER_ONBOARDING.md" "DSQL_USER=ltbase"

assert_not_contains "${ROOT_DIR}/infra/README.md" 'injects its derived `DSQL_ENDPOINT`'
assert_contains "${ROOT_DIR}/infra/internal/config/config.go" "DSQLEndpoint"
assert_not_contains "${ROOT_DIR}/infra/cmd/ltbase-infra/main.go" "ctx.Export(\"dsqlEndpoint\""
assert_contains "${ROOT_DIR}/infra/cmd/ltbase-infra/main.go" "ctx.Export(\"projectId\""
assert_contains "${ROOT_DIR}/infra/cmd/ltbase-infra/main.go" "ctx.Export(\"apiId\""
assert_contains "${ROOT_DIR}/infra/cmd/ltbase-infra/main.go" "ctx.Export(\"apiBaseUrl\""
assert_contains "${ROOT_DIR}/infra/internal/services/lambda.go" "\"DSQL_ENDPOINT\""
assert_not_contains "${ROOT_DIR}/infra/internal/services/lambda.go" "VpcEndpointServiceName"
assert_contains "${ROOT_DIR}/infra/internal/services/apigateway.go" "func APIBaseURL"

printf 'PASS: managed DSQL consistency tests\n'
