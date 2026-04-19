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
- deployment workflows validate schemas in preview, then publish versioned bundles to each stack's dedicated schema bucket during rollout
- schema publication and schema application are separate: publishing updates immutable `schemas/releases/<version>/` objects plus the published pointer at `schemas/published/manifest.json`, then an explicit control-plane `ensure-project` call applies that published version into the runtime-consumed `schemas/applied/` pointer
- the shared Pulumi backend bucket is created once and lives in the AWS account for the first stack in `PROMOTION_PATH`
- manual preview only targets the first stack in `PROMOTION_PATH`
- automated rollout continues one hop at a time across `PROMOTION_PATH`, with customer-controlled approvals on protected target environments
- `api`, `auth`, and `control-plane` are expected to use Cloudflare-proxied custom domains with API Gateway mutual TLS enabled

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
- operators must keep Cloudflare SSL mode on `Full (strict)` and enable Authenticated Origin Pulls for the API hostnames
- preview and rollout mTLS audits also require `CLOUDFLARE_API_TOKEN` to read Cloudflare zone settings for the target zone, not just DNS records
- once the mTLS rollout is applied, direct `execute-api` access is expected to fail by design
