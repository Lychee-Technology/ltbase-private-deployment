# 手动 Bootstrap

> **[English](06-bootstrap-manual.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

如果你希望逐步检查每个 bootstrap 阶段，而不是使用一键流程，请使用本文档。

## 开始前确认

- 已完成 [`04-prepare-env-file.zh.md`](04-prepare-env-file.zh.md)
- 已决定手动控制每一个 bootstrap 阶段

## 操作步骤

### 1. 创建真实部署仓库

执行：

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

### 2. 初始化 AWS 基础资源

执行：

```bash
./scripts/bootstrap-aws-foundation.sh --env-file .env
```

该步骤会创建或更新：

- GitHub OIDC provider
- deploy roles
- trust policies
- inline role policies
- Pulumi state bucket
- Pulumi KMS alias

它还会生成 `dist/foundation.env` 和审阅用文件。

### 3. 可选：合并自动生成的 foundation 值

如果 bootstrap 生成了新的 Pulumi backend 值，请将它们合并回 shell 或 `.env`：

```bash
source dist/foundation.env
```

### 4. 仅在需要时单独初始化 Pulumi backend

如果你希望单独执行 backend/KMS 流程，可运行：

```bash
./scripts/bootstrap-pulumi-backend.sh --env-file .env
```

### 5. 初始化所有已配置 stack

执行：

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack> --infra-dir infra
```

对 `STACKS` 中列出的每个 stack 都执行一次，顺序与 `PROMOTION_PATH` 保持一致。

### 6. 初始化 OIDC discovery 配套资源

执行：

```bash
./scripts/bootstrap-oidc-discovery-companion.sh --env-file .env
```

该步骤会创建或更新 OIDC discovery 配套仓库、Cloudflare Pages 项目、自定义域名绑定，以及每个 stack 对应的 OIDC discovery IAM role。

### 7. 确认仓库配置完成

确认仓库中已经出现所需 GitHub secrets 和 variables。

## 预期结果

执行完成后，所有 bootstrap 阶段都已手动完成，仓库已可用于第一次 preview 和 deployment。

## 常见问题

- 在 AWS foundation 生成新值后忘记 `source dist/foundation.env`
- 只初始化了第一个 stack，没有初始化 `STACKS` 中后续环境
- 在仓库根目录之外执行手动 bootstrap 命令

## 下一步

继续阅读 [`07-first-deploy-and-managed-dsql.zh.md`](07-first-deploy-and-managed-dsql.zh.md)。
