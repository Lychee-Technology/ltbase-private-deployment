> **[English](05-bootstrap-one-click.md)**

# 一键 Bootstrap

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

如果你希望通过一个可恢复命令完成仓库创建、策略生成、AWS 基础设施初始化、stack bootstrap，以及可选的 rollout 触发，请使用本文档。

## 开始前确认

- 已完成 [`04-prepare-env-file.zh.md`](04-prepare-env-file.zh.md)
- 拥有足够的 GitHub 和 AWS 权限来创建和更新所需资源

## 操作步骤

1. 在部署仓库根目录打开终端。
2. 确认 `.env` 已存在且已填好需要的值。
3. 如果你使用分离的 AWS 账户，请在执行 bootstrap 前导出正确的 AWS 凭据或 profile。
4. 执行：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

如果你还希望在 bootstrap 完成后自动触发第一次 rollout，请同时提供 release tag：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra --release-id v1.0.0
```

5. 等待脚本执行完成。
6. 检查 `dist/` 中生成的文件。
7. 确认部署仓库中的 GitHub variables 和 secrets 已创建。
8. 确认 `STACKS` 中的每个 Pulumi stack 都已初始化。

## 这个命令会做什么

一键脚本会按顺序执行这些阶段：

- `create-deployment-repo.sh`
- `render-bootstrap-policies.sh`
- `bootstrap-aws-foundation.sh`
- `bootstrap-oidc-discovery-companion.sh`
- `bootstrap-deployment-repo.sh --stack <each stack in STACKS>`
- optional `gh workflow run rollout.yml ...` when `--release-id` is set

## 预期结果

执行完成后，你应该获得已经写入 GitHub 的仓库配置、为所有已配置环境初始化好的 Pulumi stack，以及在需要时已经排队的第一次 rollout。

## 常见问题

- 在 GitHub 权限不足时尝试一键 bootstrap
- 在 AWS 权限不足时尝试一键 bootstrap
- 在多账户场景下忘记先准备好对应凭据再执行脚本

## 下一步

继续阅读 [`07-first-deploy-and-managed-dsql.zh.md`](07-first-deploy-and-managed-dsql.zh.md)。
