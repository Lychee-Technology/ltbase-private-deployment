> **English version: [01-prerequisites.md](01-prerequisites.md)**

# 准备前置条件

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档确认你已经具备开始 bootstrap 所需的最小账户、权限和本地工具。

## 开始前确认

你应该已经可以访问：

- 一个可以创建私有仓库的 GitHub 组织或个人账号
- 一个或多个将承载 `STACKS` 中各环境的 AWS 账户
- 用于应用域名的 Cloudflare zone
- 一个 Gemini API key
- 一个客户专用的 `LTBASE_RELEASES_TOKEN`

安装或确认以下本地工具：

- `git`
- `gh` (GitHub CLI)
- `aws` (AWS CLI)
- `pulumi`
- `python3`

## 就绪检查清单

### 1. 确认 GitHub 访问

1. 通过 GitHub CLI 完成认证。

```bash
gh auth status
```

2. 确认当前认证账号可以在目标 `GITHUB_OWNER` 下创建私有仓库。
3. 确认同一个账号后续还能管理部署仓库中的 repository secrets、repository variables 和受保护环境。
4. 记录最终要使用的 GitHub owner 和仓库名。

### 2. 确认 AWS 访问

1. 记录 `STACKS` 中每个 stack 对应的 AWS account ID 和 AWS region。
2. 确认你可以从本地工作站访问每个目标 AWS 账户。

```bash
aws sts get-caller-identity
```

3. 如果不同 stack 使用不同 AWS 账户，现在就确定你的切换方式。
4. 如果你计划按 stack 使用不同 profile，请在 bootstrap 前逐个测试。

```bash
AWS_PROFILE_STAGING=customer-staging aws sts get-caller-identity
```

5. 确认你有权限创建或更新所有由 bootstrap 管理的 AWS 资源：
   - GitHub OIDC provider
   - deploy role 与 trust policy
   - IAM inline role policy
   - 位于 `PROMOTION_PATH` 第一个 stack 对应 AWS 账户中的共享 Pulumi state bucket
   - 用于 Pulumi secrets 的 KMS alias

### 3. 确认 Cloudflare 访问

1. 记录你准备写入 `.env` 的 Cloudflare account ID 和 zone ID。
2. 确认对应 zone 已经存在。
3. 确认 API token 可以管理：
   - Cloudflare Pages 项目
   - 自定义域名绑定
   - 承载 LTBase 域名和 OIDC discovery 域名的 zone

## Bootstrap 所需最小权限

本节描述的是一键 bootstrap 路径所需的最小操作权限。

如果你没有这些权限，不要靠反复重试来碰运气。请改走 [`06-bootstrap-manual.zh.md`](06-bootstrap-manual.zh.md) 的手动路径，并让平台管理员代为创建缺失资源。

### GitHub 最小权限

当前认证的 GitHub 账号至少需要能够：

- 在 `GITHUB_OWNER` 下从模板创建部署仓库
- 读取部署仓库和 OIDC discovery companion 仓库的元数据
- 为 `PROMOTION_PATH` 中第一个之后的每个 stack 创建 GitHub environments
- 在部署仓库中写入 repository variables
- 在部署仓库中写入 repository secrets
- 在 OIDC discovery companion 仓库不存在时，从模板创建该仓库
- 在 OIDC discovery companion 仓库中写入 repository variables

实际对应的 bootstrap 动作主要是：

- 为部署仓库和 companion 仓库执行 `gh repo create`
- 执行 `gh api .../environments/<stack> --method PUT`
- 执行 `gh variable set ...`
- 执行 `gh secret set ...`

### AWS 最小权限

对于 `STACKS` 使用到的每个 AWS 账户，bootstrap 操作者至少需要能够：

- 读取或创建 `token.actions.githubusercontent.com` 对应的 GitHub OIDC provider
- 读取或创建按 stack 划分的 deploy role
- 更新 deploy role 的 trust policy
- 挂载或替换 deploy role 的 inline policy
- 在目标 region 中列出 KMS aliases
- 在 Pulumi secrets alias 不存在时创建 KMS key 和 alias

对于 `PROMOTION_PATH` 第一个 stack 对应的 AWS 账户，bootstrap 操作者还需要能够：

- 检查共享 Pulumi backend bucket 是否已存在
- 在缺失时创建共享 Pulumi backend bucket
- 开启 bucket versioning
- 开启默认 bucket encryption
- 开启 public access block 设置

如果使用 OIDC discovery companion 流程，bootstrap 操作者还需要在每个 stack 对应账户中能够：

- 读取或创建 OIDC discovery IAM role
- 更新该 role 的 trust policy
- 挂载或替换该 role 的 inline policy

这里列的是 bootstrap 阶段的最小权限，不是后续系统运行时所需的全部权限。

### AWS bootstrap 操作者配置步骤

当平台管理员需要为一键 bootstrap 配置 AWS 权限时，建议按以下流程执行：

1. 先准备好 `.env`，确保 account ID、role name、Pulumi bucket 名称和 KMS alias 都已定稿。
2. 运行 `./scripts/render-bootstrap-policies.sh --env-file .env`。
3. 对每个 stack 对应账户，把生成的 `dist/bootstrap-operator-<stack>-policy.json` 赋予 bootstrap 操作者。
4. 对 `PROMOTION_PATH` 第一个 stack 对应的账户，再额外赋予 `dist/bootstrap-operator-first-stack-s3-policy.json`。
5. 如果平台管理员希望在真正执行 bootstrap 前预审所有权限，同时检查同一个 `dist/` 目录下生成的 deploy role trust/access policy 文件。
6. 在执行 bootstrap 前，用 `AWS_PROFILE_<STACK>` 配好并测试每个账户的本地凭据。

生成出来的策略文件包括：

- `dist/bootstrap-operator-<stack>-policy.json`
  - 该 stack 账户中 bootstrap 操作者所需的通用最小 IAM 和 KMS 权限
- `dist/bootstrap-operator-first-stack-s3-policy.json`
  - 只在第一个 stack 账户中额外需要的 S3 权限，因为共享 Pulumi backend bucket 固定在这个账户里

如果你的组织是通过中央运维角色去 assume 各个目标账户，请把这些策略附加到目标账户中的角色，再由中央身份单独处理 assume-role 链路。

### Cloudflare 最小权限

bootstrap 使用的 `CLOUDFLARE_API_TOKEN` 至少需要能够：

- 在 `CLOUDFLARE_ACCOUNT_ID` 下读取和创建 Cloudflare Pages 项目
- 读取和创建 OIDC discovery Pages 项目的自定义域名绑定
- 管理 `OIDC_DISCOVERY_DOMAIN` 所在的目标 zone

如果你希望 preview 与 rollout 的 mTLS audit 能成功检查 Cloudflare SSL 模式和 Authenticated Origin Pulls，这个 token 还必须具备读取 `CLOUDFLARE_ZONE_ID` 对应 zone settings 的权限。

这样 bootstrap 才能先检查 Pages project 和 domain binding 是否已存在，并在缺失时创建它们。

### 4. 确认本地工具

运行以下命令，确认每个工具都已安装：

```bash
git --version
gh --version
aws --version
pulumi version
python3 --version
```

### 5. 确认客户提供的 secrets 与 release 输入

1. 确认你已经拿到客户专用 `LTBASE_RELEASES_TOKEN`。
2. 确认你已经拿到 `GEMINI_API_KEY`。
3. 确认你已经知道这次首次部署要使用的 `LTBASE_RELEASE_ID`。
4. 确认你已经知道要写入 `.env` 的 Cloudflare API token。

## 预期结果

你已经准备好所有必需凭据、账户映射和本地工具，不会在 bootstrap 过程中因为缺少访问权限而中断。

## 常见问题

- 使用了无法创建私有仓库的 GitHub 账号
- 在没有 Cloudflare zone ID 的情况下开始
- 在没有客户专用 releases token 的情况下开始
- 错误地认为一个 AWS profile 可以直接管理两个不同 AWS 账户而无需切换凭据
- 直到 bootstrap 命令失败后才去检查 `gh auth status` 或 `aws sts get-caller-identity`

## 下一步

继续阅读 [`02-create-repo-and-clone.zh.md`](02-create-repo-and-clone.zh.md)。
