# Customer Bootstrap Checklist / 客户 Bootstrap 清单

This is the short checklist version of the customer onboarding flow.

这是客户 onboarding 流程的简版清单。

For the full bilingual runbook, start here:

完整的中英双语说明请从这里开始：

- [`CUSTOMER_ONBOARDING.md`](CUSTOMER_ONBOARDING.md)

## Repository Layout / 仓库结构

Your deployment repository should contain:

你的部署仓库应包含：

- `infra/`
- `.github/workflows/`
- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`

## Quick Checklist / 快速清单

### 1. Prepare prerequisites / 1. 准备前置条件

- read [`onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- confirm GitHub, AWS, Cloudflare, `LTBASE_RELEASES_TOKEN`, and `GEMINI_API_KEY`

- 阅读 [`onboarding/01-prerequisites.md`](onboarding/01-prerequisites.md)
- 确认 GitHub、AWS、Cloudflare、`LTBASE_RELEASES_TOKEN` 与 `GEMINI_API_KEY` 都已准备好

### 2. Create the deployment repository / 2. 创建部署仓库

- read [`onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- create the private repo from template and clone it locally

- 阅读 [`onboarding/02-create-repo-and-clone.md`](onboarding/02-create-repo-and-clone.md)
- 从模板创建私有仓库并 clone 到本地

### 3. Create OIDC and deploy roles / 3. 创建 OIDC 和 deploy role

- read [`onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- create one deploy role for each stack in `STACKS`

- 阅读 [`onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- 为 `STACKS` 中的每个环境各创建一个 deploy role

### 4. Prepare `.env` / 4. 准备 `.env`

- read [`onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- copy `env.template` to `.env`
- fill real values and never commit `.env`

- 阅读 [`onboarding/04-prepare-env-file.md`](onboarding/04-prepare-env-file.md)
- 将 `env.template` 复制为 `.env`
- 填写真实值，并且绝对不要提交 `.env`

### 5. Choose a bootstrap path / 5. 选择 bootstrap 路径

One-click path:

一键路径：

- read [`onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)
- run `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra`

- 阅读 [`onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)
- 运行 `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra`

Manual path:

手动路径：

- read [`onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- run the bootstrap scripts stage by stage

- 阅读 [`onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- 按阶段逐个执行 bootstrap 脚本

### 6. Run the first deployment / 6. 执行首次部署

- read [`onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- run preview for the first stack in `PROMOTION_PATH`
- trigger `rollout.yml` once for the chosen release
- approve each protected target stack as GitHub requests it

- 阅读 [`onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- 对 `PROMOTION_PATH` 第一个环境执行 preview
- 针对目标 release 触发一次 `rollout.yml`
- 在 GitHub 请求时依次审批受保护目标环境

### 7. Day-2 operations / 7. 日常运维

- read [`onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- use the same preview -> rollout rhythm for upgrades

- 阅读 [`onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- 后续升级继续沿用 preview -> rollout 的节奏

## Required GitHub Secrets / 必需的 GitHub Secrets

- `AWS_ROLE_ARN_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required GitHub Variables / 必需的 GitHub Variables

- `AWS_REGION_<STACK>` for every stack in `STACKS`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>` for every stack in `STACKS`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`

## Notes / 说明

- keep `.env` private and outside version control
- the deployment repository downloads official LTBase releases; it does not build the app itself
- preview is manual in the customer repo because live credentials are customer-owned
- manual preview only supports the first stack in `PROMOTION_PATH`
- protected target environments are guarded by per-stack GitHub environment approval gates during rollout

- 保持 `.env` 私密，不要纳入版本控制
- 部署仓库负责下载官方 LTBase release，不负责自行构建应用
- 客户仓库中的 preview 默认为手动触发，因为真实凭据由客户持有
- 手动 preview 只支持 `PROMOTION_PATH` 的第一个环境
- rollout 中的受保护目标环境由各自的 GitHub environment 审批 gate 保护
