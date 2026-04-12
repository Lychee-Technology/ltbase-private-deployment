# Prebuilt Infra Binaries Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish commit-bound multi-arch Pulumi infra binaries to a dedicated public repo named `ltbase-private-deployment-binaries`, then make `ltbase-deploy-workflows` consume those releases with a safe source-build fallback.

**Architecture:** `ltbase-private-deployment` remains the source-of-truth blueprint repo and gains a publisher workflow that builds `linux-amd64` and `linux-arm64` binaries only when build-relevant inputs change. Those binaries are released into the new public repo `ltbase-private-deployment-binaries` under timestamp tags with a manifest that records the source repo and commit. `ltbase-deploy-workflows` queries that binaries repo by manifest, installs the exact matching binary for the current runner architecture, and falls back to the existing blueprint wrapper when no trusted match exists.

**Tech Stack:** Pulumi Go, GitHub Actions, GitHub Releases, GitHub CLI, Bash, jq, Markdown

**Spec:** `docs/superpowers/specs/2026-04-11-prebuilt-infra-binaries-design.md`

---

## Affected Repos

| Repo | Responsibility |
|------|----------------|
| `Lychee-Technology/ltbase-private-deployment` | Build multi-arch blueprint binaries and publish them into the binaries repo |
| `Lychee-Technology/ltbase-private-deployment-binaries` | Public release-only repo that stores timestamp-tagged binary releases and release metadata |
| `Lychee-Technology/ltbase-deploy-workflows` | Query the binaries repo, install the matching binary, and preserve source-build fallback |

## Release Contract

**Repo:** `Lychee-Technology/ltbase-private-deployment-binaries`

**Tag format:** `r<timestamp>`

**Release assets:**

- `ltbase-infra-bin-linux-amd64.tar.gz`
- `ltbase-infra-bin-linux-arm64.tar.gz`
- `manifest.json`

**`manifest.json` fields:**

- `source_repository`
- `source_commit`
- `source_ref`
- `release_tag`
- `artifacts[]`
- per artifact:
  - `file`
  - `arch`
  - `sha256`
  - `go_version`
  - `built_at`

**Consumer matching rules:**

- `source_repository` must equal the checked-out blueprint repo
- `source_commit` must equal the checked-out blueprint commit exactly
- `arch` must equal the runner architecture expressed as `linux-amd64` or `linux-arm64`
- the downloaded tarball checksum must equal the manifest checksum before installation

---

## File Map

| File | Responsibility |
|------|---------------|
| `ltbase-private-deployment/.github/workflows/build-infra-binary.yml` | Build/publish multi-arch binaries to the binaries repo only when build-relevant inputs change |
| `ltbase-private-deployment/infra/scripts/pulumi-wrapper.sh` | Preserve source-build fallback after binaries-repo consumption is added |
| `ltbase-private-deployment/README.md` | Explain the binaries repo publication path and fallback behavior |
| `ltbase-private-deployment/docs/BOOTSTRAP.md` | Explain that official workflows may use binaries from the public binaries repo |
| `ltbase-private-deployment/test/prebuilt-infra-binary-test.sh` | Assert publish workflow contract and wrapper behavior |
| `ltbase-private-deployment-binaries/README.md` | Document the repo purpose, release contract, and consumer expectations |
| `ltbase-private-deployment-binaries/.gitignore` | Keep the repo release-only and exclude local scratch files |
| `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/action.yml` | Accept binaries-repo coordinates and install the matching release asset |
| `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/install.sh` | Query releases, fetch manifest, validate checksum, unpack, and install |
| `ltbase-deploy-workflows/.github/workflows/preview-stack.yml` | Pass binaries-repo settings into the installer action before Pulumi preview |
| `ltbase-deploy-workflows/.github/workflows/rollout-hop.yml` | Pass binaries-repo settings into the installer action before Pulumi up/refresh |
| `ltbase-deploy-workflows/README.md` | Document binaries-repo lookup, architecture matching, and fallback semantics |
| `ltbase-deploy-workflows/test/install-prebuilt-infra-binary-test.sh` | Cover manifest lookup, arch matching, checksum mismatch, and fallback behavior |
| `ltbase-deploy-workflows/test/generic-workflows-test.sh` | Assert reusable workflows wire the binaries repo installer path |

---

### Task 1: Bootstrap the new public binaries repo contract

**Files:**
- Create: `ltbase-private-deployment-binaries/README.md`
- Create: `ltbase-private-deployment-binaries/.gitignore`

- [ ] Create the GitHub repository `Lychee-Technology/ltbase-private-deployment-binaries` as a public repository intended for releases only.
- [ ] Add a `README.md` that states the repo stores prebuilt blueprint binaries only, not blueprint source code.
- [ ] Document the release contract in `README.md`, including the tag format `r<timestamp>`, the two tarball names, and `manifest.json`.
- [ ] Add a minimal `.gitignore` that keeps local scratch files out of the repo while leaving release assets to GitHub Releases instead of git history.
- [ ] Verify the repo has releases enabled and that the automation identity to be used from `ltbase-private-deployment` has permission to create releases there.

### Task 2: Convert the blueprint publisher from local artifacts to binaries-repo releases

**Files:**
- Modify: `ltbase-private-deployment/.github/workflows/build-infra-binary.yml`
- Modify: `ltbase-private-deployment/README.md`
- Modify: `ltbase-private-deployment/docs/BOOTSTRAP.md`
- Modify: `ltbase-private-deployment/test/prebuilt-infra-binary-test.sh`

- [ ] Extend `build-infra-binary.yml` to build a two-entry matrix for `linux-amd64` and `linux-arm64`.
- [ ] Add path filters so automatic publication runs only when build-relevant blueprint inputs change, starting with `infra/**` and the workflow file itself.
- [ ] Package the produced binary for each matrix entry into `ltbase-infra-bin-linux-<arch>.tar.gz` with a single `ltbase-infra` executable at the tar root.
- [ ] Generate a single `manifest.json` describing the source repo, source commit, source ref, release tag, and both artifact entries.
- [ ] Replace the local `upload-artifact` publishing step with release creation and asset upload into `Lychee-Technology/ltbase-private-deployment-binaries` using a dedicated token.
- [ ] Use a timestamp-derived tag like `r20260411T120102Z` and never overwrite prior releases.
- [ ] Update docs so they explain that official workflows now look in `ltbase-private-deployment-binaries` first and only fall back to source build when no matching release is available.
- [ ] Update `test/prebuilt-infra-binary-test.sh` so it asserts the new tarball names, timestamp-tag language, manifest fields, and two-arch expectation.

### Task 3: Preserve the blueprint wrapper as the correctness fallback

**Files:**
- Modify: `ltbase-private-deployment/infra/scripts/pulumi-wrapper.sh`
- Modify: `ltbase-private-deployment/test/prebuilt-infra-binary-test.sh`

- [ ] Keep `infra/scripts/pulumi-wrapper.sh` responsible for local source build fallback when `infra/.pulumi/bin/ltbase-infra` is missing.
- [ ] Do not teach the wrapper about releases, manifests, or remote lookups; the wrapper should stay local and deterministic.
- [ ] Extend the test so one case proves a preinstalled binary skips rebuild, and another case proves the wrapper still rebuilds locally when no binary has been installed.

### Task 4: Teach reusable workflows to search the binaries repo by manifest

**Files:**
- Modify: `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/action.yml`
- Modify: `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/install.sh`
- Modify: `ltbase-deploy-workflows/.github/workflows/preview-stack.yml`
- Modify: `ltbase-deploy-workflows/.github/workflows/rollout-hop.yml`
- Modify: `ltbase-deploy-workflows/README.md`
- Modify: `ltbase-deploy-workflows/test/install-prebuilt-infra-binary-test.sh`
- Modify: `ltbase-deploy-workflows/test/generic-workflows-test.sh`

- [ ] Add installer action inputs for `binaries-repo`, `token`, and any small lookup knobs needed to keep the action generic.
- [ ] Make the install script determine the runner architecture and normalize it to `linux-amd64` or `linux-arm64`.
- [ ] Query recent releases from `Lychee-Technology/ltbase-private-deployment-binaries`, inspect `manifest.json`, and select the release whose manifest matches the checked-out source repo and commit exactly.
- [ ] Download the matching tarball, verify its checksum against the manifest entry, unpack it, and install `ltbase-infra` into `blueprint/<working-directory>/.pulumi/bin/ltbase-infra`.
- [ ] Keep all negative cases non-breaking: missing release, missing manifest, missing matching arch, or checksum mismatch must all set `installed=false` and return success so the wrapper can build from source.
- [ ] Wire the updated installer into `preview-stack.yml` and `rollout-hop.yml` before Pulumi execution, passing the default binaries repo name and the required secret token.
- [ ] Update README and workflow tests so they describe the binaries repo lookup path, manifest matching, and fallback behavior clearly.

### Task 5: Add explicit secret and operator contract for cross-repo publishing and download

**Files:**
- Modify: `ltbase-private-deployment/README.md`
- Modify: `ltbase-private-deployment/docs/BOOTSTRAP.md`
- Modify: `ltbase-deploy-workflows/README.md`

- [ ] Document the producer-side secret required for `ltbase-private-deployment` to create releases in `ltbase-private-deployment-binaries`.
- [ ] Document the consumer-side secret required for `ltbase-deploy-workflows` to read release assets from `ltbase-private-deployment-binaries`.
- [ ] State explicitly that binaries repo publication is an optimization path, not the correctness path, and that source-build fallback remains authoritative.
- [ ] State explicitly that `ltbase-releases` remains the application release channel and is unchanged by this plan.

### Task 6: Verify release publication and consumer fallback end to end

**Files:**
- Verify: `ltbase-private-deployment/.github/workflows/build-infra-binary.yml`
- Verify: `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/install.sh`
- Verify: `ltbase-deploy-workflows/.github/workflows/preview-stack.yml`
- Verify: `ltbase-deploy-workflows/.github/workflows/rollout-hop.yml`

- [ ] Run the updated blueprint publisher once on a build-relevant commit and confirm it creates a release in `ltbase-private-deployment-binaries` tagged `r<timestamp>`.
- [ ] Confirm the release contains exactly the two tarballs plus `manifest.json`.
- [ ] Confirm the manifest records the source repo and commit correctly.
- [ ] Run the reusable workflow installer tests and confirm they cover commit mismatch, missing arch, checksum mismatch, and success cases.
- [ ] Run preview or rollout once on an ARM runner and confirm logs show the binary came from `ltbase-private-deployment-binaries` when a matching release exists.
- [ ] Force a commit that has no published release and confirm the workflow still succeeds through the wrapper-based source build fallback.

---

## Suggested Issue Split

1. `ltbase-private-deployment`: publish multi-arch blueprint binaries into `ltbase-private-deployment-binaries`
2. `ltbase-deploy-workflows`: consume `ltbase-private-deployment-binaries` releases by manifest and preserve fallback
3. `ltbase-private-deployment`: bootstrap the new public repo `ltbase-private-deployment-binaries` and document its contract
