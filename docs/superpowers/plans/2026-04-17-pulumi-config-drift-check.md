# Pulumi Config Drift Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fail customer preview and deployment workflows early with a clear error when a required Pulumi stack config key is missing from `infra/Pulumi.<stack>.yaml`.

**Architecture:** Keep `scripts/bootstrap-deployment-repo.sh` as the only writer of required Pulumi config. Add a small repo-local validation script that checks key presence in stack YAML, then invoke it from the generated repo workflows before they dispatch into shared reusable workflows. Cover the script with focused shell tests and extend existing workflow assertions to ensure the preflight check stays wired in.

**Tech Stack:** Bash scripts, GitHub Actions YAML, shell-based repository tests

---

### Task 1: Add Validation Script Coverage First

**Files:**
- Create: `test/check-pulumi-stack-config-test.sh`
- Test: `test/check-pulumi-stack-config-test.sh`

- [ ] **Step 1: Write the failing test**

```bash
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

if ! output="${SCRIPT_PATH}" --stack devo --infra-dir "${temp_dir}/infra" 2>&1; then
  fail "expected success for complete config, got: ${output}"
fi

python3 - <<'PY' "${temp_dir}/infra/Pulumi.devo.yaml"
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('  ltbase-infra:deploymentAwsAccountId: "123456789012"\n', ''))
PY

if output="${SCRIPT_PATH}" --stack devo --infra-dir "${temp_dir}/infra" 2>&1; then
  fail "expected failure when deploymentAwsAccountId is missing"
fi

assert_contains "${output}" "Missing required Pulumi config key 'ltbase-infra:deploymentAwsAccountId'"
assert_contains "${output}" "infra/Pulumi.devo.yaml"

rm -f "${temp_dir}/infra/Pulumi.devo.yaml"

if output="${SCRIPT_PATH}" --stack devo --infra-dir "${temp_dir}/infra" 2>&1; then
  fail "expected failure when stack file is missing"
fi

assert_contains "${output}" "Missing Pulumi stack file"
assert_contains "${output}" "infra/Pulumi.devo.yaml"

printf 'PASS: check Pulumi stack config tests\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/check-pulumi-stack-config-test.sh`
Expected: FAIL because `scripts/check-pulumi-stack-config.sh` does not exist yet.

- [ ] **Step 3: Commit the failing test scaffold only after verifying failure is understood**

No commit in red phase. Move directly to minimal implementation.

### Task 2: Implement Minimal Config Drift Checker

**Files:**
- Create: `scripts/check-pulumi-stack-config.sh`
- Test: `test/check-pulumi-stack-config-test.sh`

- [ ] **Step 1: Write minimal implementation**

```bash
#!/usr/bin/env bash

set -euo pipefail

STACK=""
INFRA_DIR="infra"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      STACK="$2"
      shift 2
      ;;
    --infra-dir)
      INFRA_DIR="$2"
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${STACK}" ]]; then
  printf 'stack is required\n' >&2
  exit 1
fi

stack_file="${INFRA_DIR}/Pulumi.${STACK}.yaml"
display_path="infra/Pulumi.${STACK}.yaml"

if [[ ! -f "${stack_file}" ]]; then
  printf "Missing Pulumi stack file '%s'. Rerun bootstrap-deployment-repo.sh or restore the stack config file.\n" "${display_path}" >&2
  exit 1
fi

required_keys=(
  "ltbase-infra:deploymentAwsAccountId"
  "ltbase-infra:runtimeBucket"
  "ltbase-infra:tableName"
  "ltbase-infra:mtlsTruststoreFile"
  "ltbase-infra:mtlsTruststoreKey"
  "ltbase-infra:apiDomain"
  "ltbase-infra:controlPlaneDomain"
  "ltbase-infra:authDomain"
  "ltbase-infra:projectId"
  "ltbase-infra:authProviderConfigFile"
  "ltbase-infra:cloudflareZoneId"
  "ltbase-infra:oidcIssuerUrl"
  "ltbase-infra:jwksUrl"
  "ltbase-infra:releaseId"
  "ltbase-infra:githubOrg"
  "ltbase-infra:githubRepo"
  "ltbase-infra:githubOidcProviderArn"
  "ltbase-infra:geminiApiKey"
)

for key in "${required_keys[@]}"; do
  if ! grep -Fq "  ${key}:" "${stack_file}"; then
    printf "Missing required Pulumi config key '%s' in %s. Rerun bootstrap-deployment-repo.sh or update the stack config file.\n" "${key}" "${display_path}" >&2
    exit 1
  fi
done
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x scripts/check-pulumi-stack-config.sh`
Expected: no output.

- [ ] **Step 3: Run the focused test to verify it passes**

Run: `bash test/check-pulumi-stack-config-test.sh`
Expected: `PASS: check Pulumi stack config tests`

- [ ] **Step 4: Commit**

```bash
git add scripts/check-pulumi-stack-config.sh test/check-pulumi-stack-config-test.sh
git commit -m "fix: validate required Pulumi stack config before deploy"
```

### Task 3: Wire Validation Into Customer Workflows

**Files:**
- Modify: `.github/workflows/preview.yml`
- Modify: `.github/workflows/rollout-hop.yml`
- Test: `test/rollout-workflows-test.sh`

- [ ] **Step 1: Add failing workflow assertions**

Add these assertions to `test/rollout-workflows-test.sh`:

```bash
assert_file_contains "${preview_workflow}" "- uses: actions/checkout@v4"
assert_file_contains "${preview_workflow}" "name: Validate Pulumi stack config"
assert_file_contains "${preview_workflow}" "./scripts/check-pulumi-stack-config.sh --stack ${{ needs.prepare.outputs.target_stack }}"

assert_file_contains "${rollout_hop_workflow}" "- uses: actions/checkout@v4"
assert_file_contains "${rollout_hop_workflow}" "name: Validate Pulumi stack config"
assert_file_contains "${rollout_hop_workflow}" "./scripts/check-pulumi-stack-config.sh --stack ${{ needs.prepare.outputs.target_stack }}"
```

- [ ] **Step 2: Run workflow test to verify it fails**

Run: `bash test/rollout-workflows-test.sh`
Expected: FAIL because neither workflow runs the new validation script yet.

- [ ] **Step 3: Update preview workflow minimally**

Insert a local validation job between `prepare` and `preview` in `.github/workflows/preview.yml`:

```yaml
  validate_config:
    needs: prepare
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4

      - name: Validate Pulumi stack config
        run: ./scripts/check-pulumi-stack-config.sh --stack ${{ needs.prepare.outputs.target_stack }}

  preview:
    needs:
      - prepare
      - validate_config
```

- [ ] **Step 4: Update rollout hop workflow minimally**

Insert a local validation job before `approve` and `rollout` in `.github/workflows/rollout-hop.yml`:

```yaml
  validate_config:
    needs: prepare
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4

      - name: Validate Pulumi stack config
        run: ./scripts/check-pulumi-stack-config.sh --stack ${{ needs.prepare.outputs.target_stack }}

  approve:
    needs:
      - prepare
      - validate_config

  rollout:
    needs:
      - prepare
      - validate_config
      - approve
```

- [ ] **Step 5: Re-run workflow test to verify it passes**

Run: `bash test/rollout-workflows-test.sh`
Expected: `PASS: rollout workflow tests`

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/preview.yml .github/workflows/rollout-hop.yml test/rollout-workflows-test.sh
git commit -m "fix: gate workflows on Pulumi config validation"
```

### Task 4: Document Operator Recovery Path

**Files:**
- Modify: `docs/onboarding/08-day-2-operations.md`

- [ ] **Step 1: Add a focused docs note**

Add a short section like this near existing operational recovery guidance:

```md
## Pulumi Config Drift Recovery

Preview and deployment workflows now validate that `infra/Pulumi.<stack>.yaml` contains the required `ltbase-infra:*` config keys before invoking the shared deployment workflows.

If the workflow fails with a missing-key error, repair the generated deployment repository by either:

- rerunning `./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack>`, or
- restoring the missing key in `infra/Pulumi.<stack>.yaml`

This check is presence-only. It does not modify customer config automatically.
```

- [ ] **Step 2: Review docs for consistency with the non-goals**

Confirm the docs do not promise auto-healing or deploy-time mutation.

- [ ] **Step 3: Commit**

```bash
git add docs/onboarding/08-day-2-operations.md
git commit -m "docs: explain Pulumi config drift recovery"
```

### Task 5: Final Verification

**Files:**
- Test: `test/check-pulumi-stack-config-test.sh`
- Test: `test/rollout-workflows-test.sh`

- [ ] **Step 1: Run focused script test**

Run: `bash test/check-pulumi-stack-config-test.sh`
Expected: `PASS: check Pulumi stack config tests`

- [ ] **Step 2: Run workflow assertion test**

Run: `bash test/rollout-workflows-test.sh`
Expected: `PASS: rollout workflow tests`

- [ ] **Step 3: Run combined verification in sequence**

Run: `bash test/check-pulumi-stack-config-test.sh && bash test/rollout-workflows-test.sh`
Expected: both test suites pass with no failures.

- [ ] **Step 4: Review worktree**

Run: `git status --short`
Expected: only the intended script, test, workflow, doc, and plan/spec changes appear.
