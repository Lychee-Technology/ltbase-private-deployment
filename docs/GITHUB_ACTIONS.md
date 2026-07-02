> **中文版：[GITHUB_ACTIONS.zh.md](GITHUB_ACTIONS.zh.md)**

# GitHub Actions Reference

This document describes every GitHub Actions workflow shipped in `.github/workflows/` of this deployment repository: what each one does, when you should run it, which inputs it accepts (with examples), and which GitHub Variables and Secrets it depends on.

For the end-to-end deployment story, read [`CUSTOMER_ONBOARDING.md`](CUSTOMER_ONBOARDING.md) first. This page is a per-workflow reference you can return to when you need the exact inputs.

## How to Read This Page

- **Trigger** — how the workflow starts (`workflow_dispatch` = manual "Run workflow" button or `gh workflow run`, `workflow_call` = called by another workflow, `push`/`pull_request` = automatic).
- **Inputs** — parameters you supply when dispatching. Every input example is also shown as a `gh workflow run` command.
- **Config used** — the GitHub repository Variables (`vars.*`) and Secrets (`secrets.*`) the workflow reads. Bootstrap scripts write most of these automatically; see [`onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md).
- Run all `gh workflow run` commands with `--ref main`. Several OIDC roles trust only the default branch, so dispatching from another branch will fail AWS role assumption.

## Workflow Map

| Workflow | Name in GitHub UI | Primary use | You run it? |
|----------|-------------------|-------------|-------------|
| [`preview.yml`](#previewyml--preview-ltbase-blueprint) | Preview LTBase Blueprint | Validate config + Pulumi diff before deploying | Yes |
| [`rollout.yml`](#rolloutyml--rollout-ltbase-release) | Rollout LTBase Release | Deploy a release across the whole promotion path | Yes (main entrypoint) |
| [`deploy-devo.yml`](#deploy-devoyml--deploy-ltbase-start-stack) | Deploy LTBase Start Stack | Deploy only the first stack, then stop | Yes (occasionally) |
| [`promote-prod.yml`](#promote-prodyml--promote-ltbase-between-stacks) | Promote LTBase Between Stacks | Manually run one adjacent promotion hop | Yes (recovery) |
| [`rollout-hop.yml`](#rollout-hopyml--rollout-ltbase-promotion-hop) | Rollout LTBase Promotion Hop | Reusable single-hop engine used by the above | Rarely, directly |
| [`publish-oidc-discovery.yml`](#publish-oidc-discoveryyml--publish-oidc-discovery-documents) | Publish OIDC Discovery Documents | Manual recovery re-publish of the OIDC discovery site | Rarely (recovery) |
| [`build-infra-binary.yml`](#build-infra-binaryyml--build-infra-binary) | Build Infra Binary | Publish prebuilt infra binaries (upstream only) | No |
| [`test.yml`](#testyml--test) | Test | Run the repo test suite (upstream only) | No |

---

## `preview.yml` — Preview LTBase Blueprint

**What it does.** Validates the target stack before any deployment. It checks that `infra/Pulumi.<stack>.yaml` contains the required `ltbase-infra:*` config keys, dry-run-validates your `customer-owned/schemas/*.json` against the stack schema bucket (nothing is uploaded), runs the shared `preview-stack.yml` reusable workflow to produce a Pulumi diff, and finally audits Cloudflare/API Gateway mTLS posture.

**When to use it.**
- Before the first rollout of a stack.
- Any time you change stack configuration, the release selection, or other deployment inputs. Preview first, then rollout.
- To confirm a Pulumi diff is within the scope you expect.

**When not to use it.**
- To deploy. Preview is infra-only: it does not run `pulumi up`, does not publish the Control Plane UI, and does not upload schemas.
- To preview a later stack. Manual preview only supports the first stack in `PROMOTION_PATH`; any other value fails fast.

**Trigger.** `workflow_dispatch` (manual).

**Inputs.**

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `target_stack` | No | string | first stack in `PROMOTION_PATH` | Stack to preview. Must be the first promotion stack. |
| `release_id` | No | string | `vars.LTBASE_RELEASE_ID` | Official LTBase release tag to preview. |

**Examples.**

```bash
# Preview the first promotion stack using the repo default release
gh workflow run preview.yml --ref main

# Preview the first stack explicitly and override the release
gh workflow run preview.yml -f target_stack=devo -f release_id=v1.0.23 --ref main
```

**Config used.**
- Variables: `PROMOTION_PATH` (or `STACKS`), `LTBASE_RELEASE_ID`, `PULUMI_BACKEND_URL`, `AWS_REGION_<STACK>`, `PULUMI_SECRETS_PROVIDER_<STACK>`, `SCHEMA_BUCKET_<STACK>`, `LTBASE_RELEASES_REPO`, `STACKS`.
- Secrets: `AWS_ROLE_ARN_<STACK>`, `LTBASE_RELEASES_TOKEN`, `CLOUDFLARE_API_TOKEN`.

**Notes.**
- The mTLS audit reads per-stack values from `infra/Pulumi.<stack>.yaml` (`ltbase-infra:awsRegion`, `apiDomain`, `controlPlaneDomain`, `authDomain`, `runtimeBucket`, `cloudflareZoneId`). Keep that file complete or the audit fails.
- `CLOUDFLARE_API_TOKEN` must be able to read zone settings, not just DNS records, for the audit to pass.

---

## `rollout.yml` — Rollout LTBase Release

**What it does.** The recommended deployment entrypoint. It resolves the first stack in `PROMOTION_PATH` and calls `rollout-hop.yml` with `continue_chain: true`, so after each successful hop it automatically dispatches the next stack in the promotion path. Protected target environments still pause for GitHub environment approval before they deploy.

**When to use it.**
- To deploy a release across your entire promotion path in one action.
- For routine upgrades: update `LTBASE_RELEASE_ID`, run `preview.yml`, then run `rollout.yml`.

**When not to use it.**
- When you want to deploy only the first stack and stop — use [`deploy-devo.yml`](#deploy-devoyml--deploy-ltbase-start-stack).
- When you want to replay a single hop — use [`promote-prod.yml`](#promote-prodyml--promote-ltbase-between-stacks).
- Do not change the release ID midway through a promotion path; keep the same release across all hops.

**Trigger.** `workflow_dispatch` (manual).

**Inputs.**

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `release_id` | Yes | string | — | Official LTBase release tag to roll out across the full promotion path. |

**Examples.**

```bash
# Roll out release v1.0.23 across the whole promotion path
gh workflow run rollout.yml -f release_id=v1.0.23 --ref main
```

**Config used.**
- Inherits all repository Variables and Secrets (`secrets: inherit`) and passes them down to `rollout-hop.yml`. See the `rollout-hop.yml` config list below for the full set.

**Notes.**
- The chain advances one hop at a time. Each protected stack requires you to approve its GitHub environment gate before it deploys.
- Publishing OIDC discovery is automatic: each hop in `rollout-hop.yml` publishes the deployed promotion-path prefix before rollout (placeholder key) and again after rollout (real KMS key). [`publish-oidc-discovery.yml`](#publish-oidc-discoveryyml--publish-oidc-discovery-documents) is only needed for manual recovery.

---

## `deploy-devo.yml` — Deploy LTBase Start Stack

**What it does.** Deploys only the first stack in `PROMOTION_PATH` and then stops. It resolves the start stack and calls `rollout-hop.yml` with `continue_chain: false`, so no further hops are dispatched.

**When to use it.**
- When you want to deploy or redeploy just the start stack without triggering the full promotion chain.
- During early setup or debugging of the first environment.

**When not to use it.**
- For a normal full deployment — use [`rollout.yml`](#rolloutyml--rollout-ltbase-release).
- To deploy a non-start stack. Despite the historical `devo` name, it always targets whatever stack is first in `PROMOTION_PATH`, not a stack literally named `devo`.

**Trigger.** `workflow_dispatch` (manual).

**Inputs.**

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `release_id` | Yes | string | — | Official LTBase release tag to deploy into the first promotion stack. |

**Examples.**

```bash
# Deploy only the start stack with release v1.0.23
gh workflow run deploy-devo.yml -f release_id=v1.0.23 --ref main
```

**Config used.**
- Inherits all repository Variables and Secrets (`secrets: inherit`) and passes them to `rollout-hop.yml`.

**Notes.**
- The workflow file name is historical. The actual target is `PROMOTION_PATH[0]`, whatever it is named.

---

## `promote-prod.yml` — Promote LTBase Between Stacks

**What it does.** Runs exactly one promotion hop between two adjacent stacks. It calls `rollout-hop.yml` with your explicit `from_stack` and `to_stack` and `continue_chain: false`. `rollout-hop.yml` validates that `from_stack → to_stack` is an adjacent, forward hop in `PROMOTION_PATH` and fails fast on invalid jumps.

**When to use it.**
- Recovery: a hop deployed but the automatic chain did not continue, and you want to advance one more hop.
- To promote from one validated stack to the next adjacent stack only.

**When not to use it.**
- For the full path — use [`rollout.yml`](#rolloutyml--rollout-ltbase-release).
- To skip environments. Non-adjacent jumps (e.g., skipping an intermediate stack) fail immediately.

**Trigger.** `workflow_dispatch` (manual).

**Inputs.**

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `release_id` | Yes | string | — | Official LTBase release tag to promote. |
| `from_stack` | Yes | string | — | Current deployed stack in `PROMOTION_PATH`. |
| `to_stack` | Yes | string | — | Next stack in `PROMOTION_PATH` (must be adjacent to `from_stack`). |

**Examples.**

```bash
# Promote from devo to prod using release v1.0.23
gh workflow run promote-prod.yml \
  -f release_id=v1.0.23 \
  -f from_stack=devo \
  -f to_stack=prod \
  --ref main
```

**Config used.**
- Inherits all repository Variables and Secrets (`secrets: inherit`) and passes them to `rollout-hop.yml`.

**Notes.**
- The target stack still requires its GitHub environment approval before deploying.

---

## `rollout-hop.yml` — Rollout LTBase Promotion Hop

**What it does.** The single-hop deployment engine that every deploy/rollout/promote workflow above delegates to. For one target stack it: validates the Pulumi stack config, waits for approval on protected stacks, renders the Control Plane UI runtime config, publishes OIDC discovery for the deployed promotion-path prefix **before** rollout (placeholder key for the not-yet-deployed target so API Gateway can create its JWT authorizer), runs the shared `rollout-hop.yml` reusable workflow (`pulumi up`, control-plane UI publish, managed DSQL reconcile + second apply), republishes OIDC discovery for the prefix **after** rollout (now with the real KMS-backed key, polling until the placeholder is actually replaced), publishes customer schemas, invokes the control-plane `ensure-project` apply, advances the applied-schema pointer, audits mTLS, and — when `continue_chain` is true and the post-rollout discovery publish succeeded — dispatches the next hop.

**When to use it.**
- Normally you do not run this directly; use `rollout.yml`, `deploy-devo.yml`, or `promote-prod.yml`.
- Run it directly only for advanced recovery when you need precise control over a single hop's inputs (including `continue_chain`).

**When not to use it.**
- For routine deployments. The wrapper workflows set the correct inputs for you.

**Trigger.** `workflow_call` (used by other workflows) and `workflow_dispatch` (manual, advanced).

**Inputs.**

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `release_id` | Yes | string | `vars.LTBASE_RELEASE_ID` (dispatch) | Official LTBase release tag to deploy. |
| `target_stack` | Yes | string | — | Stack to deploy in this hop. |
| `from_stack` | No | string | `""` | Current stack before this hop; when set, the hop must be adjacent and forward. |
| `continue_chain` | No | boolean | `false` | Dispatch the next hop automatically after success. |

**Outputs (when called by another workflow).** `release_id`, `target_stack`, `next_stack`, `deployment_outputs_json`.

**Examples.**

```bash
# Advanced: manually run a single hop into prod and continue the chain
gh workflow run rollout-hop.yml \
  -f release_id=v1.0.23 \
  -f target_stack=prod \
  -f from_stack=devo \
  -f continue_chain=false \
  --ref main
```

**Config used.**
- Variables: `LTBASE_RELEASE_ID`, `STACKS`, `PROMOTION_PATH`, `PULUMI_BACKEND_URL`, `AWS_REGION_<STACK>`, `PULUMI_SECRETS_PROVIDER_<STACK>`, `SCHEMA_BUCKET_<STACK>`, `LTBASE_RELEASES_REPO`, `CLOUDFLARE_ACCOUNT_ID`, `CONTROLPLANE_UI_PAGES_PROJECT`, `CONTROLPLANE_UI_STACK_CONFIG`.
- Secrets: `AWS_ROLE_ARN_<STACK>`, `LTBASE_RELEASES_TOKEN`, `CLOUDFLARE_API_TOKEN`.

**Notes.**
- Approval is required for every stack that is not the start stack (`approval_required=true`); a canary also runs for those hops.
- Schema publish and schema apply are separate: `schemas/published/manifest.json` advances on publish, `schemas/applied/manifest.json` only advances after `ensure-project` succeeds.
- When `continue_chain=true` and a `next_stack` exists, the workflow dispatches itself for the next hop.

---

## `publish-oidc-discovery.yml` — Publish OIDC Discovery Documents

**What it does.** Manual recovery / re-publish entry point. Generates the OIDC discovery documents for one or more stacks and direct-uploads them to the OIDC discovery Cloudflare Pages project. It shares the `.github/actions/publish-oidc-discovery` composite action with the automatic pre/post publish jobs in `rollout-hop.yml`.

> Normal deployments do **not** need this workflow: `rollout-hop.yml` publishes OIDC discovery automatically on every hop. Use it only to recover from a failed automatic publish or to force-refresh keys.

**When to use it.**
- To re-publish after a failed automatic publish, or to force-refresh a stack's keys.
- To refresh all stacks at once.

**When not to use it.**
- As a normal step after rollout — the rollout hop already publishes discovery automatically.
- From a non-default branch. The per-stack OIDC discovery IAM roles trust only the default branch; dispatching from another branch fails role assumption.

**Trigger.** `workflow_dispatch` (manual).

**Inputs.**

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `target_stack` | No | string | `all` | Stack to publish: `all` or a specific stack name. |
| `target_stacks` | No | string | `""` | Optional CSV of stacks (e.g. `devo,prod`). Overrides `target_stack` when set. |

**Examples.**

```bash
# Recovery: republish a single stack
gh workflow run publish-oidc-discovery.yml -f target_stack=devo --ref main

# Recovery: refresh all stacks
gh workflow run publish-oidc-discovery.yml -f target_stack=all --ref main

# Recovery: republish an explicit promotion-path prefix
gh workflow run publish-oidc-discovery.yml -f target_stacks=devo,prod --ref main
```

**Config used.**
- Variables: `OIDC_DISCOVERY_DOMAIN`, `OIDC_DISCOVERY_STACK_CONFIG`, `OIDC_DISCOVERY_PAGES_PROJECT`, `CLOUDFLARE_ACCOUNT_ID`.
- Secrets: `CLOUDFLARE_API_TOKEN`.

**Notes.**
- When a stack's authservice KMS key does not exist yet, the workflow **fails**: the placeholder JWKS fallback (`ALLOW_PLACEHOLDER`) is reserved for the automatic pre-rollout publish in `rollout-hop.yml`. Publish a stack only after its first rollout has created the key.
- The workflow fails clearly if `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, or `OIDC_DISCOVERY_PAGES_PROJECT` is missing.
- It shares a repository-level concurrency group with the automatic pre/post publish jobs in `rollout-hop.yml`, so discovery publishes never overlap.

---

## `build-infra-binary.yml` — Build Infra Binary

**What it does.** Builds the `ltbase-infra` Pulumi program for `linux-amd64` and `linux-arm64`, then publishes those prebuilt binaries plus a manifest (with a `build_fingerprint`) as a release in `Lychee-Technology/ltbase-private-deployment-binaries`.

**When to use it.**
- You almost never run this. It is guarded by `if: github.repository == 'Lychee-Technology/ltbase-private-deployment'` and is skipped in generated customer deployment repositories.
- Only the upstream template repository publishes prebuilt infra binaries; customer repos consume them.

**When not to use it.**
- In a customer deployment repository. It will be skipped.

**Trigger.** `workflow_dispatch` (manual) and `push` to `main` touching `infra/**` or the workflow file itself.

**Inputs.** None.

**Config used.**
- Secrets: `LTBASE_PRIVATE_DEPLOYMENT_BINARIES_TOKEN` (only present in the upstream template repository).

**Notes.**
- Customer workflows only install a prebuilt binary when the synced `__ref__/template-provenance.json` and its `build_fingerprint` exactly match an upstream published manifest; otherwise `infra/scripts/pulumi-wrapper.sh` falls back to local source build.

---

## `test.yml` — Test

**What it does.** Runs the repository's shell test suite (`test/*-test.sh`) after ensuring `jq` and `python3` are available.

**When to use it.**
- It runs automatically on `pull_request` and on `push` to `main`, and can be dispatched manually. It is guarded by `if: github.repository == 'Lychee-Technology/ltbase-private-deployment'`, so it is skipped in customer deployment repositories.

**When not to use it.**
- In a customer deployment repository. It will be skipped.

**Trigger.** `workflow_dispatch` (manual), `pull_request`, and `push` to `main`.

**Inputs.** None.

**Config used.** None (read-only checkout).

**Notes.**
- Fails if no `test/*-test.sh` files are found or any test fails.

---

## Related Documents

| Document | Purpose |
|----------|---------|
| [CUSTOMER_ONBOARDING.md](CUSTOMER_ONBOARDING.md) | Complete from-scratch deployment guide |
| [BOOTSTRAP.md](BOOTSTRAP.md) | Quick bootstrap checklist |
| [onboarding/04-prepare-env-file.md](onboarding/04-prepare-env-file.md) | `.env`, Variables, and Secrets reference |
| [onboarding/07-first-deploy-and-managed-dsql.md](onboarding/07-first-deploy-and-managed-dsql.md) | First preview/rollout walkthrough |
| [onboarding/08-day-2-operations.md](onboarding/08-day-2-operations.md) | Day-2 operations and upgrades |
