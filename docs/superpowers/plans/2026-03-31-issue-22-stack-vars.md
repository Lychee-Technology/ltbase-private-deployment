# Persist STACKS And PROMOTION_PATH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist `STACKS`, `PROMOTION_PATH`, and the derived preview default into customer deployment repo variables so rollout workflows never fall back to `devo,prod` after bootstrap.

**Architecture:** Extend the deployment-repo bootstrap script to write the rollout topology variables, then tighten `evaluate-and-continue` repo-config validation to require them. Lock the behavior with shell tests that fail when those vars are missing and pass once bootstrap writes them.

**Tech Stack:** Bash, GitHub CLI, shell tests

---

### Task 1: Add regression coverage for missing rollout topology vars

**Files:**
- Modify: `test/bootstrap-deployment-repo-test.sh`
- Modify: `test/evaluate-and-continue-test.sh`

- [ ] **Step 1: Write the failing bootstrap regression**

Add assertions to `test/bootstrap-deployment-repo-test.sh` that require:

```bash
assert_log_contains "${log_file}" "gh variable set STACKS --repo customer-org/customer-ltbase --body devo,staging,prod"
assert_log_contains "${log_file}" "gh variable set PROMOTION_PATH --repo customer-org/customer-ltbase --body devo,staging,prod"
assert_log_contains "${log_file}" "gh variable set PREVIEW_DEFAULT_STACK --repo customer-org/customer-ltbase --body devo"
```

- [ ] **Step 2: Run the bootstrap test to verify it fails**

Run: `bash test/bootstrap-deployment-repo-test.sh`
Expected: FAIL because the script does not write those repo variables yet.

- [ ] **Step 3: Write the failing recovery regression**

Adjust `test/evaluate-and-continue-test.sh` so the fake `gh variable list` output for the healthy repo case includes `STACKS`, `PROMOTION_PATH`, and `PREVIEW_DEFAULT_STACK`, then add a `repo_config_missing` expectation that missing topology vars still yields `"status": "needs_repo_config"`.

- [ ] **Step 4: Run the recovery test to verify it still fails for the right reason**

Run: `bash test/evaluate-and-continue-test.sh`
Expected: FAIL because `repo_config_present()` does not require the rollout topology vars yet.

### Task 2: Persist rollout topology vars during bootstrap

**Files:**
- Modify: `scripts/bootstrap-deployment-repo.sh`

- [ ] **Step 1: Write the minimal implementation**

In `scripts/bootstrap-deployment-repo.sh`, add:

```bash
gh variable set STACKS --repo "${DEPLOYMENT_REPO}" --body "${STACKS}"
gh variable set PROMOTION_PATH --repo "${DEPLOYMENT_REPO}" --body "${PROMOTION_PATH}"
gh variable set PREVIEW_DEFAULT_STACK --repo "${DEPLOYMENT_REPO}" --body "${PREVIEW_DEFAULT_STACK}"
```

Place them with the other shared repo variables before secrets are written.

- [ ] **Step 2: Run the focused bootstrap test**

Run: `bash test/bootstrap-deployment-repo-test.sh`
Expected: PASS

### Task 3: Require the new vars in recovery checks

**Files:**
- Modify: `scripts/evaluate-and-continue.sh`

- [ ] **Step 1: Tighten repo config validation**

Update the required repo variables list in `repo_config_present()` to include:

```bash
for required_var in PULUMI_BACKEND_URL LTBASE_RELEASES_REPO LTBASE_RELEASE_ID STACKS PROMOTION_PATH PREVIEW_DEFAULT_STACK; do
```

- [ ] **Step 2: Run the focused recovery test**

Run: `bash test/evaluate-and-continue-test.sh`
Expected: PASS

### Task 4: Run regression suite and commit

**Files:**
- Modify: none

- [ ] **Step 1: Run the regression commands**

Run:

```bash
bash test/bootstrap-deployment-repo-test.sh
bash test/evaluate-and-continue-test.sh
bash test/rollout-workflows-test.sh
```

Expected: all PASS

- [ ] **Step 2: Commit the fix**

```bash
git add scripts/bootstrap-deployment-repo.sh scripts/evaluate-and-continue.sh test/bootstrap-deployment-repo-test.sh test/evaluate-and-continue-test.sh docs/superpowers/plans/2026-03-31-issue-22-stack-vars.md
git commit -m "[codex] persist rollout topology repo vars"
```
