> **中文版：[CUSTOMER_ONBOARDING.zh.md](CUSTOMER_ONBOARDING.zh.md)**

# LTBase Customer Onboarding Runbook

This document is the main entry point for customers deploying LTBase with the private deployment template.

## What This Document Is For

- explain the overall deployment model
- show the full onboarding order from preparation to first promotion-path rollout
- link to detailed step-by-step guides for every longer operation

## Deployment Model

Your LTBase deployment uses three repositories:

- `ltbase-deploy-workflows`
  - reusable public GitHub Actions workflows maintained by LTBase
- `ltbase-releases`
  - private release repository containing official LTBase application artifacts
- your deployment repository
  - a private repository created from `ltbase-private-deployment`
  - your customer-owned repo that stores workflows, bootstrap scripts, and Pulumi stack configuration

Your deployment repository does not build LTBase application source code. It downloads an official LTBase release and deploys it into your AWS account.

## End State

When onboarding is complete, you should have:

- one private deployment repository based on this template
- one GitHub OIDC trust relationship in each AWS account used for deployment
- one deploy role per configured stack in `STACKS`
- one Pulumi state bucket
- one KMS alias for Pulumi secrets encryption
- GitHub repository secrets and variables configured
- a first promotion stack ready for preview and deployment
- each later stack in `PROMOTION_PATH` ready for protected promotion after the previous hop is validated

## Before You Start

You will need:

- a GitHub organization or account that can host a private repository
- one or more AWS accounts that will host the stacks listed in `STACKS`
- a Cloudflare zone for your domains
- permission to create or update IAM roles, IAM OIDC providers, S3 buckets, and KMS keys
- a customer-specific `LTBASE_RELEASES_TOKEN`
- a Gemini API key

For the detailed preparation checklist, use:

- [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)

## Full Onboarding Order

Follow the steps in this order:

### Step 1 - Prepare prerequisites

- Read: [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- Covers: accounts, permissions, tokens, domains, local tools

### Step 2 - Create the deployment repository and clone it

- Read: [`docs/onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- Covers: creating the private repo from template, cloning locally, verifying repository layout

### Step 3 - Prepare OIDC and deploy roles

- Read: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- Covers: OIDC provider, per-stack deploy roles, trust policy, permissions policy
- If using one-click bootstrap, review only; the script creates these automatically

### Step 4 - Prepare the local `.env` file

- Read: [`docs/onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- Covers: every required `.env` field, where each value comes from, what must not be edited manually

### Step 5 - Choose a bootstrap path

If you have enough GitHub and AWS permissions, use the one-click path:

- [`docs/onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)

If you want to control each stage manually, use the manual path:

- [`docs/onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)

### Step 6 - Run the first preview and deployment

- Read: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- Covers: preview, promotion-path rollout, protected-environment approvals, managed DSQL post-bootstrap handling

### Step 7 - Day-2 operations

- Read: [`docs/onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- Covers: release upgrades, repeated previews, deployment rhythm, operational reminders

## Required GitHub Secrets and Variables

Set these repository secrets in your deployment repository:

- `AWS_ROLE_ARN_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

Set these repository variables in your deployment repository:

- `AWS_REGION_<STACK>` for every stack in `STACKS`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

The bootstrap scripts write these values for you when `.env` is correct.

## Important Managed DSQL Note

For managed deployments, do not manually provide an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword`.

At the time of writing, this repository's bootstrap scripts use a bootstrap-safe split: bootstrap prepares GitHub and Pulumi state first, and `scripts/reconcile-managed-dsql-endpoint.sh` publishes the managed DSQL endpoint after infrastructure exists.

Aurora DSQL itself is created by the Pulumi blueprint. You do not supply an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` for managed deployments.

The current repository version uses a bootstrap-safe flow:

- `bootstrap-all.sh` and `bootstrap-deployment-repo.sh` prepare configuration only
- the first real infrastructure apply creates the managed DSQL cluster
- `scripts/reconcile-managed-dsql-endpoint.sh` resolves the authoritative endpoint from AWS by using the Pulumi-exported `dsqlClusterIdentifier`
- the reconcile step publishes the resolved endpoint into stack config as `dsqlEndpoint`
- after reconciliation, run the next preview/deploy cycle so Lambda environment configuration picks up the managed endpoint

## Operational Constraints

- `LTBASE_RELEASES_TOKEN` is only for downloading official LTBase releases
- local `.env` files contain secrets and must never be committed
- the template repository does not auto-run preview on pull requests because it has no live customer credentials
- manual preview only supports the first stack in `PROMOTION_PATH`
- protected promotions happen in your own repository through per-stack GitHub environment gates

## Related Documents

- quick checklist: [`docs/BOOTSTRAP.md`](BOOTSTRAP.md)
- prerequisites: [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- create repo and clone: [`docs/onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- create OIDC and roles: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- prepare `.env`: [`docs/onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- one-click bootstrap: [`docs/onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)
- manual bootstrap: [`docs/onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- first deploy: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- day-2 operations: [`docs/onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
