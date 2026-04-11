> **[中文版](05-bootstrap-one-click.zh.md)**

# One-Click Bootstrap

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide when you want the repository creation, policy rendering, AWS foundation setup, stack bootstrap, and optional rollout trigger to run from one recovery-aware command.

## Before You Start

- complete [`04-prepare-env-file.md`](04-prepare-env-file.md)
- use a local clone of your real deployment repository if possible
- have enough GitHub and AWS permissions to create and update all required resources
- have enough Cloudflare permissions to manage the OIDC discovery Pages project, custom domain, and DNS record

Before using the one-click path, review the minimum bootstrap permission matrix in [`01-prerequisites.md`](01-prerequisites.md).

If you do not have those minimum GitHub, AWS, or Cloudflare permissions, use [`06-bootstrap-manual.md`](06-bootstrap-manual.md) instead and have the missing resources created outside the script.

## Recommended Working Pattern

The one-click flow is recovery-aware, but the recommended customer onboarding flow is still:

1. create the real deployment repository first
2. clone that repository locally
3. prepare `.env` in that checkout
4. run one-click bootstrap from that checkout root

This matters because the bootstrap stages also write local `infra/Pulumi.<stack>.yaml` files.

If you intentionally let the automation create a missing remote repository during recovery, clone the new repository before you review or commit generated local Pulumi stack files.

## Readiness Checklist

Confirm all of the following before you run `--force`:

1. GitHub CLI is authenticated.

```bash
gh auth status
```

2. The authenticated GitHub account can:
   - create private repositories under `GITHUB_OWNER`
   - write repository secrets and variables
   - create GitHub environments for later promotion approvals
3. `.env` contains final customer-controlled values for:
   - repository identity
   - stack/account/region mapping
   - domains
   - Cloudflare IDs and token
   - release ID and releases token
   - Gemini API key
4. If stacks use different AWS accounts, `AWS_PROFILE_<STACK>` values are already configured and tested.

```bash
AWS_PROFILE_STAGING=customer-staging aws sts get-caller-identity
```

5. You are intentionally leaving derived values blank unless you need overrides.
6. You are not manually setting `DSQL_ENDPOINT` for managed deployments.
7. The credentials for the first stack in `PROMOTION_PATH` can create and manage the shared Pulumi backend bucket, because bootstrap anchors that bucket to the first stack account.

## Recommended Preflight

### 1. Optionally render the IAM policy artifacts for review

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
```

Use this step when you want to inspect the trust policies and inline role policies before the script creates or updates IAM resources.

### 2. Run the recovery-aware bootstrap scan without `--force`

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

What to expect:

- first-run statuses such as `needs_foundation`, `needs_repo_config`, `needs_stack_bootstrap`, or `needs_oidc_companion` are normal
- hard validation failures such as missing required variables are not normal and should be fixed before continuing
- authentication failures from GitHub, AWS, Cloudflare, or Pulumi are blockers and should be fixed before continuing
- the command also writes a machine-readable report to `dist/evaluate-and-continue/report.json`
- the OIDC companion is only `complete` when the companion repo, Pages project, custom domain binding, required `CNAME`, and discovery IAM roles are all present

## Steps

1. Open a terminal in the root of your deployment repository.
2. Confirm `.env` exists and contains the values you prepared.
3. If you have not already done the preflight scan above, do that now.
4. If you are using split AWS accounts, export the correct AWS credentials or confirm `AWS_PROFILE_<STACK>` values are present before running bootstrap.
5. Run:

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

If you also want bootstrap to trigger the first rollout automatically, include the release tag:

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra --release-id v1.0.0
```

6. Wait for the script to complete.
7. Review generated files in `dist/`, especially the recovery report and any rendered policy artifacts.
8. Confirm GitHub variables and secrets were created in the deployment repository.
9. Confirm every stack in `STACKS` was initialized.

## What This Command Does

The one-click script runs these stages in order:

- `create-deployment-repo.sh`
- `render-bootstrap-policies.sh`
- `bootstrap-aws-foundation.sh`
- `bootstrap-oidc-discovery-companion.sh`
- `bootstrap-deployment-repo.sh --stack <each stack in STACKS>`
- optional `gh workflow run rollout.yml ...` when `--release-id` is set

`bootstrap-aws-foundation.sh` creates the shared Pulumi backend bucket once in the AWS account for the first stack in `PROMOTION_PATH`, then prepares per-stack role and secrets-provider inputs for every stack in `STACKS`.

`bootstrap-oidc-discovery-companion.sh` also creates the required Cloudflare DNS `CNAME` for `OIDC_DISCOVERY_DOMAIN` so the custom domain resolves directly to `${OIDC_DISCOVERY_PAGES_PROJECT}.pages.dev`.

## Expected Result

You finish with repository configuration written to GitHub, Pulumi stacks initialized for every configured environment, and optionally the first rollout already queued.

## Common Mistakes

- trying one-click bootstrap without enough GitHub permissions
- trying one-click bootstrap without enough AWS permissions
- forgetting to prepare split-account credentials before running the script
- skipping the preflight scan and only learning about missing credentials after `--force` starts making changes
- running the command from the wrong checkout and then not finding the generated Pulumi stack files

## Next Step

Continue with [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md).
