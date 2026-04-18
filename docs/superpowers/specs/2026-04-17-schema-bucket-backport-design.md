# Schema Bucket Backport Design

## Goal

Backport the schema publication and explicit schema apply rollout contract from `ltbase-private-deployment-demo01` into `ltbase-private-deployment` so the template can provision per-stack schema buckets, publish customer-owned schema bundles, and only advance runtime-consumed schema pointers after a successful control-plane `ensure-project` apply.

## Scope

- Add customer-owned schema support under `customer-owned/schemas/`.
- Provision and export a dedicated schema bucket per stack.
- Wire runtime Lambdas to read schema from S3 instead of packaged schema files.
- Validate customer schemas during preview.
- Publish immutable schema releases plus `schemas/published/manifest.json` during rollout.
- Call control-plane `ensure-project` explicitly after publication.
- Advance `schemas/applied/manifest.json` only after successful apply.
- Update bootstrap/config validation, tests, and docs to reflect `SCHEMA_BUCKET_<STACK>`.

## Non-Goals

- No product code changes in `ltbase.api`.
- No changes to unrelated bootstrap, OIDC, mTLS, or release flows beyond what the schema contract requires.
- No attempt to reconcile unrelated untracked files already present in the target repo.

## Design

### Infra and Config

Add `SchemaBucket` to stack configuration with a derived default of `<githubRepo>-schema-<stack>`. Validate that the schema bucket never matches the runtime bucket. Provision the schema bucket alongside the runtime bucket and export it from the Pulumi program so workflows can verify they are publishing to the same bucket that the deployed runtime expects.

### Lambda Contract

Remove reliance on packaged `FORMA_SCHEMA_DIR`. Data-plane and control-plane Lambdas will both receive schema source environment variables pointing at the schema bucket, but with different prefixes:

- data plane reads `schemas/applied`
- control plane reads `schemas/published`

Both Lambdas receive read-only access to the schema bucket.

### Workflow Contract

Preview validates Pulumi stack config and validates customer schemas in dry-run mode without uploading anything. Rollout publishes schemas after infrastructure rollout, then validates that the deployment outputs' `schemaBucket` matches the configured `SCHEMA_BUCKET_<STACK>` value, calls control-plane `ensure-project`, and only then copies the published manifest to the applied manifest.

### Bootstrap and Operator Contract

Bootstrap derives and writes `SCHEMA_BUCKET_<STACK>` repository variables and Pulumi config. Operator docs explain the split between published and applied pointers, the explicit apply gate, and the new customer-owned schema location.

## Verification

- `go test ./internal/config ./internal/services` in `infra/`
- `bash ./test/publish-schemas-test.sh`
- `bash ./test/rollout-workflows-test.sh`
- `bash ./test/bootstrap-deployment-repo-test.sh`
- `bash ./test/check-pulumi-stack-config-test.sh`
- `./test/managed-dsql-consistency-test.sh`
