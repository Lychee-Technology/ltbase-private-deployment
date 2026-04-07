> **[English](05-bootstrap-one-click.md)**

# 一键 Bootstrap

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

如果你希望通过一个可恢复命令完成仓库创建、策略生成、AWS 基础设施初始化、stack bootstrap，以及可选的 rollout 触发，请使用本文档。

## 开始前确认

- 已完成 [`04-prepare-env-file.zh.md`](04-prepare-env-file.zh.md)
- 如果可能，请在真实部署仓库的本地 clone 中执行这套流程
- 拥有足够的 GitHub 和 AWS 权限来创建和更新所需资源

在使用一键路径前，请先阅读 [`01-prerequisites.zh.md`](01-prerequisites.zh.md) 中的 bootstrap 最小权限矩阵。

如果你不具备这些最小 GitHub、AWS 或 Cloudflare 权限，请改用 [`06-bootstrap-manual.zh.md`](06-bootstrap-manual.zh.md) 的手动路径，并让外部管理员先创建缺失资源。

## 推荐工作方式

一键流程具备恢复能力，但推荐的客户 onboarding 顺序仍然是：

1. 先创建真实部署仓库
2. 将该仓库 clone 到本地
3. 在这个 checkout 中准备 `.env`
4. 在这个 checkout 根目录中执行一键 bootstrap

这样做很重要，因为 bootstrap 阶段还会写入本地 `infra/Pulumi.<stack>.yaml` 文件。

如果你有意让自动化在恢复过程中创建缺失的远端仓库，那么请在审查或提交生成出来的本地 Pulumi stack 文件前，先把新仓库 clone 下来。

## 就绪检查清单

在你运行 `--force` 之前，请确认以下事项：

1. GitHub CLI 已完成认证。

```bash
gh auth status
```

2. 当前 GitHub 认证账号能够：
   - 在 `GITHUB_OWNER` 下创建私有仓库
   - 写入 repository secrets 和 variables
   - 创建后续 promotion 审批所需的 GitHub environments
3. `.env` 中已经填入最终确认的客户可控输入值，包括：
   - 仓库标识
   - stack / account / region 映射
   - 域名
   - Cloudflare IDs 和 token
   - release ID 与 releases token
   - Gemini API key
4. 如果不同 stack 使用不同 AWS 账户，`AWS_PROFILE_<STACK>` 已经配置并测试通过。

```bash
AWS_PROFILE_STAGING=customer-staging aws sts get-caller-identity
```

5. 除非你明确需要 override，否则你刻意把派生值保持为空。
6. 对于 managed 部署，你没有手动设置 `DSQL_ENDPOINT`。
7. `PROMOTION_PATH` 第一个 stack 对应的凭据能够创建和管理共享的 Pulumi backend bucket，因为 bootstrap 会把这个 bucket 固定放在第一个 stack 账户里。

## 推荐 Preflight

### 1. 可选先渲染 IAM 策略产物进行审阅

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
```

如果你希望在脚本创建或更新 IAM 资源之前，先查看 trust policy 和 inline role policy，就先做这一步。

### 2. 不带 `--force` 先跑一次恢复感知扫描

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

你应该这样理解输出结果：

- 第一次运行时出现 `needs_foundation`、`needs_repo_config`、`needs_stack_bootstrap` 或 `needs_oidc_companion` 是正常的
- 如果出现缺少必填变量这类硬性校验错误，则不正常，应先修复
- GitHub、AWS、Cloudflare 或 Pulumi 的认证错误都属于阻塞问题，应先修复
- 该命令还会把机器可读报告写入 `dist/evaluate-and-continue/report.json`

## 操作步骤

1. 在部署仓库根目录打开终端。
2. 确认 `.env` 已存在且已填好需要的值。
3. 如果你还没有执行上面的 preflight 扫描，请先执行。
4. 如果你使用分离的 AWS 账户，请在执行 bootstrap 前导出正确的 AWS 凭据，或确认 `AWS_PROFILE_<STACK>` 已存在。
5. 执行：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

如果你还希望在 bootstrap 完成后自动触发第一次 rollout，请同时提供 release tag：

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra --release-id v1.0.0
```

6. 等待脚本执行完成。
7. 检查 `dist/` 中生成的文件，重点包括恢复报告和渲染出来的策略产物。
8. 确认部署仓库中的 GitHub variables 和 secrets 已创建。
9. 确认 `STACKS` 中的每个 Pulumi stack 都已初始化。

## 这个命令会做什么

一键脚本会按顺序执行这些阶段：

- `create-deployment-repo.sh`
- `render-bootstrap-policies.sh`
- `bootstrap-aws-foundation.sh`
- `bootstrap-oidc-discovery-companion.sh`
- `bootstrap-deployment-repo.sh --stack <STACKS 中的每个 stack>`
- 当设置了 `--release-id` 时，可选执行 `gh workflow run rollout.yml ...`

`bootstrap-aws-foundation.sh` 会先在 `PROMOTION_PATH` 第一个 stack 对应的 AWS 账户中创建一次共享 Pulumi backend bucket，然后为 `STACKS` 中每个 stack 准备各自的 role 和 secrets provider 输入。

## 预期结果

执行完成后，你应该获得已经写入 GitHub 的仓库配置、为所有已配置环境初始化好的 Pulumi stack，以及在需要时已经排队的第一次 rollout。

## 常见问题

- 在 GitHub 权限不足时尝试一键 bootstrap
- 在 AWS 权限不足时尝试一键 bootstrap
- 在多账户场景下忘记先准备好对应凭据再执行脚本
- 跳过 preflight 扫描，直到 `--force` 已经开始变更资源后才发现缺少凭据
- 在错误的 checkout 中执行命令，最后找不到生成出来的 Pulumi stack 文件

## 下一步

继续阅读 [`07-first-deploy-and-managed-dsql.zh.md`](07-first-deploy-and-managed-dsql.zh.md)。
