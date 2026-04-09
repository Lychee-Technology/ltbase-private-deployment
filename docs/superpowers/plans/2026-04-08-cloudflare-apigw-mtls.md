# Cloudflare to API Gateway mTLS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ltbase-private-deployment` deploy `api`, `auth`, and `control-plane` behind Cloudflare-proxied API Gateway custom domains that require Cloudflare client certificates via API Gateway mutual TLS.

**Architecture:** Reuse the existing per-stack runtime bucket as the API Gateway truststore bucket, upload a checked-in Cloudflare Global AOP PEM as a versioned S3 object, and wire that object into all three API Gateway custom domains. At the same time, disable each HTTP API's default `execute-api` endpoint and switch the corresponding Cloudflare DNS records to proxied mode so Cloudflare becomes the only public ingress path.

**Tech Stack:** Pulumi Go, AWS API Gateway v2, AWS S3, AWS ACM, Cloudflare DNS via Pulumi provider, Bash bootstrap scripts, Markdown docs

**Spec:** `docs/superpowers/specs/2026-04-08-cloudflare-apigw-mtls-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `infra/certs/cloudflare-origin-pull-ca.pem` | Checked-in Cloudflare Global AOP truststore PEM |
| `infra/internal/config/config.go` | Load mTLS truststore config values |
| `infra/internal/config/config_test.go` | Cover config model additions |
| `infra/internal/dns/cloudflare.go` | Support proxied DNS records |
| `infra/internal/services/apigateway.go` | Upload truststore object, disable execute-api, wire mTLS on custom domains |
| `infra/internal/services/apigateway_test.go` | Cover helper behavior for routes, mTLS config helpers, and disabled execute-api defaults |
| `env.template` | Add template-level mTLS inputs/defaults |
| `infra/Pulumi.devo.yaml.example` | Add sample mTLS config |
| `infra/Pulumi.prod.yaml.example` | Add sample mTLS config |
| `docs/onboarding/04-prepare-env-file.md` | Document required mTLS values |
| `docs/onboarding/04-prepare-env-file.zh.md` | Chinese version of mTLS input docs |
| `docs/BOOTSTRAP.md` | Add Cloudflare AOP and Full (strict) requirements |
| `docs/BOOTSTRAP.zh.md` | Chinese bootstrap notes |
| `docs/CUSTOMER_ONBOARDING.md` | Document validation and rollout caveats |
| `docs/CUSTOMER_ONBOARDING.zh.md` | Chinese onboarding notes |
| `README.md` | Update template-level deployment expectations |
| `README.zh.md` | Chinese README update |

---

### Task 1: Add the checked-in Cloudflare truststore asset

**Files:**
- Create: `infra/certs/cloudflare-origin-pull-ca.pem`

- [ ] Add the Cloudflare Global Authenticated Origin Pull CA PEM bundle at `infra/certs/cloudflare-origin-pull-ca.pem`.
- [ ] Verify the PEM uses plain ASCII line endings and contains only the certificate bundle needed for API Gateway truststore use.
- [ ] Confirm the file is small enough to live comfortably in the repo and does not contain secrets.

### Task 2: Extend deployment inputs and examples for mTLS

**Files:**
- Modify: `env.template`
- Modify: `infra/Pulumi.devo.yaml.example`
- Modify: `infra/Pulumi.prod.yaml.example`
- Modify: `docs/onboarding/04-prepare-env-file.md`
- Modify: `docs/onboarding/04-prepare-env-file.zh.md`

- [ ] Add `MTLS_TRUSTSTORE_FILE` to `env.template` with default example value `infra/certs/cloudflare-origin-pull-ca.pem`.
- [ ] Add `MTLS_TRUSTSTORE_KEY` to `env.template` with default example value `mtls/cloudflare-origin-pull-ca.pem`.
- [ ] Add matching `ltbase-infra:mtlsTruststoreFile` and `ltbase-infra:mtlsTruststoreKey` sample config to both example Pulumi stack files.
- [ ] Update onboarding docs so operators understand these are mandatory template defaults, not optional feature flags.
- [ ] State explicitly that `api`, `auth`, and `control-plane` will all be deployed behind mTLS and Cloudflare proxying.

### Task 3: Extend bootstrap config wiring for mTLS values

**Files:**
- Modify: `scripts/bootstrap-deployment-repo.sh`
- Test: `test/bootstrap-deployment-repo-test.sh`

- [ ] Require `MTLS_TRUSTSTORE_FILE` and `MTLS_TRUSTSTORE_KEY` in `scripts/bootstrap-deployment-repo.sh` alongside the existing required inputs.
- [ ] Add `pulumi config set mtlsTruststoreFile ... --stack <stack>` and `pulumi config set mtlsTruststoreKey ... --stack <stack>` to the bootstrap flow.
- [ ] Update any shell fixtures or assertions that validate the emitted `pulumi config set` commands.
- [ ] Keep the new values global, not per-stack, unless the current bootstrap code structure forces a different pattern.

### Task 4: Extend Pulumi stack config model

**Files:**
- Modify: `infra/internal/config/config.go`
- Test: `infra/internal/config/config_test.go`

- [ ] Add `MTLSTruststoreFile` and `MTLSTruststoreKey` fields to `StackConfig`.
- [ ] Load them from Pulumi config with `cfg.Require(...)`.
- [ ] Keep validation minimal: require values through config loading and avoid extra branching logic.
- [ ] Add tests that confirm the fields can coexist with the current config model and are preserved by `Validate()`.

### Task 5: Add DNS helper support for proxied API records

**Files:**
- Modify: `infra/internal/dns/cloudflare.go`
- Create: `infra/internal/dns/cloudflare_test.go`

- [ ] Extend `dns.RecordArgs` with a proxied flag.
- [ ] Keep the existing behavior explicit instead of relying on a hidden default.
- [ ] Update `NewCNAME` to pass the chosen proxied setting into the Cloudflare DNS resource.
- [ ] Preserve current non-API use cases by making call sites choose their proxy posture intentionally.
- [ ] Add `infra/internal/dns/cloudflare_test.go` covering default false and explicit true helper behavior without requiring live Cloudflare resources.

### Task 6: Upload the truststore object into the runtime bucket

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Add a small helper that resolves the absolute local path of `cfg.MTLSTruststoreFile` from the Pulumi root directory.
- [ ] Create an S3 object in the runtime bucket using `s3.NewBucketObjectv2` and the configured object key.
- [ ] Use the checked-in PEM file as the object source.
- [ ] Capture the object version output so API Gateway can reference a stable truststore version.
- [ ] Add tests for helper output, especially the truststore URI and key stability.

### Task 7: Disable default execute-api endpoints on all HTTP APIs

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Update the shared HTTP API creation code to set `DisableExecuteApiEndpoint=true` for `api`, `auth`, and `control-plane`.
- [ ] Keep existing route, stage, integration, authorizer, and mapping logic unchanged apart from the endpoint restriction.
- [ ] Add helper-level tests that lock this default into place.

### Task 8: Enable mTLS on all three API Gateway custom domains

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Add `MutualTlsAuthentication` to the shared API Gateway custom domain creation path.
- [ ] Set `TruststoreUri` to `s3://<runtimeBucket>/<mtlsTruststoreKey>`.
- [ ] Set `TruststoreVersion` from the uploaded S3 object's version output.
- [ ] Ensure all three custom domains (`api`, `auth`, `control`, using the repo's naming) consume the same stack-local truststore object.
- [ ] Preserve ACM certificate validation and API mapping behavior.

### Task 9: Switch API Cloudflare DNS records to proxied mode

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Modify: `infra/internal/dns/cloudflare.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Update the API-domain DNS calls in `apigateway.go` so `api`, `auth`, and `control-plane` records are created with `proxied=true`.
- [ ] Keep ACM validation DNS records unproxied.
- [ ] Keep any non-API records outside this flow unchanged.
- [ ] Add tests that validate API-domain records use proxying while validation records do not.

### Task 10: Update operator-facing docs for Cloudflare AOP and validation

**Files:**
- Modify: `docs/BOOTSTRAP.md`
- Modify: `docs/BOOTSTRAP.zh.md`
- Modify: `docs/CUSTOMER_ONBOARDING.md`
- Modify: `docs/CUSTOMER_ONBOARDING.zh.md`
- Modify: `README.md`
- Modify: `README.zh.md`

- [ ] Document that this template now assumes Cloudflare proxying for `api`, `auth`, and `control-plane`.
- [ ] Document that operators must set Cloudflare SSL mode to `Full (strict)`.
- [ ] Document that operators must enable Authenticated Origin Pulls in Cloudflare.
- [ ] Document that direct `execute-api` access failing is expected behavior.
- [ ] Add troubleshooting notes for likely `403` and `526` failure cases.

### Task 11: Verify infra behavior end to end

**Files:**
- Verify: `infra/internal/config/config_test.go`
- Verify: `infra/internal/services/apigateway_test.go`
- Verify: shell tests touched by bootstrap config changes

- [ ] Run `go test ./...` from `infra`.
- [ ] Run the affected shell/bootstrap tests from the repository root.
- [ ] Run `pulumi preview --stack <sample-stack>` and confirm the preview shows:
- [ ] a truststore object in the runtime bucket
- [ ] disabled `execute-api` endpoints on all three HTTP APIs
- [ ] mTLS on all three custom domains
- [ ] proxied Cloudflare DNS for `api`, `auth`, and `control-plane`
- [ ] Perform a final docs pass to ensure the rollout order and failure expectations are consistent.
