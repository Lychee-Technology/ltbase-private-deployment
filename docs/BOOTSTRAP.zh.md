> **English version: [BOOTSTRAP.md](BOOTSTRAP.md)**

# 客户 Bootstrap 清单

这是客户 onboarding 流程的简版清单。

完整的中英双语说明请从这里开始：

- [`CUSTOMER_ONBOARDING.zh.md`](CUSTOMER_ONBOARDING.zh.md)

## 仓库结构

你的部署仓库应包含：

- `infra/`
- `.github/workflows/`
- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-oidc-discovery-companion.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/update-sync-template-tooling.sh`
- `scripts/sync-template-upstream.sh`
- `scripts/reconcile-managed-dsql-endpoint.sh`
- `scripts/lib/bootstrap-env.sh`

## 快速清单

### 1. 准备前置条件

- 阅读 [`onboarding/01-prerequisites.zh.md`](onboarding/01-prerequisites.zh.md)
- 确认 GitHub、AWS、Cloudflare、`LTBASE_RELEASES_TOKEN` 与 `GEMINI_API_KEY` 都已准备好

### 2. 创建部署仓库

- 阅读 [`onboarding/02-create-repo-and-clone.zh.md`](onboarding/02-create-repo-and-clone.zh.md)
- 从模板创建私有仓库并 clone 到本地
- 即使使用一键 bootstrap，也推荐先完成这一步，因为后续 bootstrap 会把本地 Pulumi stack 文件写入当前 checkout

### 3. 创建 OIDC 和 deploy role

- 阅读 [`onboarding/03-create-oidc-and-deploy-roles.zh.md`](onboarding/03-create-oidc-and-deploy-roles.zh.md)
- 为 `STACKS` 中的每个环境各创建一个 deploy role

### 4. 准备 `.env`

- 阅读 [`onboarding/04-prepare-env-file.zh.md`](onboarding/04-prepare-env-file.zh.md)
- 将 `env.template` 复制为 `.env`
- 填写客户可控输入值；除非确实需要 override，否则派生值先不要手填；并且绝对不要提交 `.env`
- 除非 LTBase 另行说明，否则保持 `MTLS_TRUSTSTORE_FILE` 与 `MTLS_TRUSTSTORE_KEY` 为模板默认值

### 5. 选择 bootstrap 路径

一键路径：

- 阅读 [`onboarding/05-bootstrap-one-click.zh.md`](onboarding/05-bootstrap-one-click.zh.md)
- 可选先运行 `./scripts/render-bootstrap-policies.sh --env-file .env` 审阅生成的 IAM 策略
- 如果平台管理员需要先授予 AWS bootstrap 权限，把每个 stack 对应的 `dist/bootstrap-operator-<stack>-policy.json` 和第一个 stack 账户专用的 `dist/bootstrap-operator-first-stack-s3-policy.json` 发给对方
- 先运行 `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra` 做 preflight 检查
- 运行 `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra`

手动路径：

- 阅读 [`onboarding/06-bootstrap-manual.zh.md`](onboarding/06-bootstrap-manual.zh.md)
- 按阶段逐个执行 bootstrap 脚本

### 6. 执行首次部署

- 阅读 [`onboarding/07-first-deploy-and-managed-dsql.zh.md`](onboarding/07-first-deploy-and-managed-dsql.zh.md)
- 对 `PROMOTION_PATH` 第一个环境执行 preview
- 针对目标 release 触发一次 `rollout.yml`
- 在 GitHub 请求时依次审批受保护目标环境

### 7. 日常运维

- 阅读 [`onboarding/08-day-2-operations.zh.md`](onboarding/08-day-2-operations.zh.md)
- 后续升级继续沿用 preview -> rollout 的节奏

## 必需的 GitHub Secrets

- `AWS_ROLE_ARN_<STACK>`（`STACKS` 中每个环境各一个）
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## 必需的 GitHub Variables

- `AWS_REGION_<STACK>`（`STACKS` 中每个环境各一个）
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>`（`STACKS` 中每个环境各一个）
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

## 说明

- 保持 `.env` 私密，不要纳入版本控制
- 部署仓库负责下载官方 LTBase release，不负责自行构建应用
- 官方工作流也可能在 Pulumi 执行前从 `ltbase-private-deployment-binaries` 安装与上游模板版本绑定的预构建 `ltbase-infra`；它会读取 `__ref__/template-provenance.json` 里的 `build_fingerprint` 来查找完全匹配的上游 manifest，找不到时仓库内的 `infra/scripts/pulumi-wrapper.sh` 会回退到本地源码构建
- 客户部署仓库只消费这些预构建二进制；复制过去的 `build-infra-binary.yml` 在 `Lychee-Technology/ltbase-private-deployment` 之外会直接跳过
- 客户仓库中的 preview 默认为手动触发，因为真实凭据由客户持有
- 手动 preview 只支持 `PROMOTION_PATH` 的第一个环境
- rollout 中的受保护目标环境由各自的 GitHub environment 审批 gate 保护
- 当前模板默认假设 `api`、`auth`、`control-plane` 都通过 Cloudflare 代理的自定义域名对外提供访问
- 在承载正式流量前，将 Cloudflare SSL 模式设置为 `Full (strict)`
- 在期待 API Gateway mTLS 生效前，先启用 Cloudflare Authenticated Origin Pulls
- 一旦应用 mTLS rollout，直接访问 `execute-api` endpoint 失败属于预期行为
