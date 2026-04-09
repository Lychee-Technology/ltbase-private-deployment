> **English version: [README.md](README.md)**

# LTBase 私有部署模板

本仓库是 LTBase 面向客户的部署模板仓库。

它用于生成客户自有的私有部署仓库。

## 用途

本仓库的用途是帮助客户将官方 LTBase release 部署到自己的 AWS 账户中。

它不是 LTBase 应用源码仓库。

## 仓库包含内容

- 调用 LTBase 公共可复用部署工作流的轻量封装工作流
- 用于 GitHub 仓库初始化、AWS 基础设施初始化、Pulumi stack 配置的 bootstrap 脚本
- 例如 `env.template` 这样的部署输入示例
- 面向客户的 onboarding 与 bootstrap 文档

## 从这里开始

如果你正在启动一个新的客户部署，请从这里开始：

- 完整 onboarding 手册：[`docs/CUSTOMER_ONBOARDING.zh.md`](docs/CUSTOMER_ONBOARDING.zh.md)
- 快速 bootstrap 清单：[`docs/BOOTSTRAP.zh.md`](docs/BOOTSTRAP.zh.md)

对于新部署，推荐阅读顺序：

- 前置条件与访问检查：[`docs/onboarding/01-prerequisites.zh.md`](docs/onboarding/01-prerequisites.zh.md)
- `.env` 准备与派生值说明：[`docs/onboarding/04-prepare-env-file.zh.md`](docs/onboarding/04-prepare-env-file.zh.md)
- 一键 bootstrap 的就绪检查与 preflight：[`docs/onboarding/05-bootstrap-one-click.zh.md`](docs/onboarding/05-bootstrap-one-click.zh.md)
- 手动 bootstrap 的阶段拆解与检查点：[`docs/onboarding/06-bootstrap-manual.zh.md`](docs/onboarding/06-bootstrap-manual.zh.md)
- 首次部署、审批节奏与 managed DSQL 后续处理：[`docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`](docs/onboarding/07-first-deploy-and-managed-dsql.zh.md)

onboarding 文档支持通用多 stack 拓扑。文中出现 `devo`、`prod` 等名称时，只应视为示例。

## 文档地图

主入口文档：

- [`docs/CUSTOMER_ONBOARDING.zh.md`](docs/CUSTOMER_ONBOARDING.zh.md)
- [`docs/BOOTSTRAP.zh.md`](docs/BOOTSTRAP.zh.md)

详细 onboarding 子文档：

- 前提条件：[`docs/onboarding/01-prerequisites.zh.md`](docs/onboarding/01-prerequisites.zh.md)
- 创建仓库并克隆：[`docs/onboarding/02-create-repo-and-clone.zh.md`](docs/onboarding/02-create-repo-and-clone.zh.md)
- 创建 OIDC 与部署角色：[`docs/onboarding/03-create-oidc-and-deploy-roles.zh.md`](docs/onboarding/03-create-oidc-and-deploy-roles.zh.md)
- 准备 `.env`：[`docs/onboarding/04-prepare-env-file.zh.md`](docs/onboarding/04-prepare-env-file.zh.md)
- 一键 bootstrap：[`docs/onboarding/05-bootstrap-one-click.zh.md`](docs/onboarding/05-bootstrap-one-click.zh.md)
- 手动 bootstrap：[`docs/onboarding/06-bootstrap-manual.zh.md`](docs/onboarding/06-bootstrap-manual.zh.md)
- 首次部署与 managed DSQL 处理：[`docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`](docs/onboarding/07-first-deploy-and-managed-dsql.zh.md)
- 日常运维操作：[`docs/onboarding/08-day-2-operations.zh.md`](docs/onboarding/08-day-2-operations.zh.md)

如果你使用恢复感知的 bootstrap 路径，最关键的操作文档是：

- `docs/CUSTOMER_ONBOARDING.zh.md`
- `docs/onboarding/05-bootstrap-one-click.zh.md`
- `docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`

## Bootstrap 入口脚本

重要文件与脚本：

- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-oidc-discovery-companion.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/update-sync-template-tooling.sh`
- `scripts/sync-template-upstream.sh`

推荐的可恢复 bootstrap 入口：

- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --release-id <release>`

当前 bootstrap 流程还会自动管理客户专属的 `*-oidc-discovery` companion repo、对应的 Cloudflare Pages project 与自定义域名，以及 companion publish workflow 需要假设的每个 stack 的只读 discovery role。

对于日常维护，从该模板生成出来的部署仓库可以通过以下命令同步后续模板变更：

- `./scripts/update-sync-template-tooling.sh`
- `./scripts/sync-template-upstream.sh`

当你希望先拿到模板中的最新同步工具和对应回归测试时，先运行 `./scripts/update-sync-template-tooling.sh`，再运行 `./scripts/sync-template-upstream.sh` 同步模板管理的文件。模板同步会保留本地 `.env`、`infra/Pulumi.*.yaml`、由 deployment repo 自行维护的 `infra/auth-providers.*.json`，以及同步工具自己的脚本与测试文件。

## 部署原则

- 部署仓库负责下载官方 LTBase release，而不是自行构建应用源码
- 客户自行持有 GitHub 仓库、AWS 资源和部署审批权
- bootstrap 脚本负责准备仓库状态和部署配置
- 共享的 Pulumi backend bucket 只创建一次，并固定放在 `PROMOTION_PATH` 第一个 stack 对应的 AWS 账户中
- 手动 preview 只针对 `PROMOTION_PATH` 的第一个环境
- 自动 rollout 会按 `PROMOTION_PATH` 逐跳推进，受保护目标环境仍由客户自己审批
- `api`、`auth`、`control-plane` 默认应通过 Cloudflare 代理的自定义域名访问，并在 API Gateway 上启用 mutual TLS

## 说明

- 保持本地 `.env` 文件私密，不要纳入版本控制
- 客户 onboarding 请以 `docs/` 下文档为准
- 如果后续仓库版本调整了 managed DSQL 生命周期，请以该版本自带文档为准
- 操作者需要将 Cloudflare SSL 模式保持为 `Full (strict)`，并为 API hostname 启用 Authenticated Origin Pulls
- 一旦应用 mTLS rollout，直连 `execute-api` 失败属于设计预期
