#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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

preview_workflow="${ROOT_DIR}/.github/workflows/preview.yml"
deploy_workflow="${ROOT_DIR}/.github/workflows/deploy-devo.yml"
promote_workflow="${ROOT_DIR}/.github/workflows/promote-prod.yml"
rollout_workflow="${ROOT_DIR}/.github/workflows/rollout.yml"
rollout_hop_workflow="${ROOT_DIR}/.github/workflows/rollout-hop.yml"

assert_file_contains "${preview_workflow}" "target_stack:"
assert_file_contains "${preview_workflow}" "manual preview only supports the first promotion stack"
assert_file_contains "${preview_workflow}" "runs-on: ubuntu-24.04-arm"
assert_file_contains "${preview_workflow}" "Lychee-Technology/ltbase-deploy-workflows/.github/workflows/preview-stack.yml@main"
assert_file_contains "${preview_workflow}" "name: Validate Pulumi stack config"
assert_file_contains "${preview_workflow}" "./scripts/check-pulumi-stack-config.sh --stack \${{ needs.prepare.outputs.target_stack }}"
assert_file_contains "${preview_workflow}" "name: Validate customer schemas"
assert_file_contains "${preview_workflow}" "./scripts/publish-schemas.sh --dry-run --schema-bucket"
assert_file_contains "${preview_workflow}" "name: Audit Cloudflare mTLS"
assert_file_contains "${preview_workflow}" "./scripts/check-cloudflare-mtls.sh --env-file .github/mTLS-audit.env --stack"
assert_file_contains "${preview_workflow}" 'CLOUDFLARE_ZONE_ID: ${{ vars.CLOUDFLARE_ZONE_ID }}'
assert_file_contains "${rollout_hop_workflow}" "Lychee-Technology/ltbase-deploy-workflows/.github/workflows/rollout-hop.yml@main"

assert_file_contains "${deploy_workflow}" "uses: ./.github/workflows/rollout-hop.yml"
assert_file_contains "${deploy_workflow}" "runs-on: ubuntu-24.04-arm"
assert_file_contains "${deploy_workflow}" "continue_chain: false"
assert_file_contains "${deploy_workflow}" 'target_stack: ${{ needs.prepare.outputs.start_stack }}'

assert_file_contains "${promote_workflow}" "from_stack:"
assert_file_contains "${promote_workflow}" "to_stack:"
assert_file_contains "${promote_workflow}" "uses: ./.github/workflows/rollout-hop.yml"
assert_file_contains "${promote_workflow}" "continue_chain: false"

assert_file_contains "${rollout_workflow}" "uses: ./.github/workflows/rollout-hop.yml"
assert_file_contains "${rollout_workflow}" "runs-on: ubuntu-24.04-arm"
assert_file_contains "${rollout_workflow}" "continue_chain: true"
assert_file_contains "${rollout_workflow}" "start_stack"

assert_file_contains "${rollout_hop_workflow}" "workflow_call:"
assert_file_contains "${rollout_hop_workflow}" "workflow_dispatch:"
assert_file_contains "${rollout_hop_workflow}" "runs-on: ubuntu-24.04-arm"
assert_file_contains "${rollout_hop_workflow}" "invalid promotion hop"
assert_file_contains "${rollout_hop_workflow}" 'environment: ${{ needs.prepare.outputs.target_stack }}'
assert_file_contains "${rollout_hop_workflow}" 'gh api repos/${{ github.repository }}/actions/workflows/rollout-hop.yml/dispatches'
assert_file_contains "${rollout_hop_workflow}" "name: Audit Cloudflare mTLS"
assert_file_contains "${rollout_hop_workflow}" "./scripts/check-cloudflare-mtls.sh --env-file .github/mTLS-audit.env --stack"
assert_file_contains "${rollout_hop_workflow}" "name: Validate Pulumi stack config"
assert_file_contains "${rollout_hop_workflow}" "./scripts/check-pulumi-stack-config.sh --stack \${{ needs.prepare.outputs.target_stack }}"
assert_file_contains "${rollout_hop_workflow}" "name: Publish customer schemas"
assert_file_contains "${rollout_hop_workflow}" "./scripts/publish-schemas.sh --schema-bucket"
assert_file_contains "${rollout_hop_workflow}" "name: Validate schema bucket contract"
assert_file_contains "${rollout_hop_workflow}" "deployment outputs schemaBucket does not match"
assert_file_contains "${rollout_hop_workflow}" 'SCHEMA_BUCKET: ${{ vars[format('\''SCHEMA_BUCKET_{0}'\'', needs.prepare.outputs.target_stack_upper)] }}'
assert_file_contains "${rollout_hop_workflow}" "deployment outputs missing schemaBucket"
assert_file_contains "${rollout_hop_workflow}" "name: Ensure project"
assert_file_contains "${rollout_hop_workflow}" "aws lambda invoke"
assert_file_contains "${rollout_hop_workflow}" "name: Advance applied schema pointer"
assert_file_contains "${rollout_hop_workflow}" "s3://\${SCHEMA_BUCKET}/schemas/published/manifest.json"
assert_file_contains "${rollout_hop_workflow}" "s3://\${SCHEMA_BUCKET}/schemas/applied/manifest.json"
assert_file_contains "${rollout_hop_workflow}" "needs.publish_schemas.result == 'success'"
  assert_file_contains "${rollout_hop_workflow}" 'CLOUDFLARE_ZONE_ID: ${{ vars.CLOUDFLARE_ZONE_ID }}'
  assert_file_contains "${rollout_hop_workflow}" "MTLS_TRUSTSTORE_KEY: mtls/cloudflare-origin-pull-ca.pem"
  assert_file_contains "${rollout_hop_workflow}" "reconcile_managed_dsql_endpoint: true"
assert_file_not_contains "${rollout_hop_workflow}" "pulumi_stack: devo"
assert_file_not_contains "${rollout_hop_workflow}" "pulumi_stack: prod"

printf 'PASS: rollout workflow tests\n'
