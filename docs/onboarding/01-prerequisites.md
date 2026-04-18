> **中文版：[01-prerequisites.zh.md](01-prerequisites.zh.md)**

# Prepare Prerequisites

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to confirm that you have the minimum accounts, permissions, and local tools required before you begin bootstrap.

## Before You Start

You should have access to:

- a GitHub organization or personal account that can create private repositories
- one or more AWS accounts that will host the stacks listed in `STACKS`
- a Cloudflare zone for your application domains
- a Gemini API key
- a customer-specific `LTBASE_RELEASES_TOKEN`

Install or confirm these local tools:

- `git`
- `gh` (GitHub CLI)
- `aws` (AWS CLI)
- `pulumi`
- `python3`

## Readiness Checklist

### 1. Confirm GitHub access

1. Authenticate with GitHub CLI.

```bash
gh auth status
```

2. Confirm the authenticated account can create private repositories under the target `GITHUB_OWNER`.
3. Confirm the same account can later manage repository secrets, repository variables, and protected environments in the deployment repository.
4. Write down the final GitHub owner and repository name you plan to use.

### 2. Confirm AWS access

1. Write down the AWS account ID and AWS region for every stack in `STACKS`.
2. Confirm you can access each target AWS account from your workstation.

```bash
aws sts get-caller-identity
```

3. If different stacks use different AWS accounts, configure that switching method now.
4. If you plan to use per-stack profiles, test each one before bootstrap.

```bash
AWS_PROFILE_STAGING=customer-staging aws sts get-caller-identity
```

5. Confirm you have permission to create or update all bootstrap-managed AWS resources:
   - GitHub OIDC providers
   - deploy roles and trust policies
   - inline IAM role policies
   - the shared Pulumi state bucket in the AWS account for the first stack in `PROMOTION_PATH`
   - KMS alias for Pulumi secrets

### 3. Confirm Cloudflare access

1. Record the Cloudflare account ID and zone ID you will place into `.env`.
2. Confirm the zone already exists.
3. Confirm the API token can manage:
   - Cloudflare Pages projects
   - custom domain bindings
   - the zone DNS records used by your LTBase domains and `OIDC_DISCOVERY_DOMAIN`

## Minimum Permissions For Bootstrap

This section describes the minimum operator permissions needed for the one-click bootstrap path.

If you do not have these permissions, do not guess or keep retrying bootstrap. Use the manual path in [`06-bootstrap-manual.md`](06-bootstrap-manual.md) and ask the platform owner to create the missing resources for you.

### GitHub minimum permissions

The authenticated GitHub account must be able to:

- create the deployment repository from template under `GITHUB_OWNER`
- read repository metadata for the deployment repository and the OIDC discovery companion repository
- create GitHub environments for every stack after the first promotion hop
- write repository variables in the deployment repository
- write repository secrets in the deployment repository
- create the OIDC discovery companion repository from template when that repository does not already exist
- write repository variables in the OIDC discovery companion repository

In practice, this is enough for these bootstrap actions:

- `gh repo create` for the deployment repository and companion repository
- `gh api .../environments/<stack> --method PUT`
- `gh variable set ...`
- `gh secret set ...`

### AWS minimum permissions

For every stack account used by `STACKS`, the bootstrap operator needs permission to:

- read or create the GitHub OIDC provider for `token.actions.githubusercontent.com`
- read or create the per-stack deploy role
- update the deploy role trust policy
- attach or replace the deploy role inline policy
- list KMS aliases in the target region
- create a KMS key and alias when the Pulumi secrets alias does not already exist

For the first stack account in `PROMOTION_PATH`, the bootstrap operator also needs permission to:

- check whether the shared Pulumi backend bucket already exists
- create the shared Pulumi backend bucket if missing
- enable bucket versioning
- enable default bucket encryption
- enable public access block settings

For the OIDC discovery companion flow, the bootstrap operator also needs permission in each stack account to:

- read or create the OIDC discovery IAM role
- update that role trust policy
- attach or replace that role inline policy

These are the bootstrap-time minimums only. They are not the full runtime permissions used later by the deployed system.

### AWS bootstrap operator setup steps

Use this workflow when a platform owner needs to grant AWS access for one-click bootstrap:

1. Prepare `.env` first so account IDs, role names, the Pulumi bucket name, and the KMS alias are final.
2. Run `./scripts/render-bootstrap-policies.sh --env-file .env`.
3. For each stack account, give the bootstrap operator the generated `dist/bootstrap-operator-<stack>-policy.json` policy.
4. For the first stack account in `PROMOTION_PATH`, also give that operator `dist/bootstrap-operator-first-stack-s3-policy.json`.
5. Review the generated deploy-role trust and access policies in the same `dist/` directory if your platform owner wants to pre-approve everything before bootstrap runs.
6. Configure and test local credentials for each account with `AWS_PROFILE_<STACK>` before running bootstrap.

Generated policy files:

- `dist/bootstrap-operator-<stack>-policy.json`
  - common minimum IAM and KMS permissions for the bootstrap operator in that stack account
- `dist/bootstrap-operator-first-stack-s3-policy.json`
  - extra S3 permissions needed only in the first stack account, because that account owns the shared Pulumi backend bucket

If your organization uses a central admin role that assumes into customer accounts, attach these policies to the target account role, then let your central identity assume that role separately.

### Cloudflare minimum permissions

The `CLOUDFLARE_API_TOKEN` used for bootstrap must be able to:

- read and create Cloudflare Pages projects in `CLOUDFLARE_ACCOUNT_ID`
- read and create custom domain bindings for the OIDC discovery Pages project
- read and create the `CNAME` record for `OIDC_DISCOVERY_DOMAIN` in `CLOUDFLARE_ZONE_ID`

If you want preview and rollout mTLS audits to check Cloudflare SSL mode and Authenticated Origin Pulls successfully, that token must also be able to read zone settings for `CLOUDFLARE_ZONE_ID`.

This is enough for bootstrap to check whether the Pages project, domain binding, and required Pages `CNAME` already exist, then create them if needed.

### 4. Confirm local tools

Run these commands and make sure each tool is installed:

```bash
git --version
gh --version
aws --version
pulumi version
python3 --version
```

### 5. Confirm customer-provided secrets and release inputs

1. Confirm you have the customer-specific `LTBASE_RELEASES_TOKEN`.
2. Confirm you have the `GEMINI_API_KEY`.
3. Confirm you know which `LTBASE_RELEASE_ID` you plan to deploy first.
4. Confirm you know the Cloudflare API token value you will place into `.env`.

## Expected Result

You have all required credentials, account mappings, and local tools ready and do not need to pause bootstrap later to ask for missing access.

## Common Mistakes

- using a GitHub account that cannot create private repositories
- starting without the Cloudflare zone ID
- starting without the customer-specific releases token
- assuming one AWS profile can manage two different AWS accounts without switching credentials
- waiting until the bootstrap command fails before checking `gh auth status` or `aws sts get-caller-identity`

## Next Step

Continue with [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md).
