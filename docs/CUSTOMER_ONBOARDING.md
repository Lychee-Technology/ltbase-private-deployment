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

This onboarding set supports generic multi-stack deployments. Names such as `devo` and `prod` are examples, not hard-coded requirements.

## End State

When onboarding is complete, you should have:

- one private deployment repository based on this template
- one GitHub OIDC trust relationship in each AWS account used for deployment
- one deploy role per configured stack in `STACKS`
- one shared Pulumi state bucket in the AWS account for the first stack in `PROMOTION_PATH`
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
- Recommended even if you plan to use one-click bootstrap, because later bootstrap writes local Pulumi stack files into this checkout

### Step 3 - Prepare OIDC and deploy roles

- Read: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- Covers: OIDC provider, per-stack deploy roles, trust policy, permissions policy
- If using one-click bootstrap, review only; the script creates these automatically

### Step 4 - Prepare the local `.env` file

- Read: [`docs/onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- Covers: every required `.env` field, where each value comes from, what must not be edited manually

### Step 5 - Complete the pre-bootstrap readiness check

Before you run any bootstrap automation, confirm all of the following:

- GitHub access is ready.
  - Run `gh auth status`.
  - Confirm the authenticated account can create private repositories under `GITHUB_OWNER`.
  - Confirm the same account can write repository secrets, repository variables, and GitHub environments in the target deployment repository.
  - Review the minimum bootstrap permissions in [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md) before choosing the one-click path.
- AWS account mapping is final.
  - Confirm every stack in `STACKS` has a final AWS account ID, region, and deploy role name.
  - If different stacks use different AWS accounts, confirm you already know how you will switch credentials locally, usually with `AWS_PROFILE_<STACK>` values in `.env`.
  - Test each account access before bootstrap, for example `AWS_PROFILE_STAGING=customer-staging aws sts get-caller-identity`.
  - Remember that the shared Pulumi backend bucket is created in the AWS account for the first stack in `PROMOTION_PATH`, so the credentials for that stack must be able to create and manage the bucket.
- Cloudflare inputs are ready.
  - Confirm `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_API_TOKEN`, and `OIDC_DISCOVERY_DOMAIN` are final.
  - Confirm the token can manage the Pages project and custom domain that bootstrap creates for OIDC discovery.
  - If the operator account or token does not meet the minimum permission matrix, use the manual path instead of one-click bootstrap.
  - Confirm the zone can proxy the `api`, `auth`, and `control-plane` hostnames through Cloudflare.
  - Plan to keep Cloudflare SSL mode on `Full (strict)` and enable Authenticated Origin Pulls before sending production traffic.
- Release and application inputs are ready.
  - Confirm `LTBASE_RELEASES_REPO`, `LTBASE_RELEASE_ID`, `LTBASE_RELEASES_TOKEN`, and `GEMINI_API_KEY` are available before you continue.
- `.env` is clean.
  - Fill customer-controlled values yourself.
  - Leave derived values such as `PULUMI_BACKEND_URL`, `PULUMI_SECRETS_PROVIDER_<STACK>`, `AWS_ROLE_ARN_<STACK>`, `OIDC_ISSUER_URL_<STACK>`, and `JWKS_URL_<STACK>` unset unless you intentionally need an override.
  - Do not set `DSQL_ENDPOINT` manually for managed deployments.
- Preflight checks run successfully.
  - Optional review step: `./scripts/render-bootstrap-policies.sh --env-file .env`
  - Recovery-aware preflight: `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra`
  - A first-run report that shows `needs_foundation`, `needs_repo_config`, `needs_stack_bootstrap`, or `needs_oidc_companion` is normal.
  - Fix hard validation or authentication failures before you add `--force`.

For the detailed step-by-step one-click preparation and preflight process, use:

- [`docs/onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)

### Step 6 - Choose a bootstrap path

If you have enough GitHub and AWS permissions, use the one-click path:

- [`docs/onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)

If you want to control each stage manually, use the manual path:

- [`docs/onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)

### Step 7 - Run the first preview and deployment

- Read: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- Covers: preview, promotion-path rollout, protected-environment approvals, managed DSQL post-bootstrap handling

### Step 8 - Day-2 operations

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

## Recommended Working Pattern For One-Click Bootstrap

- Recommended path:
  - create the real deployment repository first
  - clone that repository locally
  - prepare `.env`
  - run one-click bootstrap from that cloned repository root
- Recovery path:
  - the recovery-aware bootstrap flow can create a missing remote repository and continue
  - if you use that path, clone the new repository before you review or commit generated local Pulumi stack files

## Important Managed DSQL Note

For managed deployments, do not manually provide an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword`.

At the time of writing, this repository's bootstrap scripts use a bootstrap-safe split: bootstrap prepares GitHub and Pulumi state first, and `scripts/reconcile-managed-dsql-endpoint.sh` publishes the managed DSQL endpoint after infrastructure exists.

Aurora DSQL itself is created by the Pulumi blueprint. You do not supply an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` for managed deployments.

The managed DSQL cluster uses the following default connection values set by the Lambda environment:

- `DSQL_DB=postgres`
- `DSQL_USER=admin`

These are the authoritative defaults for managed deployments.

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
- generated customer deployment repositories do not publish prebuilt infra binaries; the copied `build-infra-binary.yml` workflow is expected to be skipped outside `Lychee-Technology/ltbase-private-deployment`
- customer repositories now carry `__ref__/template-provenance.json`, which records the upstream template commit and `build_fingerprint` used for prebuilt infra binary lookup
- official workflows only install a prebuilt infra binary when that provenance and `build_fingerprint` exactly match an upstream-published manifest; otherwise they intentionally fall back to source build
- manual preview only supports the first stack in `PROMOTION_PATH`
- protected promotions happen in your own repository through per-stack GitHub environment gates

## Cloudflare mTLS Rollout Notes

- `api`, `auth`, and `control-plane` are expected to use Cloudflare-proxied custom domains.
- API Gateway custom domains are configured for mutual TLS with the template's built-in Cloudflare Authenticated Origin Pull truststore.
- Operators still need to enable Authenticated Origin Pulls in Cloudflare. This version documents that requirement but does not toggle it through IaC.
- Direct `https://<api-id>.execute-api.<region>.amazonaws.com/...` access is expected to fail after rollout because the default API Gateway endpoints are disabled.
- A `403` from the custom domain usually means Cloudflare is not presenting the expected client certificate chain or the truststore/config is out of sync.
- A `526` from Cloudflare usually means the origin TLS configuration is not compatible with `Full (strict)` or the custom domain certificate is not valid yet.
- Recommended rollout order:
  - apply the infra change in a lower environment first
  - confirm the DNS records are proxied in Cloudflare
  - confirm Authenticated Origin Pulls is enabled
  - verify the custom domain succeeds through Cloudflare
  - verify direct `execute-api` access fails

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
