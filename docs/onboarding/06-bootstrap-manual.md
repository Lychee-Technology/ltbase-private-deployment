# Manual Bootstrap / 手动 Bootstrap

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide when you want to review each bootstrap stage separately instead of running the one-click path.

如果你希望逐步检查每个 bootstrap 阶段，而不是使用一键流程，请使用本文档。

## Before You Start / 开始前确认

- complete [`04-prepare-env-file.md`](04-prepare-env-file.md)
- decide that you want to control each bootstrap stage manually

- 已完成 [`04-prepare-env-file.md`](04-prepare-env-file.md)
- 已决定手动控制每一个 bootstrap 阶段

## Steps / 操作步骤

### 1. Create the real deployment repo / 创建真实部署仓库

Run:

执行：

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

### 2. Bootstrap AWS foundation / 初始化 AWS 基础资源

Run:

执行：

```bash
./scripts/bootstrap-aws-foundation.sh --env-file .env
```

This step creates or updates:

该步骤会创建或更新：

- GitHub OIDC provider
- deploy roles
- trust policies
- inline role policies
- Pulumi state bucket
- Pulumi KMS alias

It also generates `dist/foundation.env` and review artifacts.

它还会生成 `dist/foundation.env` 和审阅用文件。

### 3. Optionally merge generated foundation values / 可选：合并自动生成的 foundation 值

If bootstrap generated new Pulumi backend values, merge them into your shell or `.env`:

如果 bootstrap 生成了新的 Pulumi backend 值，请将它们合并回 shell 或 `.env`：

```bash
source dist/foundation.env
```

### 4. Bootstrap Pulumi backend only if needed / 仅在需要时单独初始化 Pulumi backend

Run this if you want the backend/KMS path separately:

如果你希望单独执行 backend/KMS 流程，可运行：

```bash
./scripts/bootstrap-pulumi-backend.sh --env-file .env
```

### 5. Bootstrap every configured stack / 初始化所有已配置 stack

Run:

执行：

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack> --infra-dir infra
```

Repeat the command once for each stack listed in `STACKS`, in the same order as `PROMOTION_PATH`.

对 `STACKS` 中列出的每个 stack 都执行一次，顺序与 `PROMOTION_PATH` 保持一致。

### 6. Bootstrap OIDC discovery companion / 初始化 OIDC discovery 配套资源

Run:

执行：

```bash
./scripts/bootstrap-oidc-discovery-companion.sh --env-file .env
```

This step creates or updates the OIDC discovery companion repository, Cloudflare Pages project, custom domain binding, and per-stack OIDC discovery IAM roles.

该步骤会创建或更新 OIDC discovery 配套仓库、Cloudflare Pages 项目、自定义域名绑定，以及每个 stack 对应的 OIDC discovery IAM role。

### 7. Confirm repository configuration / 确认仓库配置完成

Check that the repository now contains the required GitHub secrets and variables.

确认仓库中已经出现所需 GitHub secrets 和 variables。

## Expected Result / 预期结果

You finish with all bootstrap stages completed manually and the repository is ready for the first preview and deployment.

执行完成后，所有 bootstrap 阶段都已手动完成，仓库已可用于第一次 preview 和 deployment。

## Common Mistakes / 常见问题

- forgetting to source `dist/foundation.env` after AWS foundation generated new values
- skipping later stacks in `STACKS` and only preparing the first stack
- running manual bootstrap commands outside the repository root

- 在 AWS foundation 生成新值后忘记 `source dist/foundation.env`
- 只初始化了第一个 stack，没有初始化 `STACKS` 中后续环境
- 在仓库根目录之外执行手动 bootstrap 命令

## Next Step / 下一步

Continue with [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md).

继续阅读 [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md)。
