# LTBase Customer Onboarding Runbook

This runbook is for customers deploying LTBase through the private deployment channel.

## Deployment Model

Your deployment uses three repositories:

- `ltbase-deploy-workflows`
  Public reusable GitHub Actions workflows maintained by LTBase.
- `ltbase-releases`
  Private official LTBase application releases. Access is controlled by your customer-specific token.
- your deployment repository
  A private repository created from the `ltbase-private-deployment` template. This repository holds your Pulumi stacks and deployment wrapper workflows.

Your deployment repository does not build LTBase application source code. It downloads an official LTBase release and deploys that version into your AWS account.

## What You Need Before Starting

- A GitHub organization or account that can host a private repository.
- A devo AWS account and, optionally, a separate prod AWS account.
- A Cloudflare zone for the domains you will use.
- Permission to create or update IAM roles, IAM OIDC providers, S3 buckets, and KMS keys in the target AWS accounts.
- A customer-specific `LTBASE_RELEASES_TOKEN` issued by LTBase.
- A Gemini API key for runtime summarization features.

## End State

When setup is complete, you will have:

- one private deployment repository created from `ltbase-private-deployment`
- one GitHub OIDC trust relationship per AWS account used for deployment
- one deploy role for `devo` and one deploy role for `prod`
- one Pulumi state bucket
- one AWS KMS key alias used for Pulumi stack secret encryption
- repository secrets and variables populated through the bootstrap scripts
- a `devo` stack ready for preview and deploy
- a `prod` stack ready for promotion after `devo` is validated

## Required Repository Secrets

Set these GitHub Actions secrets in your deployment repository:

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required Repository Variables

Set these GitHub Actions variables in your deployment repository:

- `AWS_REGION_DEVO`
- `AWS_REGION_PROD`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_DEVO`
- `PULUMI_SECRETS_PROVIDER_PROD`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

Recommended initial values:

- `AWS_REGION_DEVO=ap-northeast-1`
- `AWS_REGION_PROD=us-west-2`
- `PULUMI_BACKEND_URL=s3://ltbase-pulumi-state`
- `PULUMI_SECRETS_PROVIDER_DEVO=awskms://alias/ltbase-pulumi-secrets?region=ap-northeast-1`
- `PULUMI_SECRETS_PROVIDER_PROD=awskms://alias/ltbase-pulumi-secrets?region=us-west-2`
- `LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases`
- `LTBASE_RELEASE_ID=v1.0.0`

`env.template` includes these values as placeholders. Copy it to a local `.env` file, fill in the real values, and keep that file private.

## Required Pulumi Configuration

For each stack, configure these non-secret values:

- `awsRegion`
- `runtimeBucket`
- `tableName`
- `apiDomain`
- `controlPlaneDomain`
- `authDomain`
- `cloudflareZoneId`
- `oidcIssuerUrl`
- `jwksUrl`
- `githubOrg`
- `githubRepo`
- `releaseId`
- `dsqlPort`
- `dsqlDB`
- `dsqlUser`
- `dsqlProjectSchema`

Configure these as Pulumi secrets:

- `geminiApiKey`

Aurora DSQL itself is created by the Pulumi blueprint. You do not supply an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` for managed deployments.

## Step-By-Step Deployment

### 1. Create the deployment repository

1. Create a private repository from the public `ltbase-private-deployment` template.
2. Clone that repository locally.
3. Confirm the repository contains:
   - `infra/`
   - `.github/workflows/`
   - `env.template`
   - `scripts/render-bootstrap-policies.sh`
   - `scripts/create-deployment-repo.sh`
   - `scripts/bootstrap-aws-foundation.sh`
   - `scripts/bootstrap-pulumi-backend.sh`
   - `scripts/bootstrap-deployment-repo.sh`
   - `scripts/bootstrap-all.sh`

### 2. Create or confirm the GitHub OIDC provider

You need a GitHub OIDC provider in each AWS account used by deployment. If it already exists, reuse it.

Typical provider ARN:

```text
arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

If you need to create it, create it once per account with the standard GitHub issuer:

- URL: `https://token.actions.githubusercontent.com`
- audience: `sts.amazonaws.com`

### 3. Create the deploy roles

Create one IAM role for `devo` and one for `prod`. If `devo` and `prod` live in different AWS accounts, create one role in each account.

The bootstrap scripts do **not** create these IAM roles. They consume the role ARNs you provide in `.env` and write them into GitHub Actions secrets.

#### 3.1 Trust policy template

Use this trust policy as a starting point for each deploy role. Replace the placeholders:

- `<github-org>`
- `<repo-name>`
- `<default-branch>`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGitHubActionsOidc",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<github-org>/<repo-name>:ref:refs/heads/<default-branch>",
            "repo:<github-org>/<repo-name>:ref:refs/heads/feature/*",
            "repo:<github-org>/<repo-name>:pull_request"
          ]
        }
      }
    }
  ]
}
```

If you want to tighten this later, reduce the allowed `sub` patterns after your deployment process stabilizes.

#### 3.2 Permissions policy guidance

For the first successful deployment, the simplest path is to give the deploy role an administrator-scoped policy in the target account or an organization-approved equivalent broad deployment role. This is the fastest way to avoid chasing missing service permissions during the first bootstrap.

After the first deployment works, you can replace that with a tighter policy.

At minimum, the deploy role must be able to:

- read and write the Pulumi state bucket
- use the Pulumi KMS key
- create and update the AWS resources managed by the LTBase blueprint
- pass any IAM roles created during deployment if the blueprint requires it

#### 3.3 Minimal backend and KMS policy template

This is a useful baseline policy fragment for the Pulumi state bucket and secrets key. Replace the placeholders:

- `<state-bucket>`
- `<kms-key-arn>`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPulumiStateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::<state-bucket>"
    },
    {
      "Sid": "AllowPulumiStateObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::<state-bucket>/*"
    },
    {
      "Sid": "AllowPulumiSecretsKey",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "<kms-key-arn>"
    }
  ]
}
```

The bootstrap script also generates `dist/pulumi-kms-policy.json`, which you can use as a role-specific KMS access template.

### 4. Prepare the local `.env` file

1. Copy `env.template` to `.env`.
2. Fill in the real values.
3. Do not commit `.env`.

Minimum values you must provide:

```bash
DEPLOYMENT_REPO=<github-org>/<repo-name>

AWS_REGION_DEVO=<devo-region>
AWS_REGION_PROD=<prod-region>
AWS_ACCOUNT_ID_DEVO=<devo-account-id>
AWS_ACCOUNT_ID_PROD=<prod-account-id>
AWS_ROLE_ARN_DEVO=arn:aws:iam::<devo-account-id>:role/<devo-role>
AWS_ROLE_ARN_PROD=arn:aws:iam::<prod-account-id>:role/<prod-role>

PULUMI_STATE_BUCKET=<global-unique-state-bucket>
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets

LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases
LTBASE_RELEASE_ID=v1.0.0

API_DOMAIN=api.devo.example.com
CONTROL_DOMAIN=control.devo.example.com
AUTH_DOMAIN=auth.devo.example.com
CLOUDFLARE_ZONE_ID=<cloudflare-zone-id>
OIDC_ISSUER_URL=https://<issuer>
JWKS_URL=https://<issuer>/.well-known/jwks.json

RUNTIME_BUCKET=<global-unique-runtime-bucket>
TABLE_NAME=<devo-table-name>
GITHUB_ORG=<github-org>
GITHUB_REPO=<repo-name>
GEMINI_MODEL=gemini-3-flash-preview
DSQL_PORT=5432
DSQL_DB=ltbase
DSQL_USER=ltbase
DSQL_PROJECT_SCHEMA=ltbase

GEMINI_API_KEY=<gemini-api-key>
CLOUDFLARE_API_TOKEN=<cloudflare-api-token>
LTBASE_RELEASES_TOKEN=<ltbase-releases-token>
```

### 5. Optional review step: render copy-paste policies

If your security or platform team wants to review the exact trust and permissions policies before bootstrap, run:

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
```

This writes copy-paste-ready artifacts to `dist/`, including:

- `devo-trust-policy.json`
- `prod-trust-policy.json`
- `devo-role-policy.json`
- `prod-role-policy.json`
- `pulumi-kms-policy.json`
- `bootstrap-summary.env`

### 6. One-click bootstrap path

If you have enough GitHub and AWS permissions, use the one-click path:

```bash
./scripts/bootstrap-all.sh --env-file .env --mode apply --infra-dir infra
```

This orchestrates:

- creating the real deployment repo from the template
- creating or reusing the GitHub OIDC provider
- creating or reusing the deploy roles
- creating or reusing the Pulumi backend bucket and KMS key
- writing GitHub vars and secrets
- initializing `devo` and `prod` Pulumi stacks

### 7. Manual bootstrap path

If you want more control, run the steps individually.

#### 7.1 Create the real deployment repo

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

#### 7.2 Bootstrap the AWS foundation

```bash
./scripts/bootstrap-aws-foundation.sh --env-file .env
```

#### 7.3 Bootstrap the Pulumi backend and KMS configuration

Run:

```bash
./scripts/bootstrap-pulumi-backend.sh --env-file .env
```

This script will:

- create or reuse the Pulumi state bucket
- create or reuse the Pulumi KMS alias
- generate `dist/pulumi-backend.env`
- generate `dist/pulumi-kms-policy.json`

Review the outputs:

- `dist/pulumi-backend.env`
- `dist/pulumi-kms-policy.json`

If needed, merge the generated values back into `.env`:

```bash
source dist/pulumi-backend.env
```

#### 7.4 Bootstrap the repository configuration and the `devo` stack

Run:

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
```

This script will:

- write GitHub Actions variables
- write GitHub Actions secrets
- log into the Pulumi backend
- initialize the `devo` stack if it does not exist
- write Pulumi config for the `devo` stack
- store `geminiApiKey` as a Pulumi secret

#### 7.5 Bootstrap the `prod` stack

Run the same script for `prod`:

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

This will reuse the same repository secrets and variables, but apply the `prod` region and `prod` Pulumi secrets provider when configuring the `prod` stack.

### 8. Confirm repository configuration

Before running any deployment workflow, confirm the repository contains:

- secrets
  - `AWS_ROLE_ARN_DEVO`
  - `AWS_ROLE_ARN_PROD`
  - `LTBASE_RELEASES_TOKEN`
  - `CLOUDFLARE_API_TOKEN`
- variables
  - `AWS_REGION_DEVO`
  - `AWS_REGION_PROD`
  - `PULUMI_BACKEND_URL`
  - `PULUMI_SECRETS_PROVIDER_DEVO`
  - `PULUMI_SECRETS_PROVIDER_PROD`
  - `LTBASE_RELEASES_REPO`
  - `LTBASE_RELEASE_ID`

### 9. First deployment

1. Set `LTBASE_RELEASE_ID` to the release you want, such as `v1.0.0`.
2. Run the `preview` workflow manually.
3. Review the Pulumi preview output.
4. Run the `devo` deployment workflow.
5. Verify the `devo` environment.
6. Run the `prod` promotion workflow.
7. Approve the `prod` environment when GitHub asks for approval.

### 10. Day-2 upgrades

To adopt a new LTBase application version:

1. Change `LTBASE_RELEASE_ID` or pass a new `release_id` to the workflow.
2. Run preview.
3. Deploy to devo.
4. Promote the same `release_id` to prod.

You do not need to rebuild application binaries in your repository.

## Operational Constraints

- `LTBASE_RELEASES_TOKEN` is only for downloading official LTBase releases.
- Local `.env` files contain sensitive values and are ignored by git on purpose.
- The template repository does not auto-run preview on pull requests because template PRs do not have live customer deployment credentials.
- If your subscription ends, LTBase can revoke that token.
- Revoking the token does not shut down your existing environment.
- Revoking the token prevents your repository from downloading future LTBase releases.
- Prod approval happens in your repository through `environment: prod`.

## Default Version Policy

- Reusable workflows are consumed through `@v1`.
- The first stable LTBase release for this deployment channel is `v1.0.0`.
- `release_id` is the same value as the GitHub release tag in `ltbase-releases`.
