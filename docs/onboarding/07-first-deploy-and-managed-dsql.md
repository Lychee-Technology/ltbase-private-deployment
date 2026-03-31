# First Deploy and Managed DSQL Handling / 首次部署与 Managed DSQL 处理

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide to run the first preview and rollout workflows after bootstrap, and to understand how managed DSQL should be treated in the current customer repository flow.

使用本文档在 bootstrap 完成后执行第一次 preview 与 rollout 工作流，并理解当前客户仓库流程下 managed DSQL 的处理方式。

## Before You Start / 开始前确认

- complete either [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md) or [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
- confirm the required GitHub secrets and variables are present

- 已完成 [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md) 或 [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
- 已确认所需的 GitHub secrets 和 variables 已存在

## Steps / 操作步骤

### 1. Run the preview workflow / 执行 preview 工作流

Open GitHub Actions in your deployment repository and run the `Preview LTBase Blueprint` workflow for the first stack in `PROMOTION_PATH`.

打开部署仓库中的 GitHub Actions，针对 `PROMOTION_PATH` 中的第一个 stack 手动运行 `Preview LTBase Blueprint` 工作流。

Use the `release_id` input if you want to override `vars.LTBASE_RELEASE_ID`.

如果你想覆盖 `vars.LTBASE_RELEASE_ID`，请填写 `release_id` 输入参数。

### 2. Review the preview output / 审查 preview 输出

Confirm that the Pulumi preview matches your expected infrastructure changes.

确认 Pulumi preview 输出与你预期的基础设施变更一致。

### 3. Start the rollout workflow / 启动 rollout 工作流

Run the `Rollout LTBase Release` workflow and provide the release tag you want to deploy.

运行 `Rollout LTBase Release` 工作流，并填写你希望部署的 release tag。

This workflow deploys the first stack in `PROMOTION_PATH`, then automatically dispatches the next hop after each successful deployment.

该工作流会先部署 `PROMOTION_PATH` 的第一个 stack，并在每次成功部署后自动派发下一跳。

### 4. Verify each deployed environment / 验证每个已部署环境

Confirm the first deployed environment works before approving the next protected target stack.

在审批下一个受保护目标环境之前，先确认当前已部署环境工作正常。

### 5. Approve protected target environments / 审批受保护目标环境

When GitHub requests approval for a protected target stack, approve it from the matching GitHub environment gate in your repository.

当 GitHub 请求某个受保护目标 stack 的审批时，请在你的仓库中对应的 GitHub environment gate 完成审批。

### 6. Optional manual single-hop promotion / 可选：手动执行单跳 promotion

If you need to recover or replay only one hop, use `Promote LTBase Between Stacks` and provide `from_stack`, `to_stack`, and the same release tag. Invalid jumps fail fast.

如果你只需要恢复或重放某一跳，可以使用 `Promote LTBase Between Stacks`，并提供 `from_stack`、`to_stack` 与同一个 release tag。非法跳转会立即失败。

## Managed DSQL Guidance / Managed DSQL 指引

In this repository version, customers should not manually provide external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` values for managed deployments.

在当前仓库版本中，managed 部署不应由客户手动提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

Treat managed DSQL details as deployment-owned state produced by the infrastructure and release workflow of the repository version you are using.

请将 managed DSQL 的具体连接信息视为由你当前仓库版本的基础设施与发布流程生成和维护的部署状态。

In the current repository version, follow the explicit post-deploy reconciliation step when managed DSQL infrastructure exists, and do not invent your own endpoint values.

在当前仓库版本中，当 managed DSQL 基础设施已经存在时，请按显式的部署后 reconcile 步骤执行，不要自行构造 endpoint 值。

## Expected Result / 预期结果

You have completed the first full LTBase deployment path: preview, start-stack deploy, validation, and promotion-path rollout.

你已经完成 LTBase 的第一次完整部署流程：preview、起点环境部署、验证，以及按 promotion path 推进的 rollout。

## Common Mistakes / 常见问题

- approving the next protected environment before validating the previous deployed stack
- changing release IDs midway through the same promotion path rollout
- manually inventing managed DSQL endpoint values

- 在验证前一个已部署环境之前就审批下一个受保护环境
- 在同一次 promotion path rollout 中途切换 release ID
- 手动伪造 managed DSQL endpoint 值

## Next Step / 下一步

Continue with [`08-day-2-operations.md`](08-day-2-operations.md).

继续阅读 [`08-day-2-operations.md`](08-day-2-operations.md)。
