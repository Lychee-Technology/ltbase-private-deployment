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
- create one deploy role for `devo` and one for `prod`

- 阅读 [`onboarding/03-create-oidc-and-deploy-roles.md`](onboarding/03-create-oidc-and-deploy-roles.md)
- 为 `devo` 和 `prod` 各创建一个 deploy role

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
- run `./scripts/bootstrap-all.sh --env-file .env --mode apply --infra-dir infra`

- 阅读 [`onboarding/05-bootstrap-one-click.md`](onboarding/05-bootstrap-one-click.md)
- 运行 `./scripts/bootstrap-all.sh --env-file .env --mode apply --infra-dir infra`

Manual path:

手动路径：

- read [`onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- run the bootstrap scripts stage by stage

- 阅读 [`onboarding/06-bootstrap-manual.md`](onboarding/06-bootstrap-manual.md)
- 按阶段逐个执行 bootstrap 脚本

### 6. Run the first deployment / 6. 执行首次部署

- read [`onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- run preview
- deploy `devo`
- validate `devo`
- promote to `prod`

- 阅读 [`onboarding/07-first-deploy-and-managed-dsql.md`](onboarding/07-first-deploy-and-managed-dsql.md)
- 执行 preview
- 部署 `devo`
- 验证 `devo`
- 推进到 `prod`

### 7. Day-2 operations / 7. 日常运维

- read [`onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- use the same preview -> devo -> prod rhythm for upgrades

- 阅读 [`onboarding/08-day-2-operations.md`](onboarding/08-day-2-operations.md)
- 后续升级继续沿用 preview -> devo -> prod 的节奏

## Required GitHub Secrets / 必需的 GitHub Secrets

- `AWS_ROLE_ARN_DEVO`
- `AWS_ROLE_ARN_PROD`
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## Required GitHub Variables / 必需的 GitHub Variables

- `AWS_REGION_DEVO`
- `AWS_REGION_PROD`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_DEVO`
- `PULUMI_SECRETS_PROVIDER_PROD`
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`

## Notes / 说明

- keep `.env` private and outside version control
- the deployment repository downloads official LTBase releases; it does not build the app itself
- preview is manual in the customer repo because live credentials are customer-owned
- production deployment is guarded by the `prod` environment approval gate

- 保持 `.env` 私密，不要纳入版本控制
- 部署仓库负责下载官方 LTBase release，不负责自行构建应用
- 客户仓库中的 preview 默认为手动触发，因为真实凭据由客户持有
- 生产部署由 `prod` environment 审批 gate 保护
