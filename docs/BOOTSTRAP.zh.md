> **English version: [BOOTSTRAP.md](BOOTSTRAP.md)**

# 客户 Bootstrap 快速清单

这是客户部署流程的快速步骤清单。新用户请以 **[CUSTOMER_ONBOARDING.zh.md](CUSTOMER_ONBOARDING.zh.md)** 为主，本文档作为速查表使用。

如果你对某一流程需要更详细的说明，请阅读 [`onboarding/`](onboarding/) 下的对应子文档。

## 快速清单

### 1. 部署前决策

- 确定 `STACKS`（环境名称，如 `devo,prod`）
- 确定 `PROMOTION_PATH`（部署顺序）
- 确定每个 stack 的 AWS region、account ID、role 名称
- 确定 API/Control/Auth/OIDC/UI 域名
- 确定 Pulumi state bucket 名和 KMS alias

### 2. 准备前置条件

- 确认 GitHub CLI 已认证：`gh auth status`
- 确认可以访问每个 AWS 账户：`aws sts get-caller-identity --profile <profile>`
- 确认 Cloudflare zone 和 API token 就绪
- 确认 `LTBASE_RELEASES_TOKEN`、`GEMINI_API_KEY` 已获取
- 确认 Firebase 和 Supabase 浏览器配置值（公开值，不含 secret）
- 安装本地工具：`git`、`gh`、`aws`、`pulumi`、`python3`

详见：[`onboarding/01-prerequisites.zh.md`](onboarding/01-prerequisites.zh.md)

### 3. 创建部署仓库并克隆

```bash
gh repo create "${GITHUB_OWNER}/customer-ltbase" \
  --template Lychee-Technology/ltbase-private-deployment \
  --private
gh repo clone "${GITHUB_OWNER}/customer-ltbase"
cd customer-ltbase
```

详见：[`onboarding/02-create-repo-and-clone.zh.md`](onboarding/02-create-repo-and-clone.zh.md)

### 4. 填写 .env

```bash
cp env.template .env
```

填写所有手动值，保持派生值为空。**不要提交 .env。**

- Stack 拓扑：`STACKS`、`PROMOTION_PATH`
- 仓库：`GITHUB_OWNER`、`DEPLOYMENT_REPO_NAME`
- 域名：`OIDC_DISCOVERY_DOMAIN`、`CONTROLPLANE_UI_DOMAIN`、每个 stack 的 API/Control/Auth 域名
- Cloudflare：`CLOUDFLARE_ACCOUNT_ID`、`CLOUDFLARE_ZONE_ID`、`CLOUDFLARE_API_TOKEN`
- AWS：`AWS_REGION_<STACK>`、`AWS_ACCOUNT_ID_<STACK>`、`AWS_ROLE_NAME_<STACK>`
- Pulumi：`PULUMI_STATE_BUCKET`、`PULUMI_KMS_ALIAS`
- Release：`LTBASE_RELEASES_REPO`、`LTBASE_RELEASE_ID`、`LTBASE_RELEASES_TOKEN`
- 应用：`PROJECT_ID`、`AUTH_PROVIDER_CONFIG_FILE_<STACK>`、`GEMINI_API_KEY`
- 浏览器配置：`FIREBASE_*_<STACK>`、`SUPABASE_*_<STACK>`
- 保持 mTLS 默认值不变
- 不手动设置 `DSQL_ENDPOINT`

详见：[`onboarding/04-prepare-env-file.zh.md`](onboarding/04-prepare-env-file.zh.md)

### 5. Preflight 检查

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

### 6. 执行 Bootstrap

**一键路径（推荐）：**

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

**手动路径：**

```bash
./scripts/create-deployment-repo.sh --env-file .env
./scripts/bootstrap-aws-foundation.sh --env-file .env
source dist/foundation.env
./scripts/bootstrap-oidc-discovery.sh --env-file .env
./scripts/bootstrap-controlplane-ui-companion.sh --env-file .env
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

### 7. Preview

```bash
gh workflow run preview.yml -f target_stack=devo --ref main
```

完整参数与示例见 [`GITHUB_ACTIONS.zh.md`](GITHUB_ACTIONS.zh.md#previewyml--preview-ltbase-blueprint)。

### 8. Rollout

```bash
gh workflow run rollout.yml -f release_id=v1.0.23 --ref main
```

完整参数与示例见 [`GITHUB_ACTIONS.zh.md`](GITHUB_ACTIONS.zh.md#rolloutyml--rollout-ltbase-release)。

### 9. OIDC Discovery（rollout 期间自动发布）

OIDC Discovery 由 `rollout-hop.yml` 在每个 hop 中自动发布——rollout 之前用占位 key 发布（使某个 stack 首次 rollout 时能创建 API Gateway authorizer），rollout 之后再用真实的 KMS key 重新发布。无需任何手动步骤。

`publish-oidc-discovery.yml` 仅保留为手动恢复 / 重新发布入口：

```bash
# 手动恢复：重新发布单个 stack
gh workflow run publish-oidc-discovery.yml -f target_stack=devo --ref main

# 手动恢复：刷新全部 stack
gh workflow run publish-oidc-discovery.yml -f target_stack=all --ref main
```

完整参数与示例见 [`GITHUB_ACTIONS.zh.md`](GITHUB_ACTIONS.zh.md#publish-oidc-discoveryyml--publish-oidc-discovery-documents)。

### 10. 验证

```bash
./scripts/check-cloudflare-mtls.sh --env-file .env --stack devo
pulumi stack output --stack "org/customer-ltbase/devo" -C infra
```

详见：[`onboarding/07-first-deploy-and-managed-dsql.zh.md`](onboarding/07-first-deploy-and-managed-dsql.zh.md)

## 必需的 GitHub Secrets

- `AWS_ROLE_ARN_<STACK>`（每个 stack 一个）
- `LTBASE_RELEASES_TOKEN`
- `CLOUDFLARE_API_TOKEN`

## 必需的 GitHub Variables

- `AWS_REGION_<STACK>`（每个 stack 一个）
- `PULUMI_BACKEND_URL`
- `PULUMI_SECRETS_PROVIDER_<STACK>`（每个 stack 一个）
- `LTBASE_RELEASES_REPO`
- `LTBASE_RELEASE_ID`
- `STACKS`
- `PROMOTION_PATH`
- `PREVIEW_DEFAULT_STACK`

Bootstrap 脚本会自动写入这些值。

## Day-2 运维

- 升级：更新 `LTBASE_RELEASE_ID` → preview → rollout
- 同步模板：`./scripts/update-sync-template-tooling.sh` → `./scripts/sync-template-upstream.sh`
- 审计 mTLS：`./scripts/check-cloudflare-mtls.sh --env-file .env --stack <stack>`

详见：[`onboarding/08-day-2-operations.zh.md`](onboarding/08-day-2-operations.zh.md)

## 说明

- 部署仓库负责下载官方 LTBase release，不自行构建应用。
- 官方工作流可能在运行 Pulumi 前，从 `ltbase-private-deployment-binaries` 安装与上游模板版本绑定的预构建 `ltbase-infra` 二进制。它会读取 `__ref__/template-provenance.json` 及其 `build_fingerprint` 来查找完全匹配的上游 manifest；找不到时由仓库内的 `infra/scripts/pulumi-wrapper.sh` 回退到本地源码构建。
- 客户部署仓库只消费这些预构建二进制；复制过去的 `build-infra-binary.yml` 在 `Lychee-Technology/ltbase-private-deployment` 之外会被跳过。
