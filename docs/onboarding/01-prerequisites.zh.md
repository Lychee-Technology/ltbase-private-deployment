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

## 操作步骤

1. 确认你可以通过命令行登录 GitHub。
2. 确认你可以访问将承载 LTBase 的 AWS 账户。
3. 确认你已经知道 `STACKS` 中每个环境分别对应哪个 AWS 账户。
4. 确认你已经确定将要创建的 GitHub 仓库名。
5. 确认你已经知道托管域名的 Cloudflare zone ID。
6. 确认你已经准备好 `LTBASE_RELEASES_TOKEN` 和 `GEMINI_API_KEY`。

## 预期结果

你已经拥有所有必需凭据，不会在 bootstrap 过程中因为缺少访问权限而中断。

## 常见问题

- 使用了无法创建私有仓库的 GitHub 账号
- 在没有 Cloudflare zone ID 的情况下开始
- 在没有客户专用 releases token 的情况下开始
- 错误地认为一个 AWS profile 可以直接管理两个不同 AWS 账户而无需切换凭据

## 下一步

继续阅读 [`02-create-repo-and-clone.zh.md`](02-create-repo-and-clone.zh.md)。
