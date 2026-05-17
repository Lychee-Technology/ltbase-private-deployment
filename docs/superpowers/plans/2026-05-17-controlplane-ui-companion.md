# Control Plane UI Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a customer-facing control plane UI companion for private LTBase deployments and enable browser login through Firebase Google Sign-In and Supabase Google OAuth using the existing LTBase authservice exchange model.

**Architecture:** Split the work along existing repo boundaries. `ltbase-controlplane-ui` owns the browser runtime config, provider adapters, login UX, and LTBase token exchange; `ltbase-private-deployment` owns companion bootstrap, Cloudflare Pages wiring, generated runtime config, deployment validation, docs, and control-plane CORS env wiring. Keep `ltbase.api` out of scope unless browser verification reveals authservice or control-plane CORS gaps that block the deployed flow.

**Tech Stack:** React 19, TypeScript, Vite, Vitest, Firebase JS SDK, Supabase JS SDK, Bash, GitHub Actions, Cloudflare Pages, Go, Pulumi Go SDK

---

### Task 1: Convert `ltbase-controlplane-ui` Runtime Config To Multi-Provider Stack Config

**Files:**
- Modify: `ltbase-controlplane-ui/src/types.ts`
- Modify: `ltbase-controlplane-ui/src/config.ts`
- Modify: `ltbase-controlplane-ui/src/config.test.ts`
- Modify: `ltbase-controlplane-ui/public/ltbase-controlplane.config.json`

- [ ] **Step 1: Write failing runtime config tests for provider-aware stack config**

Add tests like these to `ltbase-controlplane-ui/src/config.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { parseRuntimeConfig } from './config';

describe('parseRuntimeConfig', () => {
  it('accepts firebase and supabase providers', () => {
    const config = parseRuntimeConfig({
      stacks: [
        {
          key: 'prod',
          label: 'Production',
          projectId: '11111111-1111-4111-8111-111111111111',
          authBaseUrl: 'https://auth.example.com/',
          controlPlaneBaseUrl: 'https://control.example.com/',
          apiBaseUrl: 'https://api.example.com/',
          authProviders: [
            {
              type: 'firebase',
              name: 'firebase',
              label: 'Google via Firebase',
              firebaseApiKey: 'public-key',
              firebaseProjectId: 'firebase-project',
            },
            {
              type: 'supabase',
              name: 'supabase',
              label: 'Google via Supabase',
              supabaseUrl: 'https://project.supabase.co',
              supabaseAnonKey: 'anon-key',
            },
          ],
        },
      ],
    });

    expect(config.stacks[0]?.projectId).toBe('11111111-1111-4111-8111-111111111111');
    expect(config.stacks[0]?.authBaseUrl).toBe('https://auth.example.com');
    expect(config.stacks[0]?.authProviders).toHaveLength(2);
  });

  it('rejects duplicate provider names within a stack', () => {
    expect(() =>
      parseRuntimeConfig({
        stacks: [
          {
            key: 'prod',
            label: 'Production',
            projectId: '11111111-1111-4111-8111-111111111111',
            authBaseUrl: 'https://auth.example.com',
            controlPlaneBaseUrl: 'https://control.example.com',
            apiBaseUrl: 'https://api.example.com',
            authProviders: [
              {
                type: 'firebase',
                name: 'firebase',
                label: 'Google via Firebase',
                firebaseApiKey: 'public-key',
                firebaseProjectId: 'firebase-project',
              },
              {
                type: 'firebase',
                name: 'firebase',
                label: 'Duplicate Firebase',
                firebaseApiKey: 'public-key-2',
                firebaseProjectId: 'firebase-project-2',
              },
            ],
          },
        ],
      }),
    ).toThrow('duplicate auth provider name: firebase');
  });
});
```

- [ ] **Step 2: Run the focused config test and confirm it fails**

Run: `npm test -- --run src/config.test.ts`
Expected: FAIL because `projectId` and `authProviders` are not part of the current runtime config parser.

- [ ] **Step 3: Update the runtime config types and parser minimally**

Use a shape like this in `ltbase-controlplane-ui/src/types.ts`:

```ts
export type AuthProviderConfig = FirebaseAuthProviderConfig | SupabaseAuthProviderConfig;

export interface RuntimeConfig {
  stacks: StackConfig[];
}

export interface StackConfig {
  key: string;
  label: string;
  projectId: string;
  authBaseUrl: string;
  controlPlaneBaseUrl: string;
  apiBaseUrl: string;
  authProviders: AuthProviderConfig[];
}

export interface FirebaseAuthProviderConfig {
  type: 'firebase';
  name: string;
  label: string;
  firebaseApiKey: string;
  firebaseProjectId: string;
}

export interface SupabaseAuthProviderConfig {
  type: 'supabase';
  name: string;
  label: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
}
```

Update `ltbase-controlplane-ui/src/config.ts` to require `projectId`, parse `authProviders`, and validate provider-name uniqueness with provider-type-specific required fields.

- [ ] **Step 4: Replace the sample public runtime config with a multi-provider example**

Update `ltbase-controlplane-ui/public/ltbase-controlplane.config.json` to a browser-safe example:

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

- [ ] **Step 5: Re-run the focused config test and verify it passes**

Run: `npm test -- --run src/config.test.ts`
Expected: PASS.

- [ ] **Step 6: Commit the runtime config slice**

```bash
git add src/types.ts src/config.ts src/config.test.ts public/ltbase-controlplane.config.json
git commit -m "feat: add multi-provider control plane runtime config"
```

### Task 2: Add Firebase And Supabase External Auth Adapters Plus Shared LTBase Exchange

**Files:**
- Modify: `ltbase-controlplane-ui/package.json`
- Create: `ltbase-controlplane-ui/src/auth/providers.ts`
- Create: `ltbase-controlplane-ui/src/auth/firebaseAuth.ts`
- Create: `ltbase-controlplane-ui/src/auth/supabaseAuth.ts`
- Modify: `ltbase-controlplane-ui/src/auth/auth.ts`
- Create: `ltbase-controlplane-ui/src/auth/auth.test.ts`

- [ ] **Step 1: Add failing auth tests for provider-specific login route selection and project-aware exchange**

Create `ltbase-controlplane-ui/src/auth/auth.test.ts` with focused tests like:

```ts
import { describe, expect, it, vi } from 'vitest';
import { exchangeExternalToken } from './auth';

const stack = {
  key: 'prod',
  label: 'Production',
  projectId: '11111111-1111-4111-8111-111111111111',
  authBaseUrl: 'https://auth.example.com',
  controlPlaneBaseUrl: 'https://control.example.com',
  apiBaseUrl: 'https://api.example.com',
  authProviders: [],
};

describe('exchangeExternalToken', () => {
  it('posts provider jwt to the provider-specific LTBase login route', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: 'ltbase-access', refresh_token: 'ltbase-refresh' }),
    });

    await exchangeExternalToken(stack, 'firebase', 'provider-jwt', fetchImpl as unknown as typeof fetch);

    expect(fetchImpl).toHaveBeenCalledWith('https://auth.example.com/api/v1/login/firebase', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer provider-jwt',
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ project_id: '11111111-1111-4111-8111-111111111111' }),
    });
  });
});
```

- [ ] **Step 2: Run the focused auth test and confirm it fails**

Run: `npm test -- --run src/auth/auth.test.ts`
Expected: FAIL because `exchangeExternalToken` and provider-aware auth helpers do not exist.

- [ ] **Step 3: Add the browser SDK dependencies**

Update `ltbase-controlplane-ui/package.json` dependencies to include:

```json
{
  "dependencies": {
    "@supabase/supabase-js": "^2.49.8",
    "firebase": "^11.7.1"
  }
}
```

Keep existing dependencies unchanged.

- [ ] **Step 4: Add provider-specific auth adapter modules**

Create `ltbase-controlplane-ui/src/auth/providers.ts`:

```ts
export interface ExternalAuthResult {
  externalToken: string;
  subjectLabel?: string;
}

export interface ExternalAuthProvider {
  signIn(): Promise<ExternalAuthResult>;
  signOut(): Promise<void>;
}
```

Create `ltbase-controlplane-ui/src/auth/firebaseAuth.ts` with a `createFirebaseAuthProvider(config)` helper that initializes Firebase, runs Google popup login, and returns `user.getIdToken(true)`.

Create `ltbase-controlplane-ui/src/auth/supabaseAuth.ts` with a `createSupabaseAuthProvider(config)` helper that initializes Supabase, starts Google OAuth, restores a session, and returns `session.access_token`.

- [ ] **Step 5: Replace the old fake OIDC helper with shared LTBase exchange and refresh helpers**

Update `ltbase-controlplane-ui/src/auth/auth.ts` to expose helpers like:

```ts
export async function exchangeExternalToken(
  stack: StackConfig,
  providerName: string,
  externalToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<SessionState> {
  const response = await fetchImpl(`${stack.authBaseUrl}/api/v1/login/${providerName}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${externalToken}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({ project_id: stack.projectId }),
  });
  if (!response.ok) {
    throw new Error(`token exchange failed: ${response.status}`);
  }
  const body = (await response.json()) as Record<string, unknown>;
  if (typeof body.access_token !== 'string') {
    throw new Error('token exchange response missing access_token');
  }
  return {
    accessToken: body.access_token,
    refreshToken: typeof body.refresh_token === 'string' ? body.refresh_token : undefined,
  };
}
```

Remove the obsolete `buildLoginURL()` and callback-code parsing behavior.

- [ ] **Step 6: Re-run the auth test and basic config test**

Run: `npm test -- --run src/auth/auth.test.ts src/config.test.ts`
Expected: PASS.

- [ ] **Step 7: Commit the auth adapter slice**

```bash
git add package.json package-lock.json src/auth/providers.ts src/auth/firebaseAuth.ts src/auth/supabaseAuth.ts src/auth/auth.ts src/auth/auth.test.ts
git commit -m "feat: add firebase and supabase token exchange for control plane ui"
```

### Task 3: Replace The Old Login UX In `ltbase-controlplane-ui` With Multi-Provider Browser Login

**Files:**
- Modify: `ltbase-controlplane-ui/src/App.tsx`
- Create: `ltbase-controlplane-ui/src/auth/session.ts`
- Create: `ltbase-controlplane-ui/src/App.test.tsx`
- Modify: `ltbase-controlplane-ui/src/test/setup.ts`

- [ ] **Step 1: Add a failing UI test for stack-aware provider buttons and LTBase login state**

Create `ltbase-controlplane-ui/src/App.test.tsx` with a test like:

```tsx
import { render, screen } from '@testing-library/react';
import App from './App';

vi.mock('./config', () => ({
  loadRuntimeConfig: async () => ({
    stacks: [
      {
        key: 'prod',
        label: 'Production',
        projectId: '11111111-1111-4111-8111-111111111111',
        authBaseUrl: 'https://auth.example.com',
        controlPlaneBaseUrl: 'https://control.example.com',
        apiBaseUrl: 'https://api.example.com',
        authProviders: [
          {
            type: 'firebase',
            name: 'firebase',
            label: 'Google via Firebase',
            firebaseApiKey: 'public-key',
            firebaseProjectId: 'firebase-project',
          },
        ],
      },
    ],
  }),
}));

it('renders provider login buttons from runtime config', async () => {
  render(<App />);
  expect(await screen.findByRole('button', { name: 'Google via Firebase' })).toBeInTheDocument();
});
```

- [ ] **Step 2: Run the focused app test and confirm it fails**

Run: `npm test -- --run src/App.test.tsx`
Expected: FAIL because the app still renders the old single `Login` link and local token button.

- [ ] **Step 3: Add a small session storage helper**

Create `ltbase-controlplane-ui/src/auth/session.ts` with helpers like:

```ts
import type { SessionState } from '../types';

const SESSION_KEY = 'ltbase-controlplane-session';

export function loadSavedSession(storage: Storage): SessionState | null {
  const raw = storage.getItem(SESSION_KEY);
  if (!raw) return null;
  return JSON.parse(raw) as SessionState;
}

export function saveSession(storage: Storage, session: SessionState): void {
  storage.setItem(SESSION_KEY, JSON.stringify(session));
}

export function clearSession(storage: Storage): void {
  storage.removeItem(SESSION_KEY);
}
```

- [ ] **Step 4: Update `App.tsx` to use provider buttons and shared LTBase exchange**

Replace the old topbar login controls with:

```tsx
{selectedStack && !session && selectedStack.authProviders.map((provider) => (
  <button
    key={provider.name}
    className="button ghost"
    type="button"
    onClick={() => handleProviderLogin(provider)}
  >
    {provider.label}
  </button>
))}
{session && (
  <button className="button ghost" type="button" onClick={handleLogout}>
    Logout
  </button>
)}
```

Add `handleProviderLogin()` that:

- builds the provider adapter from runtime config
- obtains the external token
- calls `exchangeExternalToken()`
- saves LTBase session to local storage
- updates status text

Remove the old fake `buildLoginURL()` link and the `Local token` debug button.

- [ ] **Step 5: Re-run UI tests and core checks**

Run:

- `npm test -- --run src/App.test.tsx src/auth/auth.test.ts src/config.test.ts`
- `npm run typecheck`
- `npm run build`

Expected: all commands PASS.

- [ ] **Step 6: Commit the UI login slice**

```bash
git add src/App.tsx src/App.test.tsx src/auth/session.ts src/test/setup.ts
git commit -m "feat: add multi-provider control plane browser login"
```

### Task 4: Add Control Plane UI Companion Bootstrap And Runtime Config Generation To `ltbase-private-deployment`

**Files:**
- Modify: `ltbase-private-deployment/env.template`
- Modify: `ltbase-private-deployment/scripts/lib/bootstrap-env.sh`
- Modify: `ltbase-private-deployment/scripts/bootstrap-all.sh`
- Create: `ltbase-private-deployment/scripts/bootstrap-controlplane-ui-companion.sh`
- Create: `ltbase-private-deployment/test/bootstrap-controlplane-ui-companion-test.sh`
- Modify: `ltbase-private-deployment/README.md`

- [ ] **Step 1: Add a failing shell test for the new companion bootstrap script**

Create `ltbase-private-deployment/test/bootstrap-controlplane-ui-companion-test.sh` by mirroring the OIDC companion test style. Require log assertions for:

```bash
assert_log_contains "${log_file}" "gh repo create customer-org/customer-ltbase-controlplane-ui"
assert_log_contains "${log_file}" "gh variable set CONTROLPLANE_UI_DOMAIN --repo customer-org/customer-ltbase-controlplane-ui"
assert_log_contains "${log_file}" "gh variable set CONTROLPLANE_UI_STACK_CONFIG --repo customer-org/customer-ltbase-controlplane-ui"
assert_log_contains "${log_file}" "https://api.cloudflare.com/client/v4/accounts/cf-account-123/pages/projects"
```

- [ ] **Step 2: Run the new shell test and confirm it fails**

Run: `bash test/bootstrap-controlplane-ui-companion-test.sh`
Expected: FAIL because the script does not exist yet.

- [ ] **Step 3: Add the new public config inputs and derivations**

Update `ltbase-private-deployment/env.template` with public values like:

```dotenv
CONTROLPLANE_UI_DOMAIN=admin.customer.example.com

# Optional overrides for the companion repo bootstrap.
# CONTROLPLANE_UI_TEMPLATE_REPO=Lychee-Technology/ltbase-controlplane-ui
# CONTROLPLANE_UI_REPO_NAME=customer-ltbase-controlplane-ui
# CONTROLPLANE_UI_REPO=customer-org/customer-ltbase-controlplane-ui
# CONTROLPLANE_UI_PAGES_PROJECT=customer-ltbase-controlplane-ui
# FIREBASE_API_KEY_DEVO=public-firebase-api-key
# FIREBASE_PROJECT_ID_DEVO=firebase-project-id
# SUPABASE_URL_DEVO=https://project.supabase.co
# SUPABASE_ANON_KEY_DEVO=public-anon-key
```

Update `ltbase-private-deployment/scripts/lib/bootstrap-env.sh` to derive repo/project defaults the same way it already derives OIDC companion defaults.

- [ ] **Step 4: Implement the new companion bootstrap script**

Create `ltbase-private-deployment/scripts/bootstrap-controlplane-ui-companion.sh` by adapting the structure of `bootstrap-oidc-discovery-companion.sh`.

The script must:

- load bootstrap env
- require companion repo, Pages, Cloudflare, and provider config vars
- clone or create the customer-owned control plane UI repo
- create the Pages project and custom domain
- ensure DNS CNAME to `${CONTROLPLANE_UI_PAGES_PROJECT}.pages.dev`
- generate and set a repo variable that contains per-stack runtime config JSON

Use a helper payload shape like:

```json
{
  "stacks": [
    {
      "key": "devo",
      "label": "Devo",
      "projectId": "11111111-1111-4111-8111-111111111111",
      "authBaseUrl": "https://auth.devo.customer.example.com",
      "controlPlaneBaseUrl": "https://control.devo.customer.example.com",
      "apiBaseUrl": "https://api.devo.customer.example.com",
      "authProviders": [
        {
          "type": "firebase",
          "name": "firebase",
          "label": "Google via Firebase",
          "firebaseApiKey": "public-key",
          "firebaseProjectId": "firebase-project"
        },
        {
          "type": "supabase",
          "name": "supabase",
          "label": "Google via Supabase",
          "supabaseUrl": "https://project.supabase.co",
          "supabaseAnonKey": "anon-key"
        }
      ]
    }
  ]
}
```

Update `ltbase-private-deployment/scripts/bootstrap-all.sh` to call the new script after OIDC discovery companion bootstrap.

- [ ] **Step 5: Re-run the new shell test and a neighboring bootstrap test**

Run:

- `bash test/bootstrap-controlplane-ui-companion-test.sh`
- `bash test/bootstrap-all-test.sh`

Expected: PASS.

- [ ] **Step 6: Commit the companion bootstrap slice**

```bash
git add env.template scripts/lib/bootstrap-env.sh scripts/bootstrap-all.sh scripts/bootstrap-controlplane-ui-companion.sh test/bootstrap-controlplane-ui-companion-test.sh README.md
git commit -m "feat: bootstrap control plane ui companion repo"
```

### Task 5: Wire Deployment Validation, Control-Plane CORS Env, And Docs In `ltbase-private-deployment`

**Files:**
- Modify: `ltbase-private-deployment/scripts/check-pulumi-stack-config.sh`
- Modify: `ltbase-private-deployment/scripts/bootstrap-deployment-repo.sh`
- Modify: `ltbase-private-deployment/infra/internal/config/config.go`
- Modify: `ltbase-private-deployment/infra/internal/services/lambda.go`
- Modify: `ltbase-private-deployment/infra/internal/services/lambda_test.go`
- Modify: `ltbase-private-deployment/test/check-pulumi-stack-config-test.sh`
- Modify: `ltbase-private-deployment/docs/CUSTOMER_ONBOARDING.md`
- Modify: `ltbase-private-deployment/docs/onboarding/04-prepare-env-file.md`
- Modify: `ltbase-private-deployment/docs/onboarding/05-bootstrap-one-click.md`

- [ ] **Step 1: Add failing validation and env wiring tests**

Extend `ltbase-private-deployment/test/check-pulumi-stack-config-test.sh` with required key assertions for the UI public config, for example:

```bash
assert_contains "${output}" "ltbase-infra:controlPlaneCorsOrigins"
```

Extend `ltbase-private-deployment/infra/internal/services/lambda_test.go` with a failing test like:

```go
func TestControlPlaneLambdaEnvIncludesCORSOrigins(t *testing.T) {
  env := controlPlaneLambdaEnv(config.StackConfig{
    APIDomain:              "api.devo.example.com",
    ProjectID:              "33333333-3333-4333-8333-333333333333",
    DeploymentProjectName:  "Customer Ltbase",
    DeploymentAWSAccountID: "123456789012",
    ControlPlaneCORSOrigins: []string{"https://admin.customer.example.com"},
    DSQLPort:               "5432",
    DSQLDB:                 "postgres",
    DSQLUser:               "admin",
    DSQLProjectSchema:      "ltbase",
  }, pulumi.String("table-name"), pulumi.String("bucket-name"), pulumi.String("schema-bucket"))

  if _, ok := env["CONTROL_PLANE_CORS_ORIGINS"]; !ok {
    t.Fatal("controlPlaneLambdaEnv() missing CONTROL_PLANE_CORS_ORIGINS")
  }
}
```

- [ ] **Step 2: Run the focused validation and Go tests and confirm they fail**

Run:

- `bash test/check-pulumi-stack-config-test.sh`
- `go test ./infra/internal/services`

Expected: FAIL because the new stack config key and Lambda env are not wired yet.

- [ ] **Step 3: Add the minimal config key and Lambda env wiring**

Update `ltbase-private-deployment/infra/internal/config/config.go` with:

```go
type StackConfig struct {
    // existing fields...
    ControlPlaneCORSOrigins []string
}
```

Load it from a new Pulumi config key such as `controlPlaneCorsOrigins`, splitting CSV values.

Update `ltbase-private-deployment/scripts/bootstrap-deployment-repo.sh` to set it from the UI domain, for example:

```bash
bootstrap_env_run_quiet "${stack_env[@]}" pulumi config set controlPlaneCorsOrigins "https://${CONTROLPLANE_UI_DOMAIN}" --stack "${STACK}"
```

Update `ltbase-private-deployment/infra/internal/services/lambda.go` so `controlPlaneLambdaEnv()` emits:

```go
"CONTROL_PLANE_CORS_ORIGINS": pulumi.String(strings.Join(cfg.ControlPlaneCORSOrigins, ",")),
```

Update `ltbase-private-deployment/scripts/check-pulumi-stack-config.sh` to require `ltbase-infra:controlPlaneCorsOrigins`.

- [ ] **Step 4: Update operator docs for public provider config and admin login prerequisites**

Add concise doc sections covering:

- required Firebase public config
- required Supabase public config
- the control plane UI companion domain
- provider-name alignment with `infra/auth-providers.<stack>.json`
- requirement that admin identities must already be bound to `role.admin` or `controlplane.admin`

- [ ] **Step 5: Re-run validation, Go tests, and one broader workflow guard**

Run:

- `bash test/check-pulumi-stack-config-test.sh`
- `go test ./infra/internal/services`
- `bash test/rollout-workflows-test.sh`

Expected: PASS.

- [ ] **Step 6: Commit the deployment wiring and docs slice**

```bash
git add scripts/check-pulumi-stack-config.sh scripts/bootstrap-deployment-repo.sh infra/internal/config/config.go infra/internal/services/lambda.go infra/internal/services/lambda_test.go test/check-pulumi-stack-config-test.sh docs/CUSTOMER_ONBOARDING.md docs/onboarding/04-prepare-env-file.md docs/onboarding/05-bootstrap-one-click.md
git commit -m "feat: wire control plane ui deployment config"
```

### Task 6: Verify Browser Flow End-To-End And Capture Any Required `ltbase.api` Follow-Up

**Files:**
- Modify if needed: `ltbase.api/cmd/controlplane/ui_http.go`
- Modify if needed: `ltbase.api/cmd/authservice/*`
- Create if needed: targeted tests in `ltbase.api/cmd/controlplane/*_test.go` or `ltbase.api/internal/authservice/*_test.go`

- [ ] **Step 1: Verify the deployed browser contracts before changing backend code**

Manual checks to run after Tasks 1-5 land:

- Firebase Google login from the deployed Pages origin
- Supabase Google login from the deployed Pages origin
- LTBase token exchange through authservice from the browser
- LTBase token refresh from the browser
- Control Plane API requests from the browser origin

Record the exact failing request, response code, and missing header if anything breaks.

- [ ] **Step 2: Only if browser verification fails, add the smallest backend test first**

Examples:

```go
func TestCORSAllowedOriginFromEnv(t *testing.T) {
    t.Setenv("CONTROL_PLANE_CORS_ORIGINS", "https://admin.customer.example.com")
    got := corsAllowedOrigin("https://admin.customer.example.com")
    if got != "https://admin.customer.example.com" {
        t.Fatalf("corsAllowedOrigin() = %q", got)
    }
}
```

or an authservice handler test that asserts browser-friendly headers or response shape for refresh.

- [ ] **Step 3: Implement only the verified backend gap**

Possible examples:

- tighten control-plane CORS allowlist behavior
- add authservice browser CORS headers if absent
- return a missing browser-expected field only if the UI truly needs it

Do not add `/oauth/authorize`, `oidcClientId`, or any new standalone authorization-server flow.

- [ ] **Step 4: Run only the targeted backend tests you changed**

Examples:

- `go test ./cmd/controlplane -run TestCORSAllowedOriginFromEnv -v`
- `go test ./internal/authservice -run TestHandleLogin -v`

- [ ] **Step 5: Commit backend-only follow-up separately if it exists**

```bash
git add <changed-backend-files>
git commit -m "fix: unblock browser auth exchange for control plane ui"
```

## Self-Review Checklist

- [ ] `ltbase-controlplane-ui` runtime config changes are covered by Task 1.
- [ ] Firebase and Supabase browser token acquisition plus LTBase exchange are covered by Tasks 2 and 3.
- [ ] Companion repo bootstrap, Pages project wiring, and runtime config generation are covered by Task 4.
- [ ] Pulumi stack config, Lambda env wiring, CORS origin config, and operator docs are covered by Task 5.
- [ ] `ltbase.api` remains conditional and minimal, with verification first, in Task 6.
