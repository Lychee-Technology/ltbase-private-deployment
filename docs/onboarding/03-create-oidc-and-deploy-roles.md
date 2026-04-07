# Create GitHub OIDC and Deploy Roles

> **[中文版](03-create-oidc-and-deploy-roles.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to prepare the AWS-side trust and deployment roles that GitHub Actions needs in order to preview and deploy LTBase.

## Note for one-click bootstrap users

If you plan to use the one-click bootstrap path (`evaluate-and-continue.sh`), the script runs `bootstrap-aws-foundation.sh` which creates OIDC providers, deploy roles, inline role policies, the shared Pulumi state bucket, and the Pulumi KMS alias automatically.

In that case, use this page to **review and verify** what will be created, rather than creating resources manually.

Before you choose one-click bootstrap, confirm that your AWS credentials can create or update all of the following:

- GitHub OIDC providers in every AWS account used by `STACKS`
- one deploy role per stack in `STACKS`
- trust policies and inline role policies on those roles
- the shared Pulumi state bucket in the AWS account for the first stack in `PROMOTION_PATH`
- the Pulumi KMS alias in each deployment region

If your AWS permissions do not allow the script to create or update those resources, follow the manual steps below instead.

## Before You Start

- complete [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md)
- know the AWS account ID for every stack in `STACKS`
- know your deployment repository full name, for example `customer-org/customer-ltbase`

## Steps

1. In each AWS account used for deployment, confirm whether the GitHub OIDC provider already exists.
2. If it does not exist, create the provider for `https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`.
3. Create one deploy role for each stack in `STACKS`.
4. Attach a trust policy that allows GitHub Actions from your deployment repository to assume each role.
5. Attach a permissions policy broad enough for first bootstrap and first deployment.
6. Make a note of every resulting role ARN.
7. If your stacks span multiple AWS accounts, confirm you can operate each account from your workstation, usually through separate AWS profiles.

The shared Pulumi backend is anchored to the first stack in `PROMOTION_PATH`. In split-account setups, that means the first stack account owns the shared backend bucket, while every stack still gets its own deploy role and secrets provider configuration.

## Practical Tip

If you want the template to generate copy-paste policy files for review, do that after `.env` is ready by using `./scripts/render-bootstrap-policies.sh --env-file .env`.

That command now generates two kinds of AWS bootstrap-operator policy templates as well:

- `dist/bootstrap-operator-<stack>-policy.json` for each stack account
- `dist/bootstrap-operator-first-stack-s3-policy.json` for the first stack account in `PROMOTION_PATH`

Use those files when a cloud administrator needs a concrete starting point for the minimum permissions required by one-click bootstrap.

For one-click users, this is the best preflight review step before you grant the script permission to create IAM resources.

## Expected Result

You now have a working OIDC trust chain and one deploy role per stack whose ARN can be placed into `.env`.

## Common Mistakes

- creating only one role and trying to reuse it for multiple stacks
- forgetting to include the deployment repository name in the trust policy
- using permissions that are too narrow for the first deployment

## Next Step

Continue with [`04-prepare-env-file.md`](04-prepare-env-file.md).
