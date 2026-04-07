> **English version: [BOOTSTRAP.md](BOOTSTRAP.md)**

# 客户 Bootstrap 清单

这是客户 onboarding 流程的简版清单。

完整的中英双语说明请从这里开始：

- [`CUSTOMER_ONBOARDING.zh.md`](CUSTOMER_ONBOARDING.zh.md)

## 仓库结构

你的部署仓库应包含：

- `infra/`
- `.github/workflows/`
- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-oidc-discovery-companion.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/sync-template-upstream.sh`
- `scripts/reconcile-managed-dsql-endpoint.sh`
- `scripts/lib/bootstrap-env.sh`

## 快速清单

### 1. 准备前置条件

- 阅读 [`onboarding/01-prerequisites.zh.md`](onboarding/01-prerequisites.zh.md)
- 确认 GitHub、AWS、Cloudflare、`LTBASE_RELEASES_TOKEN` 与 `GEMINI_API_KEY` 都已准备好

### 2. 创建部署仓库

- 阅读 [`onboarding/02-create-repo-and-clone.zh.md`](onboarding/02-create-repo-and-clone.zh.md)
- 从模板创建私有仓库并 clone 到本地

### 3. 创建 OIDC 和 deploy role

- 阅读 [`onboarding/03-create-oidc-and-deploy-roles.zh.md`](onboarding/03-create-oidc-and-deploy-roles.zh.md)
- 为 `STACKS` 中的每个环境各创建一个 deploy role

### 4. 准备 `.env`

- 阅读 [`onboarding/04-prepare-env-file.zh.md`](onboarding/04-prepare-env-file.zh.md)
- 将 `env.template` 复制为 `.env`
- 填写真实值，并且绝对不要提交 `.env`

### 5. 选择 bootstrap 路径

一键路径：

- 阅读 [`onboarding/05-bootstrap-one-click.zh.md`](onboarding/05-bootstrap-one-click.zh.md)
- 运行 `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra`

手动路径：

- 阅读 [`onboarding/06-bootstrap-manual.zh.md`](onboarding/06-bootstrap-manual.zh.md)
- 按阶段逐个执行 bootstrap 脚本

### 6. 执行首次部署

- 阅读 [`onboarding/07-first-deploy-and-managed-dsql.zh.md`](onboarding/07-first-deploy-and-managed-dsql.zh.md)
- 对 `PROMOTION_PATH` 第一个环境执行 preview
- 针对目标 release 触发一次 `rollout.yml`
- 在 GitHub 请求时依次审批受保护目标环境

### 7. 日常运维

- 阅读 [`onboarding/08-day-2-operations.zh.md`](onboarding/08-day-2-operations.zh.md)
- 后续升级继续沿用 preview -> rollout 的节奏

## 必需的 GitHub Secrets

- `AWS_ROLE_ARN_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## 必需的 GitHub Variables

- `AWS_REGION_<STACK>` for every stack in `STACKS`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

## 说明

- 保持 `.env` 私密，不要纳入版本控制
- 部署仓库负责下载官方 LTBase release，不负责自行构建应用
- 客户仓库中的 preview 默认为手动触发，因为真实凭据由客户持有
- 手动 preview 只支持 `PROMOTION_PATH` 的第一个环境
- rollout 中的受保护目标环境由各自的 GitHub environment 审批 gate 保护
