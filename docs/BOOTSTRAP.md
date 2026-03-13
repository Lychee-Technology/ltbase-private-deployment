# Customer Bootstrap

This file is the short bootstrap checklist. For the full customer runbook, use [`CUSTOMER_ONBOARDING.md`](/Users/ruoshi/code/Lychee/ltbase.api/templates/ltbase-private-deployment/docs/CUSTOMER_ONBOARDING.md).

## Repository Layout

The standalone customer repository should contain:

- `infra/` copied from the upstream LTBase blueprint
- `.github/workflows/` copied from this template
- customer-specific `Pulumi.<stack>.yaml` values and Pulumi secrets

## Required Secrets

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required Variables

- `AWS_REGION`
- `PULUMI_BACKEND_URL`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

## First-Time Setup

1. Create a Pulumi backend bucket in the customer AWS account.
2. Copy the upstream `infra/` directory into the customer repository.
3. Copy the wrapper workflows from this template into the customer repository.
4. Set the required secrets and variables in the customer repository.
5. Set Pulumi stack config and secrets for `devo` and `prod`.
6. Set `LTBASE_RELEASE_ID=v1.0.0`.
7. Run the preview workflow with that `release_id`.
8. Run the `devo` deployment workflow.
9. Approve and run the `prod` promotion workflow after `devo` is validated.

## Notes

- `LTBASE_RELEASES_TOKEN` must be a customer-specific fine-grained token with read-only access to `ltbase-releases`.
- Revoking that token stops future updates but does not stop an already deployed customer environment.
- The prod workflow uses an approval gate job in the customer repository so environment protection still lives with the customer.
