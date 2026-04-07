# First Deploy and Managed DSQL Handling

> **[中文版](07-first-deploy-and-managed-dsql.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to run the first preview and rollout workflows after bootstrap, and to understand how managed DSQL should be treated in the current customer repository flow.

## Before You Start

- complete either [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md) or [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
- confirm the required GitHub secrets and variables are present

## Recommended Final Checks Before First Deploy

- confirm `PROMOTION_PATH` is the deployment order you actually want
- confirm `LTBASE_RELEASE_ID` is final, or decide that you will override it in the workflow input
- remember that manual preview only supports the first stack in `PROMOTION_PATH`
- be ready to validate each deployed environment before approving the next one

## Steps

### 1. Run the preview workflow

Open GitHub Actions in your deployment repository and run the `Preview LTBase Blueprint` workflow for the first stack in `PROMOTION_PATH`.

Use the `release_id` input if you want to override `vars.LTBASE_RELEASE_ID`.

Important:

- the workflow accepts a `target_stack` input, but manual preview only allows the first promotion stack
- if you provide any other stack, the workflow fails fast and tells you which stack is allowed

### 2. Review the preview output

Confirm that the Pulumi preview matches your expected infrastructure changes.

At minimum, confirm:

- the target stack is the one you expected
- the release ID matches the version you intend to deploy
- the infrastructure diff is within the scope you expect

If preview does not match your expectations, fix the configuration or bootstrap gap before you start rollout.

### 3. Start the rollout workflow

Run the `Rollout LTBase Release` workflow and provide the release tag you want to deploy.

This workflow deploys the first stack in `PROMOTION_PATH`, then automatically dispatches the next hop after each successful deployment.

Additional guidance:

- if you only want to deploy the start stack and stop there, you can use `Deploy LTBase Start Stack`
- the default recommendation is still `Rollout LTBase Release`, because it keeps the full promotion chain moving automatically

### 4. Verify each deployed environment

Confirm the first deployed environment works before approving the next protected target stack.

At minimum, check:

- the workflow run completed successfully
- the expected domain endpoints are reachable
- your minimum health check, login path, or internal smoke test passes
- the environment is running the same release ID used for the current rollout

### 5. Approve protected target environments

When GitHub requests approval for a protected target stack, approve it from the matching GitHub environment gate in your repository.

Recommended approval rhythm:

- only approve the next hop after the previous hop is validated
- keep the same release ID across the entire promotion path
- if one hop has a problem, stop approvals and investigate before continuing

### 6. Optional manual single-hop promotion

If you need to recover or replay only one hop, use `Promote LTBase Between Stacks` and provide `from_stack`, `to_stack`, and the same release tag. Invalid jumps fail fast.

Use this when:

- one hop deployed successfully but the automatic chain did not continue
- you want to promote from one validated stack to the next adjacent stack only

Important:

- this workflow only allows adjacent hops in `PROMOTION_PATH`
- invalid jumps fail immediately, for example if you skip an intermediate environment

## Managed DSQL Guidance

In this repository version, customers should not manually provide external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` values for managed deployments.

Treat managed DSQL details as deployment-owned state produced by the infrastructure and release workflow of the repository version you are using.

In the current repository version, follow the explicit post-deploy reconciliation step when managed DSQL infrastructure exists, and do not invent your own endpoint values.

If the first real infrastructure deployment created a `dsqlClusterIdentifier` but the stack still does not have `dsqlEndpoint`, run:

```bash
./scripts/reconcile-managed-dsql-endpoint.sh --env-file .env --stack <stack> --infra-dir infra
```

That script:

- reads `dsqlClusterIdentifier` from the target stack's Pulumi output
- asks AWS for the authoritative managed DSQL endpoint
- writes the resolved value back into Pulumi config as `dsqlEndpoint`

After reconciliation, run the next preview or deploy cycle so runtime configuration picks up that endpoint.

For managed deployments, the default connection values are:

- `DSQL_DB=postgres`
- `DSQL_USER=admin`

## Expected Result

You have completed the first full LTBase deployment path: preview, start-stack deploy, validation, and promotion-path rollout.

## Common Mistakes

- approving the next protected environment before validating the previous deployed stack
- changing release IDs midway through the same promotion path rollout
- manually inventing managed DSQL endpoint values
- seeing the DSQL cluster exist, but skipping reconcile and the follow-up config-apply cycle

## Next Step

Continue with [`08-day-2-operations.md`](08-day-2-operations.md).
