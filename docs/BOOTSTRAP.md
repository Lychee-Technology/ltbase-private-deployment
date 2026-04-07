> **中文版：[BOOTSTRAP.zh.md](BOOTSTRAP.zh.md)**

# Customer Bootstrap Checklist

This is the short checklist version of the customer onboarding flow.

For the full runbook, start here:

- [`CUSTOMER_ONBOARDING.md`](CUSTOMER_ONBOARDING.md)

## Repository Layout

Your deployment repository should contain:

- `infra/`
- `.github/workflows/`
- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-oidc-discovery-companion.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/sync-template-upstream.sh`
- `scripts/reconcile-managed-dsql-endpoint.sh`
- `scripts/lib/bootstrap-env.sh`

## Quick Checklist

### 1. Prepare prerequisites

- read [`onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- confirm GitHub, AWS, Cloudflare, `LTBASE_RELEASES_TOKEN`, and `GEMINI_API_KEY`

### 2. Create the deployment repository

- read [`onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- create the private repo from template and clone it locally

### 3. Create OIDC and deploy roles

- read [`onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- create one deploy role for each stack in `STACKS`

### 4. Prepare `.env`

- read [`onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- copy `env.template` to `.env`
- fill real values and never commit `.env`

### 5. Choose a bootstrap path

One-click path:

- read [`onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)
- run `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra`

Manual path:

- read [`onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- run the bootstrap scripts stage by stage

### 6. Run the first deployment

- read [`onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- run preview for the first stack in `PROMOTION_PATH`
- trigger `rollout.yml` once for the chosen release
- approve each protected target stack as GitHub requests it

### 7. Day-2 operations

- read [`onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- use the same preview -> rollout rhythm for upgrades

## Required GitHub Secrets

- `AWS_ROLE_ARN_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required GitHub Variables

- `AWS_REGION_<STACK>` for every stack in `STACKS`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

## Notes

- keep `.env` private and outside version control
- the deployment repository downloads official LTBase releases; it does not build the app itself
- preview is manual in the customer repo because live credentials are customer-owned
- manual preview only supports the first stack in `PROMOTION_PATH`
- protected target environments are guarded by per-stack GitHub environment approval gates during rollout
