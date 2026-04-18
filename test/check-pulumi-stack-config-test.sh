#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/check-pulumi-stack-config.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain: ${needle}"
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
mkdir -p "${temp_dir}/infra"

cat >"${temp_dir}/infra/Pulumi.devo.yaml" <<'EOF'
config:
  ltbase-infra:deploymentAwsAccountId: "123456789012"
  ltbase-infra:runtimeBucket: example-runtime
  ltbase-infra:schemaBucket: example-schema
  ltbase-infra:tableName: example-table
  ltbase-infra:mtlsTruststoreFile: infra/certs/cloudflare-origin-pull-ca.pem
  ltbase-infra:mtlsTruststoreKey: mtls/cloudflare-origin-pull-ca.pem
  ltbase-infra:apiDomain: api.example.com
  ltbase-infra:controlPlaneDomain: control.example.com
  ltbase-infra:authDomain: auth.example.com
  ltbase-infra:projectId: 11111111-1111-4111-8111-111111111111
  ltbase-infra:authProviderConfigFile: infra/auth-providers.devo.json
  ltbase-infra:cloudflareZoneId: zone-123
  ltbase-infra:oidcIssuerUrl: https://issuer.example.com/devo
  ltbase-infra:jwksUrl: https://issuer.example.com/devo/.well-known/jwks.json
  ltbase-infra:releaseId: v1.0.0
  ltbase-infra:githubOrg: Lychee-Technology
  ltbase-infra:githubRepo: ltbase-private-deployment
  ltbase-infra:githubOidcProviderArn: arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
  ltbase-infra:geminiApiKey:
    secure: test-secret
EOF

if ! output="$(${SCRIPT_PATH} --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
  fail "expected success for complete config, got: ${output}"
fi

python3 - <<'PY' "${temp_dir}/infra/Pulumi.devo.yaml"
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace('  ltbase-infra:schemaBucket: example-schema\n', ''))
PY

if output="$(${SCRIPT_PATH} --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
  fail "expected failure when schemaBucket is missing"
fi

assert_contains "${output}" "Missing required Pulumi config key 'ltbase-infra:schemaBucket'"
assert_contains "${output}" "infra/Pulumi.devo.yaml"

python3 - <<'PY' "${temp_dir}/infra/Pulumi.devo.yaml"
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = '  ltbase-infra:runtimeBucket: example-runtime\n'
path.write_text(text.replace(marker, marker + '  ltbase-infra:schemaBucket: example-schema\n'))
PY

python3 - <<'PY' "${temp_dir}/infra/Pulumi.devo.yaml"
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace('  ltbase-infra:deploymentAwsAccountId: "123456789012"\n', ''))
PY

if output="$(${SCRIPT_PATH} --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
  fail "expected failure when deploymentAwsAccountId is missing"
fi

assert_contains "${output}" "Missing required Pulumi config key 'ltbase-infra:deploymentAwsAccountId'"
assert_contains "${output}" "infra/Pulumi.devo.yaml"

rm -f "${temp_dir}/infra/Pulumi.devo.yaml"

if output="$(${SCRIPT_PATH} --stack devo --infra-dir "${temp_dir}/infra" 2>&1)"; then
  fail "expected failure when stack file is missing"
fi

assert_contains "${output}" "Missing Pulumi stack file"
assert_contains "${output}" "infra/Pulumi.devo.yaml"

printf 'PASS: check Pulumi stack config tests\n'
