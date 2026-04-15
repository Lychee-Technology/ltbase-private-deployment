# 首次部署与 Managed DSQL 处理

> **[English](07-first-deploy-and-managed-dsql.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档在 bootstrap 完成后执行第一次 preview 与 rollout 工作流，并理解当前客户仓库流程下 managed DSQL 的处理方式。

## 开始前确认

- 已完成 [`05-bootstrap-one-click.zh.md`](05-bootstrap-one-click.zh.md) 或 [`06-bootstrap-manual.zh.md`](06-bootstrap-manual.zh.md)
- 已确认所需的 GitHub secrets 和 variables 已存在

## 开始前建议再确认一次

- `PROMOTION_PATH` 的顺序就是你想要的部署顺序
- `LTBASE_RELEASE_ID` 已经定稿，或者你已经决定在工作流输入中显式覆盖它
- 你知道手动 preview 只支持 `PROMOTION_PATH` 中的第一个 stack
- 你已经准备好在每一跳部署后先验证环境，再批准下一跳

## 操作步骤

### 1. 执行 preview 工作流

打开部署仓库中的 GitHub Actions，针对 `PROMOTION_PATH` 中的第一个 stack 手动运行 `Preview LTBase Blueprint` 工作流。

如果你想覆盖 `vars.LTBASE_RELEASE_ID`，请填写 `release_id` 输入参数。

额外说明：

- 该工作流支持 `target_stack` 输入，但手动 preview 实际只允许 `PROMOTION_PATH` 中的第一个 stack
- 如果你填了其他 stack，工作流会直接失败并提示只允许第一个 promotion stack

### 2. 审查 preview 输出

确认 Pulumi preview 输出与你预期的基础设施变更一致。

至少应检查：

- 目标 stack 与你预期一致
- 使用的 release ID 与你计划部署的版本一致
- 基础设施变更没有超出预期范围

如果 preview 结果不符合预期，先修复配置或 bootstrap 缺口，不要直接进入 rollout。

### 3. 启动 rollout 工作流

运行 `Rollout LTBase Release` 工作流，并填写你希望部署的 release tag。

该工作流会先部署 `PROMOTION_PATH` 的第一个 stack，并在每次成功部署后自动派发下一跳。

补充说明：

- 如果你只想单独部署起点 stack 而不继续整条 promotion path，还可以使用 `Deploy LTBase Start Stack`
- 默认推荐使用 `Rollout LTBase Release`，这样整条链路的后续 hop 会自动衔接

### 4. 验证每个已部署环境

在审批下一个受保护目标环境之前，先确认当前已部署环境工作正常。

建议至少检查：

- 相关工作流已经成功完成
- 目标域名可访问
- 基础健康检查、登录链路或你内部定义的最小冒烟检查通过
- 当前环境使用的 release ID 与你本次 rollout 的 release ID 一致
- rollout 工作流已经通过部署后的 stack outputs 和当前 AWS account id 自动回写 authservice 所需的 DynamoDB `project info` 记录

### 5. 审批受保护目标环境

当 GitHub 请求某个受保护目标 stack 的审批时，请在你的仓库中对应的 GitHub environment gate 完成审批。

审批节奏建议：

- 只在上一跳验证通过后再审批下一跳
- 在整条 promotion path 中保持同一个 release ID，不要中途切换
- 如果某一跳有问题，停止审批并先处理问题

### 6. 可选：手动执行单跳 promotion

如果你只需要恢复或重放某一跳，可以使用 `Promote LTBase Between Stacks`，并提供 `from_stack`、`to_stack` 与同一个 release tag。非法跳转会立即失败。

适用场景：

- 某一跳部署成功后，自动链路没有继续，需要补一次相邻 hop
- 你只想从某个已验证环境推进到下一个相邻环境

注意：

- 这个工作流只允许 `PROMOTION_PATH` 中相邻的 hop
- 非法跳转会直接失败，例如跨过中间环境的 promotion

## Project Info 指引

在当前仓库版本中，官方 deploy 工作流会在 `pulumi up` 之后、抓取 deployment outputs 之前，自动把 authservice 兼容的 `project info` 记录写入 DynamoDB。

这条记录使用以下字段：

- `PK=project#<projectId>`
- `SK=info`
- `account_id=<当前 aws account id>`
- `api_id=<已部署 data plane api id>`
- `api_base_url=https://<api domain>`

如果你需要手动修复某个 stack 的这条记录，请执行：

```bash
./scripts/reconcile-project-info.sh --env-file .env --stack <stack> --infra-dir infra
```

这个脚本会：

- 从目标 stack 的 Pulumi outputs 中读取 `projectId`、`apiId`、`apiBaseUrl` 和 `tableName`
- 通过 `sts get-caller-identity` 解析当前 AWS account id
- 将权威的 `project info` 记录重新写回 DynamoDB

## Managed DSQL 指引

在当前仓库版本中，managed 部署不应由客户手动提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

请将 managed DSQL 的具体连接信息视为由你当前仓库版本的基础设施与发布流程生成和维护的部署状态。

在当前仓库版本中，当 managed DSQL 基础设施已经存在时，请按显式的部署后 reconcile 步骤执行，不要自行构造 endpoint 值。

如果第一次真实基础设施部署后，stack 已经有 `dsqlClusterIdentifier`，但还没有 `dsqlEndpoint`，请执行：

```bash
./scripts/reconcile-managed-dsql-endpoint.sh --env-file .env --stack <stack> --infra-dir infra
```

这个脚本会：

- 从对应 stack 的 Pulumi 输出中读取 `dsqlClusterIdentifier`
- 调用 AWS 获取权威的 managed DSQL endpoint
- 将该 endpoint 写回该 stack 的 Pulumi config `dsqlEndpoint`

reconcile 完成后，请再执行下一轮 preview 或 deploy，让运行时配置拿到这个 endpoint。

对于 managed 部署，默认连接值为：

- `DSQL_DB=postgres`
- `DSQL_USER=admin`

## 预期结果

你已经完成 LTBase 的第一次完整部署流程：preview、起点环境部署、验证，以及按 promotion path 推进的 rollout。

## 常见问题

- 在验证前一个已部署环境之前就审批下一个受保护环境
- 在同一次 promotion path rollout 中途切换 release ID
- 手动伪造 managed DSQL endpoint 值
- 看到 DSQL cluster 已创建后，没有执行后续 reconcile 和下一轮配置生效流程

## 下一步

继续阅读 [`08-day-2-operations.zh.md`](08-day-2-operations.zh.md)。
