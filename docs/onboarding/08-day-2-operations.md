# Day-2 Operations

> **[中文版](08-day-2-operations.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide for normal follow-up operations after the first successful deployment.

## Typical Operations

### Audit Cloudflare mTLS wiring

Run `./scripts/check-cloudflare-mtls.sh --env-file .env --stack <stack>` from the deployment repository when you need a read-only audit of the Cloudflare to API Gateway mTLS path.

The preview workflow and the rollout hop workflow both run this audit automatically after a successful job and fail if the Cloudflare or API Gateway mTLS posture drifts.

For local runs, keep `.env` and `infra/Pulumi.<stack>.yaml` aligned. The workflow audit reads `ltbase-infra:awsRegion`, `ltbase-infra:apiDomain`, `ltbase-infra:controlPlaneDomain`, `ltbase-infra:authDomain`, `ltbase-infra:runtimeBucket`, and `ltbase-infra:cloudflareZoneId` from `infra/Pulumi.<stack>.yaml`, while the standalone script still expects those values in the env file you pass.

The script checks:

- Cloudflare proxying for `api`, `auth`, and `control-plane`
- Cloudflare SSL mode is `Full (strict)`
- Cloudflare Authenticated Origin Pulls is enabled
- the truststore object exists in the stack runtime bucket
- each API Gateway custom domain reports mutual TLS with the expected truststore URI and version

### Upgrade to a new LTBase release

1. If you want the latest template copy of the sync helper itself first, run `./scripts/update-sync-template-tooling.sh` from your deployment repository on a clean local `main` branch.
2. If you want to bring in newer template-managed files, run `./scripts/sync-template-upstream.sh` from the same clean local `main` branch.
3. Review the synced template changes. The sync preserves local `.env` files, `infra/Pulumi.*.yaml`, the entire `customer-owned/` tree, customer-owned `infra/auth-providers.*.json`, and the sync helper's own script/test files.
4. If the generated deployment repository does not yet have a real auth provider config file for a stack, copy the matching `infra/auth-providers.<stack>.json.example` file to `infra/auth-providers.<stack>.json` in that generated repository before the next bootstrap or preview run.
5. Update `LTBASE_RELEASE_ID` in GitHub variables, or pass a new `release_id` directly to the workflow.
6. Run the preview workflow for the new release. Besides the Pulumi diff, it checks `customer-owned/schemas/*.json` with the new release's own schema validator.
7. If the schema validation step fails, stop and follow [Fix a schema bundle the new release rejects](#fix-a-schema-bundle-the-new-release-rejects) before going further.
8. Review the Pulumi preview output. Remember that preview is infra-only and does not publish the Control Plane UI.
9. Trigger `rollout.yml` once for the new release. Each hop repeats the schema check before approval and before anything is deployed.
10. Validate each deployed stack before approving the next protected target environment.
11. Approve each protected hop in order until the promotion path completes.

### Fix a schema bundle the new release rejects

LTBase resolves cross-file `$ref`s when it loads a schema bundle and refuses the whole bundle if one of them does not resolve: every Forma request for the project then fails with `503 forma_unavailable`. Preview and every rollout hop therefore check `customer-owned/schemas/*.json` with the validator of the release being deployed, and stop before deploying when it reports a finding such as:

```text
result: FAILED — 1 finding(s)
  - log: log.json: $ref "lead.json#/$defs/lead_id" at /properties/leadId: ...
```

That check reads the bundle in the repository. A stack serves the bundle that was last **applied** to it, and keeps serving it while a rollout replaces the release underneath. If the release a stack runs today accepted a bundle that the new release rejects, fixing the repository and rolling out the new release is not enough: the new release starts on the old bundle and fails until the hop reaches its publish and apply steps — and stays failed if the hop stops before them.

Apply the fix with the release the stacks already run, then upgrade:

1. Fix the reported references in `customer-owned/schemas/` and merge the fix.
2. Re-run the preview workflow with the **new** `release_id` until the schema validation step passes.
3. Run `rollout.yml` with the release the stacks **currently** run. The release does not change; each hop publishes and applies the corrected bundle.
4. Run `rollout.yml` with the new release.

Step 3 is what makes the upgrade safe. Skip it only when the stack already runs the release that rejected the bundle: there is no older release to go through, and a single rollout of the corrected bundle is the fix.

The same order applies whenever `customer-owned/schemas/` has changed since the last rollout: the check cannot see a bundle that is still applied to a stack but no longer in the repository. Roll pending schema changes out with the current release before upgrading.

See [Schema bundle validation](../GITHUB_ACTIONS.md#schema-bundle-validation) for what is checked and where.

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

### Troubleshoot Control Plane UI operator access

When operators cannot sign in to the admin UI, check all of the following before changing workflow or release inputs:

- `CONTROLPLANE_UI_DOMAIN` still points at the expected Cloudflare Pages custom domain and DNS `CNAME`
- the identity provider still allows `https://<CONTROLPLANE_UI_DOMAIN>/auth/callback`
- `infra/auth-providers.<stack>.json` still contains provider names that match the browser providers rendered into the current companion runtime config
- the Control Plane API CORS allowlist still includes `https://<CONTROLPLANE_UI_DOMAIN>` unless you intentionally configured `*`
- the Firebase and Supabase values in `.env` are browser-safe values only and still match the operator-facing app setup you expect
- the current repository version may still rely on companion-oriented Control Plane UI bootstrap assumptions, so confirm those resources are still present before treating the issue as an application regression

## Operational Reminders

- do not rebuild LTBase application binaries in the deployment repository
- do not rebuild LTBase Control Plane UI source artifacts from the deployment repository
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
