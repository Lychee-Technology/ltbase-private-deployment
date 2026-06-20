# LTBase Control Plane UI Deployment Checklist

This checklist tracks the remaining post-merge work required to make `ltbase-controlplane-ui` deployable through the private deployment channel end to end.

## Scope

This checklist covers four repositories:

- `ltbase.api`
- `ltbase-controlplane-ui`
- `ltbase-deploy-workflows`
- `ltbase-private-deployment`

It assumes the implementation PRs are already merged to `main`.

## Phase 1: Publish A Unified Release

- [ ] Choose the next unified `release_id` for backend + UI, for example `v1.0.23`.
- [ ] Create the same tag in `ltbase-controlplane-ui` and `ltbase.api`.
- [ ] Confirm `ltbase.api` Actions secrets/variables are ready:
  - `PRIVATE_REPO_PAT`
  - `LTBASE_RELEASES_PUBLISH_TOKEN`
  - optional `LTBASE_RELEASES_REPO`
- [ ] Trigger `ltbase.api/.github/workflows/publish-private-release.yml` for the chosen `release_id`.
- [ ] Verify the published release in `Lychee-Technology/ltbase-releases` contains:
  - `ltbase-dataplane-lambda.zip`
  - `ltbase-controlplane-lambda.zip`
  - `ltbase-authservice-lambda.zip`
  - `ltbase-forma-cdc-lambda.zip`
  - `ltbase-controlplane-ui.tar.gz`
  - `ltbase-governance-ontology-compiler.zip`
  - `manifest.json`
- [ ] Verify `manifest.json` includes an artifact entry with:
  - `name: controlplane-ui`
  - `file: ltbase-controlplane-ui.tar.gz`
- [ ] Record the published `release_id` and release URL for later operator validation.

## Phase 2: Validate A Fresh Internal Deployment Repo

- [ ] Create a fresh internal test deployment repository from `ltbase-private-deployment`.
- [ ] Prepare a real `.env` file for the internal test repository.
- [ ] Confirm the following values are valid before bootstrap:
  - `CONTROLPLANE_UI_DOMAIN`
  - `CONTROLPLANE_UI_PAGES_PROJECT`
  - `CLOUDFLARE_ACCOUNT_ID`
  - `CLOUDFLARE_ZONE_ID`
  - `CLOUDFLARE_API_TOKEN`
  - `LTBASE_RELEASES_TOKEN`
  - `FIREBASE_API_KEY_<STACK>` for every stack
  - `FIREBASE_PROJECT_ID_<STACK>` for every stack
  - `SUPABASE_URL_<STACK>` for every stack
  - `SUPABASE_ANON_KEY_<STACK>` for every stack
- [ ] Run the bootstrap flow.
- [ ] Verify bootstrap created or reconciled the customer Cloudflare Pages project for the UI.
- [ ] Verify bootstrap reconciled the UI custom domain and DNS.
- [ ] Verify bootstrap wrote these deployment repo variables:
  - `CONTROLPLANE_UI_STACK_CONFIG`
  - `CONTROLPLANE_UI_DOMAIN`
  - `CONTROLPLANE_UI_PAGES_PROJECT`
- [ ] Verify preview remains infra-only and does not publish the UI.
- [ ] Run rollout for the first stack using the new unified `release_id`.
- [ ] Verify rollout downloads the unified release successfully.
- [ ] Verify rollout executes the UI deploy step successfully.
- [ ] Verify the deployed Pages site is reachable on the expected domain.
- [ ] Verify `/ltbase-controlplane.config.json` is present and contains the expected stack data.
- [ ] Verify direct navigation to `/auth/callback` is handled correctly by the SPA.
- [ ] Verify the UI points to the expected `authBaseUrl`, `controlPlaneBaseUrl`, and `apiBaseUrl` values.
- [ ] Run one promotion hop and verify the UI publish path still succeeds on the next stack.
- [ ] Save operator evidence:
  - workflow run URLs
  - release URL
  - Pages URL/domain
  - notes on preview, rollout, and promotion outcomes

## Phase 3: Stabilize Workflow And Template Versioning

- [ ] Decide whether the private deployment channel is ready to stop referencing `ltbase-deploy-workflows@main`.
- [ ] If yes, create a new stable version tag in `ltbase-deploy-workflows`.
- [ ] Move or confirm the floating major tag if required by version policy.
- [ ] Update `ltbase-private-deployment` workflow references from `@main` to the intended stable workflow version.
- [ ] Create a new stable template tag in `ltbase-private-deployment` after the internal validation passes.
- [ ] Record the supported operator defaults:
  - workflow reference
  - template version
  - application `release_id`

## Phase 4: Documentation Cleanup

- [ ] Review `ltbase-private-deployment` docs for stale companion-repo publishing guidance.
- [ ] Update docs so they consistently state:
  - the UI artifact is published through the unified LTBase release
  - runtime config authority lives in the deployment repo
  - preview is infra-only
  - rollout publishes the UI to Cloudflare Pages
- [ ] Confirm onboarding docs explain the required public browser config values for every stack.
- [ ] Confirm operator docs explain what evidence to collect during first deployment validation.

## Exit Criteria

- [ ] A formal `ltbase-releases` release includes `ltbase-controlplane-ui.tar.gz` and `ltbase-governance-ontology-compiler.zip`.
- [ ] A fresh internal deployment repo passes bootstrap, preview, rollout, and promotion.
- [ ] Workflow and template versioning are aligned with the intended customer path.
- [ ] Documentation matches the actual deployment model.
