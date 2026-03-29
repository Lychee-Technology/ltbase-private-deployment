# Prepare the Local .env File / 准备本地 .env 文件

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide to create the local `.env` file that drives the bootstrap scripts and repository configuration.

使用本文档创建本地 `.env` 文件，该文件将驱动 bootstrap 脚本和仓库配置。

## Before You Start / 开始前确认

- complete [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md)
- have the final GitHub repository name, AWS account IDs, role ARNs, and domain values ready

- 已完成 [`03-create-oidc-and-deploy-roles.md`](03-create-oidc-and-deploy-roles.md)
- 已准备好 GitHub 仓库名、AWS account ID、role ARN、域名等最终值

## Steps / 操作步骤

1. Copy `env.template` to `.env`.
2. Fill in the repository identity values:
   - `GITHUB_OWNER`
   - `DEPLOYMENT_REPO_NAME`
   - `DEPLOYMENT_REPO`
3. Fill in AWS environment values:
   - `AWS_REGION_DEVO`
   - `AWS_REGION_PROD`
   - `AWS_ACCOUNT_ID_DEVO`
   - `AWS_ACCOUNT_ID_PROD`
   - `AWS_ROLE_NAME_DEVO`
   - `AWS_ROLE_NAME_PROD`
   - `AWS_ROLE_ARN_DEVO`
   - `AWS_ROLE_ARN_PROD`
4. Fill in Pulumi backend values:
   - `PULUMI_STATE_BUCKET`
   - `PULUMI_KMS_ALIAS`
   - leave `PULUMI_BACKEND_URL`, `PULUMI_SECRETS_PROVIDER_DEVO`, and `PULUMI_SECRETS_PROVIDER_PROD` empty if you plan to let bootstrap generate them
5. Fill in release values:
   - `LTBASE_RELEASES_REPO`
   - `LTBASE_RELEASE_ID`
6. Fill in runtime and domain values:
   - `API_DOMAIN`
   - `CONTROL_DOMAIN`
   - `AUTH_DOMAIN`
   - `CLOUDFLARE_ZONE_ID`
   - `OIDC_ISSUER_URL`
   - `JWKS_URL`
   - `RUNTIME_BUCKET`
   - `TABLE_NAME`
   - `GITHUB_ORG`
   - `GITHUB_REPO`
   - `GEMINI_MODEL`
   - `DSQL_PORT`
   - `DSQL_DB`
   - `DSQL_USER`
   - `DSQL_PROJECT_SCHEMA`
7. Fill in secret values:
   - `GEMINI_API_KEY`
   - `CLOUDFLARE_API_TOKEN`
   - `LTBASE_RELEASES_TOKEN`
8. Save the file locally and confirm it is not committed.

1. 将 `env.template` 复制为 `.env`。
2. 填写仓库标识信息：
   - `GITHUB_OWNER`
   - `DEPLOYMENT_REPO_NAME`
   - `DEPLOYMENT_REPO`
3. 填写 AWS 环境信息：
   - `AWS_REGION_DEVO`
   - `AWS_REGION_PROD`
   - `AWS_ACCOUNT_ID_DEVO`
   - `AWS_ACCOUNT_ID_PROD`
   - `AWS_ROLE_NAME_DEVO`
   - `AWS_ROLE_NAME_PROD`
   - `AWS_ROLE_ARN_DEVO`
   - `AWS_ROLE_ARN_PROD`
4. 填写 Pulumi backend 信息：
   - `PULUMI_STATE_BUCKET`
   - `PULUMI_KMS_ALIAS`
   - 如果你希望由 bootstrap 自动生成 `PULUMI_BACKEND_URL`、`PULUMI_SECRETS_PROVIDER_DEVO`、`PULUMI_SECRETS_PROVIDER_PROD`，可先留空
5. 填写 release 信息：
   - `LTBASE_RELEASES_REPO`
   - `LTBASE_RELEASE_ID`
6. 填写运行时与域名信息：
   - `API_DOMAIN`
   - `CONTROL_DOMAIN`
   - `AUTH_DOMAIN`
   - `CLOUDFLARE_ZONE_ID`
   - `OIDC_ISSUER_URL`
   - `JWKS_URL`
   - `RUNTIME_BUCKET`
   - `TABLE_NAME`
   - `GITHUB_ORG`
   - `GITHUB_REPO`
   - `GEMINI_MODEL`
   - `DSQL_PORT`
   - `DSQL_DB`
   - `DSQL_USER`
   - `DSQL_PROJECT_SCHEMA`
7. 填写 secrets：
   - `GEMINI_API_KEY`
   - `CLOUDFLARE_API_TOKEN`
   - `LTBASE_RELEASES_TOKEN`
8. 将文件保存在本地，并确认不会提交进仓库。

## Important Rules / 重要规则

- do not commit `.env`
- do not put production secrets into tracked files
- treat `PULUMI_BACKEND_URL` and `PULUMI_SECRETS_PROVIDER_*` as generated values if you rely on bootstrap to create backend resources
- only fill values you actually control; generated values should come from bootstrap outputs

- 不要提交 `.env`
- 不要把生产 secrets 写进被版本控制的文件
- 如果你依赖 bootstrap 创建 backend 资源，请把 `PULUMI_BACKEND_URL` 和 `PULUMI_SECRETS_PROVIDER_*` 当作生成值
- 只填写你真正控制的输入项，生成值应来自 bootstrap 输出

## Expected Result / 预期结果

You now have a complete local `.env` file that can be used by the bootstrap scripts.

你现在已经拥有一个完整的本地 `.env` 文件，可供 bootstrap 脚本使用。

## Common Mistakes / 常见问题

- mixing placeholder values with real values
- setting the wrong repository name in `DEPLOYMENT_REPO`
- forgetting to update the AWS account IDs to match the target roles
- committing `.env` by accident

- 将占位符和真实值混在一起使用
- `DEPLOYMENT_REPO` 写成了错误的仓库名
- 忘记让 AWS account ID 与目标角色匹配
- 误把 `.env` 提交到仓库

## Next Step / 下一步

Choose one bootstrap path:

选择一个 bootstrap 路径：

- one-click: [`05-bootstrap-one-click.md`](05-bootstrap-one-click.md)
- manual: [`06-bootstrap-manual.md`](06-bootstrap-manual.md)
