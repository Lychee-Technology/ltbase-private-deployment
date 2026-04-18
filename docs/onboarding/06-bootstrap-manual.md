# Manual Bootstrap

> **[中文版](06-bootstrap-manual.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide when you want to review each bootstrap stage separately instead of running the one-click path.

## Before You Start

- complete [`04-prepare-env-file.md`](04-prepare-env-file.md)
- decide that you want to control each bootstrap stage manually

## When To Choose The Manual Path

The manual path is a better fit when:

- you want to review each GitHub, AWS, and Cloudflare change stage by stage
- you do not want one command to create every required resource automatically
- you need to separate repository creation, AWS foundation, stack bootstrap, and OIDC discovery companion setup

The main rule of the manual path is simple: finish one stage, verify the result, then continue.

## Steps

### 1. Create the real deployment repo

Before you run the command, confirm:

- `gh auth status` succeeds
- `.env` already contains the final `GITHUB_OWNER`, `DEPLOYMENT_REPO_NAME`, `DEPLOYMENT_REPO_VISIBILITY`, and `DEPLOYMENT_REPO_DESCRIPTION`

Run:

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

After this step, confirm:

- the remote deployment repository now exists
- GitHub environments for stacks after the first promotion hop were created for later approvals
- your local checkout is the real customer deployment repository, not the template repository

### 2. Bootstrap AWS foundation

Before you run the command, confirm:

- AWS credentials or `AWS_PROFILE_<STACK>` values are ready
- `AWS_ACCOUNT_ID_<STACK>`, `AWS_REGION_<STACK>`, and `AWS_ROLE_NAME_<STACK>` in `.env` are final
- `PULUMI_STATE_BUCKET` and `PULUMI_KMS_ALIAS` names are final

Run:

```bash
./scripts/bootstrap-aws-foundation.sh --env-file .env
```

This step creates or updates:

- GitHub OIDC provider
- deploy roles
- trust policies
- inline role policies
- the shared Pulumi state bucket in the AWS account for the first stack in `PROMOTION_PATH`
- Pulumi KMS alias

It also generates `dist/foundation.env` and review artifacts.

After this step, confirm:

- `dist/foundation.env` exists
- `dist/` contains the generated trust policy and role policy artifacts you expect to review
- the first stack account now contains the shared Pulumi backend bucket
- the target AWS accounts now contain the OIDC provider, deploy roles, and KMS alias entries you expect

### 3. Optionally merge generated foundation values

If bootstrap generated new Pulumi backend values, merge them into your shell or `.env`:

```bash
source dist/foundation.env
```

Use this step when:

- the AWS foundation stage just created backend-related values for you
- you want the rest of the current shell session to use those values immediately

Important:

- `source dist/foundation.env` only updates the current shell session
- if you want those values to persist for later sessions, copy the confirmed values back into your local `.env`

### 4. Bootstrap Pulumi backend only if needed

Run this if you want the backend/KMS path separately:

```bash
./scripts/bootstrap-pulumi-backend.sh --env-file .env
```

Most customers only need this when they intentionally want to separate backend/KMS setup from the rest of foundation bootstrap.

### 5. Bootstrap every configured stack

Before you run this stage, confirm:

- `PULUMI_BACKEND_URL` and `PULUMI_SECRETS_PROVIDER_<STACK>` are now available
- the deployment repository already exists
- you know the real order of `STACKS` and `PROMOTION_PATH`

Run:

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack> --infra-dir infra
```

Repeat the command once for each stack listed in `STACKS`. Using the same order as `PROMOTION_PATH` is the simplest default.

Example order:

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

After each stack, confirm:

- the matching `infra/Pulumi.<stack>.yaml` file exists, or the stack can be selected successfully while working from `infra/`
- GitHub repository values for that stack were written: `AWS_REGION_<STACK>`, `PULUMI_SECRETS_PROVIDER_<STACK>`, and `SCHEMA_BUCKET_<STACK>`
- GitHub repository secret `AWS_ROLE_ARN_<STACK>` was written for that stack
- shared repository configuration such as `PULUMI_BACKEND_URL`, `LTBASE_RELEASE_ID`, `LTBASE_RELEASES_TOKEN`, and `CLOUDFLARE_API_TOKEN` is present

### 6. Bootstrap OIDC discovery companion

Before you run this stage, confirm:

- `OIDC_DISCOVERY_DOMAIN`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ZONE_ID`, and `CLOUDFLARE_API_TOKEN` are correct
- you are ready for the script to create or update the companion repository, Pages project, custom domain binding, and required DNS `CNAME`

Run:

```bash
./scripts/bootstrap-oidc-discovery-companion.sh --env-file .env
```

This step creates or updates the OIDC discovery companion repository, Cloudflare Pages project, custom domain binding, the required zone DNS `CNAME` pointing at `${OIDC_DISCOVERY_PAGES_PROJECT}.pages.dev`, and per-stack OIDC discovery IAM roles.

After this step, confirm:

- the OIDC discovery companion repository now exists
- that repository has GitHub repository variables `OIDC_DISCOVERY_DOMAIN` and `OIDC_DISCOVERY_STACK_CONFIG`
- the Cloudflare Pages project and custom domain binding were created
- the Cloudflare zone now contains the expected `CNAME` for `OIDC_DISCOVERY_DOMAIN`
- the per-stack OIDC discovery IAM roles now exist

### 7. Confirm repository configuration

At minimum, confirm all of the following:

- the deployment repository now contains the required GitHub secrets and variables
- every stack in `infra/` now has initialized Pulumi configuration
- if you used the companion flow, the OIDC discovery repository and Cloudflare resources are ready

If you want one final summary check before first deploy, run:

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

In the manual path, this is a good way to confirm there are no remaining gaps such as `needs_repo_config`, `needs_stack_bootstrap`, or `needs_oidc_companion`.

## Expected Result

You finish with all bootstrap stages completed manually and the repository is ready for the first preview and deployment.

## Common Mistakes

- forgetting to source `dist/foundation.env` after AWS foundation generated new values
- skipping later stacks in `STACKS` and only preparing the first stack
- running manual bootstrap commands outside the repository root
- continuing past AWS foundation without reviewing the generated artifacts and output values
- moving to first deploy before the companion resources are actually ready

## Next Step

Continue with [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md).
