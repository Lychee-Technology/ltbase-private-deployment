> **English version: [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md)**

# GitHub Actions 参考

本文档说明部署仓库 `.github/workflows/` 中的每一个 GitHub Actions 工作流：它做什么、什么时候应该用、接受哪些输入参数（含示例），以及依赖哪些 GitHub Variables 和 Secrets。

如果你要了解完整的部署流程，请先阅读 [`CUSTOMER_ONBOARDING.zh.md`](CUSTOMER_ONBOARDING.zh.md)。本页是逐个工作流的参数速查表，需要精确输入时回到这里查阅即可。

## 如何阅读本页

- **触发方式** — 工作流如何启动（`workflow_dispatch` = 手动点击 "Run workflow" 或 `gh workflow run`，`workflow_call` = 被其他工作流调用，`push`/`pull_request` = 自动触发）。
- **输入参数** — 你在触发时提供的参数。每个示例都同时给出 `gh workflow run` 命令。
- **使用到的配置** — 工作流读取的 GitHub 仓库 Variables（`vars.*`）和 Secrets（`secrets.*`）。这些大多由 bootstrap 脚本自动写入，详见 [`onboarding/04-prepare-env-file.zh.md`](onboarding/04-prepare-env-file.zh.md)。
- 所有 `gh workflow run` 命令都请加上 `--ref main`。多个 OIDC role 只信任默认分支，从其他分支触发会导致 AWS role assumption 失败。

## 工作流一览

| 工作流 | GitHub UI 中的名称 | 主要用途 | 你需要运行吗？ |
|--------|-------------------|----------|---------------|
| [`preview.yml`](#previewyml--preview-ltbase-blueprint) | Preview LTBase Blueprint | 部署前校验配置并生成 Pulumi diff | 需要 |
| [`rollout.yml`](#rolloutyml--rollout-ltbase-release) | Rollout LTBase Release | 按整条 promotion path 部署一个 release | 需要（主入口） |
| [`deploy-devo.yml`](#deploy-devoyml--deploy-ltbase-start-stack) | Deploy LTBase Start Stack | 只部署起点 stack 后停止 | 需要（偶尔） |
| [`promote-prod.yml`](#promote-prodyml--promote-ltbase-between-stacks) | Promote LTBase Between Stacks | 手动执行一次相邻 promotion 跳转 | 需要（恢复用） |
| [`rollout-hop.yml`](#rollout-hopyml--rollout-ltbase-promotion-hop) | Rollout LTBase Promotion Hop | 上述工作流复用的单跳引擎 | 极少直接运行 |
| [`publish-oidc-discovery.yml`](#publish-oidc-discoveryyml--publish-oidc-discovery-documents) | Publish OIDC Discovery Documents | 手动恢复：重新发布 OIDC discovery 站点 | 很少（恢复） |
| [`build-infra-binary.yml`](#build-infra-binaryyml--build-infra-binary) | Build Infra Binary | 发布预构建 infra 二进制（仅上游） | 不需要 |
| [`test.yml`](#testyml--test) | Test | 运行仓库测试套件（仅上游） | 不需要 |

---

## `preview.yml` — Preview LTBase Blueprint

**做什么。** 在任何部署之前校验目标 stack。它会检查 `infra/Pulumi.<stack>.yaml` 是否包含必需的 `ltbase-infra:*` 配置键，以 dry-run 方式针对 stack schema bucket 校验 `customer-owned/schemas/*.json`（不上传任何内容），调用共享的 `preview-stack.yml` 生成 Pulumi diff，最后审计 Cloudflare / API Gateway 的 mTLS 配置。

**什么时候用。**
- 每个 stack 首次 rollout 之前。
- 每次修改 stack 配置、release 选择或其他部署输入时。先 preview，再 rollout。
- 确认 Pulumi diff 在你预期范围内。

**什么时候不该用。**
- 用于实际部署。preview 只做基础设施预览：它不执行 `pulumi up`，不发布 Control Plane UI，也不上传 schema。
- 用于预览后续 stack。手动 preview 只支持 `PROMOTION_PATH` 的第一个 stack；填其他值会直接失败。

**触发方式。** `workflow_dispatch`（手动）。

**输入参数。**

| 参数 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `target_stack` | 否 | string | `PROMOTION_PATH` 的第一个 stack | 要预览的 stack，必须是第一个 promotion stack。 |
| `release_id` | 否 | string | `vars.LTBASE_RELEASE_ID` | 要预览的官方 LTBase release tag。 |

**示例。**

```bash
# 使用仓库默认 release 预览第一个 promotion stack
gh workflow run preview.yml --ref main

# 显式指定第一个 stack，并覆盖 release
gh workflow run preview.yml -f target_stack=devo -f release_id=v1.0.23 --ref main
```

**使用到的配置。**
- Variables：`PROMOTION_PATH`（或 `STACKS`）、`LTBASE_RELEASE_ID`、`PULUMI_BACKEND_URL`、`AWS_REGION_<STACK>`、`PULUMI_SECRETS_PROVIDER_<STACK>`、`SCHEMA_BUCKET_<STACK>`、`LTBASE_RELEASES_REPO`、`STACKS`。
- Secrets：`AWS_ROLE_ARN_<STACK>`、`LTBASE_RELEASES_TOKEN`、`CLOUDFLARE_API_TOKEN`。

**注意事项。**
- mTLS 审计从 `infra/Pulumi.<stack>.yaml` 读取每个 stack 的值（`ltbase-infra:awsRegion`、`apiDomain`、`controlPlaneDomain`、`authDomain`、`runtimeBucket`、`cloudflareZoneId`）。该文件必须完整，否则审计失败。
- `CLOUDFLARE_API_TOKEN` 需要具备读取 zone settings 的权限，而不只是 DNS 记录，审计才能通过。

---

## `rollout.yml` — Rollout LTBase Release

**做什么。** 推荐的部署入口。它解析 `PROMOTION_PATH` 的第一个 stack，并以 `continue_chain: true` 调用 `rollout-hop.yml`，因此每一跳成功后会自动派发下一个 stack。受保护目标环境在部署前仍会停在 GitHub environment 审批。

**什么时候用。**
- 一次性把一个 release 部署到整条 promotion path。
- 常规升级：更新 `LTBASE_RELEASE_ID` → 运行 `preview.yml` → 运行 `rollout.yml`。

**什么时候不该用。**
- 只想部署第一个 stack 后停止时 —— 用 [`deploy-devo.yml`](#deploy-devoyml--deploy-ltbase-start-stack)。
- 只想补跑某一跳时 —— 用 [`promote-prod.yml`](#promote-prodyml--promote-ltbase-between-stacks)。
- 不要在 promotion path 中途切换 release ID；整条链路应保持同一个 release。

**触发方式。** `workflow_dispatch`（手动）。

**输入参数。**

| 参数 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `release_id` | 是 | string | — | 要在整条 promotion path 上部署的官方 LTBase release tag。 |

**示例。**

```bash
# 把 release v1.0.23 部署到整条 promotion path
gh workflow run rollout.yml -f release_id=v1.0.23 --ref main
```

**使用到的配置。**
- 通过 `secrets: inherit` 继承所有仓库 Variables 和 Secrets，并向下传给 `rollout-hop.yml`。完整清单见下方 `rollout-hop.yml`。

**注意事项。**
- 链路一次推进一跳。每个受保护 stack 在部署前都需要你审批对应的 GitHub environment gate。
- 发布 OIDC discovery 是自动的：`rollout-hop.yml` 每一跳都会在 rollout 之前（占位 key）和 rollout 之后（真实 KMS key）发布已部署的 promotion-path 前缀。[`publish-oidc-discovery.yml`](#publish-oidc-discoveryyml--publish-oidc-discovery-documents) 仅用于手动恢复。

---

## `deploy-devo.yml` — Deploy LTBase Start Stack

**做什么。** 只部署 `PROMOTION_PATH` 的第一个 stack 然后停止。它解析起点 stack，并以 `continue_chain: false` 调用 `rollout-hop.yml`，因此不会派发后续 hop。

**什么时候用。**
- 只想部署或重新部署起点 stack，不触发整条 promotion 链时。
- 首个环境的早期搭建或调试阶段。

**什么时候不该用。**
- 常规完整部署 —— 用 [`rollout.yml`](#rolloutyml--rollout-ltbase-release)。
- 部署非起点 stack。尽管文件名沿用了历史名 `devo`，它始终以 `PROMOTION_PATH` 的第一个 stack 为目标，而不是字面名为 `devo` 的 stack。

**触发方式。** `workflow_dispatch`（手动）。

**输入参数。**

| 参数 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `release_id` | 是 | string | — | 要部署到第一个 promotion stack 的官方 LTBase release tag。 |

**示例。**

```bash
# 仅用 release v1.0.23 部署起点 stack
gh workflow run deploy-devo.yml -f release_id=v1.0.23 --ref main
```

**使用到的配置。**
- 通过 `secrets: inherit` 继承所有仓库 Variables 和 Secrets，并传给 `rollout-hop.yml`。

**注意事项。**
- 工作流文件名属于历史遗留。实际目标是 `PROMOTION_PATH[0]`，无论它叫什么名字。

---

## `promote-prod.yml` — Promote LTBase Between Stacks

**做什么。** 只执行两个相邻 stack 之间的一次 promotion 跳转。它以你显式提供的 `from_stack`、`to_stack` 和 `continue_chain: false` 调用 `rollout-hop.yml`。`rollout-hop.yml` 会校验 `from_stack → to_stack` 是否是 `PROMOTION_PATH` 中相邻且向前的一跳，非法跳转会直接失败。

**什么时候用。**
- 恢复场景：某一跳部署成功但自动链路没有继续，你想再推进一跳。
- 只想从某个已验证 stack 推进到下一个相邻 stack。

**什么时候不该用。**
- 部署整条 path —— 用 [`rollout.yml`](#rolloutyml--rollout-ltbase-release)。
- 跨过中间环境。非相邻跳转（如跳过中间 stack）会立即失败。

**触发方式。** `workflow_dispatch`（手动）。

**输入参数。**

| 参数 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `release_id` | 是 | string | — | 要 promote 的官方 LTBase release tag。 |
| `from_stack` | 是 | string | — | `PROMOTION_PATH` 中当前已部署的 stack。 |
| `to_stack` | 是 | string | — | `PROMOTION_PATH` 中的下一个 stack（必须与 `from_stack` 相邻）。 |

**示例。**

```bash
# 用 release v1.0.23 从 devo promote 到 prod
gh workflow run promote-prod.yml \
  -f release_id=v1.0.23 \
  -f from_stack=devo \
  -f to_stack=prod \
  --ref main
```

**使用到的配置。**
- 通过 `secrets: inherit` 继承所有仓库 Variables 和 Secrets，并传给 `rollout-hop.yml`。

**注意事项。**
- 目标 stack 在部署前仍需要通过其 GitHub environment 审批。

---

## `rollout-hop.yml` — Rollout LTBase Promotion Hop

**做什么。** 上面每个 deploy/rollout/promote 工作流都委托给它的单跳部署引擎。对一个目标 stack，它会：校验 Pulumi stack 配置、在受保护 stack 上等待审批、渲染 Control Plane UI 运行时配置、在 rollout **之前**发布已部署 promotion-path 前缀的 OIDC discovery（尚未部署的 target 用占位 key，使 API Gateway 能创建 JWT authorizer）、调用共享的 `rollout-hop.yml`（执行 `pulumi up`、发布 control-plane UI、managed DSQL reconcile 与二次 apply）、在 rollout **之后**用真实 KMS key 重新发布该前缀的 OIDC discovery（并轮询确认占位 key 已被真实替换）、发布客户 schema、调用 control-plane 的 `ensure-project` apply、推进 applied schema 指针、审计 mTLS，并在 `continue_chain` 为 true 且 rollout 后的 discovery 发布成功时派发下一跳。

**什么时候用。**
- 一般不直接运行它；请用 `rollout.yml`、`deploy-devo.yml` 或 `promote-prod.yml`。
- 只有在高级恢复场景、需要精确控制单跳输入（包括 `continue_chain`）时才直接运行。

**什么时候不该用。**
- 常规部署。封装工作流会为你设置正确的输入。

**触发方式。** `workflow_call`（被其他工作流调用）和 `workflow_dispatch`（手动，高级用途）。

**输入参数。**

| 参数 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `release_id` | 是 | string | `vars.LTBASE_RELEASE_ID`（手动触发时） | 要部署的官方 LTBase release tag。 |
| `target_stack` | 是 | string | — | 本跳要部署的 stack。 |
| `from_stack` | 否 | string | `""` | 本跳之前的当前 stack；提供后本跳必须相邻且向前。 |
| `continue_chain` | 否 | boolean | `false` | 成功后是否自动派发下一跳。 |

**输出（被其他工作流调用时）。** `release_id`、`target_stack`、`next_stack`、`deployment_outputs_json`。

**示例。**

```bash
# 高级：手动执行一次到 prod 的单跳，并不继续链路
gh workflow run rollout-hop.yml \
  -f release_id=v1.0.23 \
  -f target_stack=prod \
  -f from_stack=devo \
  -f continue_chain=false \
  --ref main
```

**使用到的配置。**
- Variables：`LTBASE_RELEASE_ID`、`STACKS`、`PROMOTION_PATH`、`PULUMI_BACKEND_URL`、`AWS_REGION_<STACK>`、`PULUMI_SECRETS_PROVIDER_<STACK>`、`SCHEMA_BUCKET_<STACK>`、`LTBASE_RELEASES_REPO`、`CLOUDFLARE_ACCOUNT_ID`、`CONTROLPLANE_UI_PAGES_PROJECT`、`CONTROLPLANE_UI_STACK_CONFIG`。
- Secrets：`AWS_ROLE_ARN_<STACK>`、`LTBASE_RELEASES_TOKEN`、`CLOUDFLARE_API_TOKEN`。

**注意事项。**
- 除起点 stack 外的每个 stack 都需要审批（`approval_required=true`）；这些跳转还会运行 canary。
- schema 发布与 apply 是分离的：`schemas/published/manifest.json` 在发布时推进，`schemas/applied/manifest.json` 只在 `ensure-project` 成功后才推进。
- 当 `continue_chain=true` 且存在 `next_stack` 时，工作流会为下一跳派发自己。

---

## `publish-oidc-discovery.yml` — Publish OIDC Discovery Documents

**做什么。** 手动恢复 / 重新发布入口。为一个或多个 stack 生成 OIDC discovery 文档，并 direct upload 到 OIDC discovery Cloudflare Pages 项目。它与 `rollout-hop.yml` 中自动的 pre/post 发布 job 共用 `.github/actions/publish-oidc-discovery` composite action。

> 正常部署**不需要**这个工作流：`rollout-hop.yml` 会在每一跳自动发布 OIDC discovery。仅在自动发布失败后恢复，或需要强制刷新 key 时才使用它。

**什么时候用。**
- 自动发布失败后重新发布，或强制刷新某个 stack 的 key。
- 一次性刷新全部 stack。

**什么时候不该用。**
- 作为 rollout 之后的常规步骤 —— rollout hop 已自动发布 discovery。
- 从非默认分支触发。每个 stack 的 OIDC discovery IAM role 只信任默认分支，从其他分支触发会导致 role assumption 失败。

**触发方式。** `workflow_dispatch`（手动）。

**输入参数。**

| 参数 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `target_stack` | 否 | string | `all` | 要发布的 stack：`all` 或某个具体 stack 名称。 |
| `target_stacks` | 否 | string | `""` | 可选的 stack CSV（如 `devo,prod`）。设置后会覆盖 `target_stack`。 |

**示例。**

```bash
# 恢复：重新发布单个 stack
gh workflow run publish-oidc-discovery.yml -f target_stack=devo --ref main

# 恢复：刷新全部 stack
gh workflow run publish-oidc-discovery.yml -f target_stack=all --ref main

# 恢复：重新发布指定的 promotion-path 前缀
gh workflow run publish-oidc-discovery.yml -f target_stacks=devo,prod --ref main
```

**使用到的配置。**
- Variables：`OIDC_DISCOVERY_DOMAIN`、`OIDC_DISCOVERY_STACK_CONFIG`、`OIDC_DISCOVERY_PAGES_PROJECT`、`CLOUDFLARE_ACCOUNT_ID`。
- Secrets：`CLOUDFLARE_API_TOKEN`。

**注意事项。**
- 当某个 stack 的 authservice KMS key 还不存在时，工作流会**失败**：占位 JWKS 回退（`ALLOW_PLACEHOLDER`）仅供 `rollout-hop.yml` 中自动的 rollout 前发布使用。请在某个 stack 首次 rollout 创建其 key 之后再发布它。
- 当 `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID` 或 `OIDC_DISCOVERY_PAGES_PROJECT` 缺失时，工作流会明确报错。
- 它与 `rollout-hop.yml` 中自动的 rollout 前/后发布 job 共用一个仓库级 concurrency group，因此 discovery 发布不会互相重叠。

---

## `build-infra-binary.yml` — Build Infra Binary

**做什么。** 为 `linux-amd64` 和 `linux-arm64` 构建 `ltbase-infra` Pulumi 程序，然后把这些预构建二进制以及带 `build_fingerprint` 的 manifest 作为 release 发布到 `Lychee-Technology/ltbase-private-deployment-binaries`。

**什么时候用。**
- 你几乎不会运行它。它带有 `if: github.repository == 'Lychee-Technology/ltbase-private-deployment'` 守卫，在生成出来的客户部署仓库中会被跳过。
- 只有上游模板仓库发布预构建 infra 二进制；客户仓库只负责消费。

**什么时候不该用。**
- 在客户部署仓库中。它会被跳过。

**触发方式。** `workflow_dispatch`（手动）以及对 `main` 分支中 `infra/**` 或该工作流文件的 `push`。

**输入参数。** 无。

**使用到的配置。**
- Secrets：`LTBASE_PRIVATE_DEPLOYMENT_BINARIES_TOKEN`（仅存在于上游模板仓库）。

**注意事项。**
- 只有当同步下来的 `__ref__/template-provenance.json` 及其 `build_fingerprint` 与上游已发布 manifest 完全匹配时，客户工作流才会安装预构建二进制；否则 `infra/scripts/pulumi-wrapper.sh` 会回退到本地源码构建。

---

## `test.yml` — Test

**做什么。** 在确保 `jq` 和 `python3` 可用后，运行仓库的 shell 测试套件（`test/*-test.sh`）。

**什么时候用。**
- 它会在 `pull_request` 和对 `main` 的 `push` 时自动运行，也可手动触发。它带有 `if: github.repository == 'Lychee-Technology/ltbase-private-deployment'` 守卫，因此在客户部署仓库中会被跳过。

**什么时候不该用。**
- 在客户部署仓库中。它会被跳过。

**触发方式。** `workflow_dispatch`（手动）、`pull_request`，以及对 `main` 的 `push`。

**输入参数。** 无。

**使用到的配置。** 无（只读 checkout）。

**注意事项。**
- 当找不到任何 `test/*-test.sh` 文件或任一测试失败时，工作流失败。

---

## 参考文档

| 文档 | 用途 |
|------|------|
| [CUSTOMER_ONBOARDING.zh.md](CUSTOMER_ONBOARDING.zh.md) | 完整的从零部署指南 |
| [BOOTSTRAP.zh.md](BOOTSTRAP.zh.md) | 快速 bootstrap 清单 |
| [onboarding/04-prepare-env-file.zh.md](onboarding/04-prepare-env-file.zh.md) | `.env`、Variables 和 Secrets 参考 |
| [onboarding/07-first-deploy-and-managed-dsql.zh.md](onboarding/07-first-deploy-and-managed-dsql.zh.md) | 首次 preview/rollout 操作说明 |
| [onboarding/08-day-2-operations.zh.md](onboarding/08-day-2-operations.zh.md) | 日常运维与升级 |
