# Pulumi Config Drift Check Design

## Context

`ltbase-private-deployment` generates customer deployment repositories whose Pulumi stack files are initially populated by `scripts/bootstrap-deployment-repo.sh`.

The infrastructure program now requires `deploymentAwsAccountId` via `cfg.Require("deploymentAwsAccountId")` in `infra/internal/config/config.go`. A generated repo failed deployment because its existing `infra/Pulumi.devo.yaml` did not contain `ltbase-infra:deploymentAwsAccountId`, which caused a Pulumi runtime panic instead of an actionable operator error.

The root problem is config drift between the current template's required Pulumi config schema and older or partially bootstrapped generated repositories.

## Goal

Fail early and clearly when a generated deployment repository is missing required Pulumi stack config keys.

## Non-Goals

- Do not add deploy-time auto-healing or mutation of Pulumi stack config.
- Do not change `scripts/bootstrap-deployment-repo.sh` to stop writing `deploymentAwsAccountId`.
- Do not infer or synthesize missing config values during rollout.

## Chosen Approach

Keep bootstrap as the authoritative writer of required Pulumi config values and add a pre-deploy drift check in the generated deployment repository workflows.

This drift check will validate that `infra/Pulumi.<stack>.yaml` contains a defined set of required `ltbase-infra:*` keys before preview or rollout invokes the reusable deployment workflows.

## Alternatives Considered

### Bootstrap Only

Rely exclusively on bootstrap to populate required keys.

Rejected because it does not protect already-generated repositories whose stack files predate newer required config keys.

### Bootstrap Plus Auto-Heal

Derive and write missing values during workflow runtime.

Rejected because it makes deployment workflows mutate customer config, adds hidden behavior, and couples runtime logic to derivation assumptions.

## Design

### Validation Script

Add a small script to the template repository that:

- accepts a stack name
- reads `infra/Pulumi.<stack>.yaml`
- verifies the file exists
- verifies the `config:` block contains each required key
- exits non-zero with a targeted error message when a key is missing

The script will validate only presence, not semantic correctness. That keeps the behavior minimal and avoids duplicating Pulumi or application-level validation.

The initial required-key set should include the current `cfg.Require(...)` keys that are expected to be present in stack YAML, including:

- `ltbase-infra:deploymentAwsAccountId`
- `ltbase-infra:runtimeBucket`
- `ltbase-infra:tableName`
- `ltbase-infra:mtlsTruststoreFile`
- `ltbase-infra:mtlsTruststoreKey`
- `ltbase-infra:apiDomain`
- `ltbase-infra:controlPlaneDomain`
- `ltbase-infra:authDomain`
- `ltbase-infra:projectId`
- `ltbase-infra:authProviderConfigFile`
- `ltbase-infra:cloudflareZoneId`
- `ltbase-infra:oidcIssuerUrl`
- `ltbase-infra:jwksUrl`
- `ltbase-infra:releaseId`
- `ltbase-infra:githubOrg`
- `ltbase-infra:githubRepo`
- `ltbase-infra:githubOidcProviderArn`
- `ltbase-infra:geminiApiKey`

Optional keys loaded with defaults or `Get(...)` remain out of scope.

### Workflow Integration

Invoke the validation script in the generated repo's local workflows before they call the reusable workflows from `ltbase-deploy-workflows`.

This applies to:

- manual preview workflow
- first-stack deploy workflow
- rollout hop workflow path before reusable workflow dispatch

Placing the check in the generated repo keeps the error local to repository-owned config and avoids pushing template-specific file checks into the shared reusable workflow layer.

### Failure UX

On failure, print:

- the missing key name
- the stack file path
- a short recovery instruction to rerun bootstrap or repair the stack file

Example shape:

`Missing required Pulumi config key 'ltbase-infra:deploymentAwsAccountId' in infra/Pulumi.devo.yaml. Rerun bootstrap-deployment-repo.sh or update the stack config file.`

### Testing

Add a regression test for the validation script that covers:

- success when all required keys exist
- failure when `deploymentAwsAccountId` is missing
- failure when the stack file does not exist

If workflow tests already cover local workflow shell logic, add the new check there only if the existing test surface makes that cheap. Otherwise keep workflow verification focused on the script-level regression test.

### Documentation

Add a short note to onboarding or day-2 docs explaining that deployments now fail early when required stack config is missing and that the expected repair path is rerunning bootstrap or manually restoring the missing config key.

## Data Flow

1. Operator dispatches preview or deployment workflow in generated repo.
2. Local workflow resolves target stack.
3. Local workflow runs config drift check against `infra/Pulumi.<stack>.yaml`.
4. If validation fails, workflow stops with a precise message.
5. If validation passes, workflow proceeds into the reusable deployment workflow.

## Error Handling

- Missing stack file: fail with explicit file path.
- Missing required key: fail with explicit key name and recovery hint.
- No attempt is made to repair the file automatically.

## Rollout Strategy

This change protects newly generated repositories and any existing repositories that later sync workflow/script changes from the upstream template.

It does not retroactively fix already-missing keys. Existing repos still need either:

- a bootstrap rerun, or
- a manual stack file repair

## Open Questions

None. The implementation intentionally stays at presence-only validation and local workflow gating.
