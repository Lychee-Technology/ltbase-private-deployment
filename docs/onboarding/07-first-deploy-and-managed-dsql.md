# First Deploy and Managed DSQL Handling

> **[中文版](07-first-deploy-and-managed-dsql.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use this guide to run the first preview and rollout workflows after bootstrap, and to understand how managed DSQL should be treated in the current customer repository flow.

## Before You Start

- complete either [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md) or [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
- confirm the required GitHub secrets and variables are present

## Steps

### 1. Run the preview workflow

Open GitHub Actions in your deployment repository and run the `Preview LTBase Blueprint` workflow for the first stack in `PROMOTION_PATH`.

Use the `release_id` input if you want to override `vars.LTBASE_RELEASE_ID`.

### 2. Review the preview output

Confirm that the Pulumi preview matches your expected infrastructure changes.

### 3. Start the rollout workflow

Run the `Rollout LTBase Release` workflow and provide the release tag you want to deploy.

This workflow deploys the first stack in `PROMOTION_PATH`, then automatically dispatches the next hop after each successful deployment.

### 4. Verify each deployed environment

Confirm the first deployed environment works before approving the next protected target stack.

### 5. Approve protected target environments

When GitHub requests approval for a protected target stack, approve it from the matching GitHub environment gate in your repository.

### 6. Optional manual single-hop promotion

If you need to recover or replay only one hop, use `Promote LTBase Between Stacks` and provide `from_stack`, `to_stack`, and the same release tag. Invalid jumps fail fast.

## Managed DSQL Guidance

In this repository version, customers should not manually provide external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` values for managed deployments.

Treat managed DSQL details as deployment-owned state produced by the infrastructure and release workflow of the repository version you are using.

In the current repository version, follow the explicit post-deploy reconciliation step when managed DSQL infrastructure exists, and do not invent your own endpoint values.

## Expected Result

You have completed the first full LTBase deployment path: preview, start-stack deploy, validation, and promotion-path rollout.

## Common Mistakes

- approving the next protected environment before validating the previous deployed stack
- changing release IDs midway through the same promotion path rollout
- manually inventing managed DSQL endpoint values

## Next Step

Continue with [`08-day-2-operations.md`](08-day-2-operations.md).
