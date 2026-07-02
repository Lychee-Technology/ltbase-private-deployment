> **中文版：[CUSTOMER_ONBOARDING.zh.md](CUSTOMER_ONBOARDING.zh.md)**

# LTBase Customer Deployment Guide

This document is the complete LTBase private deployment runbook. Follow the steps in order to deploy LTBase from scratch.

If you need a quick reference for steps you already know, use the [bootstrap checklist](BOOTSTRAP.md).

## Table of Contents

1. [Deployment Model](#deployment-model)
2. [End State](#end-state)
3. [Pre-Deployment Decisions](#1-pre-deployment-decisions)
4. [Prepare AWS](#2-prepare-aws)
5. [Prepare GitHub](#3-prepare-github)
6. [Prepare Cloudflare](#4-prepare-cloudflare)
7. [Prepare LTBase Inputs](#5-prepare-ltbase-inputs)
8. [Create Deployment Repository and Clone](#6-create-deployment-repository-and-clone)
9. [Fill in .env](#7-fill-in-env)
10. [Preflight Check](#8-preflight-check)
11. [Run Bootstrap](#9-run-bootstrap)
12. [Preview](#10-preview)
13. [Rollout](#11-rollout)
14. [Publish OIDC Discovery](#12-publish-oidc-discovery)
15. [First Deployment Verification](#13-first-deployment-verification)
16. [Common Errors and Recovery](#14-common-errors-and-recovery)
17. [Day-2 Operations](#15-day-2-operations)
18. [Related Documents](#related-documents)

---

## Deployment Model

Your LTBase deployment involves three repositories:

| Repository | Role | Do you manage it? |
|------------|------|-------------------|
| `ltbase-deploy-workflows` | Reusable public GitHub Actions workflows maintained by LTBase | No, referenced by your deployment repo |
| `ltbase-releases` | Private release repository with official LTBase application artifacts | No, you have read-only token access |
| **Your deployment repository** | A private repo created from the `ltbase-private-deployment` template | **This is the only repo you operate and maintain** |

Your deployment repository **does not build LTBase application source code**. It downloads an official LTBase release and deploys it into your AWS account with Pulumi.

### Deployment Flow Overview

```
You prepare .env and prerequisites
       ↓
Bootstrap scripts (one-click or manual) create IAM roles, Pulumi backend, OIDC discovery, Control Plane UI Pages
       ↓
Manually trigger GitHub Actions preview workflow to validate Pulumi changes
       ↓
Manually trigger rollout workflow to deploy across PROMOTION_PATH
       ↓
Protected environments require approval in GitHub before advancing
       ↓
Deployment complete; API, Auth, Control Plane, and UI are all reachable
```

### Current Control Plane UI Model

In the current repository version:

- **Bootstrap** phase: Scripts create the Cloudflare Pages project, custom domain binding, DNS CNAME, and write browser runtime config via companion repository variables.
- **Preview** phase: Infrastructure-only preview; **does not** publish the Control Plane UI.
- **Rollout** phase: Downloads the official `ltbase-controlplane-ui.tar.gz` from the release artifact, combines it with runtime config from the deployment repo, and publishes to Cloudflare Pages.
- The deployment repository is the operator-facing source of truth for all UI inputs, including `CONTROLPLANE_UI_DOMAIN`, stack browser config, auth provider name alignment, and Control Plane CORS configuration.

### Multi-Stack Topology

Stack names like `devo` and `prod` in this document are **examples**. You may choose any names as long as they are consistent across `STACKS` and `PROMOTION_PATH`.

---

## End State

When deployment is complete, you should have:

- One private deployment repository based on this template
- GitHub OIDC trust relationships in each AWS account used for deployment
- One deploy role per stack in `STACKS`
- One shared Pulumi state bucket in the AWS account for the first stack in `PROMOTION_PATH`
- One KMS alias for Pulumi secrets encryption
- GitHub repository secrets and variables configured
- A first promotion stack ready for preview and deployment
- Each later stack in `PROMOTION_PATH` ready for protected promotion after the previous hop is validated
- A Control Plane UI admin site reachable via Cloudflare-proxied custom domain
- An admin domain allowed by Control Plane CORS
- Operator identity provider configured with the redirect URI and user binding

---

## 1. Pre-Deployment Decisions

Before any operations, finalize these topology decisions. They drive all subsequent configuration.

### 1.1 Decide Stack Topology

| Decision | Description | Example |
|----------|-------------|---------|
| `STACKS` | All environment names, comma-separated | `devo,prod` or `dev,staging,prod` |
| `PROMOTION_PATH` | Deployment promotion order, comma-separated | `devo,prod` (usually same as STACKS) |

### 1.2 Decide AWS Configuration Per Stack

For each stack, determine:

| Config | Example |
|--------|---------|
| AWS region | `ap-northeast-1` |
| AWS account ID | `123456789012` |
| Deploy role name | `ltbase-deploy-devo` |

> **Note**: Multiple stacks using the same AWS account with different regions is allowed. If using different AWS accounts, ensure you can switch AWS credentials locally.

### 1.3 Decide Domains

For each stack, determine these domains. They must all be in the same Cloudflare zone:

| Domain | Purpose | Example |
|--------|---------|---------|
| API domain | Data plane API | `api.devo.customer.example.com` |
| Control domain | Control Plane API | `control.devo.customer.example.com` |
| Auth domain | Auth Service | `auth.devo.customer.example.com` |
| OIDC Discovery domain | OIDC discovery endpoint | `oidc.customer.example.com` |
| Control Plane UI domain | Admin UI | `admin.customer.example.com` |

> **Note**: OIDC Discovery and Control Plane UI domains are global (shared by all stacks), while API/Control/Auth domains are per-stack.

### 1.4 Decide Pulumi Backend Resource Names

| Config | Description |
|--------|-------------|
| Pulumi state bucket name | Globally unique S3 bucket name for Pulumi state |
| Pulumi KMS alias | KMS alias for Pulumi secrets encryption |

---

## 2. Prepare AWS

### 2.1 Create or Confirm AWS Accounts

You need one or more AWS accounts to host LTBase stacks.

**If you do not have an AWS account:**

1. Visit https://aws.amazon.com to create an account.
2. Consider [creating an AWS Organization](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_tutorials_basic.html) for unified multi-account management (not a hard requirement for LTBase).
3. Record the account ID (12 digits) for each account, found in the top-right account menu of the AWS Console.

**If you already have AWS accounts:**

Confirm account IDs and regions are finalized, and you have sufficient permissions to create IAM resources, S3 buckets, and KMS keys.

### 2.2 Prepare Operator AWS Identity

You need an AWS identity that can operate on your accounts. Use IAM Identity Center (SSO) and avoid long-lived access keys.

#### Configure a profile with `aws configure sso`

If you use AWS Organizations / IAM Identity Center, run the `aws configure sso` interactive wizard to configure a local profile:

```bash
aws configure sso
```

The wizard prompts for the following, explained item by item:

| Prompt | What to enter | Notes |
|--------|---------------|-------|
| `SSO session name` | e.g. `customer-ltbase` | A session name so multiple profiles can reuse the same SSO login |
| `SSO start URL` | e.g. `https://your-org.awsapps.com/start` | From the AWS access portal / IAM Identity Center console |
| `SSO region` | e.g. `us-east-1` | The region hosting IAM Identity Center; **not necessarily** the stack deployment region |
| `SSO registration scopes` | `sso:account:access` | Default scope for listing accounts/roles; if the prompt already shows `[sso:account:access]`, just press Enter |

After you press Enter, the browser opens an authorization page. Once authorized, the wizard continues:

| Prompt | What to enter | Notes |
|--------|---------------|-------|
| Select AWS account | Choose the target stack's account from the list | Auto-selected if only one account is available |
| Select permission set / role | Choose a role with sufficient permissions | Auto-selected if only one role is available |
| `Default client Region` | The AWS region for this profile's stack, e.g. `ap-northeast-1` | The default region this profile operates in |
| `CLI default output format` | `json` recommended | CLI output format |
| `Profile name` | e.g. `customer-devo` | Use the stack name so it aligns with `AWS_PROFILE_<STACK>` in `.env` |

Log in (or re-login after the token expires):

```bash
aws sso login --profile customer-devo
```

#### Multiple AWS accounts

If different stacks use different AWS accounts, configure one profile per account (they can reuse the same `SSO session name`) and set the matching `AWS_PROFILE_<STACK>` in `.env`:

```bash
aws configure sso   # profile name: customer-devo
aws configure sso   # profile name: customer-prod
```

```bash
# .env
AWS_PROFILE_DEVO=customer-devo
AWS_PROFILE_PROD=customer-prod
```

### 2.3 Test AWS Access

For each stack's AWS account, verify credentials:

```bash
# For each stack
aws sts get-caller-identity --profile customer-devo
# Expected output: Account, Arn, UserId
```

If the SSO token has expired, log in again before testing:

```bash
aws sso login --profile customer-devo
aws sts get-caller-identity --profile customer-devo
```

### 2.4 Prepare Bootstrap Operator Permissions

Bootstrap scripts need to create AWS resources. You have two options:

#### Option A: Run bootstrap directly (you have admin permissions)

If the operator has sufficient AWS permissions (e.g., AdministratorAccess), run bootstrap directly. The scripts will automatically create the OIDC provider, deploy roles, Pulumi backend bucket, KMS alias, etc.

See the "Bootstrap minimum permissions" section below for details.

#### Option B: Generate minimal policies for a platform admin to grant

If the operator lacks direct IAM creation permissions, a platform admin must grant minimal permissions first.

> This depends on `.env` values. **After filling in `.env` in step 7**, run:
>
> ```bash
> ./scripts/render-bootstrap-policies.sh --env-file .env
> ```
>
> This generates the following policy files in `dist/`:
>
> | File | Purpose |
> |------|---------|
> | `dist/bootstrap-operator-<stack>-policy.json` | Permissions needed for each stack account |
> | `dist/bootstrap-operator-first-stack-s3-policy.json` | Additional S3 permissions for the first stack (owns the shared Pulumi backend bucket) |
>
> Give these policy files to the platform admin to grant in the corresponding AWS accounts.

### 2.5 Bootstrap Minimum Permissions Reference

If you need to create AWS resources manually (instead of letting bootstrap scripts do it), here are the minimum permissions:

**All stack accounts require:**

- `iam:GetOpenIDConnectProvider`
- `iam:CreateOpenIDConnectProvider`
- `iam:GetRole`
- `iam:CreateRole`
- `iam:UpdateAssumeRolePolicy`
- `iam:PutRolePolicy`
- `iam:ListAliases` (KMS)
- `kms:CreateKey`
- `kms:CreateAlias`

**The first stack account (`PROMOTION_PATH` first entry) additionally requires:**

- `s3:HeadBucket`
- `s3:CreateBucket`
- `s3:PutBucketVersioning`
- `s3:PutBucketEncryption`
- `s3:PutPublicAccessBlock`

---

## 3. Prepare GitHub

### 3.1 Confirm GitHub Account

You need a GitHub organization or personal account that can host a private repository.

```bash
# Confirm CLI is authenticated
gh auth status

# If not authenticated, log in
gh auth login
```

### 3.2 Confirm Permissions

The authenticated GitHub account must be able to:

- Create private repositories under `GITHUB_OWNER`
- Write repository secrets and variables in the deployment repository
- Create GitHub environments in the deployment repository (for protected environment approval gates)

### 3.3 Confirm GITHUB_OWNER

`GITHUB_OWNER` in `.env` is your GitHub organization name or personal username.

```bash
# If using an organization, confirm membership
gh api user/orgs --jq '.[].login'
```

---

## 4. Prepare Cloudflare

### 4.1 Confirm Cloudflare Zone

You need a Cloudflare zone for your domains.

```bash
# List your zones
curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones" | jq '.result[] | {name, id}'
```

Record these two values:

| Value | Description |
|-------|-------------|
| Cloudflare account ID | Visible at the bottom of the Cloudflare Dashboard sidebar |
| Cloudflare zone ID | The `id` field from the command above |

### 4.2 Create Cloudflare API Token

In Cloudflare Dashboard → My Profile → API Tokens → Create Token.

**Required permissions:**

| Resource | Permission |
|----------|-----------|
| Account - Cloudflare Pages | Edit |
| Zone - DNS | Edit |
| Zone - Zone Settings | Read |
| Zone - Custom Domains (Pages) | Edit |

> Zone Settings Read is required for the mTLS audit step in preview/rollout workflows.

### 4.3 Cloudflare SSL and Authenticated Origin Pulls Requirements

After deployment, all LTBase services (`api`, `auth`, `control-plane`) must be accessed through Cloudflare proxying with API Gateway mutual TLS enabled.

Before deployment, confirm:
- The Cloudflare zone uses `Full (strict)` SSL mode
- You plan to enable Authenticated Origin Pulls for API hostnames after deployment

---

## 5. Prepare LTBase Inputs

### 5.1 LTBase Releases Token

Obtain a customer-specific `LTBASE_RELEASES_TOKEN` from the LTBase team. This token is only used to download official release artifacts.

### 5.2 Gemini API Key

Obtain a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey).

### 5.3 Determine Release ID

Confirm the first LTBase release version you will deploy, e.g. `v1.0.23`. Obtain the available release ID from the LTBase team.

### 5.4 Prepare Firebase and Supabase Browser Config (Control Plane UI)

The Control Plane UI requires public Firebase and Supabase browser configuration for each stack. These are **public values** and must not contain secrets.

| Variable | Description | Example |
|----------|-------------|---------|
| `FIREBASE_API_KEY_<STACK>` | Firebase browser API key | `AIzaSy...` |
| `FIREBASE_PROJECT_ID_<STACK>` | Firebase project ID | `my-project` |
| `SUPABASE_URL_<STACK>` | Supabase project URL | `https://xxx.supabase.co` |
| `SUPABASE_ANON_KEY_<STACK>` | Supabase anonymous key | `eyJh...` |

> **Warning**: These values are delivered to browsers in the Control Plane UI runtime config. **Do not** put Firebase admin SDK private keys, Supabase service-role keys, or other secrets here.

### 5.5 Prepare Auth Provider Config

Copy the example files and edit the real auth provider configuration:

```bash
cp infra/auth-providers.devo.json.example infra/auth-providers.devo.json
cp infra/auth-providers.prod.json.example infra/auth-providers.prod.json
```

Edit the `.json` files to configure your JWT issuer, audience, etc.

> **Important**: Keep the provider names in `auth-providers.<stack>.json` aligned with the browser providers visible in the Control Plane UI. The bootstrap scripts reuse matching names when generating runtime config.

---

## 6. Create Deployment Repository and Clone

### 6.1 Create Repository from Template

On GitHub, create a **new private repository** from the `Lychee-Technology/ltbase-private-deployment` template.

```bash
gh repo create "${GITHUB_OWNER}/customer-ltbase" \
  --template Lychee-Technology/ltbase-private-deployment \
  --private \
  --description "Customer LTBase deployment repo"
```

### 6.2 Clone Locally

```bash
gh repo clone "${GITHUB_OWNER}/customer-ltbase"
cd customer-ltbase
```

### 6.3 Verify Repository Layout

Confirm these files and directories exist:

```bash
ls infra/
ls .github/workflows/
ls env.template
ls scripts/bootstrap-all.sh
ls scripts/evaluate-and-continue.sh
ls scripts/render-bootstrap-policies.sh
```

---

## 7. Fill in .env

The `.env` file is the input for all bootstrap and deployment configuration.

### 7.1 Create .env

```bash
cp env.template .env
```

**Never** commit `.env` to Git. It contains tokens and secrets.

### 7.2 Complete .env Example

Below is a complete `.env` example. Replace with your actual values.

```bash
# ============ Stack Topology ============
STACKS=devo,prod
PROMOTION_PATH=devo,prod

# ============ Repository Identity ============
TEMPLATE_REPO=Lychee-Technology/ltbase-private-deployment
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase
DEPLOYMENT_REPO_VISIBILITY=private
DEPLOYMENT_REPO_DESCRIPTION="Customer LTBase deployment repo"

# ============ Domains ============
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com

# ============ Cloudflare ============
CLOUDFLARE_ACCOUNT_ID=abc123def456
CLOUDFLARE_ZONE_ID=zone-abc123
CLOUDFLARE_API_TOKEN=your-api-token-here

# ============ AWS Environment (one set per stack) ============
# devo stack
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_ROLE_NAME_DEVO=ltbase-deploy-devo
# AWS_PROFILE_DEVO=customer-devo  # Needed when stacks use different AWS profiles

# prod stack
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_PROD=210987654321
AWS_ROLE_NAME_PROD=ltbase-deploy-prod
# AWS_PROFILE_PROD=customer-prod

# ============ Pulumi Backend ============
PULUMI_STATE_BUCKET=replace-with-pulumi-state-bucket
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
# PULUMI_BACKEND_URL           → derived by bootstrap, leave empty
# PULUMI_SECRETS_PROVIDER_DEVO → derived by bootstrap, leave empty
# PULUMI_SECRETS_PROVIDER_PROD → derived by bootstrap, leave empty

# ============ Domains (one set per stack) ============
API_DOMAIN_DEVO=api.devo.customer.example.com
API_DOMAIN_PROD=api.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
CONTROL_DOMAIN_PROD=control.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
AUTH_DOMAIN_PROD=auth.customer.example.com

# ============ CORS Config (optional) ============
# Leave empty to default to *
# API_CORS_ALLOW_ORIGINS_DEVO=*
# CONTROL_PLANE_CORS_ALLOW_ORIGINS_DEVO defaults to https://<CONTROLPLANE_UI_DOMAIN>

# ============ LTBase Application Config ============
PROJECT_ID=11111111-1111-4111-8111-111111111111
AUTH_PROVIDER_CONFIG_FILE_DEVO=infra/auth-providers.devo.json
AUTH_PROVIDER_CONFIG_FILE_PROD=infra/auth-providers.prod.json

# ============ Release Config ============
LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases
LTBASE_RELEASE_ID=v1.0.23
LTBASE_RELEASES_TOKEN=your-releases-token-here

# ============ mTLS Config ============
MTLS_TRUSTSTORE_FILE=infra/certs/cloudflare-origin-pull-ca.pem
MTLS_TRUSTSTORE_KEY=mtls/cloudflare-origin-pull-ca.pem

# ============ Control Plane UI Browser Config ============
FIREBASE_API_KEY_DEVO=public-firebase-api-key
FIREBASE_API_KEY_PROD=public-firebase-api-key
FIREBASE_PROJECT_ID_DEVO=firebase-project-id
FIREBASE_PROJECT_ID_PROD=firebase-project-id
SUPABASE_URL_DEVO=https://project.supabase.co
SUPABASE_URL_PROD=https://project.supabase.co
SUPABASE_ANON_KEY_DEVO=public-anon-key
SUPABASE_ANON_KEY_PROD=public-anon-key

# ============ Application Defaults ============
GEMINI_MODEL=gemini-3.1-flash-lite
GEMINI_API_KEY=your-gemini-api-key
DSQL_PORT=5432
DSQL_DB=postgres
DSQL_USER=admin
DSQL_PROJECT_SCHEMA=ltbase
# DSQL_ENDPOINT → Do not set manually; resolved automatically by bootstrap and deploy
```

### 7.3 Field-by-Field Reference

#### Must Fill Manually

| Variable | Where to get it |
|----------|----------------|
| `STACKS` | Your deployment topology decision |
| `PROMOTION_PATH` | Your deployment topology decision |
| `GITHUB_OWNER` | Your GitHub organization or username |
| `DEPLOYMENT_REPO_NAME` | Desired repository name |
| `OIDC_DISCOVERY_DOMAIN` | Your domain plan |
| `CONTROLPLANE_UI_DOMAIN` | Your domain plan |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Dashboard |
| `CLOUDFLARE_ZONE_ID` | Cloudflare Dashboard |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token you created |
| `AWS_REGION_<STACK>` | Target region for each stack |
| `AWS_ACCOUNT_ID_<STACK>` | AWS account ID for each stack |
| `AWS_ROLE_NAME_<STACK>` | Deploy role name for each stack |
| `PULUMI_STATE_BUCKET` | Globally unique bucket name |
| `PULUMI_KMS_ALIAS` | KMS alias, keep default |
| `API_DOMAIN_<STACK>` | Your domain plan |
| `CONTROL_DOMAIN_<STACK>` | Your domain plan |
| `AUTH_DOMAIN_<STACK>` | Your domain plan |
| `PROJECT_ID` | LTBase project ID (UUID format) |
| `AUTH_PROVIDER_CONFIG_FILE_<STACK>` | Points to `infra/auth-providers.<stack>.json` |
| `LTBASE_RELEASE_ID` | Release version to deploy |
| `LTBASE_RELEASES_TOKEN` | From LTBase team |
| `GEMINI_API_KEY` | From Google AI Studio |
| `FIREBASE_API_KEY_<STACK>` | Firebase project settings (browser-public) |
| `FIREBASE_PROJECT_ID_<STACK>` | Firebase project settings (browser-public) |
| `SUPABASE_URL_<STACK>` | Supabase project settings (browser-public) |
| `SUPABASE_ANON_KEY_<STACK>` | Supabase project settings (browser-public) |

#### Derived by Bootstrap (Must Leave Empty)

| Variable | Derivation Rule |
|----------|----------------|
| `PULUMI_BACKEND_URL` | `s3://${PULUMI_STATE_BUCKET}` |
| `PULUMI_SECRETS_PROVIDER_<STACK>` | `awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION_<STACK>}` |
| `AWS_ROLE_ARN_<STACK>` | `arn:aws:iam::${AWS_ACCOUNT_ID_<STACK>}:role/${AWS_ROLE_NAME_<STACK>}` |
| `OIDC_ISSUER_URL_<STACK>` | `https://${OIDC_DISCOVERY_DOMAIN}/<stack>` |
| `JWKS_URL_<STACK>` | `https://${OIDC_DISCOVERY_DOMAIN}/<stack>/.well-known/jwks.json` |
| `DEPLOYMENT_REPO` | `${GITHUB_OWNER}/${DEPLOYMENT_REPO_NAME}` |
| `GITHUB_ORG` / `GITHUB_REPO` | Derived from above |
| `OIDC_DISCOVERY_PAGES_PROJECT` | Derived from repo name |
| `RUNTIME_BUCKET_<STACK>` | `<DEPLOYMENT_REPO_NAME>-runtime-<stack>` |
| `SCHEMA_BUCKET_<STACK>` | `<DEPLOYMENT_REPO_NAME>-schema-<stack>` |
| `TABLE_NAME_<STACK>` | `<DEPLOYMENT_REPO_NAME>-<stack>` |
| `PREVIEW_DEFAULT_STACK` | First stack in `PROMOTION_PATH` |

#### Must Keep at Default

| Variable | Value | Notes |
|----------|-------|-------|
| `MTLS_TRUSTSTORE_FILE` | `infra/certs/cloudflare-origin-pull-ca.pem` | Cloudflare official AOP truststore |
| `MTLS_TRUSTSTORE_KEY` | `mtls/cloudflare-origin-pull-ca.pem` | truststore key in runtime bucket |
| `DSQL_HOST` / `DSQL_ENDPOINT` / `DSQL_PASSWORD` | **Do not set** | Managed deployments are auto-resolved |

### 7.4 Multi-Account Notes

If different stacks use different AWS accounts, set `AWS_PROFILE_<STACK>` for each:

```bash
AWS_PROFILE_DEVO=customer-devo
AWS_PROFILE_PROD=customer-prod
```

Test each profile:

```bash
aws sts get-caller-identity --profile customer-devo
aws sts get-caller-identity --profile customer-prod
```

> **Important**: The Pulumi shared backend bucket is created in the AWS account for the first stack in `PROMOTION_PATH`. That account's credentials must be able to create and manage the bucket.

---

## 8. Preflight Check

Before running bootstrap, perform preflight checks to ensure all prerequisites are met.

### 8.1 Check GitHub Access

```bash
gh auth status
```

### 8.2 Check AWS Access

```bash
# For each account per stack
aws sts get-caller-identity --profile customer-devo
```

### 8.3 Review Bootstrap IAM Policies (Optional but recommended)

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
```

Review the generated files in `dist/` to confirm policy content and scope match expectations.

### 8.4 Run Bootstrap Scan (without --force)

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

**Normal output**: Shows statuses like `needs_foundation`, `needs_repo_config`, `needs_stack_bootstrap`, `needs_oidc_discovery`. All steps showing "needs" means nothing has run yet — this is normal.

**Abnormal output**:

- Authentication failures (GitHub, AWS, Cloudflare, Pulumi)
- `missing required variable` → `.env` is missing required fields
- Hard exit → environment does not meet bootstrap prerequisites

**If preflight reports errors**: Fix `.env` or permissions based on the error messages, then rerun preflight until no hard errors remain.

---

## 9. Run Bootstrap

### 9.1 One-Click Bootstrap (Recommended)

If you have sufficient GitHub, AWS, and Cloudflare permissions, use one-click bootstrap:

```bash
# For split AWS accounts, ensure profile is correct first
export AWS_PROFILE=customer-devo  # or confirm AWS_PROFILE_<STACK> is in .env

./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

**One-click bootstrap runs these stages in order:**

1. `create-deployment-repo.sh` — Ensures the remote repository exists
2. `render-bootstrap-policies.sh` — Generates IAM policy artifacts
3. `bootstrap-aws-foundation.sh` — Creates GitHub OIDC provider, deploy roles, Pulumi backend bucket, KMS alias
4. `bootstrap-oidc-discovery.sh` — Creates OIDC discovery Cloudflare Pages project and DNS
5. `bootstrap-controlplane-ui-companion.sh` — Creates Control Plane UI companion repo and Pages
6. `bootstrap-deployment-repo.sh` — Configures Pulumi and GitHub values/secrets for each stack

**Verify after completion:**

```bash
# Check GitHub repository variables
gh variable list --repo "${GITHUB_OWNER}/customer-ltbase"

# Check GitHub repository secrets (lists names only)
gh secret list --repo "${GITHUB_OWNER}/customer-ltbase"

# Check Pulumi stack files
ls infra/Pulumi.*.yaml

# Verify each Pulumi stack file includes control plane CORS config
grep -l 'controlPlaneCorsOrigins' infra/Pulumi.*.yaml
```

> **Recovery-aware**: `evaluate-and-continue.sh` is idempotent. If it fails mid-way, fix the error and rerun — it skips already-completed steps.

### 9.2 Manual Bootstrap (When Permissions Are Limited)

If you lack permissions for automated resource creation, or want to control each stage:

#### Create Repository

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

#### Bootstrap AWS Foundation

```bash
# Ensure AWS credentials are ready
./scripts/bootstrap-aws-foundation.sh --env-file .env

# Source generated values into current shell
source dist/foundation.env
```

#### Bootstrap OIDC Discovery

```bash
./scripts/bootstrap-oidc-discovery.sh --env-file .env
```

#### Bootstrap Control Plane UI Companion

```bash
./scripts/bootstrap-controlplane-ui-companion.sh --env-file .env
```

#### Configure Pulumi for Each Stack

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

#### Final Confirmation

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

Confirm all statuses show `complete`.

---

## 10. Preview

The preview workflow validates Pulumi stack configuration, checks customer schemas, and runs `pulumi preview`. It **only** performs infrastructure preview and **does not** publish the Control Plane UI.

Preview **only** supports the first stack in `PROMOTION_PATH`.

### Via CLI

```bash
gh workflow run preview.yml \
  -f target_stack=devo \
  --ref main
```

Check run status:

```bash
gh run list --workflow="Preview LTBase Blueprint" --limit 3
```

Watch progress:

```bash
gh run watch $(gh run list --workflow="Preview LTBase Blueprint" --limit 1 --json databaseId --jq '.[0].databaseId')
```

### Preview Output Review

After the preview workflow completes, inspect the GitHub Actions run page:

1. **validate_config** step: Pulumi stack config validation passed
2. **preview** step: Pulumi preview output, confirm changes are within expected scope
3. **audit_mtls** step: Cloudflare mTLS configuration audit

If preview results do not match expectations, fix the configuration or bootstrap gap before starting rollout.

---

## 11. Rollout

The rollout workflow deploys across `PROMOTION_PATH` one hop at a time. Protected environments trigger a GitHub environment approval gate after each hop.

- The first stack in `PROMOTION_PATH` deploys automatically, no approval needed.
- Each subsequent hop requires your approval in the GitHub environment gate.
- Each hop automatically reconciles managed DSQL endpoint and authservice project info after `pulumi up`.

### 11.1 Trigger via CLI

```bash
gh workflow run rollout.yml \
  -f release_id=v1.0.23 \
  --ref main
```

Check run status:

```bash
gh run list --workflow="Rollout LTBase Release" --limit 3
```

### 11.2 Approve Protected Environments

When rollout reaches a hop requiring approval, GitHub pauses and waits.

You will be notified via Slack/Email, or check via CLI:

```bash
gh run list --workflow="Rollout LTBase Release" --status=waiting
```

In the GitHub Actions run page, click Review pending deployments to approve.

### 11.3 Deploy Only the Start Stack (No Auto-Promotion)

To deploy only the first stack in `PROMOTION_PATH` without auto-promotion:

```bash
gh workflow run deploy-devo.yml -f release_id=v1.0.23 --ref main
```

### 11.4 Manually Promote a Single Hop

If the auto-promotion chain breaks, or you need to promote a single hop:

```bash
gh workflow run promote-prod.yml \
  -f release_id=v1.0.23 \
  -f from_stack=devo \
  -f to_stack=prod \
  --ref main
```

> **Note**: `from_stack` and `to_stack` must be adjacent in `PROMOTION_PATH`.

### 11.5 What Each Rollout Hop Does Automatically

Each rollout hop:

1. Runs `pulumi up`
2. Reconciles managed DSQL endpoint (fetches authoritative endpoint from AWS, writes to Pulumi config)
3. Runs a second `pulumi up` (so Lambda environment variables pick up the managed DSQL endpoint)
4. Reconciles authservice `project info` DynamoDB record
5. Publishes customer schemas to stack schema bucket
6. Publishes Control Plane UI to Cloudflare Pages (if `CONTROLPLANE_UI_PAGES_PROJECT` is configured)
7. Runs Cloudflare mTLS audit

---

## 12. Publish OIDC Discovery

OIDC Discovery serves each stack's `openid-configuration` and `jwks.json` for external JWT verification.

### Why after Rollout

OIDC Discovery documents are derived from each stack's authservice signing KMS key. **That KMS key is created by Pulumi during deployment** (see `alias/ltbase-oidc-discovery-<stack>-authservice`). So publishing OIDC Discovery must happen **after** that stack's first rollout; triggering it before rollout fails because the KMS key does not exist yet.

### Current Publish Model

- There is no OIDC Discovery companion repository or standalone repository.
- Bootstrap (step 9) already prepares the hosting resources: the Cloudflare Pages project, custom domain, DNS CNAME, deployment repo variables (`OIDC_DISCOVERY_DOMAIN`, `OIDC_DISCOVERY_STACK_CONFIG`, `OIDC_DISCOVERY_PAGES_PROJECT`), and per-stack OIDC discovery IAM roles.
- Generating and uploading the discovery documents is done by the deployment repo's built-in `publish-oidc-discovery.yml` workflow: it runs `scripts/build-discovery.sh` to generate the documents, then **direct-uploads** them to the `${OIDC_DISCOVERY_PAGES_PROJECT}` Cloudflare Pages project via `wrangler pages deploy`.

> **Note**: In the current version, neither bootstrap nor rollout automatically triggers `publish-oidc-discovery.yml`. You must trigger it manually once after each stack's first rollout completes.

### Trigger via GitHub Actions UI

In your repository's Actions tab, select **Publish OIDC Discovery Documents**, click Run workflow, Branch `main`, set `target_stack` to the stack that has completed rollout (or `all` once every target stack has been rolled out).

### Trigger via CLI

```bash
# Publish only a stack that has completed rollout (recommended after each hop)
gh workflow run publish-oidc-discovery.yml \
  -f target_stack=devo \
  --ref main

# Once every target stack has completed its first rollout, refresh them all
gh workflow run publish-oidc-discovery.yml \
  -f target_stack=all \
  --ref main
```

Check run status:

```bash
gh run list --workflow=publish-oidc-discovery.yml --limit 3
```

> **Note**: Cloudflare Pages direct upload is a whole-site deploy. When publishing a single stack, `build-discovery.sh` only regenerates that stack's documents; publish each stack after its first rollout, or use `target_stack=all` once all rollouts are complete, to avoid missing a stack.

> **Note**: OIDC discovery IAM roles only trust workflows dispatched from the default branch (`repo:<DEPLOYMENT_REPO>:ref:refs/heads/<default_branch>`). Dispatching from any other branch causes AWS role assumption to fail.

### Ideal State (Future Work)

Ideally, OIDC Discovery would be published automatically during rollout instead of requiring a separate manual trigger. The plan is to add a job after the `rollout-hop.yml` rollout succeeds that direct-uploads the subset of already-deployed stacks in `PROMOTION_PATH` from the start up to the current target stack. That is a follow-up code change; this document will be updated once it lands.

---

## 13. First Deployment Verification

After rollout completes, verify each item:

### 13.1 Basic Verification

```bash
# Check Pulumi stack outputs
pulumi stack output --stack "org/customer-ltbase/devo" -C infra

# Verify OIDC discovery endpoint is reachable
curl -s "https://${OIDC_DISCOVERY_DOMAIN}/devo/.well-known/openid-configuration" | jq

# Verify API custom domain is reachable (4xx is normal, means DNS and proxying work)
curl -s -o /dev/null -w "%{http_code}" "https://${API_DOMAIN_DEVO}/health"
```

### 13.2 Control Plane UI Verification

- Visit `https://${CONTROLPLANE_UI_DOMAIN}` in a browser
- Confirm `/ltbase-controlplane.config.json` is accessible
- Confirm Firebase / Supabase login options are visible
- Confirm the redirect URI is configured in the identity provider: `https://${CONTROLPLANE_UI_DOMAIN}/auth/callback`

### 13.3 Cloudflare mTLS Verification

```bash
./scripts/check-cloudflare-mtls.sh --env-file .env --stack devo
```

Check items:

- `api`, `auth`, `control-plane` DNS records are orange-clouded (proxied) in Cloudflare
- Cloudflare SSL mode is `Full (strict)`
- Cloudflare Authenticated Origin Pulls is enabled
- truststore object exists in the stack runtime bucket
- API Gateway custom domain has mutual TLS configured

### 13.4 Schema Verification

Confirm the schema bucket has the correct published records:

```bash
# List schema bucket contents (requires AWS credentials)
aws s3 ls "s3://${SCHEMA_BUCKET_DEVO}/schemas/releases/" --profile customer-devo

# Check published manifest
aws s3 cp "s3://${SCHEMA_BUCKET_DEVO}/schemas/published/manifest.json" - --profile customer-devo | jq
```

### 13.5 Managed DSQL Verification

Confirm the managed DSQL endpoint is correctly set:

```bash
# Check dsqlEndpoint in Pulumi stack config
pulumi stack output --stack "org/customer-ltbase/devo" -C infra | grep -i dsql
```

If the DSQL endpoint is empty or incorrect, manually reconcile:

```bash
./scripts/reconcile-managed-dsql-endpoint.sh --env-file .env --stack devo --infra-dir infra
```

### 13.6 Auth Service Project Info Verification

If the auth service project info record is missing or incorrect, manually reconcile:

```bash
./scripts/reconcile-project-info.sh --env-file .env --stack devo --infra-dir infra
```

---

## 14. Common Errors and Recovery

### 14.1 AWS Credential Errors

**Symptom**: bootstrap or preview reports `InvalidClientTokenId` or `AccessDenied`

```bash
# Confirm credentials
aws sts get-caller-identity --profile customer-devo
# Confirm SSO session is not expired
aws sso login --profile customer-devo
```

### 14.2 Cloudflare API Token Insufficient Permissions

**Symptom**: bootstrap fails to create Pages or DNS records

Check token permissions:
- Account: Cloudflare Pages — Edit
- Zone: DNS — Edit
- Zone: Zone Settings — Read

### 14.3 Pulumi Config Drift

**Symptom**: preview or rollout fails with missing key in validate_config step

Fix by re-bootstrapping the stack's Pulumi config based on the missing key in the error:

```bash
# Re-bootstrap Pulumi config for a stack
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
```

### 14.4 Control Plane UI Operator Login Failure

Check in order:

1. `CONTROLPLANE_UI_DOMAIN` still points to the correct Cloudflare Pages domain
2. Identity provider allows `https://${CONTROLPLANE_UI_DOMAIN}/auth/callback`
3. Provider names in `infra/auth-providers.<stack>.json` match the browser-visible providers
4. Control Plane API CORS includes `https://${CONTROLPLANE_UI_DOMAIN}`
5. Firebase / Supabase values are correct (public client values, no secrets)

### 14.5 Managed DSQL Endpoint Incomplete

**Symptom**: Lambda cannot connect to DSQL

```bash
# Manual reconcile
./scripts/reconcile-managed-dsql-endpoint.sh --env-file .env --stack devo --infra-dir infra

# Then re-rollout or single deploy
gh workflow run deploy-devo.yml -f release_id=v1.0.23 --ref main
```

### 14.6 mTLS 403 / 526 Errors

- **403**: Cloudflare may not be presenting the expected client certificate chain, or the truststore has drifted
- **526**: Origin TLS is incompatible with `Full (strict)`, or the custom domain certificate is not yet valid

Confirm:
- Cloudflare SSL mode is `Full (strict)`
- Cloudflare Authenticated Origin Pulls is enabled
- Direct `execute-api` access fails (this is expected when mTLS is active)

---

## 15. Day-2 Operations

### 15.1 Upgrade to a New LTBase Release

```bash
# 1. Sync latest template tooling (optional, on main branch)
./scripts/update-sync-template-tooling.sh
./scripts/sync-template-upstream.sh

# 2. Update LTBASE_RELEASE_ID GitHub variable
gh variable set LTBASE_RELEASE_ID --body "v1.0.24" \
  --repo "${GITHUB_OWNER}/customer-ltbase"

# 3. Run preview for the first stack
gh workflow run preview.yml -f target_stack=devo --ref main

# 4. After confirming preview is correct, run rollout
gh workflow run rollout.yml -f release_id=v1.0.24 --ref main
```

### 15.2 Verify mTLS Configuration

```bash
./scripts/check-cloudflare-mtls.sh --env-file .env --stack devo
```

### 15.3 View Stack Outputs

```bash
pulumi stack output --stack "org/customer-ltbase/devo" -C infra
pulumi stack output --stack "org/customer-ltbase/prod" -C infra
```

### 15.4 Operational Constraints

| Constraint | Notes |
|------------|-------|
| Do not build the application yourself | The deployment repo downloads official releases only |
| Do not commit .env | `.env` contains secrets and tokens |
| Do not bypass the approval gate | Production environment protected gates must be approved |
| Do not change release ID mid-rollout | The entire promotion path uses one release ID |
| Do not manually set DSQL endpoint | Managed deployments are auto-reconciled |
| Keep Cloudflare SSL at Full (strict) | Never downgrade SSL mode |

---

## Related Documents

| Document | Purpose |
|----------|---------|
| [BOOTSTRAP.md](BOOTSTRAP.md) | Quick bootstrap checklist |
| [onboarding/01-prerequisites.md](onboarding/01-prerequisites.md) | Detailed prerequisites checklist |
| [onboarding/02-create-repo-and-clone.md](onboarding/02-create-repo-and-clone.md) | Repository creation details |
| [onboarding/03-create-oidc-and-deploy-roles.md](onboarding/03-create-oidc-and-deploy-roles.md) | OIDC and role details |
| [onboarding/04-prepare-env-file.md](onboarding/04-prepare-env-file.md) | .env field reference |
| [onboarding/05-bootstrap-one-click.md](onboarding/05-bootstrap-one-click.md) | One-click bootstrap details |
| [onboarding/06-bootstrap-manual.md](onboarding/06-bootstrap-manual.md) | Manual bootstrap details |
| [onboarding/07-first-deploy-and-managed-dsql.md](onboarding/07-first-deploy-and-managed-dsql.md) | First deploy and DSQL handling |
| [onboarding/08-day-2-operations.md](onboarding/08-day-2-operations.md) | Day-2 operations details |
| [CONTROLPLANE_UI_DEPLOYMENT_CHECKLIST.md](CONTROLPLANE_UI_DEPLOYMENT_CHECKLIST.md) | Control Plane UI deployment checklist |
