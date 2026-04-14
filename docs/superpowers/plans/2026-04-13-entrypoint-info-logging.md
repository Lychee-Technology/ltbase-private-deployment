# Entrypoint Info Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the customer-facing shell entrypoints print concise info-level progress by default while still replaying full command output on failure.

**Architecture:** Add tiny shared logging wrappers to `scripts/lib/bootstrap-env.sh`, then route each entrypoint's noisy external commands through those wrappers. Use one wrapper for fire-and-forget commands and one capture wrapper for commands whose stdout is structured data. Keep validation errors and final summaries visible, and extend the existing shell regression tests to prove success-path output stays quiet while failures remain debuggable.

**Tech Stack:** Bash, existing shell test scripts in `test/`, GitHub CLI, AWS CLI, Pulumi CLI, curl

---

## File Map

- Modify: `scripts/lib/bootstrap-env.sh`
  Responsibility: shared `info` logger, quiet command wrapper, and quiet capture wrapper used by entrypoint scripts.
- Modify: `scripts/bootstrap-all.sh`
  Responsibility: top-level bootstrap orchestration and stage-level info output.
- Modify: `scripts/bootstrap-deployment-repo.sh`
  Responsibility: quiet GitHub and Pulumi configuration for one stack.
- Modify: `scripts/create-deployment-repo.sh`
  Responsibility: quiet GitHub repo creation and environment setup.
- Modify: `scripts/bootstrap-aws-foundation.sh`
  Responsibility: quiet AWS IAM/KMS/S3 foundation reconciliation.
- Modify: `scripts/bootstrap-oidc-discovery-companion.sh`
  Responsibility: quiet GitHub, Cloudflare, and AWS reconciliation for the OIDC companion.
- Modify: `scripts/evaluate-and-continue.sh`
  Responsibility: quiet remediation execution while preserving reports and final status summary.
- Modify: `scripts/update-sync-template-tooling.sh`
  Responsibility: quiet git/tar/cp success-path output while keeping the final summary.
- Modify: `scripts/sync-template-upstream.sh`
  Responsibility: quiet sync plumbing while keeping the final summary.
- Create: `test/bootstrap-env-test.sh`
  Responsibility: direct regression coverage for the shared quiet wrapper.
- Modify: `test/bootstrap-all-test.sh`
  Responsibility: prove stage-level info lines are visible and child-script noise is absent.
- Modify: `test/bootstrap-deployment-repo-test.sh`
  Responsibility: prove GitHub/Pulumi success output is hidden while commands still run.
- Modify: `test/create-deployment-repo-test.sh`
  Responsibility: prove GitHub CLI success output is hidden and info lines are visible.
- Modify: `test/bootstrap-aws-foundation-test.sh`
  Responsibility: prove AWS CLI success output is hidden and failure output still surfaces.
- Modify: `test/bootstrap-oidc-discovery-companion-test.sh`
  Responsibility: prove quiet Cloudflare/GitHub/AWS success path and preserved failure diagnostics.
- Modify: `test/evaluate-and-continue-test.sh`
  Responsibility: prove remediation actions remain summarized without leaking tool chatter.
- Modify: `test/update-sync-template-tooling-test.sh`
  Responsibility: prove sync-tooling command chatter is hidden on success.
- Modify: `test/sync-template-upstream-test.sh`
  Responsibility: prove template sync command chatter is hidden on success.

### Task 1: Add the shared quiet logging primitives

**Files:**
- Create: `test/bootstrap-env-test.sh`
- Modify: `scripts/lib/bootstrap-env.sh`
- Test: `test/bootstrap-env-test.sh`

- [ ] **Step 1: Write the failing shared-wrapper regression test**

Create `test/bootstrap-env-test.sh` with these assertions:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB_PATH="${ROOT_DIR}/scripts/lib/bootstrap-env.sh"

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "expected output to not contain: ${needle}"
  fi
}

success_output="$({
  source "${LIB_PATH}"
  bootstrap_env_info "starting bootstrap"
  bootstrap_env_run_quiet bash -lc 'printf "verbose stdout\\n"; printf "verbose stderr\\n" >&2'
} 2>&1)"

assert_contains "${success_output}" "[info] starting bootstrap"
assert_not_contains "${success_output}" "verbose stdout"
assert_not_contains "${success_output}" "verbose stderr"

set +e
failure_output="$({
  source "${LIB_PATH}"
  bootstrap_env_run_quiet bash -lc 'printf "failure stdout\\n"; printf "failure stderr\\n" >&2; exit 17'
} 2>&1)"
failure_status=$?
set -e

if [[ "${failure_status}" -ne 17 ]]; then
  fail "expected exit status 17, got ${failure_status}"
fi

assert_contains "${failure_output}" "failure stdout"
assert_contains "${failure_output}" "failure stderr"

printf 'PASS: bootstrap-env tests\n'
```

- [ ] **Step 2: Run the new test to verify RED**

Run: `bash test/bootstrap-env-test.sh`

Expected: FAIL with `bootstrap_env_info: command not found` or `bootstrap_env_run_quiet: command not found`.

- [ ] **Step 3: Write the minimal shared implementation**

Add these helpers near the other shared functions in `scripts/lib/bootstrap-env.sh`:

```bash
bootstrap_env_info() {
  printf '[info] %s\n' "$*"
}

bootstrap_env_run_quiet() {
  local output status

  set +e
  output="$({ "$@"; } 2>&1)"
  status=$?
  set -e

  if [[ "${status}" -eq 0 ]]; then
    return 0
  fi

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" >&2
  fi
  return "${status}"
}

bootstrap_env_capture_quiet() {
  local __result_var="$1"
  shift
  local output status

  set +e
  output="$({ "$@"; } 2>&1)"
  status=$?
  set -e

  if [[ "${status}" -ne 0 ]]; then
    if [[ -n "${output}" ]]; then
      printf '%s\n' "${output}" >&2
    fi
    return "${status}"
  fi

  printf -v "${__result_var}" '%s' "${output}"
}
```

Keep it intentionally small. Do not add log levels, flags, or formatting beyond the `[info]` prefix.

- [ ] **Step 4: Run the shared test to verify GREEN**

Run: `bash test/bootstrap-env-test.sh`

Expected: `PASS: bootstrap-env tests`

- [ ] **Step 5: Commit**

```bash
git add test/bootstrap-env-test.sh scripts/lib/bootstrap-env.sh
git commit -m "test: add quiet logging helpers for bootstrap scripts"
```

### Task 2: Apply quiet logging to the bootstrap orchestrator and stack config entrypoint

**Files:**
- Modify: `test/bootstrap-all-test.sh`
- Modify: `test/bootstrap-deployment-repo-test.sh`
- Modify: `scripts/bootstrap-all.sh`
- Modify: `scripts/bootstrap-deployment-repo.sh`
- Test: `test/bootstrap-all-test.sh`
- Test: `test/bootstrap-deployment-repo-test.sh`

- [ ] **Step 1: Extend the entrypoint tests with failing expectations**

Add these helpers to `test/bootstrap-all-test.sh` next to the existing file-based assertions:

```bash
assert_output_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain: ${needle}"
  fi
}

assert_output_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "expected output to not contain: ${needle}"
  fi
}
```

Then add these assertions after the existing command-log checks:

```bash
  assert_output_contains "${output}" "[info] ensuring deployment repository"
  assert_output_contains "${output}" "[info] rendering bootstrap policies"
  assert_output_contains "${output}" "[info] bootstrapping AWS foundation"
  assert_output_contains "${output}" "[info] configuring stack devo"
```

Then make the stubs emit noisy stdout/stderr by replacing the stub body with:

```bash
printf '%s %s\n' '${name}' "$*" >>"${log_file}"
printf '${name} verbose stdout\n'
printf '${name} verbose stderr\n' >&2
```

Add these assertions to the same test:

```bash
  assert_output_not_contains "${output}" "create-deployment-repo.sh verbose stdout"
  assert_output_not_contains "${output}" "bootstrap-deployment-repo.sh verbose stderr"
```

In `test/bootstrap-deployment-repo-test.sh`, make the fake `gh` and `pulumi` commands print noisy stdout/stderr before exiting successfully:

```bash
printf 'gh noisy stdout\n'
printf 'gh noisy stderr\n' >&2
```

```bash
printf 'pulumi noisy stdout\n'
printf 'pulumi noisy stderr\n' >&2
```

Then add matching string helpers to `test/bootstrap-deployment-repo-test.sh` and use these assertions:

```bash
  assert_output_contains "${output}" "[info] configuring repository variables and secrets for Lychee-Technology/ltbase-private-deployment"
  assert_output_contains "${output}" "[info] configuring Pulumi stack prod"
  assert_output_not_contains "${output}" "gh noisy stdout"
  assert_output_not_contains "${output}" "pulumi noisy stderr"
```

- [ ] **Step 2: Run the two tests to verify RED**

Run: `bash test/bootstrap-all-test.sh && bash test/bootstrap-deployment-repo-test.sh`

Expected: FAIL because the scripts currently do not emit the new `[info]` lines and still leak child command output.

- [ ] **Step 3: Implement the minimal entrypoint changes**

In `scripts/bootstrap-all.sh`, source the helper as it already does, then wrap each child call with info lines and the quiet runner:

```bash
bootstrap_env_info "ensuring deployment repository"
bootstrap_env_run_quiet "${script_dir}/create-deployment-repo.sh" --env-file "${ENV_FILE}"

bootstrap_env_info "rendering bootstrap policies"
bootstrap_env_run_quiet "${script_dir}/render-bootstrap-policies.sh" --env-file "${ENV_FILE}"

bootstrap_env_info "bootstrapping AWS foundation"
bootstrap_env_run_quiet "${script_dir}/bootstrap-aws-foundation.sh" --env-file "${ENV_FILE}"

bootstrap_env_info "ensuring OIDC discovery companion"
bootstrap_env_run_quiet "${script_dir}/bootstrap-oidc-discovery-companion.sh" --env-file "${ENV_FILE}"

while IFS= read -r stack; do
  bootstrap_env_info "configuring stack ${stack}"
  bootstrap_env_run_quiet "${script_dir}/bootstrap-deployment-repo.sh" --env-file "${ENV_FILE}" --stack "${stack}" --infra-dir "${INFRA_DIR}"
done < <(bootstrap_env_each_stack)
```

In `scripts/bootstrap-deployment-repo.sh`, add two info lines and route every `gh`/`pulumi` invocation through the quiet helpers. Keep `pulumi stack select` as the existing silent existence probe because a missing stack is an expected branch:

```bash
bootstrap_env_info "configuring repository variables and secrets for ${DEPLOYMENT_REPO}"
bootstrap_env_run_quiet gh variable set "AWS_REGION_${target_upper}" --repo "${DEPLOYMENT_REPO}" --body "${target_region}"
bootstrap_env_run_quiet gh secret set "AWS_ROLE_ARN_${target_upper}" --repo "${DEPLOYMENT_REPO}" --body "${target_role_arn}"
```

```bash
bootstrap_env_info "configuring Pulumi stack ${STACK}"
bootstrap_env_run_quiet "${backend_env[@]}" pulumi login "${PULUMI_BACKEND_URL}"
if ! "${stack_env[@]}" pulumi stack select "${STACK}" >/dev/null 2>&1; then
  bootstrap_env_run_quiet "${stack_env[@]}" pulumi stack init "${STACK}" --secrets-provider "${selected_secrets_provider}"
fi
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set awsRegion "${selected_region}" --stack "${STACK}"
```

Do not change argument values or control flow beyond wrapping the commands and printing the info lines.

- [ ] **Step 4: Run the two tests to verify GREEN**

Run: `bash test/bootstrap-all-test.sh && bash test/bootstrap-deployment-repo-test.sh`

Expected:
- `PASS: bootstrap-all tests`
- `PASS: bootstrap-deployment-repo tests`

- [ ] **Step 5: Commit**

```bash
git add test/bootstrap-all-test.sh test/bootstrap-deployment-repo-test.sh scripts/bootstrap-all.sh scripts/bootstrap-deployment-repo.sh
git commit -m "feat: quiet bootstrap entrypoint success logs"
```

### Task 3: Apply quiet logging to the remaining operational entrypoints

**Files:**
- Modify: `test/create-deployment-repo-test.sh`
- Modify: `test/bootstrap-aws-foundation-test.sh`
- Modify: `test/bootstrap-oidc-discovery-companion-test.sh`
- Modify: `test/evaluate-and-continue-test.sh`
- Modify: `scripts/create-deployment-repo.sh`
- Modify: `scripts/bootstrap-aws-foundation.sh`
- Modify: `scripts/bootstrap-oidc-discovery-companion.sh`
- Modify: `scripts/evaluate-and-continue.sh`
- Test: `test/create-deployment-repo-test.sh`
- Test: `test/bootstrap-aws-foundation-test.sh`
- Test: `test/bootstrap-oidc-discovery-companion-test.sh`
- Test: `test/evaluate-and-continue-test.sh`

- [ ] **Step 1: Add failing regression expectations for quiet success output**

In `test/create-deployment-repo-test.sh`, make the fake `gh` command print noisy output before succeeding:

```bash
printf 'gh repo noisy stdout\n'
printf 'gh repo noisy stderr\n' >&2
```

Add matching string helpers to `test/create-deployment-repo-test.sh`, then add assertions like:

```bash
  assert_output_contains "${output}" "[info] ensuring deployment repository customer-org/customer-ltbase"
  assert_output_contains "${output}" "[info] ensuring protected deployment environments"
  assert_output_not_contains "${output}" "gh repo noisy stdout"
```

In `test/bootstrap-aws-foundation-test.sh`, make the fake `aws` command print success chatter on non-error paths:

```bash
printf 'aws noisy stdout\n'
printf 'aws noisy stderr\n' >&2
```

Add matching string helpers to `test/bootstrap-aws-foundation-test.sh`, then add assertions like:

```bash
  assert_output_contains "${output}" "[info] validating AWS credentials for stack devo"
  assert_output_contains "${output}" "[info] reconciling IAM and KMS resources for stack prod"
  assert_output_contains "${output}" "[info] ensuring shared Pulumi state bucket test-pulumi-state"
  assert_output_not_contains "${output}" "aws noisy stdout"
```

In `test/bootstrap-oidc-discovery-companion-test.sh`, add matching string helpers, make the fake `gh`, `curl`, and `aws` commands print success chatter, and assert that the overall output contains only info lines such as:

```bash
  assert_output_contains "${output}" "[info] ensuring OIDC discovery repository customer-org/customer-ltbase-oidc-discovery"
  assert_output_contains "${output}" "[info] ensuring Cloudflare Pages project customer-ltbase-oidc-discovery"
  assert_output_contains "${output}" "[info] ensuring OIDC discovery DNS record oidc.customer.example.com"
  assert_output_not_contains "${output}" "curl noisy stdout"
```

In `test/evaluate-and-continue-test.sh`, add one representative assertion that the script prints concise status summary lines and does not leak fake CLI chatter during remediation. Reuse the existing fake-bin setup by making one of the fake commands print `noisy remediation output` and asserting it stays absent.

- [ ] **Step 2: Run the four tests to verify RED**

Run:

```bash
bash test/create-deployment-repo-test.sh && \
bash test/bootstrap-aws-foundation-test.sh && \
bash test/bootstrap-oidc-discovery-companion-test.sh && \
bash test/evaluate-and-continue-test.sh
```

Expected: FAIL because the scripts do not yet emit the new info lines and still print underlying command chatter.

- [ ] **Step 3: Implement the minimal quiet wrappers in the scripts**

In `scripts/create-deployment-repo.sh`, add the two stage messages and wrap the `gh` calls:

```bash
bootstrap_env_info "ensuring deployment repository ${DEPLOYMENT_REPO}"
if gh repo view "${DEPLOYMENT_REPO}" >/dev/null 2>&1; then
  bootstrap_env_capture_quiet actual_private gh api "repos/${DEPLOYMENT_REPO}" --jq '.private'
else
  bootstrap_env_run_quiet gh repo create "${DEPLOYMENT_REPO}" --template "${TEMPLATE_REPO}" ${visibility_flag} --description "${DEPLOYMENT_REPO_DESCRIPTION}" --clone=false
fi

bootstrap_env_info "ensuring protected deployment environments"
bootstrap_env_run_quiet gh api "repos/${DEPLOYMENT_REPO}/environments/${stack}" --method PUT >/dev/null
```

In `scripts/bootstrap-aws-foundation.sh`, keep the existing credential check logic but add stage messages and wrap all mutating AWS calls:

```bash
bootstrap_env_info "validating AWS credentials for stack ${stack}"
bootstrap_env_require_aws_credentials_for_stack "${stack}"

bootstrap_env_info "reconciling IAM and KMS resources for stack ${stack}"
bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com >/dev/null
bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam create-role --role-name "${stack_role_name}" --assume-role-policy-document "file://${trust_policy_path}" >/dev/null
bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${stack}" iam put-role-policy --role-name "${stack_role_name}" --policy-name LTBaseDeploymentAccess --policy-document "file://${role_policy_path}" >/dev/null
```

```bash
bootstrap_env_capture_quiet alias_json bootstrap_env_aws_command_for_stack "${stack}" kms list-aliases --region "${stack_region}" --output json
bootstrap_env_info "ensuring shared Pulumi state bucket ${PULUMI_STATE_BUCKET}"
bootstrap_env_run_quiet bootstrap_env_aws_command_for_stack "${first_stack}" s3api put-bucket-versioning --bucket "${PULUMI_STATE_BUCKET}" --versioning-configuration Status=Enabled >/dev/null
```

In `scripts/bootstrap-oidc-discovery-companion.sh`, add stage messages and wrap every success-path `gh`, `curl`, and AWS mutation command with `bootstrap_env_run_quiet` while keeping the existing failure-specific helpers untouched. Use messages at these points:

```bash
bootstrap_env_info "ensuring OIDC discovery repository ${OIDC_DISCOVERY_REPO}"
bootstrap_env_info "ensuring Cloudflare Pages project ${OIDC_DISCOVERY_PAGES_PROJECT}"
bootstrap_env_info "ensuring Cloudflare Pages domain ${OIDC_DISCOVERY_DOMAIN}"
bootstrap_env_info "ensuring OIDC discovery DNS record ${OIDC_DISCOVERY_DOMAIN}"
bootstrap_env_info "configuring OIDC discovery repository variables and secrets"
bootstrap_env_info "reconciling OIDC discovery IAM role for stack ${stack}"
```

For commands whose stdout is data instead of operator logging, use `bootstrap_env_capture_quiet`, for example:

```bash
bootstrap_env_capture_quiet repo_metadata gh api "repos/${OIDC_DISCOVERY_REPO}"
bootstrap_env_capture_quiet dns_lookup_response cloudflare_get_json "get DNS CNAME" "${dns_lookup_url}"
```

In `scripts/evaluate-and-continue.sh`, change `run_logged()` so it records the action in `actions.log` and runs through the quiet wrapper:

```bash
run_logged() {
  printf '%s\n' "$*" >>"${actions_log}"
  bootstrap_env_run_quiet "$@"
}
```

Then add concise info lines before each remediation branch invokes child scripts or workflows.

- [ ] **Step 4: Run the four tests to verify GREEN**

Run:

```bash
bash test/create-deployment-repo-test.sh && \
bash test/bootstrap-aws-foundation-test.sh && \
bash test/bootstrap-oidc-discovery-companion-test.sh && \
bash test/evaluate-and-continue-test.sh
```

Expected:
- `PASS: create-deployment-repo tests`
- `PASS: bootstrap-aws-foundation tests`
- `PASS: bootstrap-oidc-discovery-companion tests`
- `PASS: evaluate-and-continue tests`

- [ ] **Step 5: Commit**

```bash
git add test/create-deployment-repo-test.sh test/bootstrap-aws-foundation-test.sh test/bootstrap-oidc-discovery-companion-test.sh test/evaluate-and-continue-test.sh scripts/create-deployment-repo.sh scripts/bootstrap-aws-foundation.sh scripts/bootstrap-oidc-discovery-companion.sh scripts/evaluate-and-continue.sh
git commit -m "feat: reduce bootstrap command noise to info level"
```

### Task 4: Quiet the template sync helper scripts and run the targeted verification set

**Files:**
- Modify: `test/update-sync-template-tooling-test.sh`
- Modify: `test/sync-template-upstream-test.sh`
- Modify: `scripts/update-sync-template-tooling.sh`
- Modify: `scripts/sync-template-upstream.sh`
- Test: `test/update-sync-template-tooling-test.sh`
- Test: `test/sync-template-upstream-test.sh`

- [ ] **Step 1: Add failing sync-script expectations**

Update the fake binaries in both sync tests so `git`, `tar`, `cp`, `find`, `shasum`, `jq`, and `rsync` print noise to stdout/stderr before succeeding. Add matching string helpers to both tests. Then add assertions like:

```bash
assert_output_contains "${output}" "[info] fetching upstream template main from upstream"
assert_output_contains "${output}" "[info] updating local sync helper files"
assert_output_not_contains "${output}" "git noisy stdout"
```

and:

```bash
assert_output_contains "${output}" "[info] fetching upstream template main from upstream"
assert_output_contains "${output}" "[info] syncing template-managed files"
assert_output_not_contains "${output}" "rsync noisy stderr"
```

- [ ] **Step 2: Run the sync tests to verify RED**

Run: `bash test/update-sync-template-tooling-test.sh && bash test/sync-template-upstream-test.sh`

Expected: FAIL because the scripts currently expose the fake command chatter and do not emit the new info lines.

- [ ] **Step 3: Implement the minimal sync-script changes**

In `scripts/update-sync-template-tooling.sh`, source `scripts/lib/bootstrap-env.sh`, then wrap the plumbing commands:

```bash
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/bootstrap-env.sh"

bootstrap_env_info "fetching upstream template ${BRANCH} from ${UPSTREAM_NAME}"
bootstrap_env_run_quiet git fetch "${UPSTREAM_NAME}"
bootstrap_env_run_quiet git archive --format=tar --output "${ARCHIVE_PATH}" "${UPSTREAM_NAME}/${BRANCH}"
bootstrap_env_run_quiet tar -xf "${ARCHIVE_PATH}" -C "${temp_root}"

bootstrap_env_info "updating local sync helper files"
bootstrap_env_run_quiet cp "${temp_root}/scripts/sync-template-upstream.sh" "${repo_root}/scripts/sync-template-upstream.sh"
bootstrap_env_run_quiet cp "${temp_root}/test/sync-template-upstream-test.sh" "${repo_root}/test/sync-template-upstream-test.sh"
```

In `scripts/sync-template-upstream.sh`, source the helper and wrap the success-path plumbing similarly:

```bash
bootstrap_env_info "fetching upstream template ${BRANCH} from ${UPSTREAM_NAME}"
bootstrap_env_run_quiet git fetch "${UPSTREAM_NAME}"
bootstrap_env_capture_quiet upstream_commit git rev-parse "${UPSTREAM_NAME}/${BRANCH}"
bootstrap_env_run_quiet git archive --format=tar --output "${ARCHIVE_PATH}" "${UPSTREAM_NAME}/${BRANCH}"
bootstrap_env_run_quiet tar -xf "${ARCHIVE_PATH}" -C "${temp_root}"

bootstrap_env_info "refreshing template provenance metadata"
fingerprint="$(build_fingerprint "${temp_root}")"

bootstrap_env_info "syncing template-managed files"
bootstrap_env_run_quiet rsync -a --delete \
  --exclude '.git/' \
  --exclude 'dist/' \
  --exclude '.DS_Store' \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude 'infra/Pulumi.*.yaml' \
  --exclude 'infra/auth-providers.*.json' \
  --exclude 'scripts/sync-template-upstream.sh' \
  --exclude 'test/sync-template-upstream-test.sh' \
  "${temp_root}/" "./"
```

Leave the existing final `printf 'updated ...'` and `printf 'synced ...'` summary lines intact.

- [ ] **Step 4: Run the sync tests to verify GREEN**

Run: `bash test/update-sync-template-tooling-test.sh && bash test/sync-template-upstream-test.sh`

Expected:
- `PASS: update-sync-template-tooling tests`
- `PASS: sync-template-upstream tests`

- [ ] **Step 5: Run the full targeted verification set and commit**

Run:

```bash
bash test/bootstrap-env-test.sh && \
bash test/bootstrap-all-test.sh && \
bash test/bootstrap-deployment-repo-test.sh && \
bash test/create-deployment-repo-test.sh && \
bash test/bootstrap-aws-foundation-test.sh && \
bash test/bootstrap-oidc-discovery-companion-test.sh && \
bash test/evaluate-and-continue-test.sh && \
bash test/update-sync-template-tooling-test.sh && \
bash test/sync-template-upstream-test.sh
```

Expected: all listed tests print `PASS: ...`

Then commit:

```bash
git add test/bootstrap-env-test.sh test/bootstrap-all-test.sh test/bootstrap-deployment-repo-test.sh test/create-deployment-repo-test.sh test/bootstrap-aws-foundation-test.sh test/bootstrap-oidc-discovery-companion-test.sh test/evaluate-and-continue-test.sh test/update-sync-template-tooling-test.sh test/sync-template-upstream-test.sh scripts/lib/bootstrap-env.sh scripts/bootstrap-all.sh scripts/bootstrap-deployment-repo.sh scripts/create-deployment-repo.sh scripts/bootstrap-aws-foundation.sh scripts/bootstrap-oidc-discovery-companion.sh scripts/evaluate-and-continue.sh scripts/update-sync-template-tooling.sh scripts/sync-template-upstream.sh
git commit -m "feat: keep deployment entrypoint logs at info level"
```

## Self-Review

- Spec coverage: the plan covers the shared wrapper, all nine scoped entrypoint scripts, concise info logging, suppressed success-path tool output, preserved failure output, and targeted regression coverage.
- Placeholder scan: no `TODO`, `TBD`, or implicit “write tests later” steps remain.
- Type consistency: helper names are consistent across tasks: `bootstrap_env_info` and `bootstrap_env_run_quiet`.
