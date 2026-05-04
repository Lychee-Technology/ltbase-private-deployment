# Control Plane UI

> **[中文版](09-control-plane-ui.zh.md)**

Back to the main guide: [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md)

## Purpose

Use the LTBase Control Plane UI when customer administrators need a browser-based console for stack configuration, schema status review, security policy, deployment health, repair operations, and referral management.

The UI source is not stored in this deployment template. It lives in the private repository:

- `Lychee-Technology/ltbase-controlplane-ui`

Generated customer deployment repositories should reference that UI repository and configure Cloudflare Pages for their own domain.

## Stack Model

Each stack is independent. A `devo` stack and a `prod` stack have separate `auth`, `api`, and `control-plane` hostnames. The UI may show multiple stacks in one selector, but it does not assume promotion, inheritance, or synchronization between them.

## Cloudflare Pages Setup

1. Create a Cloudflare Pages project connected to `Lychee-Technology/ltbase-controlplane-ui` or to the customer-owned fork of that repository.
2. Use the frontend build command from that repository, currently `npm run build`.
3. Use `dist` as the Pages output directory.
4. Bind the customer admin hostname, for example `admin.example.com`.
5. Add the Pages hostname to the Control Plane CORS allowed origins for each stack it should manage.

The UI does not require secrets in the static build output.

## Runtime Config

The UI loads `/ltbase-controlplane.config.json` at runtime. This file may be committed when it contains only public URLs and client IDs.

Example:

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

Do not put client secrets, Cloudflare API tokens, GitHub tokens, AWS credentials, or `.env` values in this file.

## AuthService And IdP Requirements

For each stack:

- configure the IdP redirect URL to match the UI callback URL
- configure authservice to accept the UI client ID
- make sure administrators receive LTBase JWTs with Control Plane administrator authorization
- ensure the Control Plane API accepts the Pages origin through CORS

The backend contract expects administrator access to be represented by either `role.admin` in role IDs or `controlplane.admin` in permissions.

## Local JSON Schema Editing

The UI may include a visual JSON Schema editor, but it is local-only.

Allowed outputs:

- download the edited JSON Schema file
- copy the edited JSON text

Not allowed from the UI:

- committing files into `customer-owned/schemas/`
- publishing schema bundles
- directly updating Control Plane schema registry records
- bypassing the deployment workflow

After downloading or copying a schema, commit it to `customer-owned/schemas/` and run the normal preview/rollout workflow.

## Operational Check

After setup:

1. open the UI Pages domain
2. sign in through the configured IdP
3. select a stack
4. confirm schema status loads
5. confirm Control Plane CORS allows the Pages origin
6. run a read-only health check before attempting any write operation

## Back to Onboarding

Return to [`../CUSTOMER_ONBOARDING.md`](../CUSTOMER_ONBOARDING.md).
