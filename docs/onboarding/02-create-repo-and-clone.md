# Create the Deployment Repository and Clone It

> **[中文版](02-create-repo-and-clone.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to create your customer-owned deployment repository from the template and verify that the local checkout contains the expected files.

## Before You Start

- complete [`01-prerequisites.md`](01-prerequisites.md)
- know the target GitHub owner and repository name

## Important Note For One-Click Bootstrap Users

This step is still the recommended starting point even if you plan to use the one-click bootstrap path later.

The later bootstrap stages write local `infra/Pulumi.<stack>.yaml` files into the checkout where you run them, so it is best to work from a clone of your real customer deployment repository.

The recovery-aware scripts can create a missing remote repository when needed, but that is best treated as a recovery path rather than the default onboarding flow.

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
   - `scripts/sync-template-upstream.sh`
   - `scripts/reconcile-managed-dsql-endpoint.sh`
5. Confirm that the repository is private.
6. Confirm that GitHub environments can be created for every stack after the first promotion hop, because those later stacks are where approval gates live.
7. If you plan to use one-click bootstrap later, keep using this same checkout for `.env` preparation and bootstrap commands.

## Expected Result

You have a local working copy of your deployment repository and it matches the expected LTBase private deployment layout.

## Common Mistakes

- creating the repo manually without using the template
- cloning the template repo instead of your own private repo
- forgetting to verify that `.github/workflows/` and `infra/` exist
- planning to run bootstrap from a temporary checkout and then wondering where the generated Pulumi stack files went

## Next Step

Continue with [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md).
