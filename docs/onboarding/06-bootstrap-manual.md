# Manual Bootstrap

> **[中文版](06-bootstrap-manual.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide when you want to review each bootstrap stage separately instead of running the one-click path.

## Before You Start

- complete [`04-prepare-env-file.md`](04-prepare-env-file.md)
- decide that you want to control each bootstrap stage manually

## Steps

### 1. Create the real deployment repo

Run:

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

### 2. Bootstrap AWS foundation

Run:

```bash
./scripts/bootstrap-aws-foundation.sh --env-file .env
```

This step creates or updates:

- GitHub OIDC provider
- deploy roles
- trust policies
- inline role policies
- Pulumi state bucket
- Pulumi KMS alias

It also generates `dist/foundation.env` and review artifacts.

### 3. Optionally merge generated foundation values

If bootstrap generated new Pulumi backend values, merge them into your shell or `.env`:

```bash
source dist/foundation.env
```

### 4. Bootstrap Pulumi backend only if needed

Run this if you want the backend/KMS path separately:

```bash
./scripts/bootstrap-pulumi-backend.sh --env-file .env
```

### 5. Bootstrap every configured stack

Run:

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack> --infra-dir infra
```

Repeat the command once for each stack listed in `STACKS`, in the same order as `PROMOTION_PATH`.

### 6. Bootstrap OIDC discovery companion

Run:

```bash
./scripts/bootstrap-oidc-discovery-companion.sh --env-file .env
```

This step creates or updates the OIDC discovery companion repository, Cloudflare Pages project, custom domain binding, and per-stack OIDC discovery IAM roles.

### 7. Confirm repository configuration

Check that the repository now contains the required GitHub secrets and variables.

## Expected Result

You finish with all bootstrap stages completed manually and the repository is ready for the first preview and deployment.

## Common Mistakes

- forgetting to source `dist/foundation.env` after AWS foundation generated new values
- skipping later stacks in `STACKS` and only preparing the first stack
- running manual bootstrap commands outside the repository root

## Next Step

Continue with [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md).
