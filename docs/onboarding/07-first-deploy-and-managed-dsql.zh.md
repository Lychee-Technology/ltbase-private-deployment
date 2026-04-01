# 首次部署与 Managed DSQL 处理

> **[English](07-first-deploy-and-managed-dsql.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档在 bootstrap 完成后执行第一次 preview 与 rollout 工作流，并理解当前客户仓库流程下 managed DSQL 的处理方式。

## 开始前确认

- 已完成 [`05-bootstrap-one-click.zh.md`](05-bootstrap-one-click.zh.md) 或 [`06-bootstrap-manual.zh.md`](06-bootstrap-manual.zh.md)
- 已确认所需的 GitHub secrets 和 variables 已存在

## 操作步骤

### 1. 执行 preview 工作流

打开部署仓库中的 GitHub Actions，针对 `PROMOTION_PATH` 中的第一个 stack 手动运行 `Preview LTBase Blueprint` 工作流。

如果你想覆盖 `vars.LTBASE_RELEASE_ID`，请填写 `release_id` 输入参数。

### 2. 审查 preview 输出

确认 Pulumi preview 输出与你预期的基础设施变更一致。

### 3. 启动 rollout 工作流

运行 `Rollout LTBase Release` 工作流，并填写你希望部署的 release tag。

该工作流会先部署 `PROMOTION_PATH` 的第一个 stack，并在每次成功部署后自动派发下一跳。

### 4. 验证每个已部署环境

在审批下一个受保护目标环境之前，先确认当前已部署环境工作正常。

### 5. 审批受保护目标环境

当 GitHub 请求某个受保护目标 stack 的审批时，请在你的仓库中对应的 GitHub environment gate 完成审批。

### 6. 可选：手动执行单跳 promotion

如果你只需要恢复或重放某一跳，可以使用 `Promote LTBase Between Stacks`，并提供 `from_stack`、`to_stack` 与同一个 release tag。非法跳转会立即失败。

## Managed DSQL 指引

在当前仓库版本中，managed 部署不应由客户手动提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

请将 managed DSQL 的具体连接信息视为由你当前仓库版本的基础设施与发布流程生成和维护的部署状态。

在当前仓库版本中，当 managed DSQL 基础设施已经存在时，请按显式的部署后 reconcile 步骤执行，不要自行构造 endpoint 值。

## 预期结果

你已经完成 LTBase 的第一次完整部署流程：preview、起点环境部署、验证，以及按 promotion path 推进的 rollout。

## 常见问题

- 在验证前一个已部署环境之前就审批下一个受保护环境
- 在同一次 promotion path rollout 中途切换 release ID
- 手动伪造 managed DSQL endpoint 值

## 下一步

继续阅读 [`08-day-2-operations.zh.md`](08-day-2-operations.zh.md)。
