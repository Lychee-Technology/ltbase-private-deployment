# Control Plane UI Docs Batch C Design

## Summary

Rewrite the customer-facing Control Plane UI documentation in `ltbase-private-deployment` so it is bilingual, internally consistent, and conservative about current repository behavior.

Batch C must document only what current code proves. It must not describe the intended release-driven Control Plane UI architecture as fully landed while `ltbase-private-deployment` still contains companion-style bootstrap variables, scripts, and workflow assumptions.

## Verified Current State

The documentation rewrite must treat these as the source of truth:

- `ltbase-private-deployment/.github/workflows/preview.yml` is infra-only and does not publish the Control Plane UI.
- `ltbase-deploy-workflows/.github/workflows/preview-stack.yml` and `rollout-hop.yml` perform release download plus Pulumi work only; they do not contain Control Plane UI publish steps.
- `ltbase-private-deployment/env.template` still exposes Control Plane UI companion-style variables and browser config inputs.
- `ltbase-private-deployment/scripts/bootstrap-controlplane-ui-companion.sh`, `bootstrap-all.sh`, `evaluate-and-continue.sh`, and `scripts/lib/bootstrap-env.sh` still implement or reference companion-style Control Plane UI setup.
- Current top-level and onboarding docs are inconsistent with each other and with the current codebase state.

## Goals

- Make the English and Chinese customer docs tell the same operational story.
- Keep `preview` documented as infra-only everywhere.
- Document Control Plane UI operator prerequisites clearly:
  - `CONTROLPLANE_UI_DOMAIN`
  - browser-safe Firebase and Supabase values
  - Control Plane CORS alignment
  - identity provider redirect URI alignment
  - no secrets in runtime config
- Remove unsupported claims about the final release-driven UI deployment model.
- Preserve current companion-style terminology only where the current repository still uses it.

## Non-Goals

- Changing scripts, workflows, or environment contracts.
- Renaming current companion-style variables or scripts.
- Documenting rollout-time UI publication unless the current repository code proves it.
- Closing existing issues automatically.

## Documentation Truth Model

Batch C should use these phrasing rules:

- describe one official LTBase `release_id` for deployment selection only where current workflows support it
- describe the deployment repository as the source of truth for operator inputs
- describe the Control Plane UI admin domain as a Cloudflare Pages-hosted operator endpoint
- describe runtime config as browser-safe only
- describe `preview` as infra-only
- describe companion-style Control Plane UI bootstrap/setup behavior as current repository behavior where applicable

Batch C should avoid these claims unless later code verification proves them true in this repository:

- rollout publishes the Control Plane UI
- no separate Control Plane UI bootstrap/repo model exists anymore
- runtime config is now fully release-driven end to end in `ltbase-private-deployment`

## Scope

Top-level docs:

- `README.md`
- `README.zh.md`
- `docs/CUSTOMER_ONBOARDING.md`
- `docs/CUSTOMER_ONBOARDING.zh.md`
- `docs/BOOTSTRAP.md`
- `docs/BOOTSTRAP.zh.md`

Detailed onboarding docs:

- `docs/onboarding/04-prepare-env-file.md`
- `docs/onboarding/04-prepare-env-file.zh.md`
- `docs/onboarding/05-bootstrap-one-click.md`
- `docs/onboarding/05-bootstrap-one-click.zh.md`
- `docs/onboarding/06-bootstrap-manual.md`
- `docs/onboarding/06-bootstrap-manual.zh.md`
- `docs/onboarding/07-first-deploy-and-managed-dsql.md`
- `docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`
- `docs/onboarding/08-day-2-operations.md`
- `docs/onboarding/08-day-2-operations.zh.md`

## Intended Outcomes By Doc Group

### Top-level docs

The top-level docs should explain the current operator model without overclaiming the final architecture. They should distinguish the OIDC discovery companion flow from the current Control Plane UI setup flow and explain that the deployment repo remains the operator-facing source of truth.

### Environment and bootstrap docs

The environment and bootstrap docs should explain current variable requirements and current bootstrap behavior, while clearly stating that preview does not publish the UI. They should make the browser-safe/public nature of the Firebase and Supabase values explicit and document redirect URI and CORS requirements.

### First-deploy and day-2 docs

The deploy and operations docs should explain what operators validate around the Control Plane UI today without promising unverified publish mechanics. They should add practical admin-domain, redirect URI, provider-alignment, and CORS troubleshooting guidance.

## Risks

- The existing scripts and docs reflect a transitional state, so careless wording can easily overstate current capabilities.
- English and Chinese docs can drift if updated independently.
- Manual bootstrap docs are especially likely to become inaccurate if they invent a UI deployment step that current scripts do not expose.

## Acceptance Criteria

- No updated doc claims Control Plane UI behavior unsupported by current repository code.
- `preview` is consistently documented as infra-only.
- Operator prerequisites for admin domain, browser-safe runtime config, redirect URI, and Control Plane CORS are documented in both languages.
- English and Chinese docs are structurally aligned.
- A stale-term grep pass can confirm that old overclaims and contradictions were removed from the updated doc set.
