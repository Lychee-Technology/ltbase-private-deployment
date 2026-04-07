# 创建 GitHub OIDC 与 Deploy Roles

> **[English](03-create-oidc-and-deploy-roles.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档准备 AWS 侧的信任关系与部署角色，让 GitHub Actions 可以执行 LTBase 的 preview 和 deploy。

## 一键 bootstrap 用户说明

如果你打算使用一键 bootstrap 路径（`evaluate-and-continue.sh`），该脚本会自动运行 `bootstrap-aws-foundation.sh`，创建 OIDC provider、deploy role、inline role policy、共享的 Pulumi state bucket 和 Pulumi KMS alias。

在这种情况下，本页面的作用是让你 **提前了解和确认** 将会创建哪些资源，而不是手动创建它们。

在你选择一键 bootstrap 前，请先确认你的 AWS 凭据可以创建或更新以下资源：

- `STACKS` 涉及的每个 AWS 账户中的 GitHub OIDC provider
- `STACKS` 中每个 stack 对应的 deploy role
- 这些角色上的 trust policy 和 inline role policy
- 位于 `PROMOTION_PATH` 第一个 stack 对应 AWS 账户中的共享 Pulumi state bucket
- 每个部署 region 中用于 Pulumi 的 KMS alias

如果你的 AWS 权限不允许脚本创建或更新这些资源，请改走下面的手动步骤。

## 开始前确认

- 已完成 [`02-create-repo-and-clone.zh.md`](02-create-repo-and-clone.zh.md)
- 已知道 `STACKS` 中每个环境对应的 AWS account ID
- 已知道你的部署仓库全名，例如 `customer-org/customer-ltbase`

## 操作步骤

1. 在每个用于部署的 AWS 账户中，确认 GitHub OIDC provider 是否已经存在。
2. 如果不存在，使用 `https://token.actions.githubusercontent.com` 和 audience `sts.amazonaws.com` 创建它。
3. 为 `STACKS` 中的每个环境各创建一个 deploy role。
4. 为每个角色附加 trust policy，允许你的部署仓库中的 GitHub Actions assume 该角色。
5. 为每个角色附加足以完成首次 bootstrap 与首次部署的 permissions policy。
6. 记录每个角色最终的 ARN。
7. 如果这些环境跨越多个 AWS 账户，确认你的工作站可以操作每个账户，通常通过不同 AWS profile 完成。

共享的 Pulumi backend 固定锚定在 `PROMOTION_PATH` 的第一个 stack 上。在多账户场景下，这意味着第一个 stack 对应的 AWS 账户拥有共享 backend bucket，而每个 stack 仍然有自己独立的 deploy role 和 secrets provider 配置。

## 实操建议

如果你希望模板先生成可复制的策略文件供审阅，请在 `.env` 准备完成之后运行 `./scripts/render-bootstrap-policies.sh --env-file .env`。

这个命令现在也会额外生成两类 AWS bootstrap 操作者策略模板：

- 每个 stack 账户各一份 `dist/bootstrap-operator-<stack>-policy.json`
- `PROMOTION_PATH` 第一个 stack 账户专用的 `dist/bootstrap-operator-first-stack-s3-policy.json`

当云管理员需要一个可直接起步的 one-click bootstrap 最小权限模板时，就使用这些文件。

对于一键 bootstrap 用户，这也是在允许脚本创建 IAM 资源前最适合先做的一步预审。

## 预期结果

你现在已经具备可用的 OIDC 信任链，以及每个 stack 都可写入 `.env` 的 deploy role ARN。

## 常见问题

- 只创建一个角色，然后尝试让多个 stack 共用
- 在 trust policy 中遗漏部署仓库名称
- 给首次部署分配了过窄的权限，导致 bootstrap 失败

## 下一步

继续阅读 [`04-prepare-env-file.zh.md`](04-prepare-env-file.zh.md)。
