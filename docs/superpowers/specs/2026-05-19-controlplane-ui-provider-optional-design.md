# Control Plane UI Provider Optional Design

## Scope

Adjust `ltbase-private-deployment` so each deployment stack may configure Firebase only, Supabase only, or both for Control Plane UI browser auth settings. The current requirement that both providers must always be present blocks valid single-provider deployments.

## Repository Ownership

This behavior belongs to `ltbase-private-deployment` because the required env validation, runtime config rendering, and deployment-owned `CONTROLPLANE_UI_STACK_CONFIG` generation all live in this template repository.

## Goals

- Allow bootstrap and related scripts to proceed when at least one auth provider is fully configured for a stack.
- Reject partial provider configuration such as Firebase API key without Firebase project id.
- Generate `CONTROLPLANE_UI_STACK_CONFIG` with only the providers that are actually configured.
- Preserve current behavior for deployments that already configure both providers.

## Non-Goals

- No workflow interface changes.
- No changes in `ltbase-controlplane-ui`.
- No changes to how auth providers are interpreted beyond omitting absent providers.

## Design

### Validation

Introduce a shared stack-level validation helper in the bootstrap env library that enforces:

- Firebase is considered configured only when both `FIREBASE_PROJECT_ID` and `FIREBASE_API_KEY` are non-empty.
- Supabase is considered configured only when both `SUPABASE_URL` and `SUPABASE_ANON_KEY` are non-empty.
- At least one of those provider pairs must be fully configured.
- If either provider is partially configured, fail with a targeted error explaining which pair is incomplete.

Update existing callers that currently require all four variables unconditionally:

- `scripts/bootstrap-deployment-repo.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/bootstrap-controlplane-ui-companion.sh`

### Runtime Config Generation

Update `bootstrap_env_controlplane_ui_stack_config_json()` so `authProviders` is built dynamically per stack:

- include a Firebase provider object only when Firebase is fully configured
- include a Supabase provider object only when Supabase is fully configured

Provider display names should continue to come from the auth provider config file when available. If a provider is omitted because it is not configured, no placeholder provider should be emitted.

### Testing

Adjust targeted shell tests to cover:

- Firebase-only stack succeeds
- Supabase-only stack succeeds
- both providers still succeed
- partial Firebase config fails
- partial Supabase config fails
- generated `CONTROLPLANE_UI_STACK_CONFIG` contains only configured providers

## Validation Plan

- Run the targeted shell tests covering bootstrap, evaluate-and-continue, companion config generation, and render behavior.
- Re-run bootstrap in `ltbase-private-deployment-demo01` using the Firebase-only values already provided.
- If bootstrap succeeds, continue with the existing internal validation flow from that point.
