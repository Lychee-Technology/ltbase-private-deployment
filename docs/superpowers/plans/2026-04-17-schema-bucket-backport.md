# Schema Bucket Backport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backport the schema-bucket publication and explicit `ensure-project` rollout contract from `ltbase-private-deployment-demo01` into `ltbase-private-deployment`.

**Architecture:** Extend the template's stack config and runtime resources with a dedicated schema bucket, switch Lambda schema wiring from packaged files to S3-backed prefixes, and update preview/rollout workflows so schema publication and schema application are separate steps. Keep bootstrap scripts, docs, and tests aligned with the new `SCHEMA_BUCKET_<STACK>` contract.

**Tech Stack:** Go, Pulumi, GitHub Actions, Bash

---

### Task 1: Backport infra schema bucket support

**Files:**
- Modify: `infra/internal/config/config.go`
- Modify: `infra/internal/config/config_test.go`
- Modify: `infra/internal/services/lambda.go`
- Modify: `infra/internal/services/lambda_test.go`
- Create: `infra/internal/services/schema_bucket.go`
- Create: `infra/internal/services/schema_bucket_test.go`
- Modify: `infra/cmd/ltbase-infra/main.go`

- [ ] Add `SchemaBucket` config support and validation.
- [ ] Provision schema bucket resources and export `schemaBucket` from the Pulumi program.
- [ ] Wire data-plane and control-plane Lambdas to schema-bucket env vars and read-only schema S3 access.
- [ ] Add/adjust unit tests for config defaults, validation, env wiring, and schema bucket helpers.

### Task 2: Backport workflow and script contract

**Files:**
- Modify: `.github/workflows/preview.yml`
- Modify: `.github/workflows/rollout-hop.yml`
- Modify: `scripts/bootstrap-deployment-repo.sh`
- Modify: `scripts/check-pulumi-stack-config.sh`
- Modify: `scripts/lib/bootstrap-env.sh`
- Create: `scripts/publish-schemas.sh`

- [ ] Add preview-time schema validation.
- [ ] Add rollout-time schema publication, schema bucket contract validation, explicit `ensure-project`, and applied-pointer advancement.
- [ ] Add bootstrap handling for `SCHEMA_BUCKET_<STACK>` repository variables and Pulumi config.
- [ ] Require `schemaBucket` in Pulumi stack config checks.

### Task 3: Backport tests and fixtures

**Files:**
- Modify: `test/bootstrap-deployment-repo-test.sh`
- Create: `test/check-pulumi-stack-config-test.sh`
- Create: `test/publish-schemas-test.sh`
- Modify: `test/rollout-workflows-test.sh`

- [ ] Extend bootstrap regression coverage for schema bucket variables and Pulumi config.
- [ ] Add schema publish script coverage.
- [ ] Add Pulumi stack config coverage for `schemaBucket`.
- [ ] Update rollout workflow assertions for the publish/apply split.

### Task 4: Backport docs and customer schema directory support

**Files:**
- Modify: `README.md`
- Modify: `docs/onboarding/04-prepare-env-file.md`
- Modify: `docs/onboarding/05-bootstrap-one-click.md`
- Modify: `docs/onboarding/06-bootstrap-manual.md`
- Modify: `docs/onboarding/07-first-deploy-and-managed-dsql.md`
- Modify: `env.template`
- Create: `customer-owned/schemas/.gitkeep`

- [ ] Document the customer-owned schema location and publish/apply contract.
- [ ] Document `SCHEMA_BUCKET_<STACK>` defaults and overrides in onboarding docs and `env.template`.
- [ ] Ensure the template includes the customer-owned schema directory.

### Task 5: Verify the backport

**Files:**
- No source changes expected

- [ ] Run `go test ./internal/config ./internal/services` in `infra/`.
- [ ] Run `bash ./test/publish-schemas-test.sh`.
- [ ] Run `bash ./test/rollout-workflows-test.sh`.
- [ ] Run `bash ./test/bootstrap-deployment-repo-test.sh`.
- [ ] Run `bash ./test/check-pulumi-stack-config-test.sh`.
- [ ] Run `./test/managed-dsql-consistency-test.sh`.
