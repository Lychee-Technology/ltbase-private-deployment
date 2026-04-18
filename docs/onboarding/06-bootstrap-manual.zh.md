# 手动 Bootstrap

> **[English](06-bootstrap-manual.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

如果你希望逐步检查每个 bootstrap 阶段，而不是使用一键流程，请使用本文档。

## 开始前确认

- 已完成 [`04-prepare-env-file.zh.md`](04-prepare-env-file.zh.md)
- 已决定手动控制每一个 bootstrap 阶段

## 何时选择手动路径

以下场景更适合手动 bootstrap：

- 你希望逐段审阅脚本将创建的 GitHub、AWS、Cloudflare 资源
- 你没有权限让一键流程自动创建全部资源，但可以分阶段完成
- 你想把仓库创建、AWS foundation、stack 初始化和 OIDC discovery 配套资源拆开执行

手动路径的关键点是：每一阶段做完后先检查结果，再进入下一阶段。

## 操作步骤

### 1. 创建真实部署仓库

执行前确认：

- `gh auth status` 已通过
- `.env` 中的 `GITHUB_OWNER`、`DEPLOYMENT_REPO_NAME`、`DEPLOYMENT_REPO_VISIBILITY`、`DEPLOYMENT_REPO_DESCRIPTION` 已最终确认

执行：

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

执行后检查：

- 远端部署仓库已经存在
- `PROMOTION_PATH` 中第一个之后的 environment 已在 GitHub 中创建出来，供后续审批使用
- 如果仓库是刚创建的，请确认你本地使用的就是这个真实部署仓库 checkout

### 2. 初始化 AWS 基础资源

执行前确认：

- AWS 凭据或 `AWS_PROFILE_<STACK>` 已准备好
- `AWS_ACCOUNT_ID_<STACK>`、`AWS_REGION_<STACK>`、`AWS_ROLE_NAME_<STACK>` 已与 `.env` 保持一致
- `PULUMI_STATE_BUCKET` 和 `PULUMI_KMS_ALIAS` 的命名已经最终确认

执行：

```bash
./scripts/bootstrap-aws-foundation.sh --env-file .env
```

该步骤会创建或更新：

- GitHub OIDC provider
- deploy roles
- trust policies
- inline role policies
- 位于 `PROMOTION_PATH` 第一个 stack 对应 AWS 账户中的共享 Pulumi state bucket
- Pulumi KMS alias

它还会生成 `dist/foundation.env` 和审阅用文件。

执行后检查：

- `dist/foundation.env` 已生成
- `dist/` 中存在可审阅的 trust policy 和 role policy 文件
- 第一个 stack 对应的 AWS 账户中已经出现共享 Pulumi backend bucket
- 各目标 AWS 账户中已经出现预期的 OIDC provider、deploy role 和 KMS alias

### 3. 可选：合并自动生成的 foundation 值

如果 bootstrap 生成了新的 Pulumi backend 值，请将它们合并回 shell 或 `.env`：

```bash
source dist/foundation.env
```

何时需要这一步：

- 你刚刚让脚本创建了新的 backend 相关值
- 你接下来准备继续执行 `bootstrap-deployment-repo.sh` 或 Pulumi 相关命令

注意：

- `source dist/foundation.env` 只会更新当前 shell 会话
- 如果你希望这些值在后续会话里也生效，需要把确认后的值写回你本地 `.env`

### 4. 仅在需要时单独初始化 Pulumi backend

如果你希望单独执行 backend/KMS 流程，可运行：

```bash
./scripts/bootstrap-pulumi-backend.sh --env-file .env
```

这个阶段通常只在你明确想把 backend/KMS 流程与其他 foundation 步骤拆开时才需要。

### 5. 初始化所有已配置 stack

执行前确认：

- `PULUMI_BACKEND_URL` 和 `PULUMI_SECRETS_PROVIDER_<STACK>` 已可用
- GitHub 部署仓库已经存在
- 你知道 `STACKS` 和 `PROMOTION_PATH` 的实际顺序

执行：

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack <stack> --infra-dir infra
```

对 `STACKS` 中列出的每个 stack 都执行一次。最简单的做法是按 `PROMOTION_PATH` 的顺序执行。

推荐顺序示例：

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

每执行完一个 stack，请检查：

- 对应的 `infra/Pulumi.<stack>.yaml` 已生成，或你可以在 `infra/` 目录中成功选择该 Pulumi stack
- GitHub 仓库中对应 stack 的 `AWS_REGION_<STACK>`、`PULUMI_SECRETS_PROVIDER_<STACK>`、`AWS_ROLE_ARN_<STACK>` 已写入
- 通用变量和 secrets 例如 `PULUMI_BACKEND_URL`、`LTBASE_RELEASE_ID`、`LTBASE_RELEASES_TOKEN`、`CLOUDFLARE_API_TOKEN` 已写入

### 6. 初始化 OIDC discovery 配套资源

执行前确认：

- `.env` 中的 `OIDC_DISCOVERY_DOMAIN`、`CLOUDFLARE_ACCOUNT_ID`、`CLOUDFLARE_ZONE_ID`、`CLOUDFLARE_API_TOKEN` 已确认无误
- 你已经准备好让脚本创建或更新 Cloudflare Pages 项目、自定义域名绑定和 companion 仓库

执行：

```bash
./scripts/bootstrap-oidc-discovery-companion.sh --env-file .env
```

该步骤会创建或更新 OIDC discovery 配套仓库、Cloudflare Pages 项目、自定义域名绑定，以及每个 stack 对应的 OIDC discovery IAM role。

执行后检查：

- OIDC discovery companion 仓库已存在
- companion 仓库中已经配置 GitHub repository variables `OIDC_DISCOVERY_DOMAIN` 和 `OIDC_DISCOVERY_STACK_CONFIG`
- Cloudflare Pages 项目与自定义域名绑定已经创建
- 每个 stack 对应的 OIDC discovery IAM role 已存在

### 7. 确认仓库配置完成

请至少确认以下事项：

- 部署仓库中已经出现所需 GitHub secrets 和 variables
- `infra/` 中每个 stack 的 Pulumi 配置都已初始化
- 如果你使用了 companion 流程，OIDC discovery 相关仓库和 Cloudflare 资源已经准备好

如果你希望在进入首次部署前做一次汇总检查，可以运行：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

在手动路径下，这个检查适合用来确认是否还存在 `needs_repo_config`、`needs_stack_bootstrap` 或 `needs_oidc_companion` 之类的缺口。

## 预期结果

执行完成后，所有 bootstrap 阶段都已手动完成，仓库已可用于第一次 preview 和 deployment。

## 常见问题

- 在 AWS foundation 生成新值后忘记 `source dist/foundation.env`
- 只初始化了第一个 stack，没有初始化 `STACKS` 中后续环境
- 在仓库根目录之外执行手动 bootstrap 命令
- 做完 AWS foundation 后没有检查 `dist/` 里的策略产物与输出值就继续下一步
- companion 相关资源尚未准备好就直接进入首次部署

## 下一步

继续阅读 [`07-first-deploy-and-managed-dsql.zh.md`](07-first-deploy-and-managed-dsql.zh.md)。
