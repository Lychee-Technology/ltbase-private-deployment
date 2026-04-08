# Auth Gateway Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit API Gateway route and JWT authorizer configuration in `ltbase-private-deployment`, with per-stack `PROJECT_ID` and per-stack auth provider config files.

**Architecture:** Keep `api`, `control-plane`, and `auth` as three separate HTTP APIs, but move route/auth wiring from two wildcard routes into a route-spec driven model. `api` gets explicit routes with LTBase JWT auth, `control-plane` keeps wildcard routes with LTBase JWT auth, and `auth` gets explicit routes generated from a user-supplied per-stack provider config file.

**Tech Stack:** Bash bootstrap scripts, Pulumi Go, AWS API Gateway v2, Lambda, S3 runtime bucket, GitHub Actions bootstrap tests.

---

### Task 1: Extend deployment inputs and examples

**Files:**
- Modify: `env.template`
- Modify: `infra/Pulumi.devo.yaml.example`
- Modify: `infra/Pulumi.prod.yaml.example`
- Create: `infra/auth-providers.devo.json.example`
- Create: `infra/auth-providers.prod.json.example`
- Modify: `docs/onboarding/04-prepare-env-file.md`
- Modify: `docs/onboarding/04-prepare-env-file.zh.md`

- [ ] Add `PROJECT_ID_<STACK>` and `AUTH_PROVIDER_CONFIG_FILE_<STACK>` to `env.template` with comments explaining one project ID and one provider file per stack.
- [ ] Add `ltbase-infra:projectId` and `ltbase-infra:authProviderConfigFile` to both example Pulumi stack files.
- [ ] Create example provider config JSON files with a `providers` array and two sample providers.
- [ ] Update onboarding docs to list the new required inputs and explain the provider file format at a high level.
- [ ] Manually review examples to ensure paths and variable names match the rest of the bootstrap flow.

### Task 2: Extend bootstrap env resolution and script checks

**Files:**
- Modify: `scripts/lib/bootstrap-env.sh`
- Modify: `scripts/bootstrap-deployment-repo.sh`
- Modify: `scripts/evaluate-and-continue.sh`
- Test: `test/bootstrap-deployment-repo-test.sh`
- Test: `test/bootstrap-all-test.sh`
- Test: `test/evaluate-and-continue-test.sh`

- [ ] Update env resolution so `PROJECT_ID_<STACK>` and `AUTH_PROVIDER_CONFIG_FILE_<STACK>` resolve like other per-stack values.
- [ ] Require those values in bootstrap validation for each selected stack.
- [ ] Add `pulumi config set projectId ... --stack <stack>` and `pulumi config set authProviderConfigFile ... --stack <stack>` in `scripts/bootstrap-deployment-repo.sh`.
- [ ] Update shell tests to include the new env vars in fixture `.env` data.
- [ ] Add assertions that the new `pulumi config set` commands are emitted for the selected stack.
- [ ] Run the three shell tests and fix any expected output mismatches.

### Task 3: Extend Pulumi stack config model

**Files:**
- Modify: `infra/internal/config/config.go`
- Test: `infra/internal/config/config_test.go`

- [ ] Add `ProjectID` and `AuthProviderConfigFile` to `StackConfig`.
- [ ] Load both fields from Pulumi config with `cfg.Require(...)`.
- [ ] Keep validation minimal: require values through config loading instead of adding unnecessary custom rules.
- [ ] Add tests for default behavior already covered in the file and at least one positive test that confirms the new fields can coexist with the rest of the config model.

### Task 4: Add provider config loading in infra

**Files:**
- Create: `infra/internal/services/auth_provider_config.go`
- Test: `infra/internal/services/auth_provider_config_test.go`

- [ ] Add a small loader that reads the JSON file pointed to by `cfg.AuthProviderConfigFile`.
- [ ] Define minimal types for the file shape: provider `name`, `issuer`, `audiences`, `enable_login`, and `enable_id_binding`.
- [ ] Validate the loaded config enough to reject empty provider names, empty issuers, and empty audience lists.
- [ ] Add tests for valid config, invalid JSON, duplicate provider names, and missing required fields.

### Task 5: Upload provider config for auth Lambda consumption

**Files:**
- Modify: `infra/internal/services/lambda.go`
- Test: `infra/internal/services/lambda_test.go`

- [ ] Upload the per-stack provider config file into the runtime bucket during deployment.
- [ ] Inject auth Lambda environment variables describing where to find that config at runtime.
- [ ] Keep the data plane and control-plane Lambda environment unchanged except for any shared helper refactor needed to support this upload.
- [ ] Add tests that assert the auth Lambda env contains the new config location variable(s).

### Task 6: Refactor API Gateway creation into route specs and authorizer specs

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Replace the current hardcoded `ANY /` and `ANY /{proxy+}` route creation with a route-spec driven helper.
- [ ] Add JWT authorizer creation support for API Gateway v2.
- [ ] Build LTBase authorizer settings from `cfg.OIDCIssuerURL` and `cfg.ProjectID`.
- [ ] Preserve stage, custom domain, DNS, mapping, integration, and Lambda permission behavior.
- [ ] Add tests that cover route spec generation and authorizer assignment without requiring a live AWS deployment.

### Task 7: Define `api` explicit routes

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Add explicit `api` route definitions for:
- [ ] `GET /api/ai/v1/notes`
- [ ] `POST /api/ai/v1/notes`
- [ ] `GET /api/ai/v1/notes/{note_id}`
- [ ] `PUT /api/ai/v1/notes/{note_id}`
- [ ] `DELETE /api/ai/v1/notes/{note_id}`
- [ ] `GET /api/v1/deepping`
- [ ] `GET /api/v1/{schema_name}`
- [ ] `POST /api/v1/{schema_name}`
- [ ] `GET /api/v1/{schema_name}/{row_id}`
- [ ] `PUT /api/v1/{schema_name}/{row_id}`
- [ ] `DELETE /api/v1/{schema_name}/{row_id}`
- [ ] Attach LTBase JWT auth to all of them.

### Task 8: Keep `control-plane` wildcard routes with LTBase JWT auth

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Keep `ANY /` and `ANY /{proxy+}` as the control-plane route set.
- [ ] Attach LTBase JWT auth to both routes.
- [ ] Ensure no other explicit control-plane route expansion is introduced.

### Task 9: Generate `auth` routes and third-party authorizers from provider config

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Test: `infra/internal/services/apigateway_test.go`

- [ ] Add public route `GET /api/v1/auth/health`.
- [ ] Add LTBase-protected route `POST /api/v1/auth/refresh`.
- [ ] For each configured provider, generate:
- [ ] `POST /api/v1/login/{provider}`
- [ ] `POST /api/v1/id_bindings/{provider}`
- [ ] For each configured provider, create a JWT authorizer using its `issuer` and `audiences`.
- [ ] Respect `enable_login` and `enable_id_binding` flags when generating routes.

### Task 10: Verify end-to-end infra behavior

**Files:**
- Verify: `test/bootstrap-deployment-repo-test.sh`
- Verify: `test/bootstrap-all-test.sh`
- Verify: `test/evaluate-and-continue-test.sh`
- Verify: `infra/internal/config/config_test.go`
- Verify: `infra/internal/services/auth_provider_config_test.go`
- Verify: `infra/internal/services/lambda_test.go`
- Verify: `infra/internal/services/apigateway_test.go`

- [ ] Run shell tests: `./test/bootstrap-deployment-repo-test.sh`, `./test/bootstrap-all-test.sh`, and `./test/evaluate-and-continue-test.sh`.
- [ ] Run Go tests in infra with `go test ./...` from `infra`.
- [ ] Run a `pulumi preview` for one stack using a sample provider file and confirm the preview includes explicit routes and JWT authorizers.
- [ ] Verify the auth provider config file path in Pulumi config actually points to a checked-in per-stack file.
