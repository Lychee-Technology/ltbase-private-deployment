# Day-2 Operations

> **[中文版](08-day-2-operations.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide for normal follow-up operations after the first successful deployment.

## Typical Operations

### Audit Cloudflare mTLS wiring

Run `./scripts/check-cloudflare-mtls.sh --env-file .env --stack <stack>` from the deployment repository when you need a read-only audit of the Cloudflare to API Gateway mTLS path.

The preview workflow and the rollout hop workflow both run this audit automatically after a successful job and fail if the Cloudflare or API Gateway mTLS posture drifts.

The script checks:

- Cloudflare proxying for `api`, `auth`, and `control-plane`
- Cloudflare SSL mode is `Full (strict)`
- Cloudflare Authenticated Origin Pulls is enabled
- the truststore object exists in the stack runtime bucket
- each API Gateway custom domain reports mutual TLS with the expected truststore URI and version

### Upgrade to a new LTBase release

1. If you want the latest template copy of the sync helper itself first, run `./scripts/update-sync-template-tooling.sh` from your deployment repository on a clean local `main` branch.
2. If you want to bring in newer template-managed files, run `./scripts/sync-template-upstream.sh` from the same clean local `main` branch.
3. Review the synced template changes. The sync preserves local `.env` files, `infra/Pulumi.*.yaml`, customer-owned `infra/auth-providers.*.json`, and the sync helper's own script/test files.
4. If the generated deployment repository does not yet have a real auth provider config file for a stack, copy the matching `infra/auth-providers.<stack>.json.example` file to `infra/auth-providers.<stack>.json` in that generated repository before the next bootstrap or preview run.
5. Update `LTBASE_RELEASE_ID` in GitHub variables, or pass a new `release_id` directly to the workflow.
6. Run the preview workflow.
7. Review the Pulumi preview output.
8. Trigger `rollout.yml` once for the new release.
9. Validate each deployed stack before approving the next protected target environment.
10. Approve each protected hop in order until the promotion path completes.

### Re-run preview before changes

Use preview whenever you change stack configuration, release selection, or deployment-related values.

### Recover from Pulumi config drift

Preview and deployment workflows now validate that `infra/Pulumi.<stack>.yaml` contains the required `ltbase-infra:*` config keys before invoking the shared deployment workflows.

If a workflow fails with a missing-key error, repair the generated deployment repository by either:

- rerunning `./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack>`
- restoring the missing key in `infra/Pulumi.<stack>.yaml`

This validation is presence-only. It does not modify customer config automatically during preview or deploy.

### Maintain local bootstrap inputs

Keep `.env` private, current, and outside version control.

## Operational Reminders

- do not rebuild LTBase application binaries in the deployment repository
- do not commit `.env`
- do not bypass the production approval gate
- keep `LTBASE_RELEASES_TOKEN` scoped to release download access only
- run `scripts/update-sync-template-tooling.sh` only from a clean local `main` branch
- run `scripts/sync-template-upstream.sh` only from a clean local `main` branch

## Expected Result

You can safely repeat previews and promotion-path rollouts after onboarding is complete.

## Common Mistakes

- approving a later stack before validating the previous hop
- changing deployment inputs without running preview first
- treating the deployment repository as an application source repository

## Back to Onboarding

Return to [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md).
