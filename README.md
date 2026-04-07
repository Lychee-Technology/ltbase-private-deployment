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
- example deployment inputs such as `env.template`
- customer onboarding and bootstrap documentation

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
- `scripts/sync-template-upstream.sh`

Preferred recovery-aware bootstrap entrypoint:

- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --release-id <release>`

The bootstrap flow now also manages the customer-specific `*-oidc-discovery` companion repository, its Cloudflare Pages project and custom domain, and the per-stack read-only discovery roles that the companion publish workflow assumes.

For day-2 maintenance, the generated deployment repository can sync later template changes by running:

- `./scripts/sync-template-upstream.sh`

## Deployment Principles

- the deployment repository downloads official LTBase releases instead of building the application source code
- customers own the GitHub repository, AWS account resources, and deployment approvals
- bootstrap scripts prepare repository state and deployment configuration
- the shared Pulumi backend bucket is created once and lives in the AWS account for the first stack in `PROMOTION_PATH`
- manual preview only targets the first stack in `PROMOTION_PATH`
- automated rollout continues one hop at a time across `PROMOTION_PATH`, with customer-controlled approvals on protected target environments

## Notes

- keep local `.env` files private and out of version control
- use the documentation in `docs/` as the source of truth for customer onboarding
- if a later repository version changes the managed DSQL lifecycle, follow the docs shipped with that version
