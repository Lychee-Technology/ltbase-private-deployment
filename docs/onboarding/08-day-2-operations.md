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
4. Deploy to `devo`.
5. Validate `devo`.
6. Promote the same release to `prod`.

1. 更新 GitHub variables 中的 `LTBASE_RELEASE_ID`，或在工作流中直接传入新的 `release_id`。
2. 运行 preview 工作流。
3. 审查 Pulumi preview 输出。
4. 部署到 `devo`。
5. 验证 `devo`。
6. 将同一个 release 推进到 `prod`。

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

You can safely repeat previews, deployments, and production promotions after onboarding is complete.

在 onboarding 完成之后，你可以安全地重复执行 preview、部署和生产发布。

## Common Mistakes / 常见问题

- promoting a release to prod that was not validated in devo
- changing deployment inputs without running preview first
- treating the deployment repository as an application source repository

- 将未经 devo 验证的 release 直接推到 prod
- 修改部署输入后没有先执行 preview
- 把部署仓库当成应用源码仓库来使用

## Back to Onboarding / 返回主文档

Return to [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md).

返回 [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)。
