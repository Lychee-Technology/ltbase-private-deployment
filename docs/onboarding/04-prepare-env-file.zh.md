# 准备本地 .env 文件

> **[English](04-prepare-env-file.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

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
   - 来源：你已经确认好的部署拓扑和 promotion 顺序
3. 填写模板与仓库标识：
   - `TEMPLATE_REPO`
   - `GITHUB_OWNER`
   - `DEPLOYMENT_REPO_NAME`
   - `DEPLOYMENT_REPO_VISIBILITY`
   - `DEPLOYMENT_REPO_DESCRIPTION`
   - 来源：你的目标 GitHub owner 和客户部署仓库命名决定
4. 填写 OIDC discovery 信息：
   - `OIDC_DISCOVERY_DOMAIN`
   - `CLOUDFLARE_ACCOUNT_ID`
   - 来源：你的 Cloudflare account，以及你计划给 OIDC discovery 使用的自定义域名
5. 填写 AWS 环境信息（每个 stack 一组）：
   - `AWS_REGION_<STACK>`
   - `AWS_ACCOUNT_ID_<STACK>`
   - `AWS_ROLE_NAME_<STACK>`
   - 如果不同 stack 使用不同 AWS 账户，本地还可以补充 `AWS_PROFILE_<STACK>`
   - 来源：每个 stack 对应的 AWS 账户规划
6. 填写 Pulumi backend 信息：
   - `PULUMI_STATE_BUCKET`
   - `PULUMI_KMS_ALIAS`
   - 如果你希望由 bootstrap 自动生成 `PULUMI_BACKEND_URL` 和每个 `PULUMI_SECRETS_PROVIDER_<STACK>`，可先留空
   - 来源：你希望 bootstrap 创建或使用的共享 Pulumi backend 资源命名
   - 重要：`PULUMI_STATE_BUCKET` 指向的共享 backend bucket 会创建在 `PROMOTION_PATH` 第一个 stack 对应的 AWS 账户中
7. 填写 release 信息：
    - `LTBASE_RELEASES_REPO`
    - `LTBASE_RELEASE_ID`
    - 来源：要部署的 LTBase release 仓库和 release ID
8. 保留必填的 mTLS 默认值：
   - `MTLS_TRUSTSTORE_FILE`
   - `MTLS_TRUSTSTORE_KEY`
   - 来源：此模板内置并已提交的 Cloudflare 全局 Authenticated Origin Pull truststore
   - 重要：它们是模板必需的默认值，不是可选功能开关。`api`、`auth`、`control-plane` 都会部署在 Cloudflare 代理和 API Gateway mutual TLS 之后。
9. 填写按 stack 划分的域名信息：
     - `API_DOMAIN_<STACK>`
     - `CONTROL_DOMAIN_<STACK>`
     - `AUTH_DOMAIN_<STACK>`
     - `PROJECT_ID`
     - `AUTH_PROVIDER_CONFIG_FILE_<STACK>`
     - `CLOUDFLARE_ZONE_ID`
     - 来源：你在目标 Cloudflare zone 中规划好的最终域名
     - bootstrap 会从 `.env` 里的 `CLOUDFLARE_ZONE_ID` 写入每个 `infra/Pulumi.<stack>.yaml` stack 配置；后续 preview 与 rollout 的 mTLS audit 会从该 stack 文件中读取 `ltbase-infra:awsRegion`、`ltbase-infra:apiDomain`、`ltbase-infra:controlPlaneDomain`、`ltbase-infra:authDomain`、`ltbase-infra:runtimeBucket` 和 `ltbase-infra:cloudflareZoneId`。
     - `AUTH_PROVIDER_CONFIG_FILE_<STACK>` 应该指向一个已提交的 JSON 文件，该文件列出该 stack 启用的外部 JWT provider。
     - 先把 `infra/auth-providers.<stack>.json.example` 复制成 `infra/auth-providers.<stack>.json`，再在生成出来的客户 deployment repo 中编辑这个真实文件。
10. 填写应用默认值：
    - `GEMINI_MODEL`
    - `DSQL_PORT`、`DSQL_DB`、`DSQL_USER`、`DSQL_PROJECT_SCHEMA`
    - 来源：LTBase 应用默认值，以及经过确认的客户特定 override
11. 填写 secrets：
    - `GEMINI_API_KEY`
    - `CLOUDFLARE_API_TOKEN`
    - `LTBASE_RELEASES_TOKEN`
12. 将文件保存在本地，并确认不会提交进仓库。

## 通常需要手动填写的值

以下值属于客户可控输入，通常应该在 `.env` 中显式填写：

- `STACKS`、`PROMOTION_PATH`
- `TEMPLATE_REPO`、`GITHUB_OWNER`、`DEPLOYMENT_REPO_NAME`、`DEPLOYMENT_REPO_VISIBILITY`、`DEPLOYMENT_REPO_DESCRIPTION`
- `OIDC_DISCOVERY_DOMAIN`、`CLOUDFLARE_ACCOUNT_ID`
- `AWS_REGION_<STACK>`、`AWS_ACCOUNT_ID_<STACK>`、`AWS_ROLE_NAME_<STACK>`
- 多账户场景下的 `AWS_PROFILE_<STACK>`
- `PULUMI_STATE_BUCKET`、`PULUMI_KMS_ALIAS`
- `LTBASE_RELEASES_REPO`、`LTBASE_RELEASE_ID`
- 保持模板默认值不变的 `MTLS_TRUSTSTORE_FILE`、`MTLS_TRUSTSTORE_KEY`
- `API_DOMAIN_<STACK>`、`CONTROL_DOMAIN_<STACK>`、`AUTH_DOMAIN_<STACK>`、`PROJECT_ID`、`AUTH_PROVIDER_CONFIG_FILE_<STACK>`、`CLOUDFLARE_ZONE_ID`
  - `CLOUDFLARE_ZONE_ID` 仍然是 `.env` 中需要手动提供的 bootstrap 输入，但 preview 与 rollout 的 mTLS audit 实际读取的是 `infra/Pulumi.<stack>.yaml` 里保存的每个 stack 值，包括 `ltbase-infra:cloudflareZoneId`、域名、`awsRegion` 和 `runtimeBucket`。
- `GEMINI_MODEL`、`DSQL_PORT`、`DSQL_DB`、`DSQL_USER`、`DSQL_PROJECT_SCHEMA`
- `GEMINI_API_KEY`、`CLOUDFLARE_API_TOKEN`、`LTBASE_RELEASES_TOKEN`

## 通常由 Bootstrap 自动推导的值

除非你明确需要 override，否则以下值通常应保持未设置：

- `DEPLOYMENT_REPO`
  - 默认值：`${GITHUB_OWNER}/${DEPLOYMENT_REPO_NAME}`
- `GITHUB_ORG`、`GITHUB_REPO`
  - 默认值：由 `GITHUB_OWNER` 和 `DEPLOYMENT_REPO_NAME` 推导
- `AWS_ROLE_ARN_<STACK>`
  - 默认值：由 `AWS_ACCOUNT_ID_<STACK>` 和 `AWS_ROLE_NAME_<STACK>` 推导
- `PULUMI_BACKEND_URL`
  - 默认值：`s3://${PULUMI_STATE_BUCKET}`
- `PULUMI_SECRETS_PROVIDER_<STACK>`
  - 默认值：由 `PULUMI_KMS_ALIAS` 和 `AWS_REGION_<STACK>` 推导
- `OIDC_DISCOVERY_TEMPLATE_REPO`、`OIDC_DISCOVERY_REPO_NAME`、`OIDC_DISCOVERY_REPO`、`OIDC_DISCOVERY_PAGES_PROJECT`
  - 默认值：由 deployment repository 的命名输入推导
- `OIDC_DISCOVERY_AWS_ROLE_NAME_<STACK>`、`OIDC_DISCOVERY_AWS_ROLE_ARN_<STACK>`
  - 默认值：由 deployment repository 名称和目标 AWS account ID 推导
- `OIDC_ISSUER_URL_<STACK>`、`JWKS_URL_<STACK>`
  - 默认值：由 `OIDC_DISCOVERY_DOMAIN` 推导
- `RUNTIME_BUCKET_<STACK>`、`TABLE_NAME_<STACK>`
  - 默认值：由 `DEPLOYMENT_REPO_NAME` 推导
- `PREVIEW_DEFAULT_STACK`
  - 默认值：`PROMOTION_PATH` 中的第一个 stack

## 可选 Override

只有在默认值不适用于你的客户环境时，才需要填写这些项：

- `DEPLOYMENT_REPO`
- `OIDC_DISCOVERY_TEMPLATE_REPO`
- `OIDC_DISCOVERY_REPO_NAME`
- `OIDC_DISCOVERY_REPO`
- `OIDC_DISCOVERY_PAGES_PROJECT`
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>`
- `OIDC_ISSUER_URL_<STACK>`
- `JWKS_URL_<STACK>`
- `RUNTIME_BUCKET_<STACK>`
- `TABLE_NAME_<STACK>`
- `OIDC_DISCOVERY_AWS_ROLE_NAME_<STACK>`

## 重要规则

- 不要提交 `.env`
- 不要把生产 secrets 写进被版本控制的文件
- 模板仓库只提供 `infra/auth-providers.*.json.example`；真实的 `infra/auth-providers.<stack>.json` 文件应保留在生成出来的客户 deployment repo 中维护
- 如果你依赖 bootstrap 创建 backend 资源，请把 `PULUMI_BACKEND_URL` 和 `PULUMI_SECRETS_PROVIDER_*` 当作生成值
- 只填写你真正控制的输入项，生成值应来自 bootstrap 输出
- 对于 managed 部署，不要手动设置 `DSQL_ENDPOINT`；bootstrap 和后续 reconcile 会发布权威值
- 除非 LTBase 模板本身发生变更，否则保持 `MTLS_TRUSTSTORE_FILE=infra/certs/cloudflare-origin-pull-ca.pem` 和 `MTLS_TRUSTSTORE_KEY=mtls/cloudflare-origin-pull-ca.pem`；bootstrap 要求这两个值必须存在
- 一旦应用后续 mTLS rollout 任务，`api`、`auth`、`control-plane` 将只通过 Cloudflare 代理的自定义域名对外提供访问
- 以下变量由 `scripts/lib/bootstrap-env.sh` 自动派生，通常不需要手动填写：`DEPLOYMENT_REPO`、`PULUMI_BACKEND_URL`、`PULUMI_SECRETS_PROVIDER_*`、`AWS_ROLE_ARN_*`、`OIDC_ISSUER_URL_*`、`JWKS_URL_*`、`RUNTIME_BUCKET_*`、`TABLE_NAME_*`、`GITHUB_ORG`、`GITHUB_REPO`、`OIDC_DISCOVERY_TEMPLATE_REPO`、`OIDC_DISCOVERY_REPO_NAME`、`OIDC_DISCOVERY_REPO`、`OIDC_DISCOVERY_PAGES_PROJECT`、`OIDC_DISCOVERY_AWS_ROLE_NAME_*`、`OIDC_DISCOVERY_AWS_ROLE_ARN_*`、`PREVIEW_DEFAULT_STACK`

## 预期结果

你现在已经拥有一个完整的本地 `.env` 文件，可供 bootstrap 脚本使用。

## 常见问题

- 将占位符和真实值混在一起使用
- `DEPLOYMENT_REPO` 写成了错误的仓库名
- 忘记让 AWS account ID 与目标角色匹配
- 误把 `.env` 提交到仓库
- 手动填写了派生值，但后来又忘记同步更新上方的客户输入值

## 下一步

选择一个 bootstrap 路径：

- 一键部署：[`05-bootstrap-one-click.zh.md`](05-bootstrap-one-click.zh.md)
- 手动部署：[`06-bootstrap-manual.zh.md`](06-bootstrap-manual.zh.md)
