> **[中文版](05-bootstrap-one-click.zh.md)**

# One-Click Bootstrap

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide when you want the repository creation, policy rendering, AWS foundation setup, stack bootstrap, and optional rollout trigger to run from one recovery-aware command.

## Before You Start

- complete [`04-prepare-env-file.md`](04-prepare-env-file.md)
- have enough GitHub and AWS permissions to create and update all required resources

## Steps

1. Open a terminal in the root of your deployment repository.
2. Confirm `.env` exists and contains the values you prepared.
3. If you are using split AWS accounts, export the correct AWS credentials or profiles before running bootstrap.
4. Run:

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

If you also want bootstrap to trigger the first rollout automatically, include the release tag:

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra --release-id v1.0.0
```

5. Wait for the script to complete.
6. Review any generated files in `dist/`.
7. Confirm GitHub variables and secrets were created in the deployment repository.
8. Confirm every stack in `STACKS` was initialized.

## What This Command Does

The one-click script runs these stages in order:

- `create-deployment-repo.sh`
- `render-bootstrap-policies.sh`
- `bootstrap-aws-foundation.sh`
- `bootstrap-oidc-discovery-companion.sh`
- `bootstrap-deployment-repo.sh --stack <each stack in STACKS>`
- optional `gh workflow run rollout.yml ...` when `--release-id` is set

## Expected Result

You finish with repository configuration written to GitHub, Pulumi stacks initialized for every configured environment, and optionally the first rollout already queued.

## Common Mistakes

- trying one-click bootstrap without enough GitHub permissions
- trying one-click bootstrap without enough AWS permissions
- forgetting to prepare split-account credentials before running the script

## Next Step

Continue with [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md).
