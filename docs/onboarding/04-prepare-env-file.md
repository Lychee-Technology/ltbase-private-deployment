# Prepare the Local .env File

> **[中文版](04-prepare-env-file.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to create the local `.env` file that drives the bootstrap scripts and repository configuration.

## Before You Start

- complete [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md)
- have the final GitHub repository name, AWS account IDs, role ARNs, and domain values ready

## Steps

1. Copy `env.template` to `.env`.
2. Fill in stack topology:
   - `STACKS` — comma-separated list of environment names, e.g. `devo,prod`
   - `PROMOTION_PATH` — promotion order, e.g. `devo,prod`
3. Fill in template and repository identity:
   - `TEMPLATE_REPO`
   - `GITHUB_OWNER`
   - `DEPLOYMENT_REPO_NAME`
   - `DEPLOYMENT_REPO_VISIBILITY`
   - `DEPLOYMENT_REPO_DESCRIPTION`
4. Fill in OIDC discovery values:
   - `OIDC_DISCOVERY_DOMAIN`
   - `CLOUDFLARE_ACCOUNT_ID`
5. Fill in AWS environment values (one pair per stack):
   - `AWS_REGION_DEVO`, `AWS_REGION_PROD`
   - `AWS_ACCOUNT_ID_DEVO`, `AWS_ACCOUNT_ID_PROD`
   - `AWS_ROLE_NAME_DEVO`, `AWS_ROLE_NAME_PROD`
6. Fill in Pulumi backend values:
   - `PULUMI_STATE_BUCKET`
   - `PULUMI_KMS_ALIAS`
   - `PULUMI_PROJECT`
   - leave `PULUMI_BACKEND_URL`, `PULUMI_SECRETS_PROVIDER_DEVO`, and `PULUMI_SECRETS_PROVIDER_PROD` empty if you plan to let bootstrap generate them
7. Fill in release values:
   - `LTBASE_RELEASES_REPO`
   - `LTBASE_RELEASE_ID`
8. Fill in per-stack domain values:
   - `API_DOMAIN_DEVO`, `API_DOMAIN_PROD`
   - `CONTROL_DOMAIN_DEVO`, `CONTROL_DOMAIN_PROD`
   - `AUTH_DOMAIN_DEVO`, `AUTH_DOMAIN_PROD`
   - `CLOUDFLARE_ZONE_ID`
9. Fill in application defaults:
   - `GEMINI_MODEL`
   - `DSQL_PORT`, `DSQL_DB`, `DSQL_USER`, `DSQL_PROJECT_SCHEMA`
10. Fill in secret values:
    - `GEMINI_API_KEY`
    - `CLOUDFLARE_API_TOKEN`
    - `LTBASE_RELEASES_TOKEN`
11. Save the file locally and confirm it is not committed.

## Important Rules

- do not commit `.env`
- do not put production secrets into tracked files
- treat `PULUMI_BACKEND_URL` and `PULUMI_SECRETS_PROVIDER_*` as generated values if you rely on bootstrap to create backend resources
- only fill values you actually control; generated values should come from bootstrap outputs
- the following variables are auto-derived by `scripts/lib/bootstrap-env.sh` and normally do not need manual filling: `DEPLOYMENT_REPO`, `AWS_PROFILE_*`, `PULUMI_BACKEND_URL`, `PULUMI_SECRETS_PROVIDER_*`, `OIDC_ISSUER_URL_*`, `JWKS_URL_*`, `RUNTIME_BUCKET_*`, `TABLE_NAME_*`, `GITHUB_ORG`, `GITHUB_REPO`, `OIDC_DISCOVERY_TEMPLATE_REPO`, `OIDC_DISCOVERY_REPO_NAME`, `OIDC_DISCOVERY_REPO`, `OIDC_DISCOVERY_PAGES_PROJECT`, `OIDC_DISCOVERY_AWS_ROLE_NAME_*`

## Expected Result

You now have a complete local `.env` file that can be used by the bootstrap scripts.

## Common Mistakes

- mixing placeholder values with real values
- setting the wrong repository name in `DEPLOYMENT_REPO`
- forgetting to update the AWS account IDs to match the target roles
- committing `.env` by accident

## Next Step

Choose one bootstrap path:

- one-click: [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md)
- manual: [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
