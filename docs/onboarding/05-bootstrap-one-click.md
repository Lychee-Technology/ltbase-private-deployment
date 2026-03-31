# One-Click Bootstrap / 一键 Bootstrap

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide when you want the repository creation, policy rendering, AWS foundation setup, stack bootstrap, and optional rollout trigger to run from one recovery-aware command.

如果你希望通过一个可恢复命令完成仓库创建、策略生成、AWS 基础设施初始化、stack bootstrap，以及可选的 rollout 触发，请使用本文档。

## Before You Start / 开始前确认

- complete [`04-prepare-env-file.md`](04-prepare-env-file.md)
- have enough GitHub and AWS permissions to create and update all required resources

- 已完成 [`04-prepare-env-file.md`](04-prepare-env-file.md)
- 拥有足够的 GitHub 和 AWS 权限来创建和更新所需资源

## Steps / 操作步骤

1. Open a terminal in the root of your deployment repository.
2. Confirm `.env` exists and contains the values you prepared.
3. If you are using split AWS accounts, export the correct AWS credentials or profiles before running bootstrap.
4. Run:

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

If you also want bootstrap to trigger the first rollout automatically, include the release tag:

如果你还希望在 bootstrap 完成后自动触发第一次 rollout，请同时提供 release tag：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra --release-id v1.0.0
```

5. Wait for the script to complete.
6. Review any generated files in `dist/`.
7. Confirm GitHub variables and secrets were created in the deployment repository.
8. Confirm every stack in `STACKS` was initialized.

1. 在部署仓库根目录打开终端。
2. 确认 `.env` 已存在且已填好需要的值。
3. 如果你使用分离的 AWS 账户，请在执行 bootstrap 前导出正确的 AWS 凭据或 profile。
4. 执行：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

5. 等待脚本执行完成。
6. 检查 `dist/` 中生成的文件。
7. 确认部署仓库中的 GitHub variables 和 secrets 已创建。
8. 确认 `STACKS` 中的每个 Pulumi stack 都已初始化。

## What This Command Does / 这个命令会做什么

The one-click script runs these stages in order:

一键脚本会按顺序执行这些阶段：

- `create-deployment-repo.sh`
- `render-bootstrap-policies.sh`
- `bootstrap-aws-foundation.sh`
- `bootstrap-oidc-discovery-companion.sh`
- `bootstrap-deployment-repo.sh --stack <each stack in STACKS>`
- optional `gh workflow run rollout.yml ...` when `--release-id` is set

## Expected Result / 预期结果

You finish with repository configuration written to GitHub, Pulumi stacks initialized for every configured environment, and optionally the first rollout already queued.

执行完成后，你应该获得已经写入 GitHub 的仓库配置、为所有已配置环境初始化好的 Pulumi stack，以及在需要时已经排队的第一次 rollout。

## Common Mistakes / 常见问题

- trying one-click bootstrap without enough GitHub permissions
- trying one-click bootstrap without enough AWS permissions
- forgetting to prepare split-account credentials before running the script

- 在 GitHub 权限不足时尝试一键 bootstrap
- 在 AWS 权限不足时尝试一键 bootstrap
- 在多账户场景下忘记先准备好对应凭据再执行脚本

## Next Step / 下一步

Continue with [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md).

继续阅读 [`07-first-deploy-and-managed-dsql.md`](07-first-deploy-and-managed-dsql.md)。
