# Prebuilt Infra Binary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `preview`, `deploy`, and `refresh` from recompiling the Go Pulumi program on every run by letting official blueprint repositories publish commit-bound prebuilt infra binaries that `ltbase-deploy-workflows` can download and use with a safe source-build fallback.

**Architecture:** Keep `ltbase-private-deployment` and `ltbase-private-deployment-demo01` as the source of truth for infra code. Each blueprint repository builds and uploads an `linux/arm64` Pulumi program binary keyed by the exact source commit. `ltbase-deploy-workflows` installs that binary into a fixed in-repo path before `pulumi preview/up/refresh`; if the artifact is missing, mismatched, or corrupt, the existing wrapper falls back to local `go build` and preserves current behavior.

**Tech Stack:** Pulumi Go, GitHub Actions artifacts, GitHub CLI, Bash, Markdown docs

---

## Affected Repos

| Repo | Responsibility |
|------|----------------|
| `Lychee-Technology/ltbase-private-deployment` | Blueprint source of truth, Pulumi runtime switch, binary producer workflow, local fallback wrapper, docs |
| `Lychee-Technology/ltbase-deploy-workflows` | Reusable workflow consumer that downloads and validates prebuilt infra binaries before running Pulumi |
| `Lychee-Technology/ltbase-private-deployment-demo01` | Internal/demo blueprint kept aligned with the template path for preview and rollout verification |

## Artifact Contract

**Artifact name:** `infra-binary-linux-arm64-<commit_sha>`

**Artifact contents:**

- `ltbase-infra`
- `manifest.json`

**`manifest.json` fields:**

- `source_repository`
- `source_commit`
- `source_ref`
- `project`
- `binary_name`
- `os`
- `arch`
- `sha256`
- `go_version`
- `built_at`

**Validation rules in consumer workflows:**

- downloaded `source_commit` must match the checked-out blueprint commit exactly
- `os=linux` and `arch=arm64` must match the runner path used by `preview-stack.yml` and `rollout-hop.yml`
- the binary checksum must match `manifest.json`
- any validation failure falls back to source build instead of running an untrusted binary

---

## File Map

| File | Responsibility |
|------|---------------|
| `ltbase-private-deployment/infra/Pulumi.yaml` | Switch Pulumi Go runtime to a fixed binary path instead of implicit temp builds |
| `ltbase-private-deployment/scripts/pulumi-wrapper.sh` | Build the binary locally when the prebuilt one is absent, then execute Pulumi unchanged |
| `ltbase-private-deployment/.github/workflows/build-infra-binary.yml` | Build and upload commit-bound `linux/arm64` infra binary artifacts |
| `ltbase-private-deployment/README.md` | Document prebuilt binary path and source-build fallback |
| `ltbase-private-deployment/docs/BOOTSTRAP.md` | Document how official workflows consume blueprint-owned prebuilt binaries |
| `ltbase-private-deployment-demo01/infra/Pulumi.yaml` | Mirror template runtime change |
| `ltbase-private-deployment-demo01/scripts/pulumi-wrapper.sh` | Mirror template wrapper behavior |
| `ltbase-private-deployment-demo01/.github/workflows/build-infra-binary.yml` | Mirror template producer workflow for internal validation |
| `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/action.yml` | Download, unpack, validate, and install blueprint-owned prebuilt binary |
| `ltbase-deploy-workflows/.github/workflows/preview-stack.yml` | Call the install action before running Pulumi preview |
| `ltbase-deploy-workflows/.github/workflows/rollout-hop.yml` | Call the install action before running Pulumi up/refresh |
| `ltbase-deploy-workflows/README.md` | Document new optional prebuilt binary behavior and fallback semantics |
| `ltbase-deploy-workflows/test/generic-workflows-test.sh` | Assert reusable workflows wire the new install action |
| `ltbase-deploy-workflows/test/run-pulumi-test.sh` | Keep wrapper fallback behavior covered |

---

### Task 1: Convert the template blueprint to a fixed Pulumi binary path

**Files:**
- Modify: `ltbase-private-deployment/infra/Pulumi.yaml`
- Create: `ltbase-private-deployment/scripts/pulumi-wrapper.sh`
- Modify: `ltbase-private-deployment/README.md`
- Modify: `ltbase-private-deployment/docs/BOOTSTRAP.md`

- [ ] Update `infra/Pulumi.yaml` so the Go runtime uses `options.binary` pointing at `./.pulumi/bin/ltbase-infra` relative to the `infra` project root.
- [ ] Create `scripts/pulumi-wrapper.sh` in the blueprint repo so it ensures `infra/.pulumi/bin/ltbase-infra` exists before invoking `pulumi "$@"`.
- [ ] Make the wrapper build with `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -buildvcs=false -o .pulumi/bin/ltbase-infra ./cmd/ltbase-infra` from the `infra` directory when the binary is missing.
- [ ] Keep the wrapper intentionally minimal: do not add cache invalidation logic, commit detection, or multi-arch branching in phase 1.
- [ ] Document that official workflows may pre-install the binary, while local development keeps working because the wrapper still builds from source if needed.

### Task 2: Add a commit-bound binary producer workflow to the template repo

**Files:**
- Create: `ltbase-private-deployment/.github/workflows/build-infra-binary.yml`
- Modify: `ltbase-private-deployment/README.md`
- Modify: `ltbase-private-deployment/docs/BOOTSTRAP.md`

- [ ] Add a workflow triggered on `push` to the default branch and `workflow_dispatch` that checks out the repo at the current commit.
- [ ] Run the job on `ubuntu-24.04-arm` so the produced binary matches the reusable workflow runner architecture.
- [ ] Build `infra/.pulumi/bin/ltbase-infra` from `./cmd/ltbase-infra` inside the `infra` directory.
- [ ] Generate `manifest.json` with the exact commit SHA, repo name, architecture, Go version, checksum, and timestamp.
- [ ] Upload a single artifact named `infra-binary-linux-arm64-${{ github.sha }}` containing `ltbase-infra` and `manifest.json`.
- [ ] Document that this artifact is for official workflow acceleration only and is safe to regenerate from the same commit.

### Task 3: Teach reusable workflows to install a prebuilt binary before Pulumi runs

**Files:**
- Create: `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/action.yml`
- Create: `ltbase-deploy-workflows/.github/actions/install-prebuilt-infra-binary/install.sh`
- Modify: `ltbase-deploy-workflows/.github/workflows/preview-stack.yml`
- Modify: `ltbase-deploy-workflows/.github/workflows/rollout-hop.yml`
- Modify: `ltbase-deploy-workflows/README.md`
- Modify: `ltbase-deploy-workflows/test/generic-workflows-test.sh`

- [ ] Add a composite action that accepts `repository`, `commit`, `working-directory`, and `token` inputs and installs the binary into `blueprint/<working-directory>/.pulumi/bin/ltbase-infra`.
- [ ] Make the install script use `gh api` or `gh run download` style artifact download against the blueprint repository, targeting `infra-binary-linux-arm64-<commit>`.
- [ ] Unpack into a temporary directory, verify `manifest.json.source_commit == <commit>`, verify `os=linux`, `arch=arm64`, and verify `sha256` for `ltbase-infra` before moving the binary into place.
- [ ] Return an explicit output such as `installed=true|false` so the workflow log clearly shows whether it used a prebuilt binary or fell back.
- [ ] Wire the action into `preview-stack.yml` after the blueprint checkout and before `setup-pulumi` or `run-pulumi`.
- [ ] Wire the same action into `rollout-hop.yml` before the `up` and `refresh` executions.
- [ ] Keep the new behavior optional and non-breaking: if no artifact exists, log that fact and continue without failing the job.
- [ ] Document the new contract in `README.md`, including that the blueprint repository owns the artifact and the reusable workflow only consumes it.

### Task 4: Preserve safe fallback behavior in the shared Pulumi execution path

**Files:**
- Modify: `ltbase-deploy-workflows/.github/actions/run-pulumi/run.sh`
- Modify: `ltbase-deploy-workflows/test/run-pulumi-test.sh`
- Modify: `ltbase-private-deployment/scripts/pulumi-wrapper.sh`

- [ ] Keep `run-pulumi` preferring `scripts/pulumi-wrapper.sh` exactly as it does today so no caller contract changes.
- [ ] Ensure the blueprint wrapper treats a preinstalled binary as the fast path and only runs `go build` when the binary file is absent or non-executable.
- [ ] Add or extend tests so one case proves an installed binary prevents a rebuild, and another case proves a missing binary still falls back to source build.
- [ ] Do not add logic that silently rebuilds after manifest validation failure inside the reusable workflow action; validation failure should skip installation so the wrapper remains the single fallback path.

### Task 5: Mirror the template path in the demo blueprint repo

**Files:**
- Modify: `ltbase-private-deployment-demo01/infra/Pulumi.yaml`
- Create: `ltbase-private-deployment-demo01/scripts/pulumi-wrapper.sh`
- Create: `ltbase-private-deployment-demo01/.github/workflows/build-infra-binary.yml`
- Modify: `ltbase-private-deployment-demo01/README.md`

- [ ] Apply the same fixed binary path in `demo01` so internal preview and rollout runs exercise the same behavior as the template.
- [ ] Add the same wrapper semantics and artifact producer workflow in `demo01`.
- [ ] Keep naming and manifest fields identical to the template repo so `ltbase-deploy-workflows` does not need repo-specific branching.
- [ ] Update `demo01` docs only where they explicitly describe workflow internals; avoid unrelated onboarding churn.

### Task 6: Verify the end-to-end official path and lock in observability

**Files:**
- Verify: `ltbase-private-deployment/.github/workflows/build-infra-binary.yml`
- Verify: `ltbase-deploy-workflows/.github/workflows/preview-stack.yml`
- Verify: `ltbase-deploy-workflows/.github/workflows/rollout-hop.yml`
- Verify: `ltbase-private-deployment-demo01/.github/workflows/preview.yml`
- Verify: `ltbase-private-deployment-demo01/.github/workflows/rollout-hop.yml`

- [ ] Run the blueprint producer workflow once and confirm it uploads `infra-binary-linux-arm64-<commit>` with both expected files.
- [ ] Run preview against the official blueprint repo and confirm logs show the reusable workflow installed the prebuilt binary before Pulumi preview.
- [ ] Confirm preview still succeeds after manually forcing the no-artifact path so the wrapper performs a local build.
- [ ] Run one `rollout-hop` deployment and confirm both the `up` and optional `refresh` path can consume the prebuilt binary.
- [ ] Leave `diagnose-go-compile.yml` unchanged in phase 1 so it continues to exercise the source-build path for compile diagnostics.
- [ ] Perform a final docs pass to ensure all operator-facing text consistently states: official repos may use a prebuilt binary, but behavior is identical because the binary is commit-bound and fallback remains source build.

---

## Suggested Issue Split

1. `ltbase-private-deployment`: add fixed Pulumi binary path, wrapper fallback, and binary producer workflow
2. `ltbase-deploy-workflows`: add prebuilt binary installer action and wire it into preview/rollout reusable workflows
3. `ltbase-private-deployment-demo01`: mirror template binary producer and runtime path for internal validation
