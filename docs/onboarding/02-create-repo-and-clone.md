# Create the Deployment Repository and Clone It

> **[中文版](02-create-repo-and-clone.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to create your customer-owned deployment repository from the template and verify that the local checkout contains the expected files.

## Before You Start

- complete [`01-prerequisites.md`](01-prerequisites.md)
- know the target GitHub owner and repository name

## Steps

1. Create a new private repository from the `ltbase-private-deployment` template.
2. Use a repository name that matches your internal naming convention.
3. Clone the newly created repository locally.
4. Open the repository root and confirm the following exist:
   - `infra/`
   - `.github/workflows/`
   - `env.template`
   - `scripts/create-deployment-repo.sh`
   - `scripts/render-bootstrap-policies.sh`
   - `scripts/bootstrap-aws-foundation.sh`
   - `scripts/bootstrap-pulumi-backend.sh`
   - `scripts/bootstrap-oidc-discovery-companion.sh`
   - `scripts/bootstrap-deployment-repo.sh`
   - `scripts/bootstrap-all.sh`
   - `scripts/evaluate-and-continue.sh`
   - `scripts/reconcile-managed-dsql-endpoint.sh`
5. Confirm that the repository is private.
6. Confirm that the `prod` environment will be available for later approval gating.

## Expected Result

You have a local working copy of your deployment repository and it matches the expected LTBase private deployment layout.

## Common Mistakes

- creating the repo manually without using the template
- cloning the template repo instead of your own private repo
- forgetting to verify that `.github/workflows/` and `infra/` exist

## Next Step

Continue with [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md).
