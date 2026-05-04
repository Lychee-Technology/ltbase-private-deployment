# Control Plane UI

> **[English](09-control-plane-ui.md)**

返回主文档：[`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)

## 目的

当客户管理员需要通过浏览器管理 stack 配置、schema 状态、安全策略、部署健康、修复操作和 referral code 时，可以使用 LTBase Control Plane UI。

UI 源码不存放在本部署模板中。它位于私有仓库：

- `Lychee-Technology/ltbase-controlplane-ui`

从模板生成的客户部署仓库应引用该 UI 仓库，或使用客户自己的 fork，并为自己的域名配置 Cloudflare Pages。

## Stack 模型

每个 stack 都是独立实例。`devo` 与 `prod` 拥有各自独立的 `auth`、`api`、`control-plane` hostname。UI 可以在一个 selector 中展示多个 stack，但不会假设它们之间存在 promotion、继承或同步关系。

## Cloudflare Pages 设置

1. 创建 Cloudflare Pages project，并连接到 `Lychee-Technology/ltbase-controlplane-ui` 或客户 fork。
2. 使用该 UI 仓库中的前端构建命令，目前为 `npm run build`。
3. 使用 `dist` 作为 Pages 输出目录。
4. 绑定客户管理员域名，例如 `admin.example.com`。
5. 将该 Pages 域名加入每个目标 stack 的 Control Plane CORS allowed origins。

UI 的静态构建产物不需要包含任何 secret。

## Runtime Config

UI 会在运行时加载 `/ltbase-controlplane.config.json`。当该文件只包含公开 URL 和 client ID 时，可以提交到仓库中。

示例：

```json
{
  "stacks": [
    {
      "key": "prod",
      "label": "Production",
      "authBaseUrl": "https://auth.example.com",
      "controlPlaneBaseUrl": "https://control-plane.example.com",
      "apiBaseUrl": "https://api.example.com",
      "oidcClientId": "ltbase-controlplane-ui",
      "redirectUri": "https://admin.example.com/auth/callback"
    }
  ]
}
```

不要在该文件中放入 client secret、Cloudflare API token、GitHub token、AWS credential 或 `.env` 值。

## AuthService 与 IdP 要求

每个 stack 都需要：

- 将 IdP redirect URL 配置为 UI callback URL
- 配置 authservice 接受 UI client ID
- 确保管理员拿到的 LTBase JWT 具备 Control Plane 管理员权限
- 确保 Control Plane API 的 CORS 允许 Pages origin

后端契约中，管理员权限由 JWT role IDs 中的 `role.admin` 或 permissions 中的 `controlplane.admin` 表示。

## 本地 JSON Schema 编辑

UI 可以提供可视化 JSON Schema editor，但它只能进行本地编辑。

允许的输出：

- 下载编辑后的 JSON Schema 文件
- 复制编辑后的 JSON 文本

UI 不允许：

- 将文件提交到 `customer-owned/schemas/`
- 发布 schema bundle
- 直接更新 Control Plane schema registry 记录
- 绕过 deployment workflow

下载或复制 schema 后，请将文件提交到 `customer-owned/schemas/`，再运行正常的 preview/rollout workflow。

## 操作检查

设置完成后：

1. 打开 UI Pages 域名
2. 通过配置好的 IdP 登录
3. 选择 stack
4. 确认 schema status 可以加载
5. 确认 Control Plane CORS 允许 Pages origin
6. 在执行任何写操作前，先运行只读 health check

## 返回主文档

返回 [`../CUSTOMER_ONBOARDING.zh.md`](../CUSTOMER_ONBOARDING.zh.md)。
