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
- An AWS account for deployment.
- A Cloudflare zone for the customer domains you will use.
- A Pulumi backend bucket in your AWS account.
- A customer-specific `LTBASE_RELEASES_TOKEN` issued by LTBase.

## Required Repository Secrets

Set these GitHub Actions secrets in your deployment repository:

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required Repository Variables

Set these GitHub Actions variables in your deployment repository:

- `AWS_REGION`
- `PULUMI_BACKEND_URL`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

Recommended initial values:

- `AWS_REGION=ap-northeast-1`
- `LTBASE_RELEASES_REPO=Lychee-Technology/ltbase-releases`
- `LTBASE_RELEASE_ID=v1.0.0`

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
- `dsqlHost` or `dsqlEndpoint`
- `dsqlPort`
- `dsqlDB`
- `dsqlUser`
- `dsqlProjectSchema`

Configure these as Pulumi secrets:

- `dsqlPassword`
- `geminiApiKey`

## Initial Setup

1. Create a private repository from the public `ltbase-private-deployment` template.
2. Add the required GitHub Actions secrets and variables.
3. Copy or update `Pulumi.devo.yaml` and `Pulumi.prod.yaml` from the template examples.
4. Set Pulumi secrets for both stacks.
5. Confirm your deploy roles can be assumed through GitHub OIDC.
6. Confirm `LTBASE_RELEASES_TOKEN` can read the LTBase private releases repository.

## First Deployment

1. Set `LTBASE_RELEASE_ID` to `v1.0.0`.
2. Run the preview workflow.
3. Review the Pulumi preview output.
4. Run the devo deployment workflow.
5. Verify the devo environment.
6. Run the prod promotion workflow.
7. Approve the `prod` environment when GitHub asks for approval.

## Day-2 Upgrades

To adopt a new LTBase application version:

1. Change `LTBASE_RELEASE_ID` or pass a new `release_id` to the workflow.
2. Run preview.
3. Deploy to devo.
4. Promote the same `release_id` to prod.

You do not need to rebuild application binaries in your repository.

## Operational Constraints

- `LTBASE_RELEASES_TOKEN` is only for downloading official LTBase releases.
- If your subscription ends, LTBase can revoke that token.
- Revoking the token does not shut down your existing environment.
- Revoking the token prevents your repository from downloading future LTBase releases.
- Prod approval happens in your repository through `environment: prod`.

## Default Version Policy

- Reusable workflows are consumed through `@v1`.
- The first stable LTBase release for this deployment channel is `v1.0.0`.
- `release_id` is the same value as the GitHub release tag in `ltbase-releases`.
