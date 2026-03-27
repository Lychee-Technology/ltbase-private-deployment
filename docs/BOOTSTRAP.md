# Customer Bootstrap

This file is the short bootstrap checklist. For the full customer runbook, use [`CUSTOMER_ONBOARDING.md`](/Users/ruoshi/code/Lychee/ltbase.api/templates/ltbase-private-deployment/docs/CUSTOMER_ONBOARDING.md).

## Repository Layout

The standalone customer repository should contain:

- `infra/` copied from the upstream LTBase blueprint
- `.github/workflows/` copied from this template
- `env.template` copied to a local `.env` file for bootstrap inputs
- `scripts/render-bootstrap-policies.sh` for copy-paste trust and permissions policies
- `scripts/create-deployment-repo.sh` for creating a real repo from the template
- `scripts/bootstrap-aws-foundation.sh` for OIDC, IAM, S3, and KMS setup
- `scripts/bootstrap-pulumi-backend.sh` for AWS backend/KMS bootstrap
- `scripts/bootstrap-deployment-repo.sh` for GitHub/Pulumi bootstrap
- `scripts/bootstrap-all.sh` for one-click bootstrap when you have enough AWS/GitHub permissions
- customer-specific `Pulumi.<stack>.yaml` values and Pulumi secrets

## Required Secrets

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required Variables

- `AWS_REGION_DEVO`
- `AWS_REGION_PROD`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_DEVO`
- `PULUMI_SECRETS_PROVIDER_PROD`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

## First-Time Setup

1. Copy `env.template` to a local `.env` file and fill in the placeholders, including sensitive values.
2. Optional review path: run `./scripts/render-bootstrap-policies.sh --env-file .env` and inspect `dist/*.json` before creating AWS resources.
3. One-click path: run `./scripts/bootstrap-all.sh --env-file .env --mode apply --infra-dir infra`.
4. Manual path: run `./scripts/create-deployment-repo.sh`, `./scripts/bootstrap-aws-foundation.sh`, and `./scripts/bootstrap-deployment-repo.sh` separately.
5. Set `LTBASE_RELEASE_ID=v1.0.0` if you want the first stable release.
6. Run the preview workflow manually with that `release_id` after the repository secrets and variables are configured.
7. Run the `devo` deployment workflow.
8. Approve and run the `prod` promotion workflow after `devo` is validated.

## Notes

- `LTBASE_RELEASES_TOKEN` must be a customer-specific fine-grained token with read-only access to `ltbase-releases`.
- Local `.env` files are ignored by git and should never be committed.
- `PULUMI_BACKEND_URL` controls where Pulumi state is stored; the `PULUMI_SECRETS_PROVIDER_*` values control how Pulumi secrets are encrypted for each environment.
- `env.template` separates `AWS_REGION_DEVO` and `AWS_REGION_PROD` so you can bootstrap split-region deployments.
- `env.template` separates `AWS_ACCOUNT_ID_DEVO` and `AWS_ACCOUNT_ID_PROD` so you can bootstrap split-account deployments.
- `bootstrap-all.sh` is intended for operators who have enough AWS and GitHub permissions to create the real deployment repo and its foundation resources.
- This template repository keeps preview as a manual workflow because the template itself does not ship with live customer secrets or AWS roles.
- Revoking that token stops future updates but does not stop an already deployed customer environment.
- The prod workflow uses an approval gate job in the customer repository so environment protection still lives with the customer.
