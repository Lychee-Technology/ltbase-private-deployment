> **中文版：[BOOTSTRAP.zh.md](BOOTSTRAP.zh.md)**

# Customer Bootstrap Quick Checklist

This is the quick step checklist for the customer deployment flow. New users should start with **[CUSTOMER_ONBOARDING.md](CUSTOMER_ONBOARDING.md)**; use this document as a cheat sheet.

For more detail on a specific flow, read the corresponding guide under [`onboarding/`](onboarding/).

## Quick Checklist

### 1. Pre-deployment decisions

- Decide `STACKS` (environment names, e.g. `devo,prod`)
- Decide `PROMOTION_PATH` (deployment order)
- Decide AWS region, account ID, and role name for each stack
- Decide API/Control/Auth/OIDC/UI domains
- Decide Pulumi state bucket name and KMS alias

### 2. Prepare prerequisites

- Confirm GitHub CLI authenticated: `gh auth status`
- Confirm access to each AWS account: `aws sts get-caller-identity --profile <profile>`
- Confirm Cloudflare zone and API token are ready
- Confirm `LTBASE_RELEASES_TOKEN` and `GEMINI_API_KEY` are available
- Confirm Firebase and Supabase browser config values (public, no secrets)
- Install local tools: `git`, `gh`, `aws`, `pulumi`, `python3`

See: [`onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)

### 3. Create deployment repository and clone

```bash
gh repo create "${GITHUB_OWNER}/customer-ltbase" \
  --template Lychee-Technology/ltbase-private-deployment \
  --private
gh repo clone "${GITHUB_OWNER}/customer-ltbase"
cd customer-ltbase
```

See: [`onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)

### 4. Fill in .env

```bash
cp env.template .env
```

Fill in all manual values, leave derived values empty. **Do not commit .env.**

- Stack topology: `STACKS`, `PROMOTION_PATH`
- Repository: `GITHUB_OWNER`, `DEPLOYMENT_REPO_NAME`
- Domains: `OIDC_DISCOVERY_DOMAIN`, `CONTROLPLANE_UI_DOMAIN`, per-stack API/Control/Auth domains
- Cloudflare: `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_API_TOKEN`
- AWS: `AWS_REGION_<STACK>`, `AWS_ACCOUNT_ID_<STACK>`, `AWS_ROLE_NAME_<STACK>`
- Pulumi: `PULUMI_STATE_BUCKET`, `PULUMI_KMS_ALIAS`
- Release: `LTBASE_RELEASES_REPO`, `LTBASE_RELEASE_ID`, `LTBASE_RELEASES_TOKEN`
- Application: `PROJECT_ID`, `AUTH_PROVIDER_CONFIG_FILE_<STACK>`, `GEMINI_API_KEY`
- Browser config: `FIREBASE_*_<STACK>`, `SUPABASE_*_<STACK>`
- Keep mTLS defaults as-is
- Do not manually set `DSQL_ENDPOINT`

See: [`onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)

### 5. Preflight check

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

### 6. Run bootstrap

**One-click path (recommended):**

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

**Manual path:**

```bash
./scripts/create-deployment-repo.sh --env-file .env
./scripts/bootstrap-aws-foundation.sh --env-file .env
source dist/foundation.env
./scripts/bootstrap-oidc-discovery.sh --env-file .env
./scripts/bootstrap-controlplane-ui-companion.sh --env-file .env
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

### 7. Publish OIDC Discovery

```bash
gh workflow run publish-oidc-discovery.yml -f target_stack=all --ref main
```

### 8. Preview

```bash
gh workflow run preview.yml -f target_stack=devo --ref main
```

### 9. Rollout

```bash
gh workflow run rollout.yml -f release_id=v1.0.23 --ref main
```

### 10. Verify

```bash
./scripts/check-cloudflare-mtls.sh --env-file .env --stack devo
pulumi stack output --stack "org/customer-ltbase/devo" -C infra
```

See: [`onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)

## Required GitHub Secrets

- `AWS_ROLE_ARN_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required GitHub Variables

- `AWS_REGION_<STACK>` for every stack in `STACKS`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

Bootstrap scripts write these values automatically.

## Day-2 Operations

- Upgrade: update `LTBASE_RELEASE_ID` → preview → rollout
- Sync template: `./scripts/update-sync-template-tooling.sh` → `./scripts/sync-template-upstream.sh`
- Audit mTLS: `./scripts/check-cloudflare-mtls.sh --env-file .env --stack <stack>`

See: [`onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
