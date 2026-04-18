# 日常运维操作

> **[English](08-day-2-operations.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档处理首次成功部署之后的日常操作。

## 常见操作

### 审计 Cloudflare mTLS 连通性

当你需要只读方式审计 Cloudflare 到 API Gateway 的 mTLS 链路时，请在 deployment repository 中运行 `./scripts/check-cloudflare-mtls.sh --env-file .env --stack <stack>`。

preview workflow 与 rollout hop workflow 会在成功完成后自动运行这项审计；如果 Cloudflare 或 API Gateway 的 mTLS 配置发生漂移，工作流会直接失败。

本地执行时，请保持 `.env` 与 `infra/Pulumi.<stack>.yaml` 一致。workflow 中的审计会从 `infra/Pulumi.<stack>.yaml` 读取 `ltbase-infra:awsRegion`、`ltbase-infra:apiDomain`、`ltbase-infra:controlPlaneDomain`、`ltbase-infra:authDomain`、`ltbase-infra:runtimeBucket` 和 `ltbase-infra:cloudflareZoneId`，而你手动执行脚本时，脚本仍然要求你传入的 env 文件中包含这些值。

脚本会检查：

- `api`、`auth`、`control-plane` 三个域名是否都通过 Cloudflare 代理
- Cloudflare SSL 模式是否为 `Full (strict)`
- Cloudflare Authenticated Origin Pulls 是否已启用
- 该 stack 的 runtime bucket 中是否存在 truststore 对象
- 每个 API Gateway 自定义域名是否报告了预期的 mutual TLS truststore URI 与版本

### 升级到新的 LTBase release

1. 如果你想先拿到模板中的最新同步工具本身，请在部署仓库干净的本地 `main` 分支上运行 `./scripts/update-sync-template-tooling.sh`。
2. 如果你还想同步较新的模板管理文件，再在同一个干净的本地 `main` 分支上运行 `./scripts/sync-template-upstream.sh`。
3. 审查同步进来的模板变更。模板同步会保留本地 `.env`、`infra/Pulumi.*.yaml`、整个 `customer-owned/` 目录树、由 deployment repo 自行维护的 `infra/auth-providers.*.json`，以及同步工具自己的脚本与测试文件。
4. 如果生成出来的 deployment repo 某个 stack 还没有真实的 auth provider 配置文件，请先把对应的 `infra/auth-providers.<stack>.json.example` 复制成 `infra/auth-providers.<stack>.json`，再进行下一次 bootstrap 或 preview。
5. 更新 GitHub variables 中的 `LTBASE_RELEASE_ID`，或在工作流中直接传入新的 `release_id`。
6. 运行 preview 工作流。
7. 审查 Pulumi preview 输出。
8. 针对新 release 触发一次 `rollout.yml`。
9. 在审批下一个受保护目标环境前，验证当前已部署 stack。
10. 按顺序审批每一跳，直到 promotion path 完成。

### 在变更前重新执行 preview

当你修改 stack 配置、release 选择或部署相关值时，都应先重新执行 preview。

### 维护本地 bootstrap 输入

保持 `.env` 私密、最新，并确保它不受版本控制。

## 运维提醒

- 不要在部署仓库中自行重建 LTBase 应用二进制
- 不要提交 `.env`
- 不要绕过生产审批 gate
- 保持 `LTBASE_RELEASES_TOKEN` 仅具备下载 release 的最小权限
- 只在干净的本地 `main` 分支上运行 `scripts/update-sync-template-tooling.sh`
- 只在干净的本地 `main` 分支上运行 `scripts/sync-template-upstream.sh`

## 预期结果

在 onboarding 完成之后，你可以安全地重复执行 preview 与按 promotion path 推进的 rollout。

## 常见问题

- 在未验证前一跳之前就审批后续 stack
- 修改部署输入后没有先执行 preview
- 把部署仓库当成应用源码仓库来使用

## 返回主文档

返回 [`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)。
