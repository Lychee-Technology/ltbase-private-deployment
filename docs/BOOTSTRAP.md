# Customer Bootstrap

This file is the short bootstrap checklist. For the full customer runbook, use [`CUSTOMER_ONBOARDING.md`](/Users/ruoshi/code/Lychee/ltbase.api/templates/ltbase-private-deployment/docs/CUSTOMER_ONBOARDING.md).

## Repository Layout

The standalone customer repository should contain:

- `infra/` copied from the upstream LTBase blueprint
- `.github/workflows/` copied from this template
- `env.template` copied to a local `.env` file for bootstrap inputs
- `scripts/bootstrap-pulumi-backend.sh` for AWS backend/KMS bootstrap
- `scripts/bootstrap-deployment-repo.sh` for GitHub/Pulumi bootstrap
- customer-specific `Pulumi.<stack>.yaml` values and Pulumi secrets

## Required Secrets

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required Variables

- `AWS_REGION`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

## First-Time Setup

1. Copy `env.template` to a local `.env` file and fill in the placeholders, including sensitive values.
2. Run `./scripts/bootstrap-pulumi-backend.sh --env-file .env` to create or reuse the S3 backend and AWS KMS secrets key.
3. Review `dist/pulumi-backend.env` and `dist/pulumi-kms-policy.json`.
4. Apply the generated KMS policy to the customer deploy role if needed.
5. Run `./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra`.
6. Set `LTBASE_RELEASE_ID=v1.0.0` if you want the first stable release.
7. Run the preview workflow with that `release_id`.
8. Run the `devo` deployment workflow.
9. Approve and run the `prod` promotion workflow after `devo` is validated.

## Notes

- `LTBASE_RELEASES_TOKEN` must be a customer-specific fine-grained token with read-only access to `ltbase-releases`.
- Local `.env` files are ignored by git and should never be committed.
- `PULUMI_BACKEND_URL` controls where Pulumi state is stored; `PULUMI_SECRETS_PROVIDER` controls how Pulumi secrets are encrypted.
- Revoking that token stops future updates but does not stop an already deployed customer environment.
- The prod workflow uses an approval gate job in the customer repository so environment protection still lives with the customer.
