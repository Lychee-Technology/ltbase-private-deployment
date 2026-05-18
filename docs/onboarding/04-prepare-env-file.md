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
   - Source: your agreed deployment topology and promotion order
3. Fill in template and repository identity:
   - `TEMPLATE_REPO`
   - `GITHUB_OWNER`
   - `DEPLOYMENT_REPO_NAME`
   - `DEPLOYMENT_REPO_VISIBILITY`
   - `DEPLOYMENT_REPO_DESCRIPTION`
   - Source: your target GitHub owner and customer deployment repository naming decision
4. Fill in OIDC discovery and admin UI domain values:
    - `OIDC_DISCOVERY_DOMAIN`
    - `CONTROLPLANE_UI_DOMAIN`
    - `CLOUDFLARE_ACCOUNT_ID`
    - Source: your Cloudflare account and the custom domains you want to use for OIDC discovery and the control-plane UI admin site
    - In the current repository version, the Control Plane UI bootstrap uses `CONTROLPLANE_UI_DOMAIN` when it provisions the control-plane UI companion Pages site and when it later writes `ltbase-infra:controlPlaneCorsOrigins=https://<CONTROLPLANE_UI_DOMAIN>` into each Pulumi stack.
5. Fill in AWS environment values (one pair per stack):
   - `AWS_REGION_<STACK>`
   - `AWS_ACCOUNT_ID_<STACK>`
   - `AWS_ROLE_NAME_<STACK>`
   - Optional when stacks use different AWS accounts: `AWS_PROFILE_<STACK>`
   - Source: your AWS account plan for each stack
6. Fill in Pulumi backend values:
   - `PULUMI_STATE_BUCKET`
   - `PULUMI_KMS_ALIAS`
   - leave `PULUMI_BACKEND_URL` and every `PULUMI_SECRETS_PROVIDER_<STACK>` empty if you plan to let bootstrap generate them
   - Source: the names you want bootstrap to use for shared Pulumi backend resources
   - Important: the shared backend bucket named by `PULUMI_STATE_BUCKET` is created in the AWS account for the first stack in `PROMOTION_PATH`
7. Fill in release values:
    - `LTBASE_RELEASES_REPO`
    - `LTBASE_RELEASE_ID`
    - Source: the LTBase release repository and release ID you plan to deploy
8. Keep the mandatory mTLS defaults in place:
   - `MTLS_TRUSTSTORE_FILE`
   - `MTLS_TRUSTSTORE_KEY`
   - Source: the checked-in Cloudflare global Authenticated Origin Pull truststore shipped with this template
   - Important: these are required defaults for the template, not optional feature flags. `api`, `auth`, and `control-plane` are all deployed behind Cloudflare proxying and API Gateway mutual TLS.
9. Fill in per-stack domain values:
      - `API_DOMAIN_<STACK>`
      - `CONTROL_DOMAIN_<STACK>`
      - `AUTH_DOMAIN_<STACK>`
      - `API_CORS_ALLOW_ORIGINS_<STACK>` (optional)
      - `AUTH_CORS_ALLOW_ORIGINS_<STACK>` (optional)
      - `CONTROL_PLANE_CORS_ALLOW_ORIGINS_<STACK>` (optional)
      - `PROJECT_ID`
      - `AUTH_PROVIDER_CONFIG_FILE_<STACK>`
      - `CLOUDFLARE_ZONE_ID`
      - Source: your final DNS plan in the target Cloudflare zone
      - Bootstrap uses `CLOUDFLARE_ZONE_ID` from `.env` when it writes each `infra/Pulumi.<stack>.yaml` stack config. Preview and rollout mTLS audits then read `ltbase-infra:awsRegion`, `ltbase-infra:apiDomain`, `ltbase-infra:controlPlaneDomain`, `ltbase-infra:authDomain`, `ltbase-infra:runtimeBucket`, and `ltbase-infra:cloudflareZoneId` from that stack file.
      - The `API_CORS_ALLOW_ORIGINS_<STACK>` and `AUTH_CORS_ALLOW_ORIGINS_<STACK>` values are optional comma-separated allowlists for API Gateway CORS. Leave them unset to default to `*`.
      - `CONTROL_PLANE_CORS_ALLOW_ORIGINS_<STACK>` is also optional, but its default behavior is different: when unset, bootstrap uses `https://<CONTROLPLANE_UI_DOMAIN>`; when set to a concrete CSV allowlist, bootstrap appends `https://<CONTROLPLANE_UI_DOMAIN>` automatically; when set to `*`, bootstrap keeps `*` unchanged.
      - For `AUTH_PROVIDER_CONFIG_FILE_<STACK>`, point to a checked-in JSON file that lists the external JWT providers enabled for that stack.
      - Start by copying `infra/auth-providers.<stack>.json.example` to `infra/auth-providers.<stack>.json`, then edit the real file in the generated customer deployment repository.
      - Keep the provider names in `infra/auth-providers.<stack>.json` aligned with the public browser config you are publishing for the control-plane UI. The current companion bootstrap reuses matching deployment-owned provider names when it renders `public/ltbase-controlplane.config.json`.
      - Bootstrap also writes `ltbase-infra:controlPlaneCorsOrigins=https://<CONTROLPLANE_UI_DOMAIN>` into each stack file so the deployed control-plane API accepts browser requests from the admin UI domain.
      - Before operators try the admin UI, configure the identity provider to allow `https://<CONTROLPLANE_UI_DOMAIN>/auth/callback`.
10. Fill in required public browser auth values for every stack:
    - `FIREBASE_API_KEY_<STACK>`, `FIREBASE_PROJECT_ID_<STACK>`
    - `SUPABASE_URL_<STACK>`, `SUPABASE_ANON_KEY_<STACK>`
    - Source: the public Firebase/Supabase application settings that the control-plane UI companion publishes to browsers
    - Important: these values are intentionally public. Do not put server-side Firebase admin credentials, Supabase service-role keys, or any other secret values here.
    - The current Control Plane UI bootstrap uses these values when it renders browser runtime config for each stack.
11. Fill in application defaults:
     - `GEMINI_MODEL`
     - `DSQL_PORT`, `DSQL_DB`, `DSQL_USER`, `DSQL_PROJECT_SCHEMA`
     - Source: LTBase application defaults and any approved customer-specific override
12. Fill in secret values:
      - `GEMINI_API_KEY`
      - `CLOUDFLARE_API_TOKEN`
      - `LTBASE_RELEASES_TOKEN`
13. Decide whether you will accept the default per-stack schema bucket names or set explicit overrides:
     - `SCHEMA_BUCKET_<STACK>`
     - Source: the stack-specific S3 bucket that preview and rollout use for schema validation/publication
     - Important: preview and rollout now depend on the GitHub repository variable `SCHEMA_BUCKET_<STACK>` for every deployed stack. If you do not want the default `<DEPLOYMENT_REPO_NAME>-schema-<stack>` naming, set the override explicitly in `.env` before bootstrap.
14. Save the file locally and confirm it is not committed.

## Values You Normally Fill Manually

These values are customer-controlled inputs and should usually be set explicitly in `.env`:

- `STACKS`, `PROMOTION_PATH`
- `TEMPLATE_REPO`, `GITHUB_OWNER`, `DEPLOYMENT_REPO_NAME`, `DEPLOYMENT_REPO_VISIBILITY`, `DEPLOYMENT_REPO_DESCRIPTION`
- `OIDC_DISCOVERY_DOMAIN`, `CONTROLPLANE_UI_DOMAIN`, `CLOUDFLARE_ACCOUNT_ID`
- `AWS_REGION_<STACK>`, `AWS_ACCOUNT_ID_<STACK>`, `AWS_ROLE_NAME_<STACK>`
- `AWS_PROFILE_<STACK>` when multiple stacks use different AWS credentials locally
- `PULUMI_STATE_BUCKET`, `PULUMI_KMS_ALIAS`
- `SCHEMA_BUCKET_<STACK>` when you do not want the default `<DEPLOYMENT_REPO_NAME>-schema-<stack>` bucket names used by preview and rollout
- `LTBASE_RELEASES_REPO`, `LTBASE_RELEASE_ID`
- `MTLS_TRUSTSTORE_FILE`, `MTLS_TRUSTSTORE_KEY` with the template defaults intact
- `API_DOMAIN_<STACK>`, `CONTROL_DOMAIN_<STACK>`, `AUTH_DOMAIN_<STACK>`, `PROJECT_ID`, `AUTH_PROVIDER_CONFIG_FILE_<STACK>`, `CLOUDFLARE_ZONE_ID`
- `API_CORS_ALLOW_ORIGINS_<STACK>` and `AUTH_CORS_ALLOW_ORIGINS_<STACK>` when you need browser CORS to be stricter than the default `*`
- `CONTROL_PLANE_CORS_ALLOW_ORIGINS_<STACK>` when the control-plane API should allow extra browser origins in addition to `https://<CONTROLPLANE_UI_DOMAIN>`, or when you intentionally want wildcard `*`
  - `CLOUDFLARE_ZONE_ID` is still a manual bootstrap input in `.env`, but preview and rollout mTLS audits consume per-stack values stored in `infra/Pulumi.<stack>.yaml`, including `ltbase-infra:cloudflareZoneId`, domains, `awsRegion`, and `runtimeBucket`.
- `FIREBASE_API_KEY_<STACK>`, `FIREBASE_PROJECT_ID_<STACK>`, `SUPABASE_URL_<STACK>`, `SUPABASE_ANON_KEY_<STACK>`
  - These are public browser settings for the control-plane UI companion, not backend secrets.
- `GEMINI_MODEL`, `DSQL_PORT`, `DSQL_DB`, `DSQL_USER`, `DSQL_PROJECT_SCHEMA`
- `GEMINI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `LTBASE_RELEASES_TOKEN`

## Values Bootstrap Normally Derives For You

Leave these unset unless you intentionally need an override:

- `DEPLOYMENT_REPO`
  - default: `${GITHUB_OWNER}/${DEPLOYMENT_REPO_NAME}`
- `GITHUB_ORG`, `GITHUB_REPO`
  - default: derived from `GITHUB_OWNER` and `DEPLOYMENT_REPO_NAME`
- `AWS_ROLE_ARN_<STACK>`
  - default: derived from `AWS_ACCOUNT_ID_<STACK>` and `AWS_ROLE_NAME_<STACK>`
- `PULUMI_BACKEND_URL`
  - default: `s3://${PULUMI_STATE_BUCKET}`
- `PULUMI_SECRETS_PROVIDER_<STACK>`
  - default: derived from `PULUMI_KMS_ALIAS` and `AWS_REGION_<STACK>`
- `OIDC_DISCOVERY_TEMPLATE_REPO`, `OIDC_DISCOVERY_REPO_NAME`, `OIDC_DISCOVERY_REPO`, `OIDC_DISCOVERY_PAGES_PROJECT`
  - default: derived from the deployment repository naming inputs
- `OIDC_DISCOVERY_AWS_ROLE_NAME_<STACK>`, `OIDC_DISCOVERY_AWS_ROLE_ARN_<STACK>`
  - default: derived from deployment repository name and target AWS account ID
- `OIDC_ISSUER_URL_<STACK>`, `JWKS_URL_<STACK>`
  - default: derived from `OIDC_DISCOVERY_DOMAIN`
- `RUNTIME_BUCKET_<STACK>`, `SCHEMA_BUCKET_<STACK>`, `TABLE_NAME_<STACK>`
  - default: derived from `DEPLOYMENT_REPO_NAME`
- `PREVIEW_DEFAULT_STACK`
  - default: first stack in `PROMOTION_PATH`

## Optional Overrides

Only fill these when the defaults are wrong for your customer environment:

- `DEPLOYMENT_REPO`
- `OIDC_DISCOVERY_TEMPLATE_REPO`
- `OIDC_DISCOVERY_REPO_NAME`
- `OIDC_DISCOVERY_REPO`
- `OIDC_DISCOVERY_PAGES_PROJECT`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>`
- `OIDC_ISSUER_URL_<STACK>`
- `JWKS_URL_<STACK>`
- `RUNTIME_BUCKET_<STACK>`
- `SCHEMA_BUCKET_<STACK>`
- `TABLE_NAME_<STACK>`
- `OIDC_DISCOVERY_AWS_ROLE_NAME_<STACK>`

## Important Rules

- do not commit `.env`
- do not put production secrets into tracked files
- do not put server-only Firebase credentials, Supabase service-role keys, or other secrets into Control Plane UI runtime config inputs
- the template repository only ships `infra/auth-providers.*.json.example`; keep the real `infra/auth-providers.<stack>.json` files in the generated customer deployment repository
- keep the provider names in each real `infra/auth-providers.<stack>.json` file aligned with the public browser providers you publish for the control-plane UI companion; the bootstrap will reuse matching deployment-owned names in `public/ltbase-controlplane.config.json`
- treat `PULUMI_BACKEND_URL` and `PULUMI_SECRETS_PROVIDER_*` as generated values if you rely on bootstrap to create backend resources
- only fill values you actually control; generated values should come from bootstrap outputs
- do not set `DSQL_ENDPOINT` manually for managed deployments; bootstrap and later reconciliation publish the authoritative value
- keep `MTLS_TRUSTSTORE_FILE=infra/certs/cloudflare-origin-pull-ca.pem` and `MTLS_TRUSTSTORE_KEY=mtls/cloudflare-origin-pull-ca.pem` unless the LTBase template itself changes; bootstrap requires both values
- expect `api`, `auth`, and `control-plane` to be reachable only through Cloudflare-proxied custom domains once the mTLS rollout tasks are applied
- preview and rollout require a valid `SCHEMA_BUCKET_<STACK>` repository variable for each stack; bootstrap writes it from `.env` or the derived default
- expect bootstrap to write `ltbase-infra:controlPlaneCorsOrigins=https://<CONTROLPLANE_UI_DOMAIN>` into each stack config so the deployed control-plane API accepts browser calls from the admin UI domain
- before operators try the admin UI, configure the identity provider to allow `https://<CONTROLPLANE_UI_DOMAIN>/auth/callback` and bind at least one admin user or group to the LTBase project you plan to manage
- the following variables are auto-derived by `scripts/lib/bootstrap-env.sh` and normally do not need manual filling: `DEPLOYMENT_REPO`, `PULUMI_BACKEND_URL`, `PULUMI_SECRETS_PROVIDER_*`, `AWS_ROLE_ARN_*`, `OIDC_ISSUER_URL_*`, `JWKS_URL_*`, `RUNTIME_BUCKET_*`, `SCHEMA_BUCKET_*`, `TABLE_NAME_*`, `GITHUB_ORG`, `GITHUB_REPO`, `OIDC_DISCOVERY_TEMPLATE_REPO`, `OIDC_DISCOVERY_REPO_NAME`, `OIDC_DISCOVERY_REPO`, `OIDC_DISCOVERY_PAGES_PROJECT`, `OIDC_DISCOVERY_AWS_ROLE_NAME_*`, `OIDC_DISCOVERY_AWS_ROLE_ARN_*`, `PREVIEW_DEFAULT_STACK`

## Expected Result

You now have a complete local `.env` file that can be used by the bootstrap scripts.

## Common Mistakes

- mixing placeholder values with real values
- setting the wrong repository name in `DEPLOYMENT_REPO`
- forgetting to update the AWS account IDs to match the target roles
- committing `.env` by accident
- filling derived values manually and then forgetting they no longer match the customer-controlled inputs above them

## Next Step

Choose one bootstrap path:

- one-click: [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md)
- manual: [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
