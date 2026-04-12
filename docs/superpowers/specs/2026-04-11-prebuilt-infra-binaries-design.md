# Prebuilt Infra Binaries Distribution Design

## Purpose

Move prebuilt Pulumi infra binaries out of blueprint-local GitHub Actions artifacts and into a dedicated public distribution repository so official workflows can consume stable multi-arch binaries without tying their lifecycle to `ltbase-private-deployment` releases.

The immediate target is the LTBase private deployment blueprint flow:

- producer source repo: `ltbase-private-deployment`
- binary distribution repo: `ltbase-private-deployment-binaries`
- consumer workflow repo: `ltbase-deploy-workflows`

## Background

Phase 1 added commit-bound prebuilt infra binaries directly in the blueprint repositories as GitHub Actions artifacts. That solved repeated recompilation of the Pulumi Go program, but it has three limitations:

1. artifact retention is not a long-term distribution mechanism
2. artifacts are awkward for multi-arch publishing and discovery
3. the blueprint source repo should not become the long-term binary registry

The user wants a dedicated public repository for binaries with these rules:

- repo name: `ltbase-private-deployment-binaries`
- release tag format: `r<timestamp>`
- asset names:
  - `ltbase-infra-bin-linux-amd64.tar.gz`
  - `ltbase-infra-bin-linux-arm64.tar.gz`

The user also wants to avoid recompiling on every unrelated blueprint repo update and to support both Linux x64 and ARM64.

## Scope

This design covers:

- publishing prebuilt infra binaries from `ltbase-private-deployment` into `ltbase-private-deployment-binaries`
- release and manifest contract for binary discovery
- multi-arch binary publishing for `linux/amd64` and `linux/arm64`
- consumption logic in `ltbase-deploy-workflows`
- fallback behavior when no matching binary exists

It does not cover:

- moving application release assets out of `ltbase-releases`
- customer fork publication into the new binaries repo
- signing, attestations, or provenance beyond checksums in this version
- deprecating the existing source-build fallback

## Decisions

### 1. Use a dedicated public binaries repo

Prebuilt infra binaries will live in a separate public repository named `ltbase-private-deployment-binaries`.

Rationale:

- keeps blueprint source and binary distribution separate
- avoids polluting `ltbase-private-deployment` with high-volume machine-oriented releases
- avoids mixing blueprint binaries into `ltbase-releases`, which is reserved for official application release assets

### 2. Publish by source commit, not by application release ID

The binary identity is tied to the exact blueprint source commit that produced it.

The binary is not an application release asset. It is a build artifact for the Pulumi program owned by the blueprint repo. Matching must therefore use:

- source repository
- source commit
- target architecture

Tag names such as `r<timestamp>` are only containers for publication. They are not semantic version identifiers for the consumer.

### 3. Support two Linux architectures in version 1

The binaries repo will publish:

- `linux/amd64`
- `linux/arm64`

These map to the two expected runtime targets for CI and operational flexibility.

### 4. Publish only when build-relevant inputs change

Automatic publishing from `ltbase-private-deployment` should trigger only when changes can affect the compiled Pulumi program or its execution contract.

Initial path filter:

- `infra/**`
- `.github/workflows/build-infra-binary*.yml`
- `docs/` excluded
- top-level docs and onboarding changes excluded unless they also touch infra build inputs

This avoids recompiling on documentation-only or unrelated template maintenance changes.

### 5. Keep source-build fallback as the correctness path

`ltbase-deploy-workflows` will treat the binaries repo as an optimization layer only.

If the workflow cannot find a matching binary for the exact source commit and current architecture, or if checksum validation fails, it must continue with the existing wrapper-based source build path.

This preserves correctness and keeps official workflows resilient during publication lag or transient release lookup failures.

### 6. Use timestamp tags plus manifest-driven lookup

Each publication in `ltbase-private-deployment-binaries` creates a new release tagged `r<timestamp>`.

Consumers must not infer semantics from the tag. They must inspect `manifest.json` to find a binary whose:

- `source_repository` matches the current blueprint repo
- `source_commit` matches the checked-out commit exactly
- `arch` matches the current runner architecture

This keeps the tag format simple while making matching explicit and future-proof.

## Architecture

## Producer side: `ltbase-private-deployment`

The blueprint repo keeps owning the source code and the build recipe.

Producer workflow responsibilities:

1. detect whether a push or manual run should publish binaries
2. build `ltbase-infra` for `linux/amd64` and `linux/arm64`
3. package each binary as:
   - `ltbase-infra-bin-linux-amd64.tar.gz`
   - `ltbase-infra-bin-linux-arm64.tar.gz`
4. generate a single `manifest.json`
5. create a release in `ltbase-private-deployment-binaries` tagged `r<timestamp>`
6. upload both tarballs plus `manifest.json`

The producer must publish metadata that allows exact source-commit lookup. It should not require the consumer to guess which release belongs to which source commit.

## Distribution side: `ltbase-private-deployment-binaries`

This repository is a release-only distribution channel for public blueprint binaries.

Expected contents per release:

- `ltbase-infra-bin-linux-amd64.tar.gz`
- `ltbase-infra-bin-linux-arm64.tar.gz`
- `manifest.json`

The repo should not store blueprint source code.

## Consumer side: `ltbase-deploy-workflows`

The reusable workflows gain a lookup path that:

1. identifies the checked-out blueprint repository and commit
2. determines the runner architecture
3. queries `ltbase-private-deployment-binaries` releases
4. downloads `manifest.json` from candidate releases
5. finds the matching artifact by source repo, source commit, and arch
6. downloads the corresponding tarball
7. verifies checksum
8. installs `ltbase-infra` into `blueprint/<working_directory>/.pulumi/bin/ltbase-infra`

If any step fails to produce a trustworthy exact match, the workflow emits `installed=false` and leaves the current wrapper path to build from source.

## Manifest contract

Each release includes one `manifest.json` with this shape:

```json
{
  "source_repository": "Lychee-Technology/ltbase-private-deployment",
  "source_commit": "<git sha>",
  "source_ref": "main",
  "release_tag": "r20260411T120102Z",
  "artifacts": [
    {
      "file": "ltbase-infra-bin-linux-amd64.tar.gz",
      "arch": "linux-amd64",
      "sha256": "...",
      "go_version": "go1.x.y",
      "built_at": "2026-04-11T12:01:02Z"
    },
    {
      "file": "ltbase-infra-bin-linux-arm64.tar.gz",
      "arch": "linux-arm64",
      "sha256": "...",
      "go_version": "go1.x.y",
      "built_at": "2026-04-11T12:01:02Z"
    }
  ]
}
```

Notes:

- `source_commit` is the primary identity field for consumers
- `release_tag` is recorded for auditability only
- `arch` values should use the same strings as the asset suffixes to avoid translation ambiguity

## Data flow

1. A change lands in `ltbase-private-deployment` that affects infra build output.
2. The producer workflow builds both Linux binaries.
3. The workflow creates a release in `ltbase-private-deployment-binaries` tagged `r<timestamp>`.
4. The release publishes both tarballs and `manifest.json`.
5. A reusable workflow in `ltbase-deploy-workflows` checks out the blueprint repo.
6. Before Pulumi runs, it looks for a matching binary in `ltbase-private-deployment-binaries`.
7. If it finds a release whose manifest matches the checked-out source commit and current architecture, it downloads and installs the binary.
8. If it does not find one, or validation fails, the blueprint wrapper builds from source.

## Error handling and operator experience

Expected situations:

- no matching binary exists yet for the current commit
- binary release publication is delayed relative to source push
- checksum mismatch or malformed manifest
- target architecture not published

All of these should degrade to source build, not workflow failure.

Workflow logs should clearly say whether execution used:

- prebuilt binary from `ltbase-private-deployment-binaries`, or
- source-build fallback via `infra/scripts/pulumi-wrapper.sh`

## Testing

### Producer tests

- validate release packaging names for both architectures
- validate `manifest.json` fields and checksums
- validate path filters only publish when build-relevant inputs change

### Consumer tests

- install succeeds when source repo, source commit, and arch all match
- install skips when commit differs
- install skips when arch is missing
- install skips on checksum mismatch
- fallback path remains green when no release matches

### End-to-end verification

- publish one release from `ltbase-private-deployment` into `ltbase-private-deployment-binaries`
- confirm `ltbase-deploy-workflows` can download `linux-arm64` on the ARM runner path
- confirm forcing a commit without a published binary still succeeds via source build fallback

## Trade-offs

Pros:

- clean separation between blueprint source and binary distribution
- long-lived multi-arch binary retention
- exact source-commit matching remains possible
- reusable workflows stay resilient through fallback

Cons:

- one more repository and publication token to manage
- consumer logic becomes release-search based instead of local-artifact based
- timestamp-tagged releases are machine-oriented and not especially human-friendly

## Rollout plan

### Phase 2A

- create `ltbase-private-deployment-binaries`
- make `ltbase-private-deployment` publish both architectures there
- make `ltbase-deploy-workflows` query the binaries repo first, then fall back to source build

### Phase 2B

- decide whether `demo01` or other official blueprint repos should publish to the same binaries repo using the same manifest contract
- keep the contract generic enough to support multiple source repositories without changing consumer semantics
