# Day-2 Operations / 日常运维操作

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide for normal follow-up operations after the first successful deployment.

使用本文档处理首次成功部署之后的日常操作。

## Typical Operations / 常见操作

### Upgrade to a new LTBase release / 升级到新的 LTBase release

1. Update `LTBASE_RELEASE_ID` in GitHub variables, or pass a new `release_id` directly to the workflow.
2. Run the preview workflow.
3. Review the Pulumi preview output.
4. Trigger `rollout.yml` once for the new release.
5. Validate each deployed stack before approving the next protected target environment.
6. Approve each protected hop in order until the promotion path completes.

1. 更新 GitHub variables 中的 `LTBASE_RELEASE_ID`，或在工作流中直接传入新的 `release_id`。
2. 运行 preview 工作流。
3. 审查 Pulumi preview 输出。
4. 针对新 release 触发一次 `rollout.yml`。
5. 在审批下一个受保护目标环境前，验证当前已部署 stack。
6. 按顺序审批每一跳，直到 promotion path 完成。

### Re-run preview before changes / 在变更前重新执行 preview

Use preview whenever you change stack configuration, release selection, or deployment-related values.

当你修改 stack 配置、release 选择或部署相关值时，都应先重新执行 preview。

### Maintain local bootstrap inputs / 维护本地 bootstrap 输入

Keep `.env` private, current, and outside version control.

保持 `.env` 私密、最新，并确保它不受版本控制。

## Operational Reminders / 运维提醒

- do not rebuild LTBase application binaries in the deployment repository
- do not commit `.env`
- do not bypass the production approval gate
- keep `LTBASE_RELEASES_TOKEN` scoped to release download access only

- 不要在部署仓库中自行重建 LTBase 应用二进制
- 不要提交 `.env`
- 不要绕过生产审批 gate
- 保持 `LTBASE_RELEASES_TOKEN` 仅具备下载 release 的最小权限

## Expected Result / 预期结果

You can safely repeat previews and promotion-path rollouts after onboarding is complete.

在 onboarding 完成之后，你可以安全地重复执行 preview 与按 promotion path 推进的 rollout。

## Common Mistakes / 常见问题

- approving a later stack before validating the previous hop
- changing deployment inputs without running preview first
- treating the deployment repository as an application source repository

- 在未验证前一跳之前就审批后续 stack
- 修改部署输入后没有先执行 preview
- 把部署仓库当成应用源码仓库来使用

## Back to Onboarding / 返回主文档

Return to [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md).

返回 [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)。
