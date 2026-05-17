# Control Plane UI Companion Design

## Summary

Add a customer-facing Control Plane UI companion deployment path to `ltbase-private-deployment` and integrate `ltbase-controlplane-ui` as a Cloudflare Pages app for private LTBase deployments.

V1 must support two external identity providers for administrator login:

- Firebase Google Sign-In
- Supabase Google OAuth

The UI will not implement a standalone OAuth authorization server flow. Instead, it will reuse the existing LTBase authservice exchange model:

1. browser authenticates with an external provider
2. UI obtains the provider-issued JWT
3. UI calls `POST {authBaseUrl}/api/v1/login/{provider}` with `Authorization: Bearer <external_jwt>` and `{ "project_id": "..." }`
4. authservice returns LTBase access and refresh tokens
5. UI uses LTBase access token for Control Plane API calls

This keeps `ltbase.api` generic and aligns the browser UI with the authservice contract that already exists today.

## Goals

- Deploy `ltbase-controlplane-ui` as a customer-owned companion site in private deployments.
- Support both Firebase and Supabase as external admin login providers in V1.
- Reuse the existing authservice login contract rather than adding a new `/oauth/authorize` flow.
- Generate non-secret runtime configuration for the UI per deployment stack.
- Wire deployment-managed CORS so browser calls to authservice and control plane work from the UI origin.
- Keep clear boundaries between product source, deployment template, and testing tools.

## Non-Goals

- Adding a new generic OAuth authorization server flow to `ltbase.api`.
- Supporting email/password, magic link, or non-Google Supabase login in V1.
- Making `ltbase.webtester` a runtime dependency of the production UI.
- Bundling the control plane UI artifact into LTBase release assets for V1.
- Generalizing this work into reusable deployment workflows before the deployment-template path is proven.

## Repositories and Ownership

This work is intentionally cross-repo.

### `ltbase-private-deployment`

Owns:

- customer-facing bootstrap flow for the companion UI repository
- Cloudflare Pages project creation and custom domain wiring
- generated runtime config values
- deployment docs and onboarding docs
- per-stack environment and config contract for provider settings
- control plane CORS origin wiring through deployment-managed infra

### `ltbase-controlplane-ui`

Owns:

- browser login UX
- provider-specific external token acquisition
- LTBase token exchange and refresh logic
- local session persistence and logout behavior
- runtime config parsing and validation

### `ltbase.api`

Owns only server-side gaps if the browser flow proves blocked by existing behavior, such as:

- authservice response/cors issues that prevent browser exchange or refresh
- control plane CORS restrictions that must be tightened or corrected

It does not own frontend assets or deployment bootstrap logic.

### `ltbase.webtester`

Acts as a reference implementation for Firebase-based browser login and LTBase token exchange. It is not a production dependency and should not be imported by the control plane UI.

## Current State

### Existing control plane UI assumptions

`ltbase-controlplane-ui` currently loads `/ltbase-controlplane.config.json` with fields including:

- `authBaseUrl`
- `controlPlaneBaseUrl`
- `apiBaseUrl`
- `oidcClientId`
- `redirectUri`

Its current auth flow assumes:

- browser redirect to `${authBaseUrl}/oauth/authorize`
- callback with `code`
- token exchange via `POST ${authBaseUrl}/api/v1/login/oidc`

That flow does not match the currently deployed LTBase authservice contract.

### Existing authservice contract

`ltbase.api` authservice currently exposes provider-scoped login routes such as:

- `POST /api/v1/login/firebase`
- `POST /api/v1/login/supabase`
- `POST /api/v1/id_bindings/firebase`
- `POST /api/v1/id_bindings/supabase`
- `POST /api/v1/auth/refresh`

These routes expect the external provider JWT in the `Authorization` header and `project_id` in the JSON body.

### Existing deployment template pattern

`ltbase-private-deployment` already bootstraps an OIDC discovery companion repository and its Cloudflare Pages project. That companion pattern is the correct V1 template for the control plane UI companion as well.

## V1 Architecture

### High-level flow

1. operator bootstraps private deployment repository
2. bootstrap also creates or syncs a customer-owned control plane UI companion repository
3. bootstrap ensures a Cloudflare Pages project and custom domain for that repo
4. deployment-managed configuration publishes `/ltbase-controlplane.config.json`
5. administrator opens the UI
6. administrator selects stack and login provider
7. UI authenticates with Firebase Google Sign-In or Supabase Google OAuth
8. UI receives provider JWT from the browser SDK/session
9. UI exchanges provider JWT for LTBase JWT through authservice
10. UI calls control plane endpoints with LTBase JWT

### Why this architecture

- It matches the server contract that exists now.
- It avoids inventing a second browser auth model.
- It keeps provider-specific browser logic in the frontend, where those SDKs already belong.
- It uses the same companion deployment shape already proven by OIDC discovery.

## Runtime Config Contract

Replace the current single-provider OIDC-oriented runtime config shape with a multi-provider stack config.

### V1 runtime config

```json
{
  "stacks": [
    {
      "key": "prod",
      "label": "Production",
      "projectId": "11111111-1111-4111-8111-111111111111",
      "authBaseUrl": "https://auth.example.com",
      "controlPlaneBaseUrl": "https://control.example.com",
      "apiBaseUrl": "https://api.example.com",
      "authProviders": [
        {
          "type": "firebase",
          "name": "firebase",
          "label": "Google via Firebase",
          "firebaseApiKey": "public-firebase-api-key",
          "firebaseProjectId": "firebase-project-id"
        },
        {
          "type": "supabase",
          "name": "supabase",
          "label": "Google via Supabase",
          "supabaseUrl": "https://project.supabase.co",
          "supabaseAnonKey": "public-anon-key"
        }
      ]
    }
  ]
}
```

### Field semantics

- `projectId`: LTBase project scope sent to authservice during login exchange
- `authProviders[].type`: frontend provider implementation selector
- `authProviders[].name`: LTBase authservice route suffix and expected provider record name, such as `firebase` or `supabase`
- `firebaseApiKey`, `firebaseProjectId`, `supabaseUrl`, `supabaseAnonKey`: public browser values only

### Validation rules

- every stack must have at least one auth provider
- provider names must be unique within a stack
- provider names must match deployment-managed auth provider config names
- firebase config fields are required only for `type=firebase`
- supabase config fields are required only for `type=supabase`

## Frontend Design

### Auth model

The control plane UI will implement a provider abstraction with one shared LTBase exchange path.

Conceptually:

```ts
type ExternalAuthProvider = {
  type: 'firebase' | 'supabase'
  name: string
  label: string
  signIn(): Promise<{ externalToken: string; subjectLabel?: string }>
  signOut(): Promise<void>
}
```

The shared LTBase exchange logic will:

1. call `signIn()` on the selected provider
2. receive the external JWT
3. call `POST {authBaseUrl}/api/v1/login/{provider.name}`
4. persist LTBase `access_token` and `refresh_token`
5. create the control plane client from the LTBase token

### Firebase login path

The Firebase path should mirror the proven `ltbase.webtester` flow:

- initialize Firebase app from runtime config
- use Google Sign-In popup
- get fresh Firebase ID token from the signed-in user
- exchange that token with authservice using `/api/v1/login/firebase`

### Supabase login path

The Supabase path supports only Google OAuth in V1:

- initialize Supabase browser client from runtime config
- start Google OAuth through Supabase
- restore session after redirect or popup completion
- read `session.access_token`
- exchange that token with authservice using `/api/v1/login/supabase`

### LTBase token storage

The UI stores LTBase session state locally:

- access token
- refresh token
- selected stack key
- selected provider name
- optional display identity label

External provider session state remains owned by the provider SDK.

### Logout behavior

Logout clears LTBase local session and triggers provider logout for the active provider when possible.

### UI behavior

V1 login screen should include:

- stack selector
- available provider buttons for the selected stack
- current signed-in identity label when available
- LTBase exchange/loading/error state
- explicit logout

This replaces the current fake `Login` link generated from `oidcClientId` and `redirectUri`.

## Deployment Design

### Companion repository bootstrap

`ltbase-private-deployment` will add a second companion bootstrap path modeled after `bootstrap-oidc-discovery-companion.sh`.

Responsibilities:

- create or sync a customer-owned `*-controlplane-ui` repo from an approved template source
- create a Cloudflare Pages project
- bind a custom domain
- create the required DNS CNAME
- set GitHub repo variables and secrets needed for publish

### Domain model

Recommended V1 convention:

- `admin.<customer-domain>` for the production UI
- optional stack-qualified admin subdomain for non-prod if needed later

V1 should prefer one UI site per deployment that can switch between stacks at runtime, rather than one site per stack.

### Runtime config publication

The companion repo publish workflow should emit `/ltbase-controlplane.config.json` from deployment-managed variables. This keeps provider settings public and editable through deployment bootstrap rather than hardcoding values in `ltbase-controlplane-ui`.

### Deployment-managed inputs

`env.template` and bootstrap docs will need public config values such as:

- control plane UI domain
- control plane UI repo name and Pages project name overrides
- Firebase API key and project ID
- Supabase URL and anon key
- per-stack enabled provider list if different by stack

### Pulumi wiring

`ltbase-private-deployment` infra must set `CONTROL_PLANE_CORS_ORIGINS` for the control plane Lambda environment to the UI origin rather than depending on request-origin echo behavior.

If authservice does not already behave correctly for browser CORS, deployment work may also need to set authservice CORS origins through a corresponding server-side capability. That is a verification item, not a committed V1 backend change.

## Auth Provider Contract Alignment

The deployment repository already owns `infra/auth-providers.<stack>.json`.

For V1, if a stack enables browser login through Firebase and Supabase, the matching provider config file must contain provider entries with names exactly equal to:

- `firebase`
- `supabase`

The UI runtime config `authProviders[].name` must match those names exactly. This keeps the browser config, authservice route, and deployment-owned auth provider records aligned.

## Error Handling

### Browser login errors

The UI must show actionable messages for:

- provider popup blocked or canceled
- provider redirect return with no active session
- missing provider configuration
- authservice login failure
- `identity_unbound`
- `project_not_configured`
- expired LTBase access token with refresh failure

### Identity binding

V1 does not add browser-first identity binding UX unless needed to complete admin onboarding. If administrators are expected to be pre-bound before using the UI, docs must say so clearly.

If a first-login admin binding flow is required later, it should reuse the same provider token acquisition path and call the existing `/api/v1/id_bindings/{provider}` endpoint.

## Security Notes

- runtime config contains only public browser-safe values
- Firebase API key and Supabase anon key are public by design
- LTBase access and refresh tokens are sensitive and must only live in browser storage controlled by the UI
- provider JWTs should not be persisted longer than required for exchange
- control plane API access remains gated by LTBase role and permission checks, specifically `role.admin` or `controlplane.admin`

## Dependencies

V1 should use standard npm dependencies inside `ltbase-controlplane-ui` rather than CDN globals.

Expected additions:

- `firebase`
- `@supabase/supabase-js`

This is the correct fit for a Vite/React app because it preserves typechecking, testability, and build consistency.

## Testing Strategy

### `ltbase-controlplane-ui`

- runtime config parsing tests for multi-provider stack config
- provider-specific auth helper tests for Firebase and Supabase paths
- LTBase exchange tests for provider-specific login route selection
- session persistence tests
- login state rendering tests

### `ltbase-private-deployment`

- bootstrap script tests for control plane UI companion creation and sync
- config rendering tests for generated runtime config JSON
- stack config validation tests for required public provider values
- infra tests for Lambda env wiring, including `CONTROL_PLANE_CORS_ORIGINS`

### End-to-end verification

Manual V1 verification should cover:

- Firebase Google login -> LTBase exchange -> Control Plane API success
- Supabase Google login -> LTBase exchange -> Control Plane API success
- unbound user failure mode
- wrong project/provider config failure mode
- refresh flow after LTBase token expiry

## Alternatives Considered

### Option 1: manual external JWT input

The UI could ask operators to paste a Firebase or Supabase token and then exchange it.

Why not chosen:

- poor operator experience
- duplicates work already solved by browser SDKs
- not appropriate for a customer-facing admin UI

### Option 2: continue with generic OIDC redirect config

The UI could keep `oidcClientId` and `redirectUri` and expect LTBase authservice to behave as an OIDC authorization server.

Why not chosen:

- does not match current backend behavior
- would require substantial backend scope expansion
- unnecessary for V1

### Option 3: import or embed `ltbase.webtester`

The UI could directly depend on `ltbase.webtester` logic or load it as a helper app.

Why not chosen:

- wrong ownership boundary
- test tool should not become product runtime dependency
- React/Vite app should own its own typed auth integration

## Risks and Follow-ups

- authservice browser CORS behavior may still require backend changes once verified against a real Pages origin
- Supabase Google OAuth callback handling must fit the deployed custom domain exactly
- deployment docs must clearly state that provider names in runtime config and `auth-providers.<stack>.json` are coupled
- if customers require more providers later, the provider abstraction should extend without changing the LTBase exchange contract

## Implementation Order

1. update `ltbase-controlplane-ui` runtime config model and login UX for multi-provider auth
2. implement Firebase and Supabase provider adapters plus shared LTBase exchange logic
3. verify browser exchange and refresh against deployed authservice
4. add control plane UI companion bootstrap and runtime config generation in `ltbase-private-deployment`
5. wire strict control plane CORS origin configuration in deployment infra
6. update onboarding and day-2 docs

## Success Criteria

- a private deployment can bootstrap a customer-owned control plane UI companion repo and Cloudflare Pages site
- the UI can log in administrators through Firebase Google Sign-In or Supabase Google OAuth
- the UI exchanges provider JWTs through the existing LTBase authservice routes without adding a new server auth flow
- the UI can call control plane APIs successfully from the deployed browser origin
- deployment docs explain required public config and provider-name alignment clearly
