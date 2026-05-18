# Control Plane UI Docs Batch C Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the `ltbase-private-deployment` Control Plane UI docs so they are bilingual, conservative, and accurate to the current repository state.

**Architecture:** Treat current repository code as the documentation truth source. Update the English top-level and onboarding docs first, then mirror the same structure and semantics into the Chinese docs, and finish with a stale-terminology and cross-link consistency pass.

**Tech Stack:** Markdown, GitHub Issues, GitHub CLI, ripgrep

---

## File Map

Top-level docs:

- `README.md` - top-level customer template overview
- `README.zh.md` - Chinese mirror of the top-level overview
- `docs/CUSTOMER_ONBOARDING.md` - main onboarding runbook
- `docs/CUSTOMER_ONBOARDING.zh.md` - Chinese mirror of the main onboarding runbook
- `docs/BOOTSTRAP.md` - short checklist version of onboarding
- `docs/BOOTSTRAP.zh.md` - Chinese mirror of the short checklist

Detailed onboarding docs:

- `docs/onboarding/04-prepare-env-file.md` - operator input and environment contract guide
- `docs/onboarding/04-prepare-env-file.zh.md` - Chinese mirror
- `docs/onboarding/05-bootstrap-one-click.md` - one-click bootstrap guide
- `docs/onboarding/05-bootstrap-one-click.zh.md` - Chinese mirror
- `docs/onboarding/06-bootstrap-manual.md` - manual bootstrap guide
- `docs/onboarding/06-bootstrap-manual.zh.md` - Chinese mirror
- `docs/onboarding/07-first-deploy-and-managed-dsql.md` - first preview and rollout guide
- `docs/onboarding/07-first-deploy-and-managed-dsql.zh.md` - Chinese mirror
- `docs/onboarding/08-day-2-operations.md` - day-2 operations guide
- `docs/onboarding/08-day-2-operations.zh.md` - Chinese mirror

Reference files to verify wording against:

- `.github/workflows/preview.yml`
- `.github/workflows/rollout-hop.yml`
- `env.template`
- `scripts/bootstrap-controlplane-ui-companion.sh`
- `scripts/bootstrap-all.sh`
- `scripts/evaluate-and-continue.sh`
- `scripts/lib/bootstrap-env.sh`
- `../ltbase-deploy-workflows/.github/workflows/preview-stack.yml`
- `../ltbase-deploy-workflows/.github/workflows/rollout-hop.yml`

### Task 1: Top-Level Overview Rewrite

**Files:**
- Modify: `README.md`
- Modify: `README.zh.md`
- Modify: `docs/CUSTOMER_ONBOARDING.md`
- Modify: `docs/CUSTOMER_ONBOARDING.zh.md`
- Modify: `docs/BOOTSTRAP.md`
- Modify: `docs/BOOTSTRAP.zh.md`

- [ ] Add a short `Current Control Plane UI Model` section to `README.md` that states:
  - the admin UI uses `CONTROLPLANE_UI_DOMAIN`
  - preview is infra-only
  - runtime config must be browser-safe
  - identity provider redirect and Control Plane CORS must match the admin domain
  - current repo versions still contain companion-style Control Plane UI setup

- [ ] Mirror the same section and meaning in `README.zh.md`.

- [ ] Update `docs/CUSTOMER_ONBOARDING.md` so the `End State` and pre-bootstrap readiness sections explicitly mention:
  - one admin domain
  - control-plane CORS alignment
  - redirect URI alignment
  - browser-safe Firebase and Supabase values
  - no secrets in runtime config

- [ ] Mirror those changes in `docs/CUSTOMER_ONBOARDING.zh.md`.

- [ ] Update `docs/BOOTSTRAP.md` to add short checklist reminders that:
  - Control Plane UI values are browser-facing inputs
  - preview is infra-only
  - current repo versions may still expose companion-oriented Control Plane UI scripts and variables

- [ ] Mirror those changes in `docs/BOOTSTRAP.zh.md`.

### Task 2: Environment Contract Rewrite

**Files:**
- Modify: `docs/onboarding/04-prepare-env-file.md`
- Modify: `docs/onboarding/04-prepare-env-file.zh.md`

- [ ] Rewrite the Control Plane UI env guidance in `docs/onboarding/04-prepare-env-file.md` so it clearly distinguishes:
  - admin domain setup
  - browser-safe Firebase and Supabase values
  - Control Plane CORS behavior
  - redirect URI setup

- [ ] Keep current variable names exactly as they appear in `env.template`, including:
  - `CONTROLPLANE_UI_DOMAIN`
  - `FIREBASE_API_KEY_<STACK>`
  - `FIREBASE_PROJECT_ID_<STACK>`
  - `SUPABASE_URL_<STACK>`
  - `SUPABASE_ANON_KEY_<STACK>`

- [ ] Add an explicit warning in the English file that server-only secrets, service-role keys, and admin credentials must not appear in UI runtime config.

- [ ] Keep the current documented Control Plane CORS behavior accurate:
  - the admin domain is included by default unless the operator intentionally sets `*`

- [ ] Add an explicit reminder that the identity provider must allow `https://<CONTROLPLANE_UI_DOMAIN>/auth/callback` before operator login will work.

- [ ] Mirror the same structure and warnings in `docs/onboarding/04-prepare-env-file.zh.md`.

### Task 3: Bootstrap Docs Rewrite

**Files:**
- Modify: `docs/onboarding/05-bootstrap-one-click.md`
- Modify: `docs/onboarding/05-bootstrap-one-click.zh.md`
- Modify: `docs/onboarding/06-bootstrap-manual.md`
- Modify: `docs/onboarding/06-bootstrap-manual.zh.md`

- [ ] Update the one-click readiness checklist in `docs/onboarding/05-bootstrap-one-click.md` so Control Plane UI inputs are described conservatively as current bootstrap/operator inputs, not proof of a final release-driven UI pipeline.

- [ ] In the `What This Command Does` section, keep the current script list and describe `bootstrap-controlplane-ui-companion.sh` using only verified current behavior.

- [ ] Add one explicit line in `docs/onboarding/05-bootstrap-one-click.md` that later preview runs do not publish the Control Plane UI.

- [ ] Add post-bootstrap verification bullets for:
  - redirect URI registration
  - provider-name alignment with `infra/auth-providers.<stack>.json`
  - browser-safe config only

- [ ] Mirror those changes in `docs/onboarding/05-bootstrap-one-click.zh.md`.

- [ ] Add a missing Control Plane UI-related stage to `docs/onboarding/06-bootstrap-manual.md` if the current manual story requires explicit companion/bootstrap setup.

- [ ] Document only what the current scripts actually perform in that manual stage:
  - required env inputs
  - Pages and domain expectations
  - what the operator verifies afterward

- [ ] Add a final manual-path confirmation list covering:
  - admin domain readiness
  - redirect URI readiness
  - Control Plane CORS alignment
  - browser-safe config only

- [ ] Mirror those changes in `docs/onboarding/06-bootstrap-manual.zh.md`.

### Task 4: First Deploy And Day-2 Rewrite

**Files:**
- Modify: `docs/onboarding/07-first-deploy-and-managed-dsql.md`
- Modify: `docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`
- Modify: `docs/onboarding/08-day-2-operations.md`
- Modify: `docs/onboarding/08-day-2-operations.zh.md`

- [ ] Update the preview section in `docs/onboarding/07-first-deploy-and-managed-dsql.md` to state explicitly that preview validates release selection and infrastructure changes only.

- [ ] Add an explicit note that preview does not publish the admin UI.

- [ ] Add rollout-time operator validation bullets for:
  - admin domain reachability
  - provider-name alignment
  - redirect URI acceptance by the identity provider
  - Control Plane CORS alignment with the admin domain

- [ ] Keep the DSQL guidance intact except where surrounding wording must be aligned to the new conservative docs story.

- [ ] Mirror those changes in `docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`.

- [ ] Update the upgrade guidance in `docs/onboarding/08-day-2-operations.md` to explain that `LTBASE_RELEASE_ID` remains the workflow-level deployment selector where current workflows support it.

- [ ] Add a short troubleshooting subsection covering:
  - admin domain checks
  - redirect URI registration
  - Control Plane CORS allowlist checks
  - browser-safe config inputs
  - current repo version Control Plane UI bootstrap assumptions

- [ ] Add an explicit reminder that operators do not rebuild LTBase UI source artifacts from the deployment repo.

- [ ] Mirror those changes in `docs/onboarding/08-day-2-operations.zh.md`.

### Task 5: Repository-Wide Consistency Pass

**Files:**
- Verify: `README.md`
- Verify: `README.zh.md`
- Verify: `docs/CUSTOMER_ONBOARDING.md`
- Verify: `docs/CUSTOMER_ONBOARDING.zh.md`
- Verify: `docs/BOOTSTRAP.md`
- Verify: `docs/BOOTSTRAP.zh.md`
- Verify: `docs/onboarding/04-prepare-env-file.md`
- Verify: `docs/onboarding/04-prepare-env-file.zh.md`
- Verify: `docs/onboarding/05-bootstrap-one-click.md`
- Verify: `docs/onboarding/05-bootstrap-one-click.zh.md`
- Verify: `docs/onboarding/06-bootstrap-manual.md`
- Verify: `docs/onboarding/06-bootstrap-manual.zh.md`
- Verify: `docs/onboarding/07-first-deploy-and-managed-dsql.md`
- Verify: `docs/onboarding/07-first-deploy-and-managed-dsql.zh.md`
- Verify: `docs/onboarding/08-day-2-operations.md`
- Verify: `docs/onboarding/08-day-2-operations.zh.md`

- [ ] Search the updated docs for stale overclaims involving:
  - `controlplane-ui companion`
  - `CONTROLPLANE_UI_STACK_CONFIG`
  - `public/ltbase-controlplane.config.json`
  - `publish workflow`
  - `preview` language that implies deploy or publish side effects

- [ ] Re-read the top-level docs and confirm they no longer contradict the onboarding docs.

- [ ] Re-read the English and Chinese pairs and confirm they match in structure and meaning.

- [ ] Check internal links from `README*`, `CUSTOMER_ONBOARDING*`, `BOOTSTRAP*`, and onboarding pages.

- [ ] Leave untouched any behavior that current code still requires, even if the naming remains companion-oriented.

## GitHub Issue Checklist

- [ ] Create one missing top-level documentation issue for `README*`, `CUSTOMER_ONBOARDING*`, and `BOOTSTRAP*`.
- [ ] Reuse existing issues `#74`, `#76`, and `#77` for the detailed onboarding doc slices instead of creating duplicates.
- [ ] Add a comment to epic `#75` linking the Batch C top-level docs issue and clarifying that Batch C intentionally documents current verified behavior rather than unverified intended architecture.
