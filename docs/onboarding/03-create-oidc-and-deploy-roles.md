# Create GitHub OIDC and Deploy Roles / 创建 GitHub OIDC 与 Deploy Roles

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide to prepare the AWS-side trust and deployment roles that GitHub Actions needs in order to preview and deploy LTBase.

使用本文档准备 AWS 侧的信任关系与部署角色，让 GitHub Actions 可以执行 LTBase 的 preview 和 deploy。

## Before You Start / 开始前确认

- complete [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md)
- know the AWS account ID for every stack in `STACKS`
- know your deployment repository full name, for example `customer-org/customer-ltbase`

- 已完成 [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md)
- 已知道 `STACKS` 中每个环境对应的 AWS account ID
- 已知道你的部署仓库全名，例如 `customer-org/customer-ltbase`

## Steps / 操作步骤

1. In each AWS account used for deployment, confirm whether the GitHub OIDC provider already exists.
2. If it does not exist, create the provider for `https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`.
3. Create one deploy role for each stack in `STACKS`.
4. Attach a trust policy that allows GitHub Actions from your deployment repository to assume each role.
5. Attach a permissions policy broad enough for first bootstrap and first deployment.
6. Make a note of every resulting role ARN.
7. If your stacks span multiple AWS accounts, confirm you can operate each account from your workstation, usually through separate AWS profiles.

1. 在每个用于部署的 AWS 账户中，确认 GitHub OIDC provider 是否已经存在。
2. 如果不存在，使用 `https://token.actions.githubusercontent.com` 和 audience `sts.amazonaws.com` 创建它。
3. 为 `STACKS` 中的每个环境各创建一个 deploy role。
4. 为两个角色分别附加 trust policy，允许你的部署仓库中的 GitHub Actions assume 该角色。
5. 为角色附加足以完成首次 bootstrap 与首次部署的 permissions policy。
6. 记录每个角色最终的 ARN。
7. 如果这些环境跨越多个 AWS 账户，确认你的工作站可以操作每个账户，通常通过不同 AWS profile 完成。

## Practical Tip / 实操建议

If you want the template to generate copy-paste policy files for review, do that after `.env` is ready by using `./scripts/render-bootstrap-policies.sh --env-file .env`.

如果你希望模板先生成可复制的策略文件供审阅，请在 `.env` 准备完成之后运行 `./scripts/render-bootstrap-policies.sh --env-file .env`。

## Expected Result / 预期结果

You now have a working OIDC trust chain and one deploy role per stack whose ARN can be placed into `.env`.

你现在已经具备可用的 OIDC 信任链，以及每个 stack 都可写入 `.env` 的 deploy role ARN。

## Common Mistakes / 常见问题

- creating only one role and trying to reuse it for multiple stacks
- forgetting to include the deployment repository name in the trust policy
- using permissions that are too narrow for the first deployment

- 只创建一个角色，然后尝试让多个 stack 共用
- 在 trust policy 中遗漏部署仓库名称
- 给首次部署分配了过窄的权限，导致 bootstrap 失败

## Next Step / 下一步

Continue with [`04-prepare-env-file.md`](04-prepare-env-file.md).

继续阅读 [`04-prepare-env-file.md`](04-prepare-env-file.md)。
