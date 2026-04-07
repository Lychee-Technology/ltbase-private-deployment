# 创建部署仓库并克隆到本地

> **[English](02-create-repo-and-clone.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

使用本文档从模板创建你的客户部署仓库，并确认本地仓库包含预期文件。

## 开始前确认

- 已完成 [`01-prerequisites.zh.md`](01-prerequisites.zh.md)
- 已确定目标 GitHub owner 和仓库名

## 给一键 Bootstrap 用户的重要说明

即使你后续计划使用一键 bootstrap，这一步仍然是推荐的起点。

后续 bootstrap 阶段会把本地 `infra/Pulumi.<stack>.yaml` 文件写入你执行命令的 checkout，因此最好直接在你自己的真实客户部署仓库 clone 中完成这些操作。

恢复感知脚本在必要时可以创建缺失的远端仓库，但更适合作为恢复路径，而不是默认 onboarding 流程。

## 操作步骤

1. 从 `ltbase-private-deployment` 模板创建新的私有仓库。
2. 使用符合你内部规范的仓库命名。
3. 将新仓库 clone 到本地。
4. 打开仓库根目录，确认以下内容存在：
   - `infra/`
   - `.github/workflows/`
   - `env.template`
   - `scripts/create-deployment-repo.sh`
   - `scripts/render-bootstrap-policies.sh`
   - `scripts/bootstrap-aws-foundation.sh`
   - `scripts/bootstrap-pulumi-backend.sh`
   - `scripts/bootstrap-oidc-discovery-companion.sh`
   - `scripts/bootstrap-deployment-repo.sh`
   - `scripts/bootstrap-all.sh`
   - `scripts/evaluate-and-continue.sh`
   - `scripts/sync-template-upstream.sh`
   - `scripts/reconcile-managed-dsql-endpoint.sh`
5. 确认仓库是私有的。
6. 确认可以为 `PROMOTION_PATH` 中第一个之后的每个 stack 创建 GitHub environment，因为后续审批 gate 会挂在这些环境上。
7. 如果你后续打算使用一键 bootstrap，请继续在这个 checkout 中完成 `.env` 准备和 bootstrap 命令。

## 预期结果

你已经获得本地部署仓库副本，并且目录结构符合 LTBase 私有部署模板预期。

## 常见问题

- 手动创建空仓库而不是从模板生成
- clone 错了仓库，拉到了模板仓库而不是自己的私有仓库
- 没有确认 `.github/workflows/` 和 `infra/` 是否存在
- 打算在临时 checkout 中运行 bootstrap，最后却找不到生成出来的 Pulumi stack 文件

## 下一步

继续阅读 [`03-create-oidc-and-deploy-roles.zh.md`](03-create-oidc-and-deploy-roles.zh.md)。
