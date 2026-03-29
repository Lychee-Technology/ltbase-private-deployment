# First Deploy and Managed DSQL Handling / 首次部署与 Managed DSQL 处理

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide to run the first preview and deployment workflows after bootstrap, and to understand how managed DSQL should be treated in the current customer repository flow.

使用本文档在 bootstrap 完成后执行第一次 preview 与部署工作流，并理解当前客户仓库流程下 managed DSQL 的处理方式。

## Before You Start / 开始前确认

- complete either [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md) or [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
- confirm the required GitHub secrets and variables are present

- 已完成 [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md) 或 [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
- 已确认所需的 GitHub secrets 和 variables 已存在

## Steps / 操作步骤

### 1. Run the preview workflow / 执行 preview 工作流

Open GitHub Actions in your deployment repository and run the `Preview LTBase Blueprint` workflow.

打开部署仓库中的 GitHub Actions，手动运行 `Preview LTBase Blueprint` 工作流。

Use the `release_id` input if you want to override `vars.LTBASE_RELEASE_ID`.

如果你想覆盖 `vars.LTBASE_RELEASE_ID`，请填写 `release_id` 输入参数。

### 2. Review the preview output / 审查 preview 输出

Confirm that the Pulumi preview matches your expected infrastructure changes.

确认 Pulumi preview 输出与你预期的基础设施变更一致。

### 3. Run the devo deployment workflow / 执行 devo 部署工作流

Run the `Deploy LTBase Devo` workflow and provide the release tag you want to deploy.

运行 `Deploy LTBase Devo` 工作流，并填写你希望部署的 release tag。

### 4. Verify the devo environment / 验证 devo 环境

Confirm the deployed devo environment works before you continue to production.

在继续到生产环境之前，先确认 devo 环境工作正常。

### 5. Run the prod promotion workflow / 执行 prod promotion 工作流

Run the `Promote LTBase Prod` workflow with the same release tag.

使用相同的 release tag 运行 `Promote LTBase Prod` 工作流。

### 6. Approve production / 批准生产环境部署

When GitHub requests production approval through the `prod` environment gate, approve it from your repository.

当 GitHub 通过 `prod` environment gate 请求生产审批时，请在你的仓库中完成审批。

## Managed DSQL Guidance / Managed DSQL 指引

In this repository version, customers should not manually provide external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` values for managed deployments.

在当前仓库版本中，managed 部署不应由客户手动提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

Treat managed DSQL details as deployment-owned state produced by the infrastructure and release workflow of the repository version you are using.

请将 managed DSQL 的具体连接信息视为由你当前仓库版本的基础设施与发布流程生成和维护的部署状态。

If LTBase later ships a repository version that introduces an explicit post-deploy reconciliation step, follow that version's instructions exactly and do not invent your own endpoint values.

如果 LTBase 后续发布的仓库版本引入了显式的部署后 reconcile 步骤，请严格按该版本文档执行，不要自行构造 endpoint 值。

## Expected Result / 预期结果

You have completed the first full LTBase deployment path: preview, devo deploy, validation, and prod promotion.

你已经完成 LTBase 的第一次完整部署流程：preview、devo deploy、验证、prod promotion。

## Common Mistakes / 常见问题

- promoting to prod before validating devo
- changing release IDs between devo and prod for the same rollout
- manually inventing managed DSQL endpoint values

- 在验证 devo 之前就推进到 prod
- 在同一次发布过程中给 devo 和 prod 使用不同 release ID
- 手动伪造 managed DSQL endpoint 值

## Next Step / 下一步

Continue with [`08-day-2-operations.md`](08-day-2-operations.md).

继续阅读 [`08-day-2-operations.md`](08-day-2-operations.md)。
