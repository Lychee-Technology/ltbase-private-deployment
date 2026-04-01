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

## Steps

1. Confirm you can log in to GitHub from the CLI.
2. Confirm you can access the AWS accounts that will host LTBase.
3. Confirm you know which AWS account will host each stack in `STACKS`.
4. Confirm you know which GitHub repo name you plan to create.
5. Confirm you know the Cloudflare zone ID that will host the domains.
6. Confirm you have both `LTBASE_RELEASES_TOKEN` and `GEMINI_API_KEY` ready.

## Expected Result

You have all required credentials and no longer need to pause the bootstrap process to ask for missing access.

## Common Mistakes

- using a GitHub account that cannot create private repositories
- starting without the Cloudflare zone ID
- starting without the customer-specific releases token
- assuming one AWS profile can manage two different AWS accounts without switching credentials

## Next Step

Continue with [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md).
