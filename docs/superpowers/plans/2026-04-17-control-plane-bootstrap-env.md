# Control Plane Bootstrap Env Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the private-deployment template injects the deployment project bootstrap environment required by the control-plane Lambda at startup.

**Architecture:** Keep the fix in the deployment template. Extend the Pulumi-managed Lambda environment for the control-plane function so it receives `PROJECT_ID`, a derived `PROJECT_NAME`, `ACCOUNT_ID`, and `API_BASE_URL` from existing stack config and derived deployment values. Cover the behavior with focused Go tests and template consistency assertions.

**Tech Stack:** Go, Pulumi Go SDK, shell-based repository tests

---

### Task 1: Lock The Missing Env Contract In Tests

**Files:**
- Modify: `infra/internal/services/lambda_test.go`
- Modify: `test/managed-dsql-consistency-test.sh`

- [ ] Add a failing Go test that builds the control-plane bootstrap env map and asserts it contains `PROJECT_ID`, `PROJECT_NAME`, `ACCOUNT_ID`, and `API_BASE_URL`.
- [ ] Add a failing shell assertion that checks `infra/internal/services/lambda.go` for those env keys in the control-plane Lambda wiring.
- [ ] Run `go test ./infra/internal/services` and confirm the new env test fails because the control-plane bootstrap env is not wired yet.
- [ ] Run `./test/managed-dsql-consistency-test.sh` and confirm the new shell assertion fails for the same reason.

### Task 2: Inject Control Plane Bootstrap Env

**Files:**
- Modify: `infra/internal/config/config.go`
- Modify: `infra/internal/services/lambda.go`
- Modify: `infra/cmd/ltbase-infra/main.go`

- [ ] Add the minimal config helpers needed to derive a stable deployment `PROJECT_NAME` from existing template identity inputs instead of introducing a new required env input.
- [ ] Implement a dedicated control-plane env builder that merges the common Lambda env with `PROJECT_ID`, derived `PROJECT_NAME`, stack `ACCOUNT_ID`, and `API_BASE_URL`.
- [ ] Update the control-plane Lambda declaration to use that env builder instead of bare `commonEnv`.
- [ ] Keep data-plane/authservice env behavior unchanged except for any shared helper extraction required to avoid duplication.

### Task 3: Verify And Guard The Fix

**Files:**
- Test: `infra/internal/services/lambda_test.go`
- Test: `test/managed-dsql-consistency-test.sh`

- [ ] Re-run `go test ./infra/internal/services` and confirm the bootstrap env test passes.
- [ ] Re-run `./test/managed-dsql-consistency-test.sh` and confirm the template-level assertions pass.
- [ ] If needed, run one broader targeted test command that exercises neighboring config wiring without expanding scope.
