> **English version: [CUSTOMER_ONBOARDING.md](CUSTOMER_ONBOARDING.md)**

# LTBase 客户部署入门指南

本文档是客户使用私有部署模板部署 LTBase 时的主入口文档。

## 本文档的用途

- 解释整体部署模型
- 给出从准备到第一次按 promotion path 推进 rollout 的完整顺序
- 为每个较长操作链接到详细步骤文档

## 部署模型

你的 LTBase 部署会涉及三个仓库：

- `ltbase-deploy-workflows`
  - LTBase 维护的公共可复用 GitHub Actions 工作流
- `ltbase-releases`
  - 私有发布仓库，存放官方 LTBase 应用发布产物
- 你的部署仓库
  - 由 `ltbase-private-deployment` 模板创建出来的私有仓库
  - 这是你自己的部署仓库，用来保存工作流、bootstrap 脚本和 Pulumi stack 配置

你的部署仓库不会自行构建 LTBase 应用源码。它会下载官方 LTBase release，并将其部署到你的 AWS 账户中。

## 最终完成状态

完成 onboarding 后，你应该具备以下结果：

- 一个基于本模板创建的私有部署仓库
- 每个用于部署的 AWS 账户中各自存在 GitHub OIDC 信任关系
- `STACKS` 中每个环境各自对应一个 deploy role
- 一个 Pulumi state bucket
- 一个用于 Pulumi secrets 加密的 KMS alias
- 已配置好的 GitHub 仓库 secrets 和 variables
- 一个可用于 preview 与部署的起点 stack
- `PROMOTION_PATH` 中每个后续环境在前一跳验证后都可用于受保护 promotion

## 开始之前

你需要提前准备：

- 一个可以创建私有仓库的 GitHub 组织或账号
- 一个或多个将承载 `STACKS` 中各环境的 AWS 账户
- 一个用于业务域名的 Cloudflare zone
- 创建或更新 IAM role、IAM OIDC provider、S3 bucket、KMS key 的权限
- 一个客户专用的 `LTBASE_RELEASES_TOKEN`
- 一个 Gemini API key

更详细的准备清单请看：

- [`docs/onboarding/01-prerequisites.zh.md`](onboarding/01-prerequisites.zh.md)

## 完整操作顺序

请按下面顺序操作：

### 第一步：准备前置条件

- 阅读：[`docs/onboarding/01-prerequisites.zh.md`](onboarding/01-prerequisites.zh.md)
- 内容包括：账户、权限、token、域名、本地工具

### 第二步：创建部署仓库并克隆到本地

- 阅读：[`docs/onboarding/02-create-repo-and-clone.zh.md`](onboarding/02-create-repo-and-clone.zh.md)
- 内容包括：从模板创建私有仓库、拉取到本地、确认目录结构

### 第三步：准备 OIDC 和 deploy role

- 阅读：[`docs/onboarding/03-create-oidc-and-deploy-roles.zh.md`](onboarding/03-create-oidc-and-deploy-roles.zh.md)
- 内容包括：OIDC provider、按 stack 划分的 deploy role、信任策略、权限策略
- 如果使用一键 bootstrap，只需确认即可；脚本会自动创建这些资源

### 第四步：准备本地 `.env` 文件

- 阅读：[`docs/onboarding/04-prepare-env-file.zh.md`](onboarding/04-prepare-env-file.zh.md)
- 内容包括：`.env` 每个必填字段、每个值从哪里来、哪些值不能手填

### 第五步：选择 bootstrap 路径

如果你拥有足够的 GitHub 和 AWS 权限，优先使用一键路径：

- [`docs/onboarding/05-bootstrap-one-click.zh.md`](onboarding/05-bootstrap-one-click.zh.md)

如果你希望逐步控制每一个阶段，请使用手动路径：

- [`docs/onboarding/06-bootstrap-manual.zh.md`](onboarding/06-bootstrap-manual.zh.md)

### 第六步：执行第一次 preview 和部署

- 阅读：[`docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`](onboarding/07-first-deploy-and-managed-dsql.zh.md)
- 内容包括：preview、按 promotion path 推进的 rollout、受保护环境审批、managed DSQL 的 bootstrap 后处理

### 第七步：日常运维与升级

- 阅读：[`docs/onboarding/08-day-2-operations.zh.md`](onboarding/08-day-2-operations.zh.md)
- 内容包括：release 升级、重复 preview、部署节奏、运维提醒

## 必需的 GitHub Secrets 与 Variables

在你的部署仓库中设置以下 secrets：

- `AWS_ROLE_ARN_<STACK>`（`STACKS` 中每个环境各一个）
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

在你的部署仓库中设置以下 variables：

- `AWS_REGION_<STACK>`（`STACKS` 中每个环境各一个）
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>`（`STACKS` 中每个环境各一个）
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

当 `.env` 正确时，bootstrap 脚本会帮你写入这些值。

## Managed DSQL 重要说明

对于 managed 部署，不要手动提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

在当前仓库版本中，bootstrap 脚本采用 bootstrap-safe 的拆分流程：bootstrap 先准备 GitHub 与 Pulumi 状态，`scripts/reconcile-managed-dsql-endpoint.sh` 会在基础设施实际存在之后发布 managed DSQL endpoint。

Aurora DSQL 由 Pulumi blueprint 自动创建。对于 managed 部署，你不需要提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

当前仓库版本采用 bootstrap-safe 流程：

- `bootstrap-all.sh` 和 `bootstrap-deployment-repo.sh` 只负责准备配置
- 第一次真实基础设施 apply 会创建 managed DSQL cluster
- `scripts/reconcile-managed-dsql-endpoint.sh` 会通过 Pulumi 导出的 `dsqlClusterIdentifier` 从 AWS 获取权威 endpoint
- reconcile 步骤会把解析出的 endpoint 写入 stack config 的 `dsqlEndpoint`
- reconcile 完成后，需要再执行下一轮 preview/deploy，才能让 Lambda 环境变量拿到这个 managed endpoint

## 运维约束

- `LTBASE_RELEASES_TOKEN` 仅用于下载官方 LTBase release
- 本地 `.env` 文件包含敏感信息，绝对不能提交到仓库
- 模板仓库不会在 pull request 上自动执行 preview，因为模板仓库不包含真实客户凭据
- 手动 preview 只支持 `PROMOTION_PATH` 中的第一个环境
- 受保护环境的 promotion 会在你自己的仓库中通过各自的 GitHub environment gate 完成

## 相关文档

- 快速清单：[`docs/BOOTSTRAP.zh.md`](BOOTSTRAP.zh.md)
- 前置条件：[`docs/onboarding/01-prerequisites.zh.md`](onboarding/01-prerequisites.zh.md)
- 创建仓库并克隆：[`docs/onboarding/02-create-repo-and-clone.zh.md`](onboarding/02-create-repo-and-clone.zh.md)
- 创建 OIDC 和 role：[`docs/onboarding/03-create-oidc-and-deploy-roles.zh.md`](onboarding/03-create-oidc-and-deploy-roles.zh.md)
- 准备 `.env`：[`docs/onboarding/04-prepare-env-file.zh.md`](onboarding/04-prepare-env-file.zh.md)
- 一键 bootstrap：[`docs/onboarding/05-bootstrap-one-click.zh.md`](onboarding/05-bootstrap-one-click.zh.md)
- 手动 bootstrap：[`docs/onboarding/06-bootstrap-manual.zh.md`](onboarding/06-bootstrap-manual.zh.md)
- 首次部署：[`docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`](onboarding/07-first-deploy-and-managed-dsql.zh.md)
- 日常运维：[`docs/onboarding/08-day-2-operations.zh.md`](onboarding/08-day-2-operations.zh.md)
