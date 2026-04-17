# Managed DSQL Rollout Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure customer rollout workflows reconcile the managed DSQL endpoint and redeploy Lambda configuration so control plane and other functions receive `DSQL_ENDPOINT` in the same rollout path.

**Architecture:** Keep managed DSQL endpoint resolution in deployment-owned workflow logic. Enable the reconcile step from the customer template and update the shared rollout workflow so it runs a second `pulumi up` after reconciliation, making the new `dsqlEndpoint` config effective for Lambda environment variables before downstream verification and canary actions.

**Tech Stack:** GitHub Actions YAML, shell-based repository tests, Pulumi workflow wrappers

---

### Task 1: Private Deployment Workflow Wiring

**Files:**
- Modify: `.github/workflows/rollout-hop.yml`
- Test: `test/rollout-workflows-test.sh`

- [ ] Add a failing shell assertion requiring `reconcile_managed_dsql_endpoint: true` in `.github/workflows/rollout-hop.yml`.
- [ ] Run `./test/rollout-workflows-test.sh` and confirm it fails because the workflow does not yet pass that input.
- [ ] Update `.github/workflows/rollout-hop.yml` to pass `reconcile_managed_dsql_endpoint: true` to the shared workflow.
- [ ] Re-run `./test/rollout-workflows-test.sh` and confirm it passes.

### Task 2: Shared Workflow Second Apply

**Files:**
- Modify: `.github/workflows/rollout-hop.yml`
- Test: `test/generic-workflows-test.sh`

- [ ] Add failing shell assertions that require the rollout workflow to expose `reconcile_managed_dsql_endpoint`, invoke the reconcile action, and run a second `command: up` gated by that input after reconciliation.
- [ ] Run `./test/generic-workflows-test.sh` and confirm it fails because the second apply step is missing.
- [ ] Update `.github/workflows/rollout-hop.yml` so when `reconcile_managed_dsql_endpoint` is true it performs a second `run-pulumi` apply after the reconcile action and before output capture/canaries.
- [ ] Re-run `./test/generic-workflows-test.sh` and confirm it passes.

### Task 3: Managed DSQL Operator Docs

**Files:**
- Modify: `docs/CUSTOMER_ONBOARDING.md`
- Modify: `docs/onboarding/07-first-deploy-and-managed-dsql.md`

- [ ] Update managed DSQL docs to explain that official rollout workflows now reconcile `dsqlEndpoint` and perform a second apply automatically.
- [ ] Keep the manual `scripts/reconcile-managed-dsql-endpoint.sh` guidance as a recovery path when operators need to repair an existing stack outside the official workflow.

### Task 4: Focused Verification

**Files:**
- Test: `test/rollout-workflows-test.sh`
- Test: `test/managed-dsql-consistency-test.sh`

- [ ] Run `./test/rollout-workflows-test.sh`.
- [ ] Run `./test/managed-dsql-consistency-test.sh`.
- [ ] Confirm both pass and note any residual manual recovery scenarios.
