# LTBase Customer Onboarding Runbook / LTBase 客户部署入门指南

This document is the main entry point for customers deploying LTBase with the private deployment template.

本文档是客户使用私有部署模板部署 LTBase 时的主入口文档。

## What This Document Is For / 本文档的用途

- explain the overall deployment model
- show the full onboarding order from preparation to first production promotion
- link to detailed step-by-step guides for every longer operation

- 解释整体部署模型
- 给出从准备到首次生产发布的完整顺序
- 为每个较长操作链接到详细步骤文档

## Deployment Model / 部署模型

Your LTBase deployment uses three repositories:

你的 LTBase 部署会涉及三个仓库：

- `ltbase-deploy-workflows`
  - reusable public GitHub Actions workflows maintained by LTBase
  - LTBase 维护的公共可复用 GitHub Actions 工作流
- `ltbase-releases`
  - private release repository containing official LTBase application artifacts
  - 私有发布仓库，存放官方 LTBase 应用发布产物
- your deployment repository
  - a private repository created from `ltbase-private-deployment`
  - your customer-owned repo that stores workflows, bootstrap scripts, and Pulumi stack configuration
  - 由 `ltbase-private-deployment` 模板创建出来的私有仓库
  - 这是你自己的部署仓库，用来保存工作流、bootstrap 脚本和 Pulumi stack 配置

Your deployment repository does not build LTBase application source code. It downloads an official LTBase release and deploys it into your AWS account.

你的部署仓库不会自行构建 LTBase 应用源码。它会下载官方 LTBase release，并将其部署到你的 AWS 账户中。

## End State / 最终完成状态

When onboarding is complete, you should have:

完成 onboarding 后，你应该具备以下结果：

- one private deployment repository based on this template
- one GitHub OIDC trust relationship in each AWS account used for deployment
- one deploy role for `devo` and one for `prod`
- one Pulumi state bucket
- one KMS alias for Pulumi secrets encryption
- GitHub repository secrets and variables configured
- a `devo` stack ready for preview and deployment
- a `prod` stack ready for promotion after `devo` is validated

- 一个基于本模板创建的私有部署仓库
- 每个用于部署的 AWS 账户中各自存在 GitHub OIDC 信任关系
- 一个 `devo` deploy role 和一个 `prod` deploy role
- 一个 Pulumi state bucket
- 一个用于 Pulumi secrets 加密的 KMS alias
- 已配置好的 GitHub 仓库 secrets 和 variables
- 一个可用于 preview 与部署的 `devo` stack
- 一个在 `devo` 验证完成后可用于 promotion 的 `prod` stack

## Before You Start / 开始之前

You will need:

你需要提前准备：

- a GitHub organization or account that can host a private repository
- a devo AWS account and optionally a separate prod AWS account
- a Cloudflare zone for your domains
- permission to create or update IAM roles, IAM OIDC providers, S3 buckets, and KMS keys
- a customer-specific `LTBASE_RELEASES_TOKEN`
- a Gemini API key

- 一个可以创建私有仓库的 GitHub 组织或账号
- 一个 devo AWS 账户，以及可选的单独 prod AWS 账户
- 一个用于业务域名的 Cloudflare zone
- 创建或更新 IAM role、IAM OIDC provider、S3 bucket、KMS key 的权限
- 一个客户专用的 `LTBASE_RELEASES_TOKEN`
- 一个 Gemini API key

For the detailed preparation checklist, use:

更详细的准备清单请看：

- [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)

## Full Onboarding Order / 完整操作顺序

Follow the steps in this order:

请按下面顺序操作：

### Step 1 - Prepare prerequisites / 第一步：准备前置条件

- Read: [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- Covers: accounts, permissions, tokens, domains, local tools

- 阅读：[`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- 内容包括：账户、权限、token、域名、本地工具

### Step 2 - Create the deployment repository and clone it / 第二步：创建部署仓库并克隆到本地

- Read: [`docs/onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- Covers: creating the private repo from template, cloning locally, verifying repository layout

- 阅读：[`docs/onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- 内容包括：从模板创建私有仓库、拉取到本地、确认目录结构

### Step 3 - Create GitHub OIDC and deploy roles / 第三步：创建 GitHub OIDC 和 deploy role

- Read: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- Covers: OIDC provider, devo/prod deploy roles, trust policy, permissions policy

- 阅读：[`docs/onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- 内容包括：OIDC provider、devo/prod deploy role、信任策略、权限策略

### Step 4 - Prepare the local `.env` file / 第四步：准备本地 `.env` 文件

- Read: [`docs/onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- Covers: every required `.env` field, where each value comes from, what must not be edited manually

- 阅读：[`docs/onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- 内容包括：`.env` 每个必填字段、每个值从哪里来、哪些值不能手填

### Step 5 - Choose a bootstrap path / 第五步：选择 bootstrap 路径

If you have enough GitHub and AWS permissions, use the one-click path:

如果你拥有足够的 GitHub 和 AWS 权限，优先使用一键路径：

- [`docs/onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)

If you want to control each stage manually, use the manual path:

如果你希望逐步控制每一个阶段，请使用手动路径：

- [`docs/onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)

### Step 6 - Run the first preview and deployment / 第六步：执行第一次 preview 和部署

- Read: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- Covers: preview, devo deploy, prod promotion, managed DSQL post-bootstrap handling

- 阅读：[`docs/onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- 内容包括：preview、devo deploy、prod promotion、managed DSQL 的 bootstrap 后处理

### Step 7 - Day-2 operations / 第七步：日常运维与升级

- Read: [`docs/onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- Covers: release upgrades, repeated previews, deployment rhythm, operational reminders

- 阅读：[`docs/onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- 内容包括：release 升级、重复 preview、部署节奏、运维提醒

## Required GitHub Secrets and Variables / 必需的 GitHub Secrets 与 Variables

Set these repository secrets in your deployment repository:

在你的部署仓库中设置以下 secrets：

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

Set these repository variables in your deployment repository:

在你的部署仓库中设置以下 variables：

- `AWS_REGION_DEVO`
- `AWS_REGION_PROD`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_DEVO`
- `PULUMI_SECRETS_PROVIDER_PROD`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

The bootstrap scripts write these values for you when `.env` is correct.

当 `.env` 正确时，bootstrap 脚本会帮你写入这些值。

## Important Managed DSQL Note / Managed DSQL 重要说明

For managed deployments, do not manually provide an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword`.

对于 managed 部署，不要手动提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

At the time of writing, this repository's bootstrap scripts use a bootstrap-safe split: bootstrap prepares GitHub and Pulumi state first, and `scripts/reconcile-managed-dsql-endpoint.sh` publishes the managed DSQL endpoint after infrastructure exists.

在当前仓库版本中，bootstrap 脚本采用 bootstrap-safe 的拆分流程：bootstrap 先准备 GitHub 与 Pulumi 状态，`scripts/reconcile-managed-dsql-endpoint.sh` 会在基础设施实际存在之后发布 managed DSQL endpoint。

Aurora DSQL itself is created by the Pulumi blueprint. You do not supply an external `dsqlHost`, `dsqlEndpoint`, or `dsqlPassword` for managed deployments.

Aurora DSQL 由 Pulumi blueprint 自动创建。对于 managed 部署，你不需要提供外部 `dsqlHost`、`dsqlEndpoint` 或 `dsqlPassword`。

The current repository version uses a bootstrap-safe flow:

当前仓库版本采用 bootstrap-safe 流程：

- `bootstrap-all.sh` and `bootstrap-deployment-repo.sh` prepare configuration only
- the first real infrastructure apply creates the managed DSQL cluster
- `scripts/reconcile-managed-dsql-endpoint.sh` resolves the authoritative endpoint from AWS by using the Pulumi-exported `dsqlClusterIdentifier`
- the reconcile step publishes the resolved endpoint into stack config as `dsqlEndpoint`
- after reconciliation, run the next preview/deploy cycle so Lambda environment configuration picks up the managed endpoint

- `bootstrap-all.sh` 和 `bootstrap-deployment-repo.sh` 只负责准备配置
- 第一次真实基础设施 apply 会创建 managed DSQL cluster
- `scripts/reconcile-managed-dsql-endpoint.sh` 会通过 Pulumi 导出的 `dsqlClusterIdentifier` 从 AWS 获取权威 endpoint
- reconcile 步骤会把解析出的 endpoint 写入 stack config 的 `dsqlEndpoint`
- reconcile 完成后，需要再执行下一轮 preview/deploy，才能让 Lambda 环境变量拿到这个 managed endpoint

## Operational Constraints / 运维约束

- `LTBASE_RELEASES_TOKEN` is only for downloading official LTBase releases
- local `.env` files contain secrets and must never be committed
- the template repository does not auto-run preview on pull requests because it has no live customer credentials
- production approval happens in your own repository through the `prod` environment gate

- `LTBASE_RELEASES_TOKEN` 仅用于下载官方 LTBase release
- 本地 `.env` 文件包含敏感信息，绝对不能提交到仓库
- 模板仓库不会在 pull request 上自动执行 preview，因为模板仓库不包含真实客户凭据
- 生产环境审批发生在你自己的仓库中，通过 `prod` environment gate 实现

## Related Documents / 相关文档

- quick checklist: [`docs/BOOTSTRAP.md`](BOOTSTRAP.md)
- prerequisites: [`docs/onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- create repo and clone: [`docs/onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- create OIDC and roles: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- prepare `.env`: [`docs/onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- one-click bootstrap: [`docs/onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)
- manual bootstrap: [`docs/onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- first deploy: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- day-2 operations: [`docs/onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
