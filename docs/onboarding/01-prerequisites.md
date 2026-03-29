# Prepare Prerequisites / 准备前置条件

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

返回主文档：[`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose / 目的

Use this guide to confirm that you have the minimum accounts, permissions, and local tools required before you begin bootstrap.

使用本文档确认你已经具备开始 bootstrap 所需的最小账户、权限和本地工具。

## Before You Start / 开始前确认

You should have access to:

你应该已经可以访问：

- a GitHub organization or personal account that can create private repositories
- a devo AWS account, and optionally a separate prod AWS account
- a Cloudflare zone for your application domains
- a Gemini API key
- a customer-specific `LTBASE_RELEASES_TOKEN`

- 一个可以创建私有仓库的 GitHub 组织或个人账号
- 一个 devo AWS 账户，以及可选的独立 prod AWS 账户
- 用于应用域名的 Cloudflare zone
- 一个 Gemini API key
- 一个客户专用的 `LTBASE_RELEASES_TOKEN`

Install or confirm these local tools:

安装或确认以下本地工具：

- `git`
- `gh` (GitHub CLI)
- `aws` (AWS CLI)
- `pulumi`
- `python3`

## Steps / 操作步骤

1. Confirm you can log in to GitHub from the CLI.
2. Confirm you can access the AWS accounts that will host LTBase.
3. Confirm you know which AWS account is `devo` and which is `prod`.
4. Confirm you know which GitHub repo name you plan to create.
5. Confirm you know the Cloudflare zone ID that will host the domains.
6. Confirm you have both `LTBASE_RELEASES_TOKEN` and `GEMINI_API_KEY` ready.

1. 确认你可以通过命令行登录 GitHub。
2. 确认你可以访问将承载 LTBase 的 AWS 账户。
3. 确认你已经知道哪个 AWS 账户对应 `devo`，哪个对应 `prod`。
4. 确认你已经确定将要创建的 GitHub 仓库名。
5. 确认你已经知道托管域名的 Cloudflare zone ID。
6. 确认你已经准备好 `LTBASE_RELEASES_TOKEN` 和 `GEMINI_API_KEY`。

## Expected Result / 预期结果

You have all required credentials and no longer need to pause the bootstrap process to ask for missing access.

你已经拥有所有必需凭据，不会在 bootstrap 过程中因为缺少访问权限而中断。

## Common Mistakes / 常见问题

- using a GitHub account that cannot create private repositories
- starting without the Cloudflare zone ID
- starting without the customer-specific releases token
- assuming one AWS profile can manage two different AWS accounts without switching credentials

- 使用了无法创建私有仓库的 GitHub 账号
- 在没有 Cloudflare zone ID 的情况下开始
- 在没有客户专用 releases token 的情况下开始
- 错误地认为一个 AWS profile 可以直接管理两个不同 AWS 账户而无需切换凭据

## Next Step / 下一步

Continue with [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md).

继续阅读 [`02-create-repo-and-clone.md`](02-create-repo-and-clone.md)。
