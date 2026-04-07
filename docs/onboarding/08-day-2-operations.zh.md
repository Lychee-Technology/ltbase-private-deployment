# 日常运维操作

> **[English](08-day-2-operations.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档处理首次成功部署之后的日常操作。

## 常见操作

### 升级到新的 LTBase release

1. 如果你想先同步较新的模板工作流或脚本，请在部署仓库干净的本地 `main` 分支上运行 `./scripts/sync-template-upstream.sh`。
2. 处理可能出现的 merge conflict，并审查同步进来的模板变更。
3. 更新 GitHub variables 中的 `LTBASE_RELEASE_ID`，或在工作流中直接传入新的 `release_id`。
4. 运行 preview 工作流。
5. 审查 Pulumi preview 输出。
6. 针对新 release 触发一次 `rollout.yml`。
7. 在审批下一个受保护目标环境前，验证当前已部署 stack。
8. 按顺序审批每一跳，直到 promotion path 完成。

### 在变更前重新执行 preview

当你修改 stack 配置、release 选择或部署相关值时，都应先重新执行 preview。

### 维护本地 bootstrap 输入

保持 `.env` 私密、最新，并确保它不受版本控制。

## 运维提醒

- 不要在部署仓库中自行重建 LTBase 应用二进制
- 不要提交 `.env`
- 不要绕过生产审批 gate
- 保持 `LTBASE_RELEASES_TOKEN` 仅具备下载 release 的最小权限
- 只在干净的本地 `main` 分支上运行 `scripts/sync-template-upstream.sh`

## 预期结果

在 onboarding 完成之后，你可以安全地重复执行 preview 与按 promotion path 推进的 rollout。

## 常见问题

- 在未验证前一跳之前就审批后续 stack
- 修改部署输入后没有先执行 preview
- 把部署仓库当成应用源码仓库来使用

## 返回主文档

返回 [`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)。
