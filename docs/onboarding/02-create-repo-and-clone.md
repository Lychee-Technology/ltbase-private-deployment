# Create the Deployment Repository and Clone It / 创建部署仓库并克隆到本地

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide to create your customer-owned deployment repository from the template and verify that the local checkout contains the expected files.

使用本文档从模板创建你的客户部署仓库，并确认本地仓库包含预期文件。

## Before You Start / 开始前确认

- complete [`01-prerequisites.md`](01-prerequisites.md)
- know the target GitHub owner and repository name

- 已完成 [`01-prerequisites.md`](01-prerequisites.md)
- 已确定目标 GitHub owner 和仓库名

## Steps / 操作步骤

1. Create a new private repository from the `ltbase-private-deployment` template.
2. Use a repository name that matches your internal naming convention.
3. Clone the newly created repository locally.
4. Open the repository root and confirm the following exist:
   - `infra/`
   - `.github/workflows/`
   - `env.template`
   - `scripts/create-deployment-repo.sh`
   - `scripts/render-bootstrap-policies.sh`
   - `scripts/bootstrap-aws-foundation.sh`
   - `scripts/bootstrap-pulumi-backend.sh`
   - `scripts/bootstrap-oidc-discovery-companion.sh`
   - `scripts/bootstrap-deployment-repo.sh`
   - `scripts/bootstrap-all.sh`
   - `scripts/evaluate-and-continue.sh`
   - `scripts/reconcile-managed-dsql-endpoint.sh`
5. Confirm that the repository is private.
6. Confirm that the `prod` environment will be available for later approval gating.

1. 从 `ltbase-private-deployment` 模板创建新的私有仓库。
2. 使用符合你内部规范的仓库命名。
3. 将新仓库 clone 到本地。
4. 打开仓库根目录，确认以下内容存在：
   - `infra/`
   - `.github/workflows/`
   - `env.template`
   - `scripts/create-deployment-repo.sh`
   - `scripts/render-bootstrap-policies.sh`
   - `scripts/bootstrap-aws-foundation.sh`
   - `scripts/bootstrap-pulumi-backend.sh`
   - `scripts/bootstrap-oidc-discovery-companion.sh`
   - `scripts/bootstrap-deployment-repo.sh`
   - `scripts/bootstrap-all.sh`
   - `scripts/evaluate-and-continue.sh`
   - `scripts/reconcile-managed-dsql-endpoint.sh`
5. 确认仓库是私有的。
6. 确认后续用于审批的 `prod` environment 可以创建。

## Expected Result / 预期结果

You have a local working copy of your deployment repository and it matches the expected LTBase private deployment layout.

你已经获得本地部署仓库副本，并且目录结构符合 LTBase 私有部署模板预期。

## Common Mistakes / 常见问题

- creating the repo manually without using the template
- cloning the template repo instead of your own private repo
- forgetting to verify that `.github/workflows/` and `infra/` exist

- 手动创建空仓库而不是从模板生成
- clone 错了仓库，拉到了模板仓库而不是自己的私有仓库
- 没有确认 `.github/workflows/` 和 `infra/` 是否存在

## Next Step / 下一步

Continue with [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md).

继续阅读 [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md)。
