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
AWS_PROFILE_DEVO=customer-devo aws sts get-caller-identity
AWS_PROFILE_PROD=customer-prod aws sts get-caller-identity
```

5. Confirm you have permission to create or update all bootstrap-managed AWS resources:
   - GitHub OIDC providers
   - deploy roles and trust policies
   - inline IAM role policies
   - Pulumi state bucket
   - KMS alias for Pulumi secrets

### 3. Confirm Cloudflare access

1. Record the Cloudflare account ID and zone ID you will place into `.env`.
2. Confirm the zone already exists.
3. Confirm the API token can manage:
   - Cloudflare Pages projects
   - custom domain bindings
   - the zone used by your LTBase domains and OIDC discovery domain

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
