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

## 当前 Control Plane UI 模型

在当前仓库版本中，操作者应把 Control Plane UI 视为一个以 `CONTROLPLANE_UI_DOMAIN` 为入口、托管在 Cloudflare Pages 上的管理端站点。

- `preview` 仍然只做基础设施预览；它会校验 release 选择、stack 配置和 Pulumi 变更，但不会发布 Control Plane UI
- 当前 bootstrap 脚本仍然使用 companion 风格的 Control Plane UI 初始化方式，包括单独的 `*-controlplane-ui` 仓库、Cloudflare Pages project、自定义域名绑定、DNS 配置，以及 companion 仓库变量
- deployment repo 仍然是这些 UI 输入的操作者侧权威来源，包括 `CONTROLPLANE_UI_DOMAIN`、各 stack 的浏览器配置值、auth provider 名称对齐，以及 Control Plane CORS 输入
- UI runtime config 只能包含浏览器可公开的信息；不要把服务端 secret、service-role key 或管理凭据写进 Control Plane UI 配置
- 操作者的身份提供方必须允许 `https://<CONTROLPLANE_UI_DOMAIN>/auth/callback`，同时部署出来的 Control Plane API 也必须通过 CORS 允许这个 admin 域名

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
- `scripts/bootstrap-oidc-discovery.sh`
- `scripts/bootstrap-controlplane-ui-companion.sh`
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

当前 bootstrap 流程还会管理 OIDC discovery Cloudflare Pages 项目（以直接上传方式创建，无 companion 仓库）、其自定义域名绑定、指向 `${OIDC_DISCOVERY_PAGES_PROJECT}.pages.dev` 的 zone 级 `CNAME`，以及每个 stack 的只读 discovery role。随后由部署仓库自身的 `publish-oidc-discovery.yml` 工作流生成 discovery 文档，并通过 `wrangler pages deploy` 发布。

在当前仓库版本中，`scripts/bootstrap-controlplane-ui-companion.sh` 还会管理客户专属的 `*-controlplane-ui` companion repo、对应的 Cloudflare Pages project、自定义域名绑定、指向 `${CONTROLPLANE_UI_PAGES_PROJECT}.pages.dev` 的 zone 级 `CNAME`，以及通过 companion 仓库变量 `CONTROLPLANE_UI_STACK_CONFIG` 发布到 `public/ltbase-controlplane.config.json` 的 runtime config JSON。

当前 control plane UI bootstrap 会为每个 stack 同时输出 Firebase 和 Supabase 两种浏览器 provider。它还会在 `AUTH_PROVIDER_CONFIG_FILE_<STACK>` 中存在匹配 issuer 且 `enable_login=true` 的 deployment 自有 provider 记录时，复用对应的 provider 名称。因此在运行 `scripts/bootstrap-controlplane-ui-companion.sh` 之前，每个 stack 都必须在 `.env` 中提供以下公开、可安全下发到浏览器的字段：

- `FIREBASE_API_KEY_<STACK>`
- `FIREBASE_PROJECT_ID_<STACK>`
- `SUPABASE_URL_<STACK>`
- `SUPABASE_ANON_KEY_<STACK>`

这四个值现在也会由 `scripts/bootstrap-deployment-repo.sh` 写入每个 Pulumi stack config。infra 程序会导出一个浏览器安全的 `controlplaneUiStackConfig` output，供官方 rollout 工作流聚合成共享 control plane UI 的运行时配置。

对于日常维护，从该模板生成出来的部署仓库可以通过以下命令同步后续模板变更：

- `./scripts/update-sync-template-tooling.sh`
- `./scripts/sync-template-upstream.sh`

当你希望先拿到模板中的最新同步工具和对应回归测试时，先运行 `./scripts/update-sync-template-tooling.sh`，再运行 `./scripts/sync-template-upstream.sh` 同步模板管理的文件。模板同步会保留本地 `.env`、`infra/Pulumi.*.yaml`、整个 `customer-owned/` 目录树、由 deployment repo 自行维护的 `infra/auth-providers.*.json`，以及同步工具自己的脚本与测试文件。

此模板仓库只跟踪 `infra/auth-providers.*.json.example`。从模板生成出来的客户 deployment repo 需要自行创建并维护真实的 `infra/auth-providers.<stack>.json` 文件，并且可以在该客户仓库中提交这些客户专属文件。

## 部署原则

- 部署仓库负责下载官方 LTBase release，而不是自行构建应用源码
- 官方工作流也可能先从 `Lychee-Technology/ltbase-private-deployment-binaries` 下载与上游模板版本绑定的预构建 `ltbase-infra` 二进制，以避免每次都重新编译 Pulumi Go 程序
- 这些预构建 infra binary 只由上游模板仓库发布；从模板生成出的客户部署仓库只负责消费
- 客户自行持有 GitHub 仓库、AWS 资源和部署审批权
- bootstrap 脚本负责准备仓库状态和部署配置
- 即使当前仍保留 companion 风格的 Control Plane UI 初始化脚本，相关操作者输入的权威来源仍然是 deployment repo
- 共享的 Pulumi backend bucket 只创建一次，并固定放在 `PROMOTION_PATH` 第一个 stack 对应的 AWS 账户中
- 手动 preview 只针对 `PROMOTION_PATH` 的第一个环境
- 自动 rollout 会按 `PROMOTION_PATH` 逐跳推进，受保护目标环境仍由客户自己审批
- `api`、`auth`、`control-plane` 默认应通过 Cloudflare 代理的自定义域名访问，并在 API Gateway 上启用 mutual TLS

## Control Plane UI Rollout

从模板生成出的 deployment repo 现在会把以下三个可选值透传给共享的 `ltbase-deploy-workflows` rollout workflow：

- `CONTROLPLANE_UI_DOMAIN`
- `CONTROLPLANE_UI_PAGES_PROJECT`
- `STACKS`

当这些值存在，且上游 release contract 已经包含官方 UI artifact 时，rollout 就可以直接从 release 资产发布 control plane UI，而不必只依赖 companion repo 的 publish flow。

rollout 侧的运行时配置来自每个 stack 的 Pulumi outputs：

- 每个 stack 都必须导出 `controlplaneUiStackConfig`
- 只有输出完整的 stack 才会被写入最终部署的 `ltbase-controlplane.config.json`
- 当前 rollout 的 target stack 必须存在，否则 rollout 失败
- `redirectUri` 会在 rollout 时通过 `https://${CONTROLPLANE_UI_DOMAIN}/auth/callback` 派生

上游 release contract 在每个 `ltbase-releases` GitHub release 中都包含官方的 `ltbase-controlplane-ui.tar.gz` artifact。当 deployment 仓库提供 `CONTROLPLANE_UI_PAGES_PROJECT` 和渲染好的 runtime config 时，rollout 工作流会直接从下载到的 release 资产发布 control plane UI 到 Cloudflare Pages。

## 说明

- 保持本地 `.env` 文件私密，不要纳入版本控制
- 客户 onboarding 请以 `docs/` 下文档为准
- `__ref__/template-provenance.json` 会记录上游模板 commit 和 `build_fingerprint`，官方工作流会用它来查找可用的预构建 infra binary
- 向 `ltbase-private-deployment-binaries` 发布二进制只需要在上游模板仓库配置 `LTBASE_PRIVATE_DEPLOYMENT_BINARIES_TOKEN`
- 从模板生成出的客户部署仓库也会带上 `.github/workflows/build-infra-binary.yml`，但该工作流带有 repo guard，在 `Lychee-Technology/ltbase-private-deployment` 之外会直接跳过
- 只有当同步下来的 provenance 和 `build_fingerprint` 与上游已发布 manifest 完全匹配时，官方工作流才会安装预构建 binary；否则会回退到源码构建
- 如果后续仓库版本调整了 Control Plane UI 部署模型，请以该版本自带文档为准；本文档当前刻意记录的是这个仓库里仍然存在的 companion 风格 setup
- 如果后续仓库版本调整了 managed DSQL 生命周期，请以该版本自带文档为准
- 操作者需要将 Cloudflare SSL 模式保持为 `Full (strict)`，并为 API hostname 启用 Authenticated Origin Pulls
- preview 与 rollout 的 mTLS audit 还要求 `CLOUDFLARE_API_TOKEN` 具备读取目标 zone 的 Cloudflare zone settings 权限，而不只是读取 DNS 记录
- 一旦应用 mTLS rollout，直连 `execute-api` 失败属于设计预期
