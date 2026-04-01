# 准备本地 .env 文件

> **[English](04-prepare-env-file.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档创建本地 `.env` 文件，该文件将驱动 bootstrap 脚本和仓库配置。

## 开始前确认

- 已完成 [`03-create-oidc-and-deploy-roles.zh.md`](03-create-oidc-and-deploy-roles.zh.md)
- 已准备好 GitHub 仓库名、AWS account ID、role ARN、域名等最终值

## 操作步骤

1. 将 `env.template` 复制为 `.env`。
2. 填写 stack 拓扑：
   - `STACKS` — 逗号分隔的环境名列表，例如 `devo,prod`
   - `PROMOTION_PATH` — promotion 顺序，例如 `devo,prod`
3. 填写模板与仓库标识：
   - `TEMPLATE_REPO`
   - `GITHUB_OWNER`
   - `DEPLOYMENT_REPO_NAME`
   - `DEPLOYMENT_REPO_VISIBILITY`
   - `DEPLOYMENT_REPO_DESCRIPTION`
4. 填写 OIDC discovery 信息：
   - `OIDC_DISCOVERY_DOMAIN`
   - `CLOUDFLARE_ACCOUNT_ID`
5. 填写 AWS 环境信息（每个 stack 一组）：
   - `AWS_REGION_DEVO`、`AWS_REGION_PROD`
   - `AWS_ACCOUNT_ID_DEVO`、`AWS_ACCOUNT_ID_PROD`
   - `AWS_ROLE_NAME_DEVO`、`AWS_ROLE_NAME_PROD`
6. 填写 Pulumi backend 信息：
   - `PULUMI_STATE_BUCKET`
   - `PULUMI_KMS_ALIAS`
   - `PULUMI_PROJECT`
   - 如果你希望由 bootstrap 自动生成 `PULUMI_BACKEND_URL`、`PULUMI_SECRETS_PROVIDER_DEVO`、`PULUMI_SECRETS_PROVIDER_PROD`，可先留空
7. 填写 release 信息：
   - `LTBASE_RELEASES_REPO`
   - `LTBASE_RELEASE_ID`
8. 填写按 stack 划分的域名信息：
   - `API_DOMAIN_DEVO`、`API_DOMAIN_PROD`
   - `CONTROL_DOMAIN_DEVO`、`CONTROL_DOMAIN_PROD`
   - `AUTH_DOMAIN_DEVO`、`AUTH_DOMAIN_PROD`
   - `CLOUDFLARE_ZONE_ID`
9. 填写应用默认值：
   - `GEMINI_MODEL`
   - `DSQL_PORT`、`DSQL_DB`、`DSQL_USER`、`DSQL_PROJECT_SCHEMA`
10. 填写 secrets：
    - `GEMINI_API_KEY`
    - `CLOUDFLARE_API_TOKEN`
    - `LTBASE_RELEASES_TOKEN`
11. 将文件保存在本地，并确认不会提交进仓库。

## 重要规则

- 不要提交 `.env`
- 不要把生产 secrets 写进被版本控制的文件
- 如果你依赖 bootstrap 创建 backend 资源，请把 `PULUMI_BACKEND_URL` 和 `PULUMI_SECRETS_PROVIDER_*` 当作生成值
- 只填写你真正控制的输入项，生成值应来自 bootstrap 输出
- 以下变量由 `scripts/lib/bootstrap-env.sh` 自动派生，通常不需要手动填写：`DEPLOYMENT_REPO`、`AWS_PROFILE_*`、`PULUMI_BACKEND_URL`、`PULUMI_SECRETS_PROVIDER_*`、`OIDC_ISSUER_URL_*`、`JWKS_URL_*`、`RUNTIME_BUCKET_*`、`TABLE_NAME_*`、`GITHUB_ORG`、`GITHUB_REPO`、`OIDC_DISCOVERY_TEMPLATE_REPO`、`OIDC_DISCOVERY_REPO_NAME`、`OIDC_DISCOVERY_REPO`、`OIDC_DISCOVERY_PAGES_PROJECT`、`OIDC_DISCOVERY_AWS_ROLE_NAME_*`

## 预期结果

你现在已经拥有一个完整的本地 `.env` 文件，可供 bootstrap 脚本使用。

## 常见问题

- 将占位符和真实值混在一起使用
- `DEPLOYMENT_REPO` 写成了错误的仓库名
- 忘记让 AWS account ID 与目标角色匹配
- 误把 `.env` 提交到仓库

## 下一步

选择一个 bootstrap 路径：

- 一键部署：[`05-bootstrap-one-click.zh.md`](05-bootstrap-one-click.zh.md)
- 手动部署：[`06-bootstrap-manual.zh.md`](06-bootstrap-manual.zh.md)
