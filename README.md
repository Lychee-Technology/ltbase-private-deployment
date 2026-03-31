# LTBase Private Deployment Template / LTBase 私有部署模板

This repository is the customer-facing deployment template for LTBase.

本仓库是 LTBase 面向客户的部署模板仓库。

It is the seed repository used to create a customer-owned private deployment repository.

它用于生成客户自有的私有部署仓库。

## Purpose / 用途

This repository exists to help customers deploy official LTBase releases into their own AWS accounts.

本仓库的用途是帮助客户将官方 LTBase release 部署到自己的 AWS 账户中。

It is not the LTBase application source repository.

它不是 LTBase 应用源码仓库。

## What's Included / 仓库包含内容

- thin wrapper workflows that call the public reusable LTBase deployment workflows
- bootstrap scripts for GitHub repository setup, AWS foundation setup, and Pulumi stack configuration
- example deployment inputs such as `env.template`
- customer onboarding and bootstrap documentation

- 调用 LTBase 公共可复用部署工作流的轻量封装工作流
- 用于 GitHub 仓库初始化、AWS 基础设施初始化、Pulumi stack 配置的 bootstrap 脚本
- 例如 `env.template` 这样的部署输入示例
- 面向客户的 onboarding 与 bootstrap 文档

## Start Here / 从这里开始

If you are onboarding a new customer deployment, start with:

如果你正在启动一个新的客户部署，请从这里开始：

- full onboarding runbook: [`docs/CUSTOMER_ONBOARDING.md`](docs/CUSTOMER_ONBOARDING.md)
- quick bootstrap checklist: [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md)

## Documentation Map / 文档地图

Main entrypoints:

主入口文档：

- [`docs/CUSTOMER_ONBOARDING.md`](docs/CUSTOMER_ONBOARDING.md)
- [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md)

Detailed onboarding guides:

详细 onboarding 子文档：

- prerequisites: [`docs/onboarding/01-prerequisites.md`](docs/onboarding/01-prerequisites.md)
- create repo and clone: [`docs/onboarding/02-create-repo-and-clone.md`](docs/onboarding/02-create-repo-and-clone.md)
- create OIDC and deploy roles: [`docs/onboarding/03-create-oidc-and-deploy-roles.md`](docs/onboarding/03-create-oidc-and-deploy-roles.md)
- prepare `.env`: [`docs/onboarding/04-prepare-env-file.md`](docs/onboarding/04-prepare-env-file.md)
- one-click bootstrap: [`docs/onboarding/05-bootstrap-one-click.md`](docs/onboarding/05-bootstrap-one-click.md)
- manual bootstrap: [`docs/onboarding/06-bootstrap-manual.md`](docs/onboarding/06-bootstrap-manual.md)
- first deploy and managed DSQL handling: [`docs/onboarding/07-first-deploy-and-managed-dsql.md`](docs/onboarding/07-first-deploy-and-managed-dsql.md)
- day-2 operations: [`docs/onboarding/08-day-2-operations.md`](docs/onboarding/08-day-2-operations.md)

## Bootstrap Entrypoints / Bootstrap 入口脚本

Important files and scripts:

重要文件与脚本：

- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`

Preferred recovery-aware bootstrap entrypoint:

推荐的可恢复 bootstrap 入口：

- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap`
- `./scripts/evaluate-and-continue.sh --env-file .env --scope bootstrap --force`

## Deployment Principles / 部署原则

- the deployment repository downloads official LTBase releases instead of building the application source code
- customers own the GitHub repository, AWS account resources, and deployment approvals
- bootstrap scripts prepare repository state and deployment configuration
- preview and production approval remain customer-controlled workflow actions

- 部署仓库负责下载官方 LTBase release，而不是自行构建应用源码
- 客户自行持有 GitHub 仓库、AWS 资源和部署审批权
- bootstrap 脚本负责准备仓库状态和部署配置
- preview 和生产审批仍由客户自己控制和触发

## Notes / 说明

- keep local `.env` files private and out of version control
- use the documentation in `docs/` as the source of truth for customer onboarding
- if a later repository version changes the managed DSQL lifecycle, follow the docs shipped with that version

- 保持本地 `.env` 文件私密，不要纳入版本控制
- 客户 onboarding 请以 `docs/` 下文档为准
- 如果后续仓库版本调整了 managed DSQL 生命周期，请以该版本自带文档为准
