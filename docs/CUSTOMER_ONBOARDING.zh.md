> **English version: [CUSTOMER_ONBOARDING.md](CUSTOMER_ONBOARDING.md)**

# LTBase 客户部署指南

本文档是 LTBase 私有部署的完整操作手册。按照本文档的步骤操作，你可以从零完成 LTBase 的私有部署。

如果你需要快速回顾已熟悉的步骤，请使用[快速清单](BOOTSTRAP.zh.md)。

## 目录

1. [部署模型](#部署模型)
2. [最终完成状态](#最终完成状态)
3. [部署前决策](#1-部署前决策)
4. [准备 AWS](#2-准备-aws)
5. [准备 GitHub](#3-准备-github)
6. [准备 Cloudflare](#4-准备-cloudflare)
7. [准备 LTBase 输入](#5-准备-ltbase-输入)
8. [创建部署仓库并克隆](#6-创建部署仓库并克隆)
9. [填写 .env 文件](#7-填写-env-文件)
10. [Preflight 检查](#8-preflight-检查)
11. [执行 Bootstrap](#9-执行-bootstrap)
12. [Preview](#10-preview)
13. [Rollout](#11-rollout)
14. [发布 OIDC Discovery](#12-发布-oidc-discovery)
15. [首次部署验证](#13-首次部署验证)
16. [常见错误与恢复](#14-常见错误与恢复)
17. [Day-2 日常运维](#15-day-2-日常运维)
18. [参考文档](#参考文档)

---

## 部署模型

你的 LTBase 部署涉及三个仓库：

| 仓库 | 角色 | 你需不需要管 |
|------|------|------------|
| `ltbase-deploy-workflows` | LTBase 维护的公共可复用 GitHub Actions 工作流 | 不需要，被你的部署仓库引用 |
| `ltbase-releases` | 私有发布仓库，存放官方 LTBase 应用发布产物 | 不需要，你有只读 token 即可 |
| **你的部署仓库** | 从 `ltbase-private-deployment` 模板创建的私有仓库 | **这是你唯一需要操作和维护的仓库** |

你的部署仓库**不构建 LTBase 应用源码**。它下载官方 LTBase release，通过 Pulumi 将其部署到你的 AWS 账户中。

### 部署流程概览

```
你准备 .env 和前置条件
       ↓
bootstrap 脚本（一键或手动）创建 IAM 角色、Pulumi backend、OIDC discovery、Control Plane UI Pages
       ↓
手动触发 GitHub Actions preview 工作流，验证 Pulumi 变更
       ↓
手动触发 rollout 工作流，按 PROMOTION_PATH 逐环境部署
       ↓
保护环境在 GitHub 中审批后自动推进
       ↓
每个 stack 首次 rollout 完成后，手动触发 publish-oidc-discovery.yml 发布 OIDC Discovery 文档（见第 12 节）
       ↓
部署完成，API/Auth/Control Plane/UI 均可访问
```

### 当前 Control Plane UI 模型

在当前仓库版本中：

- **bootstrap** 阶段：`bootstrap-controlplane-ui-companion.sh` 创建 Cloudflare Pages 项目、自定义域名绑定和 DNS CNAME（不创建任何仓库；脚本名中的 companion 是历史命名）；浏览器运行时配置（`CONTROLPLANE_UI_STACK_CONFIG`）由 `bootstrap-deployment-repo.sh` 写入 **deployment repo 的 GitHub variable**。
- **preview** 阶段：纯基础设施预览，**不发布** Control Plane UI。
- **rollout** 阶段：从 release artifact 中下载官方 `ltbase-controlplane-ui.tar.gz`，结合 deployment repo 中的运行时配置，发布到 Cloudflare Pages。
- deployment repo 是所有这些 UI 输入的操作者侧权威来源，包括 `CONTROLPLANE_UI_DOMAIN`、各 stack 浏览器配置、auth provider 名称对齐、Control Plane CORS 配置。

### 多 Stack 拓扑说明

本文档中的 stack 名称如 `devo`、`prod` 都是**示例**。你可以根据自己的需求选用任何名称，只要在 `STACKS` 和 `PROMOTION_PATH` 中保持一致即可。

---

## 最终完成状态

完成部署后，你应该具备：

- 一个基于本模板创建的私有部署仓库
- 每个 AWS 账户中各自存在 GitHub OIDC 信任关系
- `STACKS` 中每个环境各自对应一个 deploy role
- 一个共享的 Pulumi state bucket（位于 `PROMOTION_PATH` 第一个 stack 的 AWS 账户中）
- 一个用于 Pulumi secrets 加密的 KMS alias
- 已配置好的 GitHub 仓库 secrets 和 variables
- 一个可用于 preview 与部署的起点 stack
- `PROMOTION_PATH` 中每个后续环境在前一跳验证后可用于受保护 promotion
- 一个可通过 Cloudflare 代理域名访问的 Control Plane UI 管理站点
- 一个可被 Control Plane CORS 允许的 admin 域名
- 操作者身份提供方已配置 redirect URI 和用户绑定

---

## 1. 部署前决策

在开始任何操作之前，先确定以下拓扑决策。这些值将决定后续所有配置。

### 1.1 决定 Stack 拓扑

| 决策项 | 说明 | 示例 |
|--------|------|------|
| `STACKS` | 所有环境名称，逗号分隔 | `devo,prod` 或 `dev,staging,prod` |
| `PROMOTION_PATH` | 部署推进顺序，逗号分隔 | `devo,prod`（通常与 STACKS 相同） |

> **当前限制（并行部署）**：`PROMOTION_PATH` 目前只支持**扁平的、逗号分隔的顺序列表**，rollout 一次只推进一个 stack（`devo` → `prod-na` → `prod-eu` 逐个部署）。目前**不支持** `devo,(prod-na,prod-eu)` 这类并行阶段语法（即从 `devo` 晋级时同时部署 `prod-na` 和 `prod-eu`）。如果需要在一个阶段并行部署多个 stack，需要后续对 workflow 做改造（阶段解析、matrix rollout、以及所有并行 stack 完成后再 dispatch 下一阶段的 fan-in）。stack 名称请使用小写字母、数字和连字符。

### 1.2 决定每个 Stack 的 AWS 配置

为每个 stack 确定：

| 配置项 | 示例值 |
|--------|--------|
| AWS region | `ap-northeast-1` |
| AWS account ID | `123456789012` |
| Deploy role 名称 | `ltbase-deploy-devo` |

> **注意**：如果多个 stack 使用同一个 AWS 账户的不同 region，这是允许的。如果使用不同 AWS 账户，请确保你在本地可以切换 AWS 凭据。

### 1.3 决定域名

为每个 stack 确定以下域名，它们需要在同一个 Cloudflare zone 下：

| 域名 | 作用 | 示例 |
|------|------|------|
| API 域名 | 数据面 API | `api.devo.customer.example.com` |
| Control 域名 | Control Plane API | `control.devo.customer.example.com` |
| Auth 域名 | Auth Service | `auth.devo.customer.example.com` |
| OIDC Discovery 域名 | OIDC 发现端点 | `oidc.customer.example.com` |
| Control Plane UI 域名 | 管理端界面 | `admin.customer.example.com` |

> **注意**：OIDC Discovery 域名和 Control Plane UI 域名是全局的（所有 stack 共用），而 API/Control/Auth 域名是每个 stack 独立的。

### 1.4 决定 Pulumi 后端资源名

| 配置项 | 说明 |
|--------|------|
| Pulumi state bucket 名称 | 全局唯一 S3 bucket 名称，存放 Pulumi 状态文件 |
| Pulumi KMS alias | KMS 别名，用于 Pulumi secrets 加密 |

---

## 2. 准备 AWS

### 2.1 创建或确认 AWS 账户

你需要一个或多个 AWS 账户来承载 LTBase 的各 stack 环境。

**如果你还没有 AWS 账户：**

1. 访问 https://aws.amazon.com 创建账户。
2. 推荐同时[创建 AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_tutorials_basic.html) 来统一管理多账户，但这不是 LTBase 部署的硬性要求。
3. 记录每个账户的 account ID（12 位数字），可在 AWS Console 右上角账户菜单中找到。

**如果你已有 AWS 账户：**

确认账户 ID 和区域已确定，并且你有足够权限创建 IAM 资源、S3 bucket、KMS key。

### 2.2 准备操作者 AWS 身份

你需要一个可以操作 AWS 的身份。推荐使用 IAM Identity Center（SSO），避免使用长期 access key。

#### 使用 `aws configure sso` 配置 profile

如果你使用 AWS Organizations / IAM Identity Center，运行 `aws configure sso` 交互式向导来配置本地 profile：

```bash
aws configure sso
```

向导会依次提示以下内容，逐项说明如下：

| Prompt | 填什么 | 说明 |
|--------|--------|------|
| `SSO session name` | 例如 `customer-ltbase` | 一个会话名称，供多个 profile 复用同一次 SSO 登录 |
| `SSO start URL` | 例如 `https://your-org.awsapps.com/start` | 从 AWS access portal / IAM Identity Center 控制台获取 |
| `SSO region` | 例如 `us-east-1` | IAM Identity Center 所在 region，**不一定**等于 stack 部署 region |
| `SSO registration scopes` | `sso:account:access` | 用于列出账户/角色的默认 scope；如果 prompt 已经默认显示 `[sso:account:access]`，直接回车即可 |

回车后浏览器会打开授权页面。授权成功后向导继续提示：

| Prompt | 填什么 | 说明 |
|--------|--------|------|
| 选择 AWS account | 从列表中选择目标 stack 的账户 | 只有一个账户时会自动选中 |
| 选择 permission set / role | 选择有足够权限的角色 | 只有一个角色时会自动选中 |
| `Default client Region` | 该 profile 对应 stack 的 AWS region，例如 `ap-northeast-1` | 影响该 profile 默认操作的 region |
| `CLI default output format` | 建议 `json` | CLI 输出格式 |
| `Profile name` | 例如 `customer-devo` | 建议用 stack 名称，方便和 `.env` 中 `AWS_PROFILE_<STACK>` 对齐 |

登录（或 token 过期后重新登录）：

```bash
aws sso login --profile customer-devo
```

#### 多 AWS 账户

如果不同 stack 使用不同 AWS 账户，为每个账户各配置一个 profile（可复用同一个 `SSO session name`），并在 `.env` 中设置对应的 `AWS_PROFILE_<STACK>`：

```bash
aws configure sso   # profile 名称填 customer-devo
aws configure sso   # profile 名称填 customer-prod
```

```bash
# .env
AWS_PROFILE_DEVO=customer-devo
AWS_PROFILE_PROD=customer-prod
```

### 2.3 测试 AWS 访问

对每个 stack 对应的 AWS 账户，测试凭据是否可用：

```bash
# 对每个 stack 执行
aws sts get-caller-identity --profile customer-devo
# 预期输出：包含 Account、Arn、UserId
```

如果 SSO token 过期，先重新登录再测试：

```bash
aws sso login --profile customer-devo
aws sts get-caller-identity --profile customer-devo
```

### 2.4 准备 Bootstrap 操作者权限

bootstrap 脚本需要在 AWS 中创建资源。你有两个选择：

#### 选择 A：直接运行 bootstrap（你有管理员权限）

如果操作者有足够的 AWS 权限（如 AdministratorAccess），可以直接执行 bootstrap，脚本会自动创建 OIDC provider、deploy role、Pulumi backend bucket、KMS alias 等。

所需权限详见本节的"bootstrap 最小权限"部分。

#### 选择 B：生成最小 policy 后由平台管理员授予

如果操作者没有直接的 IAM 创建权限，需要平台管理员先授予最小权限。

> 这个流程依赖 `.env` 文件中的值。**在第 7 步填写 `.env` 后**，运行：
>
> ```bash
> ./scripts/render-bootstrap-policies.sh --env-file .env
> ```
>
> 该命令在 `dist/` 目录下生成以下 policy 文件：
>
> | 文件 | 用途 |
> |------|------|
> | `dist/bootstrap-operator-<stack>-policy.json` | 每个 stack 的 bootstrap 操作者所需权限 |
> | `dist/bootstrap-operator-first-stack-s3-policy.json` | 第一个 stack 账户特有的 S3 权限（因为该账户拥有共享的 Pulumi backend bucket） |
>
> 将这些 policy 文件交给平台管理员，让他们为操作者在对应 AWS 账户中授予这些权限。

### 2.5 Bootstrap 最小权限参考

如果你需要手动创建 AWS 资源（而非让 bootstrap 脚本自动创建），以下是 bootstrap 脚本所需的最小权限：

**所有 stack 账户都需要：**

- `iam:GetOpenIDConnectProvider`
- `iam:CreateOpenIDConnectProvider`
- `iam:GetRole`
- `iam:CreateRole`
- `iam:UpdateAssumeRolePolicy`
- `iam:PutRolePolicy`
- `iam:ListAliases`（KMS）
- `kms:CreateKey`
- `kms:CreateAlias`

**第一个 stack 账户（在 `PROMOTION_PATH` 最前面）额外需要：**

- `s3:HeadBucket`
- `s3:CreateBucket`
- `s3:PutBucketVersioning`
- `s3:PutBucketEncryption`
- `s3:PutPublicAccessBlock`
- `s3:GetBucketPolicy`
- `s3:PutBucketPolicy`

### 2.6 跨账户 Pulumi Backend 访问

共享的 Pulumi state bucket（`PULUMI_STATE_BUCKET`）只创建在 `PROMOTION_PATH` 第一个 stack 对应的 AWS 账户里。所有 stack 共用同一个 backend bucket。

在多账户拓扑下，这会带来一个常见问题：**其他账户的身份默认无法访问第一个账户里的 backend bucket**。例如当 `prod` 在独立账户、你用 `AWS_PROFILE_PROD` 在本地操作时，它无法读写 `devo` 账户里的 Pulumi state S3 文件，`pulumi` 会报 `AccessDenied`。

`bootstrap-aws-foundation.sh` 会在第一个 stack 账户的 backend bucket 上写一条 **resource-based bucket policy** 来解决这个问题：

- 自动授权每个 stack 的 deploy role（`AWS_ROLE_ARN_<STACK>`）对 backend bucket 的 `s3:ListBucket`、`s3:GetObject`、`s3:PutObject`、`s3:DeleteObject`。
- GitHub Actions 中的 rollout 使用的是 deploy role（通过 OIDC assume `AWS_ROLE_ARN_<STACK>`），因此 CI 路径由这条 policy 自动覆盖。

如果你在**本地**用某个非第一账户的 profile（例如 `AWS_PROFILE_PROD`）直接跑 `pulumi`，该 profile 背后的 IAM/SSO role 不是 deploy role。**bootstrap 会自动处理这种情况**：`bootstrap-aws-foundation.sh` 对每个设置了 `AWS_PROFILE_<STACK>` 的 stack 运行 `aws sts get-caller-identity`，推导出该 profile 背后的 IAM role ARN（包括 IAM Identity Center / SSO role 的 `aws-reserved/sso.amazonaws.com/<region>/...` 路径），并自动写入 backend bucket policy。因此通常不需要手动设置。

只有当某个身份**无法**通过 `AWS_PROFILE_<STACK>` 自动推导（例如你用一个不在 `.env` profile 列表里的 role 本地操作）时，才手动把它的 role ARN 加入 `.env` 的 `PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS`（逗号分隔），bootstrap 会把它一并写入 bucket policy：

```bash
# .env
# 允许本地 prod operator profile 背后的 role 访问 devo 账户里的共享 backend bucket
PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS=arn:aws:iam::210987654321:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_Admin_abc123
```

> **如何拿到 SSO role ARN**：`aws configure sso` 配好的 profile 用的是 SSO assumed-role。运行 `aws sts get-caller-identity --profile customer-prod --query Arn --output text` 得到形如 `arn:aws:sts::<account>:assumed-role/AWSReservedSSO_Admin_abc123/<user>` 的 ARN；对应的可信 principal role ARN 是 `arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/<sso-region>/AWSReservedSSO_Admin_abc123`。

> **注意**：如果所有 stack 都在同一个 AWS 账户，backend bucket 与所有身份同账户，通常不需要设置 `PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS`。

---

## 3. 准备 GitHub

### 3.1 确认 GitHub 账户

你需要一个 GitHub 组织或个人账户，用于创建私有部署仓库。

```bash
# 确认 CLI 已认证
gh auth status

# 如果未认证，先登录
gh auth login
```

### 3.2 确认权限

认证的 GitHub 账户需要能够：

- 在 `GITHUB_OWNER` 下创建私有仓库
- 在部署仓库中写入 repository secrets 和 variables
- 在部署仓库中创建 GitHub environments（用于保护环境的审批 gate）

### 3.3 确认 `GITHUB_OWNER`

在 `.env` 中会用到的 `GITHUB_OWNER` 是你的 GitHub 组织名或个人用户名。

```bash
# 如果使用组织，确认你是组织成员
gh api user/orgs --jq '.[].login'
```

---

## 4. 准备 Cloudflare

### 4.1 确认 Cloudflare Zone

你需要一个 Cloudflare zone 来管理你的域名。

```bash
# 列出你的 zone
curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones" | jq '.result[] | {name, id}'
```

记录以下两个值：

| 值 | 说明 |
|----|------|
| Cloudflare account ID | 在 Cloudflare Dashboard 侧栏底部可见 |
| Cloudflare zone ID | 上述命令输出中的 `id` 字段 |

### 4.2 创建 Cloudflare API Token

在 Cloudflare Dashboard → My Profile → API Tokens → Create Token 中创建一个 token。

**所需权限：**

| 资源 | 权限 |
|------|------|
| Account - Cloudflare Pages | Edit |
| Zone - DNS | Edit |
| Zone - Zone Settings | Read |
| Zone - Custom Domains（Pages 相关） | Edit |

> Zone Settings Read 权限用于 preview/rollout 中的 mTLS audit 步骤。

### 4.3 Cloudflare SSL 和 Authenticated Origin Pulls 要求

部署完成后，所有 LTBase 服务（`api`、`auth`、`control-plane`）都需要通过 Cloudflare 代理访问，并且启用了 API Gateway mutual TLS。

在开始部署前，确认以下事项即可，部署后需要逐个检查：

- Cloudflare zone 使用了 `Full (strict)` SSL 模式
- API hostname 启用了 Authenticated Origin Pulls


## 5. 准备 LTBase 输入

### 5.1 LTBase Releases Token

从 LTBase 团队获取客户专用的 `LTBASE_RELEASES_TOKEN`。该 token 仅用于下载官方 release 产物。

### 5.2 Gemini API Key

从 [Google AI Studio](https://aistudio.google.com/apikey) 获取 Gemini API key。

### 5.3 确定 Release ID

确认你要部署的第一个 LTBase release 版本号，如 `v1.0.23`。从 LTBase 团队获取可用的 release ID。

### 5.4 准备 Firebase 和 Supabase 浏览器配置（Control Plane UI）

Control Plane UI 需要为每个 stack 提供浏览器公开的 Firebase 和 Supabase 配置。这些是**公开值**，不包含 secret。

| 变量 | 说明 | 示例 |
|------|------|------|
| `FIREBASE_API_KEY_<STACK>` | Firebase 浏览器 API key | `AIzaSy...` |
| `FIREBASE_PROJECT_ID_<STACK>` | Firebase 项目 ID | `my-project` |
| `SUPABASE_URL_<STACK>` | Supabase 项目 URL | `https://xxx.supabase.co` |
| `SUPABASE_ANON_KEY_<STACK>` | Supabase 匿名 key | `eyJh...` |

> **警告**：这些值会在 Control Plane UI 运行时配置中下发到浏览器。**不要**把 Firebase admin SDK private key、Supabase service-role key 或其他 secret 放在这里。

### 5.5 准备 Auth Provider 配置

从模板中的示例文件复制并编辑真实的 auth provider 配置：

```bash
cp infra/auth-providers.devo.json.example infra/auth-providers.devo.json
cp infra/auth-providers.prod.json.example infra/auth-providers.prod.json
```

编辑 `.json` 文件，配置你的 JWT issuer、audience 等。

> **重要**：保持 `auth-providers.<stack>.json` 中的 provider 名称与控制面 UI 中显示的浏览器 provider 名称一致。bootstrap 脚本在生成运行时配置时会复用匹配的名称。

---

## 6. 创建部署仓库并克隆

### 6.1 从模板创建仓库

在 GitHub 上，从 `Lychee-Technology/ltbase-private-deployment` 模板创建一个**新的私有仓库**。

```bash
gh repo create "${GITHUB_OWNER}/customer-ltbase" \
  --template Lychee-Technology/ltbase-private-deployment \
  --private \
  --description "Customer LTBase deployment repo"
```

### 6.2 克隆到本地

```bash
gh repo clone "${GITHUB_OWNER}/customer-ltbase"
cd customer-ltbase
```

### 6.3 验证仓库结构

确认以下文件和目录存在：

```bash
ls infra/
ls .github/workflows/
ls env.template
ls scripts/bootstrap-all.sh
ls scripts/evaluate-and-continue.sh
ls scripts/render-bootstrap-policies.sh
```

---

## 7. 填写 .env 文件

`.env` 文件是所有 bootstrap 和部署配置的输入。以下提供完整的填写指南。

### 7.1 创建 .env

```bash
cp env.template .env
```

**绝对不要**把 `.env` 提交到 Git。它包含 token 和 secret。

### 7.2 最小 .env 示例

以下示例只包含**必须手动填写**的变量。所有可以由 `scripts/lib/bootstrap-env.sh` 派生或有固定默认值的变量都不在这里，除非你要覆盖默认值（见 7.3）。

```bash
# ============ Stack 拓扑 ============
STACKS=devo,prod
# PROMOTION_PATH 默认等于 STACKS，需要不同顺序时才设置

# ============ 仓库身份 ============
GITHUB_OWNER=customer-org
DEPLOYMENT_REPO_NAME=customer-ltbase

# ============ 域名（全局）============
OIDC_DISCOVERY_DOMAIN=oidc.customer.example.com
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com

# ============ Cloudflare ============
CLOUDFLARE_ACCOUNT_ID=abc123def456
CLOUDFLARE_ZONE_ID=zone-abc123
CLOUDFLARE_API_TOKEN=your-api-token-here

# ============ AWS 环境（每个 stack 一组）============
AWS_REGION_DEVO=ap-northeast-1
AWS_ACCOUNT_ID_DEVO=123456789012
AWS_REGION_PROD=us-west-2
AWS_ACCOUNT_ID_PROD=210987654321
# 不同 stack 使用不同 AWS 账户时，为每个 stack 设置 AWS_PROFILE_<STACK>
# AWS_PROFILE_DEVO=customer-devo
# AWS_PROFILE_PROD=customer-prod

# ============ Pulumi 后端 ============
PULUMI_STATE_BUCKET=replace-with-pulumi-state-bucket

# ============ 域名（每个 stack 一组）============
API_DOMAIN_DEVO=api.devo.customer.example.com
API_DOMAIN_PROD=api.customer.example.com
CONTROL_DOMAIN_DEVO=control.devo.customer.example.com
CONTROL_DOMAIN_PROD=control.customer.example.com
AUTH_DOMAIN_DEVO=auth.devo.customer.example.com
AUTH_DOMAIN_PROD=auth.customer.example.com

# ============ LTBase 应用配置 ============
PROJECT_ID=11111111-1111-4111-8111-111111111111

# ============ Release 配置 ============
LTBASE_RELEASE_ID=v1.0.23
LTBASE_RELEASES_TOKEN=your-releases-token-here

# ============ Control Plane UI 浏览器配置 ============
FIREBASE_API_KEY_DEVO=public-firebase-api-key
FIREBASE_API_KEY_PROD=public-firebase-api-key
FIREBASE_PROJECT_ID_DEVO=firebase-project-id
FIREBASE_PROJECT_ID_PROD=firebase-project-id
SUPABASE_URL_DEVO=https://project.supabase.co
SUPABASE_URL_PROD=https://project.supabase.co
SUPABASE_ANON_KEY_DEVO=public-anon-key
SUPABASE_ANON_KEY_PROD=public-anon-key

# ============ Gemini ============
GEMINI_API_KEY=your-gemini-api-key
```

### 7.3 逐项说明

#### 必须手动填写的值（无法推导）

| 变量 | 从哪获得 |
|------|---------|
| `STACKS` | 你的部署拓扑决策 |
| `GITHUB_OWNER` | 你的 GitHub 组织名或用户名 |
| `DEPLOYMENT_REPO_NAME` | 你想要的仓库名称 |
| `OIDC_DISCOVERY_DOMAIN` | 你的域名计划 |
| `CONTROLPLANE_UI_DOMAIN` | 你的域名计划 |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Dashboard |
| `CLOUDFLARE_ZONE_ID` | Cloudflare Dashboard |
| `CLOUDFLARE_API_TOKEN` | 你在 Cloudflare 创建的 API token |
| `AWS_REGION_<STACK>` | 每个 stack 的目标区域 |
| `AWS_ACCOUNT_ID_<STACK>` | 每个 stack 的 AWS 账户 ID |
| `PULUMI_STATE_BUCKET` | 你选择的全局唯一 bucket 名称 |
| `API_DOMAIN_<STACK>` | 你的域名计划 |
| `CONTROL_DOMAIN_<STACK>` | 你的域名计划 |
| `AUTH_DOMAIN_<STACK>` | 你的域名计划 |
| `PROJECT_ID` | LTBase 项目 ID（UUID 格式） |
| `LTBASE_RELEASE_ID` | 要部署的 release 版本号 |
| `LTBASE_RELEASES_TOKEN` | 从 LTBase 团队获取 |
| `GEMINI_API_KEY` | 从 Google AI Studio 获取 |
| `FIREBASE_API_KEY_<STACK>` | Firebase 项目设置（浏览器公开值） |
| `FIREBASE_PROJECT_ID_<STACK>` | Firebase 项目设置（浏览器公开值） |
| `SUPABASE_URL_<STACK>` | Supabase 项目设置（浏览器公开值） |
| `SUPABASE_ANON_KEY_<STACK>` | Supabase 项目设置（浏览器公开值） |

> `AWS_PROFILE_<STACK>` 不是必填项，但在多账户拓扑下必须设置（见 7.4）。

#### 由 Bootstrap 自动派生的值（默认留空）

| 变量 | 派生规则 |
|------|---------|
| `PROMOTION_PATH` | 默认等于 `STACKS` |
| `TEMPLATE_REPO` | 默认 `Lychee-Technology/ltbase-private-deployment` |
| `DEPLOYMENT_REPO` | `${GITHUB_OWNER}/${DEPLOYMENT_REPO_NAME}` |
| `DEPLOYMENT_REPO_VISIBILITY` | 默认 `private` |
| `DEPLOYMENT_REPO_DESCRIPTION` | 默认 `Customer LTBase deployment repo` |
| `GITHUB_ORG` / `GITHUB_REPO` | 从上述值派生 |
| `AWS_ROLE_NAME_<STACK>` | 默认 `ltbase-deploy-<stack>` |
| `AWS_ROLE_ARN_<STACK>` | `arn:aws:iam::${AWS_ACCOUNT_ID_<STACK>}:role/${AWS_ROLE_NAME_<STACK>}` |
| `PULUMI_KMS_ALIAS` | 默认 `alias/ltbase-pulumi-secrets` |
| `PULUMI_BACKEND_URL` | `s3://${PULUMI_STATE_BUCKET}` |
| `PULUMI_SECRETS_PROVIDER_<STACK>` | `awskms://${PULUMI_KMS_ALIAS}?region=${AWS_REGION_<STACK>}` |
| `LTBASE_RELEASES_REPO` | 默认 `Lychee-Technology/ltbase-releases` |
| `AUTH_PROVIDER_CONFIG_FILE_<STACK>` | 默认 `infra/auth-providers.<stack>.json` |
| `OIDC_ISSUER_URL_<STACK>` | `https://${OIDC_DISCOVERY_DOMAIN}/<stack>` |
| `JWKS_URL_<STACK>` | `https://${OIDC_DISCOVERY_DOMAIN}/<stack>/.well-known/jwks.json` |
| `OIDC_DISCOVERY_PAGES_PROJECT` | `<DEPLOYMENT_REPO_NAME>-oidc-discovery` |
| `CONTROLPLANE_UI_PAGES_PROJECT` | `<DEPLOYMENT_REPO_NAME>-controlplane-ui` |
| `RUNTIME_BUCKET_<STACK>` | `<DEPLOYMENT_REPO_NAME>-runtime-<stack>` |
| `SCHEMA_BUCKET_<STACK>` | `<DEPLOYMENT_REPO_NAME>-schema-<stack>` |
| `TABLE_NAME_<STACK>` | `<DEPLOYMENT_REPO_NAME>-<stack>` |
| `PREVIEW_DEFAULT_STACK` | `PROMOTION_PATH` 的第一个 stack |
| `PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS` | bootstrap 会从 `AWS_PROFILE_<STACK>` 自动推导本地 operator role（见 7.4），只有无法自动推导时才手动填写 |

#### 有固定默认值、通常保持不变的变量

| 变量 | 默认值 | 说明 |
|------|----|------|
| `MTLS_TRUSTSTORE_FILE` | `infra/certs/cloudflare-origin-pull-ca.pem` | Cloudflare 官方 AOP truststore |
| `MTLS_TRUSTSTORE_KEY` | `mtls/cloudflare-origin-pull-ca.pem` | truststore 在 runtime bucket 中的 key |
| `GEMINI_MODEL` | `gemini-3.1-flash-lite` | 默认模型 |
| `DSQL_PORT` / `DSQL_DB` / `DSQL_USER` / `DSQL_PROJECT_SCHEMA` | `5432` / `postgres` / `admin` / `ltbase` | DSQL 连接默认值 |
| `DSQL_HOST` / `DSQL_ENDPOINT` / `DSQL_PASSWORD` | **不要设置** | Managed 部署由 bootstrap 和 deploy 自动解析 |

### 7.4 Multi-Account 特别说明

如果不同 stack 使用不同 AWS 账户，需要为每个 stack 设置对应的 `AWS_PROFILE_<STACK>`：

```bash
AWS_PROFILE_DEVO=customer-devo
AWS_PROFILE_PROD=customer-prod
```

测试每个 profile 的访问：

```bash
aws sts get-caller-identity --profile customer-devo
aws sts get-caller-identity --profile customer-prod
```

> **重要**：Pulumi 共享 backend bucket 会创建在 `PROMOTION_PATH` 第一个 stack 的 AWS 账户中。该账户的凭据需要有权限创建和管理这个 bucket。

> **本地跨账户访问自动处理**：`bootstrap-aws-foundation.sh` 会对每个设置了 `AWS_PROFILE_<STACK>` 的 stack 运行 `aws sts get-caller-identity`，把该 profile 背后的 IAM role（包括 IAM Identity Center / SSO role 的 `aws-reserved/sso.amazonaws.com/<region>/...` 路径）自动加入共享 backend bucket policy。因此通常**不需要**手动设置 `PULUMI_BACKEND_ACCESS_PRINCIPAL_ARNS`；只有当某个身份无法自动推导（例如不通过 profile 使用的 CI 之外的 role）时才手动补充（见 2.6）。

---

## 8. Preflight 检查

在运行 bootstrap 之前，先执行 preflight 检查，确保所有前置条件都满足。

### 8.1 检查 GitHub 访问

```bash
gh auth status
```

### 8.2 检查 AWS 访问

```bash
# 对每个 stack 的每个账户执行
aws sts get-caller-identity --profile customer-devo
```

### 8.3 审核 Bootstrap 将创建的 IAM Policy（可选但推荐）

```bash
./scripts/render-bootstrap-policies.sh --env-file .env
```

查看 `dist/` 目录下生成的文件，确认 policy 内容和 scope 符合预期。

### 8.4 运行 Bootstrap 扫描（不加 --force）

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

**正常输出**：会显示 `needs_foundation`、`needs_repo_config`、`needs_stack_bootstrap`、`needs_oidc_discovery` 等状态。这表示所有步骤都还没执行，属于正常状态。

**异常输出**：

- 认证失败信息（GitHub、AWS、Cloudflare、Pulumi）
- `missing required variable` → `.env` 缺少必填字段
- 强制退出 → 环境不满足 bootstrap 前提

**如果 preflight 报错**：根据错误信息修复 `.env` 或权限，重新运行 preflight 直到没有硬性错误。

---

## 9. 执行 Bootstrap

### 9.1 一键 Bootstrap（推荐）

如果你有足够的 GitHub、AWS 和 Cloudflare 权限，使用一键 bootstrap：

```bash
# 如果使用 split AWS account，先确保 profile 正确
export AWS_PROFILE=customer-devo  # 或确保 AWS_PROFILE_<STACK> 在 .env 中设置

./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force --infra-dir infra
```

**一键 bootstrap 会依次执行：**

1. `create-deployment-repo.sh` — 确保远程仓库存在
2. `render-bootstrap-policies.sh` — 生成 IAM policy 工件
3. `bootstrap-aws-foundation.sh` — 创建 GitHub OIDC provider、deploy role、Pulumi backend bucket、KMS alias
4. `bootstrap-oidc-discovery.sh` — 创建 OIDC discovery Cloudflare Pages 项目和 DNS
5. `bootstrap-controlplane-ui-companion.sh` — 创建 Control Plane UI 的 Cloudflare Pages 项目、自定义域名和 DNS CNAME（不创建任何仓库）
6. `bootstrap-deployment-repo.sh` — 为每个 stack 配置 Pulumi 和 GitHub values/secrets

**完成后确认：**

```bash
# 检查 GitHub repository variables
gh variable list --repo "${GITHUB_OWNER}/customer-ltbase"

# 检查 GitHub repository secrets（只列名称，不显示值）
gh secret list --repo "${GITHUB_OWNER}/customer-ltbase"

# 检查 Pulumi stack 文件
ls infra/Pulumi.*.yaml

# 检查每个 stack 的 Pulumi stack 文件包含 control plane CORS 配置
grep -l 'controlPlaneCorsOrigins' infra/Pulumi.*.yaml
```

> **恢复感知**：`evaluate-and-continue.sh` 是幂等的。如果中途失败，修复错误后重新运行即可跳过已完成步骤。

### 9.2 手动 Bootstrap（权限不足时）

如果你没有足够权限让脚本自动创建所有资源，或想逐阶段控制：

#### 创建仓库

```bash
./scripts/create-deployment-repo.sh --env-file .env
```

#### Bootstrap AWS Foundation

```bash
# 确保 AWS 凭据就绪
./scripts/bootstrap-aws-foundation.sh --env-file .env

# 加载生成的值到当前 shell
source dist/foundation.env
```

#### Bootstrap OIDC Discovery

```bash
./scripts/bootstrap-oidc-discovery.sh --env-file .env
```

#### Bootstrap Control Plane UI Companion

```bash
./scripts/bootstrap-controlplane-ui-companion.sh --env-file .env
```

#### 为每个 Stack 配置 Pulumi

```bash
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack prod --infra-dir infra
```

#### 最后确认

```bash
./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --infra-dir infra
```

确认所有状态都已经是 `complete`。

---

## 10. Preview

Preview 工作流验证 Pulumi stack 配置、校验 customer schema，并运行 `pulumi preview`。它**只做基础设施预览，不发布 Control Plane UI**。

Preview **只支持 `PROMOTION_PATH` 的第一个 stack**。

### 通过 CLI

```bash
gh workflow run preview.yml \
  -f target_stack=devo \
  --ref main
```

查看运行状态：

```bash
gh run list --workflow="Preview LTBase Blueprint" --limit 3
```

监控运行进度：

```bash
gh run watch $(gh run list --workflow="Preview LTBase Blueprint" --limit 1 --json databaseId --jq '.[0].databaseId')
```

### Preview 输出检查

Preview 工作流完成后，在 GitHub Actions run 页面查看：

1. **validate_config 步骤**：Pulumi stack config 验证是否通过
2. **preview 步骤**：Pulumi preview 输出，确认变更范围符合预期
3. **audit_mtls 步骤**：Cloudflare mTLS 配置审计

如果 preview 结果不符合预期，修复配置或 bootstrap 遗漏后再重试，**不要直接开始 rollout**。

---

## 11. Rollout

Rollout 工作流按 `PROMOTION_PATH` 逐环境部署。每个 hop 完成后，对受保护环境会触发 GitHub environment 审批 gate。

- `PROMOTION_PATH` 的第一个 stack 自动部署，无需审批。
- 后续各 hop 需要你在 GitHub environment gate 审批后才会推进。
- 每个 hop 会在 `pulumi up` 后自动 reconcile managed DSQL endpoint 和 authservice project info。

### 11.1 通过 CLI 触发

```bash
gh workflow run rollout.yml \
  -f release_id=v1.0.23 \
  --ref main
```

查看运行状态：

```bash
gh run list --workflow="Rollout LTBase Release" --limit 3
```

### 11.2 审批受保护环境

当 rollout 到达需要审批的 hop 时，GitHub 会暂停并等待审批。

在 Slack/Email 中会收到 GitHub 通知，或通过 CLI 查看：

```bash
gh run list --workflow="Rollout LTBase Release" --status=waiting
```

在 GitHub Actions run 页面中点击 Review pending deployments 审批。

### 11.3 仅部署起始 stack（不自动推进）

如果你只想部署 `PROMOTION_PATH` 的第一个 stack 而不自动推进：

```bash
gh workflow run deploy-devo.yml -f release_id=v1.0.23 --ref main
```

### 11.4 手动推进单个 hop

如果自动推进链中断，或需要单独推进一跳：

```bash
gh workflow run promote-prod.yml \
  -f release_id=v1.0.23 \
  -f from_stack=devo \
  -f to_stack=prod \
  --ref main
```

> **注意**：`from_stack` 和 `to_stack` 必须是 `PROMOTION_PATH` 中相邻的 stack。

### 11.5 Rollout 期间自动执行的操作

每个 rollout hop 会自动：

1. 运行 `pulumi up`
2. Reconcile managed DSQL endpoint（从 AWS 获取权威 endpoint 写入 Pulumi config）
3. 运行第二次 `pulumi up`（让 Lambda 环境变量获取 managed DSQL endpoint）
4. Reconcile authservice `project info` DynamoDB 记录
5. Publish customer schemas 到 stack schema bucket
6. Publish Control Plane UI 到 Cloudflare Pages（如果配置了 `CONTROLPLANE_UI_PAGES_PROJECT`）
7. 运行 Cloudflare mTLS audit

---

## 12. 发布 OIDC Discovery

OIDC Discovery 提供各 stack 的 `openid-configuration` 和 `jwks.json`，供外部 JWT 校验使用。

### 为什么在 Rollout 之后

OIDC Discovery 文档来自每个 stack 的 authservice 签名 KMS key。**该 KMS key 由 Pulumi 在部署时创建**（见 `alias/ltbase-oidc-discovery-<stack>-authservice`）。因此发布 OIDC Discovery 必须在该 stack **首次 rollout 之后**执行；在 rollout 之前触发会因为 KMS key 不存在而失败。

### 当前的发布模型

- 没有 OIDC Discovery companion 仓库或独立仓库。
- bootstrap（第 9 步）已经准备好承载资源：Cloudflare Pages project、custom domain、DNS CNAME、deployment repo variables（`OIDC_DISCOVERY_DOMAIN`、`OIDC_DISCOVERY_STACK_CONFIG`、`OIDC_DISCOVERY_PAGES_PROJECT`），以及每个 stack 的 OIDC discovery IAM role。
- 生成并上传 discovery 文档由 deployment repo 内置的 `publish-oidc-discovery.yml` 工作流完成：它运行 `scripts/build-discovery.sh` 生成文档，再通过 `wrangler pages deploy` **direct upload** 到 `${OIDC_DISCOVERY_PAGES_PROJECT}` 这个 Cloudflare Pages 项目。

> **注意**：当前版本 bootstrap 和 rollout 都不会自动触发 `publish-oidc-discovery.yml`，需要你在对应 stack 首次 rollout 完成后手动触发一次。

### 通过 GitHub Actions UI 触发

在 GitHub 仓库的 Actions 页面，选择 **Publish OIDC Discovery Documents** 工作流，点击 Run workflow，Branch 选择 `main`，`target_stack` 填已完成 rollout 的 stack（或在所有目标 stack 都已 rollout 后填 `all`）。

### 通过 CLI 触发

```bash
# 只发布已完成 rollout 的 stack（推荐在每个 hop 后执行）
gh workflow run publish-oidc-discovery.yml \
  -f target_stack=devo \
  --ref main

# 当所有目标 stack 都已完成首次 rollout 后，可一次性刷新全部
gh workflow run publish-oidc-discovery.yml \
  -f target_stack=all \
  --ref main
```

查看运行状态：

```bash
gh run list --workflow=publish-oidc-discovery.yml --limit 3
```

> **注意**：Cloudflare Pages direct upload 是整站部署。发布单个 stack 时，`build-discovery.sh` 只会重新生成该 stack 的文档；请在每个 stack 首次 rollout 后逐个发布，或在全部 rollout 完成后用 `target_stack=all` 一次性发布，避免遗漏 stack。

> **注意**：OIDC discovery IAM role 只信任从 default branch 触发的工作流（`repo:<DEPLOYMENT_REPO>:ref:refs/heads/<default_branch>`）。从其他 branch 触发会导致 AWS role assumption 失败。

### 理想状态（后续实现）

理想情况下，OIDC Discovery 应在 rollout 中自动发布，而不是要求单独手动触发。计划是在 `rollout-hop.yml` 的 rollout 成功后新增一个 job，对 `PROMOTION_PATH` 中从起点到当前 target stack 的已部署 stack 子集运行 direct upload。该改动属于后续代码变更，本文档会在实现后更新。

---

## 13. 首次部署验证

Rollout 完成后，逐项验证：

### 13.1 基础验证

```bash
# 检查 Pulumi stack outputs
pulumi stack output --stack "org/customer-ltbase/devo" -C infra

# 验证 OIDC discovery endpoint 可访问
curl -s "https://${OIDC_DISCOVERY_DOMAIN}/devo/.well-known/openid-configuration" | jq

# 验证 API 自定义域名可访问（会返回 4xx 是正常的，说明域名解析和代理已生效）
curl -s -o /dev/null -w "%{http_code}" "https://${API_DOMAIN_DEVO}/health"
```

### 13.2 Control Plane UI 验证

- 在浏览器中访问 `https://${CONTROLPLANE_UI_DOMAIN}`
- 确认 `/ltbase-controlplane.config.json` 可访问
- 确认 Firebase / Supabase 登录选项可见
- 确认 redirect URI 已在身份提供方中配置：`https://${CONTROLPLANE_UI_DOMAIN}/auth/callback`

### 13.3 Cloudflare mTLS 验证

```bash
./scripts/check-cloudflare-mtls.sh --env-file .env --stack devo
```

检查项：

- `api`、`auth`、`control-plane` DNS 记录是否在 Cloudflare 中 orange-clouded（proxied）
- Cloudflare SSL 模式是否为 `Full (strict)`
- Cloudflare Authenticated Origin Pulls 是否已启用
- truststore 对象是否在 stack runtime bucket 中存在
- API Gateway custom domain 是否配置了 mutual TLS

### 13.4 Schema 验证

确认 schema bucket 中有正确的发布记录：

```bash
# 列出 schema bucket 内容（需要 AWS 凭据）
aws s3 ls "s3://${SCHEMA_BUCKET_DEVO}/schemas/releases/" --profile customer-devo

# 检查 published manifest
aws s3 cp "s3://${SCHEMA_BUCKET_DEVO}/schemas/published/manifest.json" - --profile customer-devo | jq
```

### 13.5 Managed DSQL 验证

确认 managed DSQL endpoint 已正确设置：

```bash
# 查看 Pulumi stack config 中的 dsqlEndpoint
pulumi stack output --stack "org/customer-ltbase/devo" -C infra | grep -i dsql
```

如果 DSQL endpoint 空或不对，手动 reconcile：

```bash
./scripts/reconcile-managed-dsql-endpoint.sh --env-file .env --stack devo --infra-dir infra
```

### 13.6 Auth Service Project Info 验证

如果 auth service 的 project info 缺失或不对，手动 reconcile：

```bash
./scripts/reconcile-project-info.sh --env-file .env --stack devo --infra-dir infra
```

---

## 14. 常见错误与恢复

### 14.1 AWS 凭据错误

**症状**：bootstrap 或 preview 报 `InvalidClientTokenId` 或 `AccessDenied`

```bash
# 确认凭据
aws sts get-caller-identity --profile customer-devo
# 确认 SSO session 未过期
aws sso login --profile customer-devo
```

### 14.2 Cloudflare API Token 权限不足

**症状**：bootstrap 创建 Pages 或 DNS 记录失败

检查 token 权限：
- Account: Cloudflare Pages — Edit
- Zone: DNS — Edit
- Zone: Zone Settings — Read

### 14.3 Pulumi Config 漂移

**症状**：preview 或 rollout 在 validate_config 步骤报 missing key

根据错误信息确定缺失的 key，修复：

```bash
# 重新 bootstrap 某个 stack 的 Pulumi 配置
./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra
```

### 14.4 Control Plane UI 操作者无法登录

依次检查：

1. `CONTROLPLANE_UI_DOMAIN` 是否仍然指向正确的 Cloudflare Pages 域名
2. 身份提供方是否允许 `https://${CONTROLPLANE_UI_DOMAIN}/auth/callback`
3. `infra/auth-providers.<stack>.json` 中的 provider 名称是否与浏览器中可见的 provider 一致
4. Control Plane API CORS 是否包含 `https://${CONTROLPLANE_UI_DOMAIN}`
5. Firebase / Supabase 配置值是否正确（公开客户端值，不含 secret）

### 14.5 Managed DSQL Endpoint 不完整

**症状**：Lambda 无法连接 DSQL

```bash
# 手动 reconcile
./scripts/reconcile-managed-dsql-endpoint.sh --env-file .env --stack devo --infra-dir infra

# 然后重新 rollout 或单独 deploy
gh workflow run deploy-devo.yml -f release_id=v1.0.23 --ref main
```

### 14.6 mTLS 403 / 526 错误

- **403**：Cloudflare 可能没有正确呈现客户端证书链，或 truststore 已漂移
- **526**：源站 TLS 与 `Full (strict)` 不兼容，或自定义域名证书尚未生效

确认：
- Cloudflare SSL 模式为 `Full (strict)`
- Cloudflare Authenticated Origin Pulls 已启用
- 直连 `execute-api` 地址失败（这是预期行为，表示 mTLS 已生效）

---

## 15. Day-2 日常运维

### 15.1 升级到新 LTBase Release

```bash
# 1. 同步最新模板工具（可选，在 main 分支上）
./scripts/update-sync-template-tooling.sh
./scripts/sync-template-upstream.sh

# 2. 更新 GitHub variable 中的 LTBASE_RELEASE_ID
gh variable set LTBASE_RELEASE_ID --body "v1.0.24" \
  --repo "${GITHUB_OWNER}/customer-ltbase"

# 3. 对第一个 stack 执行 preview
gh workflow run preview.yml -f target_stack=devo --ref main

# 4. 确认 preview 无误后，执行 rollout
gh workflow run rollout.yml -f release_id=v1.0.24 --ref main
```

### 15.2 验证 mTLS 配置

```bash
./scripts/check-cloudflare-mtls.sh --env-file .env --stack devo
```

### 15.3 查看 Stack Outputs

```bash
pulumi stack output --stack "org/customer-ltbase/devo" -C infra
pulumi stack output --stack "org/customer-ltbase/prod" -C infra
```

### 15.4 运维约束

| 约束 | 说明 |
|------|------|
| 不要自行构建应用 | 部署仓库只下载官方 release，不构建 LTBase 源码 |
| 不要提交 .env | `.env` 包含 secret 和 token |
| 不要绕过审批 gate | 生产环境的 protected environment gate 必须经过审批 |
| 不要在 rollout 中途改 release ID | 整个 promotion path 使用同一个 release ID |
| 不要手动设置 DSQL endpoint | Managed 部署由 reconcile 自动管理 |
| 保持 Cloudflare SSL Full (strict) | 任何时候都不要降级 SSL 模式 |

---

## 参考文档

| 文档 | 用途 |
|------|------|
| [BOOTSTRAP.zh.md](BOOTSTRAP.zh.md) | 快速 bootstrap 清单 |
| [onboarding/01-prerequisites.zh.md](onboarding/01-prerequisites.zh.md) | 前置条件详细清单 |
| [onboarding/02-create-repo-and-clone.zh.md](onboarding/02-create-repo-and-clone.zh.md) | 仓库创建详细说明 |
| [onboarding/03-create-oidc-and-deploy-roles.zh.md](onboarding/03-create-oidc-and-deploy-roles.zh.md) | OIDC 和 role 详细说明 |
| [onboarding/04-prepare-env-file.zh.md](onboarding/04-prepare-env-file.zh.md) | .env 字段详细参考 |
| [onboarding/05-bootstrap-one-click.zh.md](onboarding/05-bootstrap-one-click.zh.md) | 一键 bootstrap 详细说明 |
| [onboarding/06-bootstrap-manual.zh.md](onboarding/06-bootstrap-manual.zh.md) | 手动 bootstrap 详细说明 |
| [onboarding/07-first-deploy-and-managed-dsql.zh.md](onboarding/07-first-deploy-and-managed-dsql.zh.md) | 首次部署和 DSQL 处理 |
| [onboarding/08-day-2-operations.zh.md](onboarding/08-day-2-operations.zh.md) | 日常运维详细说明 |
| [CONTROLPLANE_UI_DEPLOYMENT_CHECKLIST.md](CONTROLPLANE_UI_DEPLOYMENT_CHECKLIST.md) | Control Plane UI 部署检查清单 |
