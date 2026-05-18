> **中文版：[README.zh.md](README.zh.md)**

# LTBase Private Deployment Template

This repository is the customer-facing deployment template for LTBase.

It is the seed repository used to create a customer-owned private deployment repository.

## Purpose

This repository exists to help customers deploy official LTBase releases into their own AWS accounts.

It is not the LTBase application source repository.

## What's Included

- thin wrapper workflows that call the public reusable LTBase deployment workflows
- bootstrap scripts for GitHub repository setup, AWS foundation setup, and Pulumi stack configuration
- a Pulumi program wrapper at `infra/scripts/pulumi-wrapper.sh` that uses a prebuilt binary when available and falls back to local source build when it is not
- example deployment inputs such as `env.template`
- customer onboarding and bootstrap documentation
- customer-owned production schema files under `customer-owned/schemas/`

## Start Here

If you are onboarding a new customer deployment, start with:

- full onboarding runbook: [`docs/CUSTOMER_ONBOARDING.md`](docs/CUSTOMER_ONBOARDING.md)
- quick bootstrap checklist: [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md)

Recommended reading order for new deployments:

- prerequisites and access checks: [`docs/onboarding/01-prerequisites.md`](docs/onboarding/01-prerequisites.md)
- `.env` preparation and derived values: [`docs/onboarding/04-prepare-env-file.md`](docs/onboarding/04-prepare-env-file.md)
- one-click bootstrap readiness and preflight: [`docs/onboarding/05-bootstrap-one-click.md`](docs/onboarding/05-bootstrap-one-click.md)
- manual bootstrap stages and verification points: [`docs/onboarding/06-bootstrap-manual.md`](docs/onboarding/06-bootstrap-manual.md)
- first deploy, approvals, and managed DSQL follow-up: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](docs/onboarding/07-first-deploy-and-managed-dsql.md)

The onboarding docs support generic multi-stack topologies. When they show names like `devo` or `prod`, treat them as examples only.

## Current Control Plane UI Model

In the current repository version, operators should treat the Control Plane UI as a Cloudflare Pages-hosted admin site rooted at `CONTROLPLANE_UI_DOMAIN`.

- `preview` remains infra-only; it validates release selection, stack config, and Pulumi changes, but does not publish the Control Plane UI
- the current bootstrap scripts still use companion-style Control Plane UI setup, including a separate `*-controlplane-ui` repository, Cloudflare Pages project, custom domain binding, DNS wiring, and companion repository variables
- the deployment repository is still the operator-facing source of truth for the UI inputs that feed that setup, including `CONTROLPLANE_UI_DOMAIN`, stack browser config values, auth provider config alignment, and Control Plane CORS inputs
- runtime config for the UI is browser-safe only; do not place server-side secrets, service-role keys, or admin credentials into the Control Plane UI config
- operator identity providers must allow `https://<CONTROLPLANE_UI_DOMAIN>/auth/callback`, and the deployed Control Plane API must allow the admin domain through its CORS configuration

## Documentation Map

Main entrypoints:

- [`docs/CUSTOMER_ONBOARDING.md`](docs/CUSTOMER_ONBOARDING.md)
- [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md)

Detailed onboarding guides:

- prerequisites: [`docs/onboarding/01-prerequisites.md`](docs/onboarding/01-prerequisites.md)
- create repo and clone: [`docs/onboarding/02-create-repo-and-clone.md`](docs/onboarding/02-create-repo-and-clone.md)
- create OIDC and deploy roles: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](docs/onboarding/03-create-oidc-and-deploy-roles.md)
- prepare `.env`: [`docs/onboarding/04-prepare-env-file.md`](docs/onboarding/04-prepare-env-file.md)
- one-click bootstrap: [`docs/onboarding/05-bootstrap-one-click.md`](docs/onboarding/05-bootstrap-one-click.md)
- manual bootstrap: [`docs/onboarding/06-bootstrap-manual.md`](docs/onboarding/06-bootstrap-manual.md)
- first deploy and managed DSQL handling: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](docs/onboarding/07-first-deploy-and-managed-dsql.md)
- day-2 operations: [`docs/onboarding/08-day-2-operations.md`](docs/onboarding/08-day-2-operations.md)

If you are using the recovery-aware path, treat these as the key operator guides:

- `docs/CUSTOMER_ONBOARDING.md`
- `docs/onboarding/05-bootstrap-one-click.md`
- `docs/onboarding/07-first-deploy-and-managed-dsql.md`

## Bootstrap Entrypoints

Important files and scripts:

- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-oidc-discovery-companion.sh`
- `scripts/bootstrap-controlplane-ui-companion.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/update-sync-template-tooling.sh`
- `scripts/sync-template-upstream.sh`

Preferred recovery-aware bootstrap entrypoint:

- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --release-id <release>`

The bootstrap flow now also manages the customer-specific `*-oidc-discovery` companion repository, its Cloudflare Pages project, its custom domain binding, the required zone-level CNAME pointing at `${OIDC_DISCOVERY_PAGES_PROJECT}.pages.dev`, and the per-stack read-only discovery roles that the companion publish workflow assumes.

In the current repository version, `scripts/bootstrap-controlplane-ui-companion.sh` also manages a customer-specific `*-controlplane-ui` companion repository, its Cloudflare Pages project, its custom domain binding, the required zone-level CNAME pointing at `${CONTROLPLANE_UI_PAGES_PROJECT}.pages.dev`, and the runtime config JSON published to `public/ltbase-controlplane.config.json` from the companion repository variable `CONTROLPLANE_UI_STACK_CONFIG`.

The current control plane UI bootstrap emits both Firebase and Supabase browser providers for every stack. It also tries to reuse provider names from each stack's `AUTH_PROVIDER_CONFIG_FILE_<STACK>` when those deployment-owned records match the Firebase and Supabase issuers implied by the public browser config. That means each stack in `.env` must provide all of these public, browser-safe values before running `scripts/bootstrap-controlplane-ui-companion.sh`:

- `FIREBASE_API_KEY_<STACK>`
- `FIREBASE_PROJECT_ID_<STACK>`
- `SUPABASE_URL_<STACK>`
- `SUPABASE_ANON_KEY_<STACK>`

The same four values are now also written into each Pulumi stack config by `scripts/bootstrap-deployment-repo.sh`. The infra program exports a browser-safe `controlplaneUiStackConfig` output that official rollout workflows can aggregate into the shared control plane UI runtime config.

For day-2 maintenance, the generated deployment repository can sync later template changes by running:

- `./scripts/update-sync-template-tooling.sh`
- `./scripts/sync-template-upstream.sh`

Use `./scripts/update-sync-template-tooling.sh` first when you want the latest sync helper and its regression test from the template. Then run `./scripts/sync-template-upstream.sh` to sync template-managed files. The template sync preserves local `.env` files, `infra/Pulumi.*.yaml`, the entire `customer-owned/` tree, customer-owned `infra/auth-providers.*.json`, and the sync helper's own script/test files.

This template repository only tracks `infra/auth-providers.*.json.example`. A generated customer deployment repository should create and maintain the real `infra/auth-providers.<stack>.json` files itself, and may commit those customer-specific files in that generated repository.

## Deployment Principles

- the deployment repository downloads official LTBase releases instead of building the application source code
- official workflows may also download an upstream-template-bound prebuilt `ltbase-infra` binary from `Lychee-Technology/ltbase-private-deployment-binaries` to avoid recompiling the Pulumi Go program on every run
- only the upstream template repository publishes those prebuilt infra binaries; generated customer deployment repositories consume them only
- customers own the GitHub repository, AWS account resources, and deployment approvals
- bootstrap scripts prepare repository state and deployment configuration
- current Control Plane UI operator inputs still originate in the deployment repository even when companion-style setup scripts publish or mirror those values elsewhere
- deployment workflows validate schemas in preview, then publish versioned bundles to each stack's dedicated schema bucket during rollout
- schema publication and schema application are separate: publishing updates immutable `schemas/releases/<version>/` objects plus the published pointer at `schemas/published/manifest.json`, then an explicit control-plane `ensure-project` call applies that published version into the runtime-consumed `schemas/applied/` pointer
- the shared Pulumi backend bucket is created once and lives in the AWS account for the first stack in `PROMOTION_PATH`
- manual preview only targets the first stack in `PROMOTION_PATH`
- automated rollout continues one hop at a time across `PROMOTION_PATH`, with customer-controlled approvals on protected target environments
- `api`, `auth`, and `control-plane` are expected to use Cloudflare-proxied custom domains with API Gateway mutual TLS enabled

## Control Plane UI Rollout

Generated deployment repositories now pass three optional values through to the shared `ltbase-deploy-workflows` rollout workflow:

- `CONTROLPLANE_UI_DOMAIN`
- `CONTROLPLANE_UI_PAGES_PROJECT`
- `STACKS`

When those values are present and the upstream release contract includes the official UI artifact, rollout can publish the control plane UI directly from release assets instead of relying only on the companion-repo publish flow.

The rollout-side runtime config is built from per-stack Pulumi outputs:

- each stack must export `controlplaneUiStackConfig`
- only stacks with a complete output are included in the deployed `ltbase-controlplane.config.json`
- the current rollout target must be included, or rollout fails
- `redirectUri` is derived during rollout from `https://${CONTROLPLANE_UI_DOMAIN}/auth/callback`

Important: the current public release contract still does not document the control plane UI artifact. Until that contract is updated in `ltbase.api` / `ltbase-releases`, the new rollout-side UI deploy path remains blocked on the release bundle not yet containing the expected artifact.

## Notes

- keep local `.env` files private and out of version control
- use the documentation in `docs/` as the source of truth for customer onboarding
- keep customer-specific Forma schemas in `customer-owned/schemas/*.json`; deployment workflows publish them to the stack `SCHEMA_BUCKET`
- keep `infra/.pulumi/bin/ltbase-infra` out of version control; the wrapper can recreate it locally and official workflows may preinstall it temporarily
- `__ref__/template-provenance.json` records the upstream template commit and `build_fingerprint` that official workflows use when looking up prebuilt infra binaries
- publishing into `ltbase-private-deployment-binaries` requires a repo secret named `LTBASE_PRIVATE_DEPLOYMENT_BINARIES_TOKEN` in the upstream template repository
- generated customer deployment repositories still receive `.github/workflows/build-infra-binary.yml` from the template, but the workflow is repo-guarded and is skipped outside `Lychee-Technology/ltbase-private-deployment`
- official workflows only install a prebuilt infra binary when the synced template provenance and `build_fingerprint` exactly match an upstream published manifest; otherwise they fall back to source build
- if a later repository version changes the managed DSQL lifecycle, follow the docs shipped with that version
- if a later repository version changes the Control Plane UI deployment model, follow the docs shipped with that version; this README intentionally documents the current companion-style setup that still exists in this repository
- operators must keep Cloudflare SSL mode on `Full (strict)` and enable Authenticated Origin Pulls for the API hostnames
- preview and rollout mTLS audits also require `CLOUDFLARE_API_TOKEN` to read Cloudflare zone settings for the target zone, not just DNS records
- once the mTLS rollout is applied, direct `execute-api` access is expected to fail by design
