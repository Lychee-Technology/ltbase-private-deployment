# Entrypoint Info Logging Design

## Purpose

Reduce noisy command output from the customer-facing shell entrypoints in `ltbase-private-deployment` so routine runs show concise `info`-level progress only.

The user wants default output to stay short and readable and does not want a verbose mode in this change.

## Scope

This design covers the public shell entrypoints in `scripts/`:

- `bootstrap-all.sh`
- `create-deployment-repo.sh`
- `render-bootstrap-policies.sh`
- `bootstrap-aws-foundation.sh`
- `bootstrap-oidc-discovery-companion.sh`
- `bootstrap-deployment-repo.sh`
- `evaluate-and-continue.sh`
- `update-sync-template-tooling.sh`
- `sync-template-upstream.sh`

It covers default operator output and failure output for those scripts.

It does not cover:

- `infra/cmd/ltbase-infra/main.go` or Pulumi program logging
- adding a `--verbose` or log-level flag
- changing error semantics or control flow

## Problem

The current entrypoints directly invoke tools such as `gh`, `pulumi`, `aws`, and `curl`. Many of those commands emit success-path output that is useful for debugging but too noisy for routine operator use.

The result is that bootstrap and maintenance flows produce long logs even when everything is healthy.

## Decision

Default behavior will become concise `info` logging:

- entrypoint scripts print short stage-level progress messages
- successful external command output is suppressed by default
- failed external commands still print their captured output to help diagnosis
- existing explicit validation errors remain visible

There will be no verbose mode in this version.

## Recommended Approach

Add a very small shared logging helper in `scripts/lib/bootstrap-env.sh` because that file is already sourced by the entrypoints.

The helper should provide two primitives:

1. `bootstrap_env_info <message>`
2. `bootstrap_env_run_quiet <command ...>`

Behavior:

- `bootstrap_env_info` prints one concise progress line to stdout
- `bootstrap_env_run_quiet` captures stdout and stderr from the wrapped command
- if the command succeeds, the wrapper returns success without replaying captured output
- if the command fails, the wrapper replays captured output to stderr and returns the same exit status

This keeps the change small and avoids introducing a separate shell framework.

## Script-Level Changes

### `bootstrap-all.sh`

Add top-level stage messages before invoking each child script so operators can still see high-level progress through the bootstrap flow.

### `create-deployment-repo.sh`

Wrap GitHub create and environment setup calls so successful `gh` output is hidden. Keep one-line info messages such as ensuring the deployment repository and protected environments.

### `render-bootstrap-policies.sh`

This script already writes files rather than printing much runtime output. Keep it mostly unchanged unless there are noisy external commands during verification.

### `bootstrap-aws-foundation.sh`

Wrap AWS IAM, KMS, and S3 commands. Emit short info messages per stack and for shared backend bucket setup.

### `bootstrap-oidc-discovery-companion.sh`

Wrap `gh` and `curl` success-path output. Emit short info messages for companion repo creation, Pages project setup, domain binding, DNS reconciliation, and discovery role reconciliation.

### `bootstrap-deployment-repo.sh`

Wrap `gh` variable and secret operations plus Pulumi login, stack selection/init, and config writes. Emit short info messages for repo configuration and stack configuration.

### `evaluate-and-continue.sh`

Keep the generated report files and status summary. Ensure remediation actions taken through child scripts or external commands use quiet wrappers so the terminal output stays focused on evaluated status and next actions.

### `update-sync-template-tooling.sh` and `sync-template-upstream.sh`

Keep their final summary lines, but suppress success-path git plumbing output.

## Error Handling

Failure behavior must stay operator-friendly:

- validation failures continue printing direct human-readable messages
- wrapped command failures replay the captured command output
- wrappers preserve the original exit code so calling scripts still fail fast under `set -e`

This preserves debuggability without keeping routine success output visible.

## Testing

Follow TDD for the logging behavior.

Initial regression coverage should focus on the shared wrapper behavior because that is the highest leverage point:

- a success-path test proves wrapped commands do not leak verbose stdout/stderr
- a failure-path test proves captured stderr/stdout is replayed and the exit status is preserved

Then add at least one entrypoint-focused regression test around a representative script, likely `bootstrap-all.sh` or `bootstrap-deployment-repo.sh`, to verify that:

- concise info lines remain visible
- raw tool output is hidden on success

## Risks and Constraints

- over-suppressing output could make operators unsure whether a long-running step is still active, so stage-level info messages are required
- `evaluate-and-continue.sh` already writes machine-readable report files; those outputs must remain intact
- wrapping commands must not accidentally swallow non-zero exit codes or reorder meaningful stderr on failure

## Implementation Notes

- prefer the smallest possible helper additions in `scripts/lib/bootstrap-env.sh`
- keep existing script interfaces unchanged
- do not modify Go logging in `infra/` for this task
- do not add a future-facing verbose flag unless the implementation needs a tiny internal hook to keep the wrapper code clean
