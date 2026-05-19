# Control Plane UI Provider Optional Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow each deployment stack to configure Firebase only, Supabase only, or both for Control Plane UI browser auth settings.

**Architecture:** Keep the change inside `ltbase-private-deployment` by introducing one shared provider-validation helper in the bootstrap env library, then reusing it from the scripts that currently require all four browser auth variables. Generate `CONTROLPLANE_UI_STACK_CONFIG` dynamically so only fully configured providers are emitted.

**Tech Stack:** Bash, Python 3, shell test scripts

---

### Task 1: Add shared provider validation and dynamic config generation

**Files:**
- Modify: `scripts/lib/bootstrap-env.sh`

- [ ] **Step 1: Write the failing test expectations to support provider-optional behavior**

Update existing tests to expect these new outcomes from library callers:

```text
Firebase pair present + Supabase pair absent => success
Supabase pair present + Firebase pair absent => success
Either pair partially present => fail
No provider pairs present => fail
Generated authProviders array contains only configured providers
```

- [ ] **Step 2: Add a shared validation helper in `scripts/lib/bootstrap-env.sh`**

Implement a helper with this shape near the existing stack validation helpers:

```bash
bootstrap_env_require_controlplane_ui_auth_provider() {
  local stack="$1"
  local upper_name firebase_project_id firebase_api_key supabase_url supabase_anon_key

  upper_name="$(bootstrap_env_stack_upper "${stack}")"
  firebase_project_id="$(bootstrap_env_resolve_stack_value FIREBASE_PROJECT_ID "${stack}")"
  firebase_api_key="$(bootstrap_env_resolve_stack_value FIREBASE_API_KEY "${stack}")"
  supabase_url="$(bootstrap_env_resolve_stack_value SUPABASE_URL "${stack}")"
  supabase_anon_key="$(bootstrap_env_resolve_stack_value SUPABASE_ANON_KEY "${stack}")"

  if [[ -n "${firebase_project_id}" || -n "${firebase_api_key}" ]]; then
    if [[ -z "${firebase_project_id}" || -z "${firebase_api_key}" ]]; then
      printf 'Firebase control plane UI config for stack %s must include both FIREBASE_PROJECT_ID_%s and FIREBASE_API_KEY_%s\n' "${stack}" "${upper_name}" "${upper_name}" >&2
      return 1
    fi
  fi

  if [[ -n "${supabase_url}" || -n "${supabase_anon_key}" ]]; then
    if [[ -z "${supabase_url}" || -z "${supabase_anon_key}" ]]; then
      printf 'Supabase control plane UI config for stack %s must include both SUPABASE_URL_%s and SUPABASE_ANON_KEY_%s\n' "${stack}" "${upper_name}" "${upper_name}" >&2
      return 1
    fi
  fi

  if [[ -n "${firebase_project_id}" && -n "${firebase_api_key}" ]]; then
    return 0
  fi

  if [[ -n "${supabase_url}" && -n "${supabase_anon_key}" ]]; then
    return 0
  fi

  printf 'stack %s must configure at least one control plane UI auth provider: Firebase or Supabase\n' "${stack}" >&2
  return 1
}
```

- [ ] **Step 3: Make `bootstrap_env_controlplane_ui_stack_config_json()` emit only configured providers**

Adjust the embedded Python so it builds `authProviders` dynamically instead of always appending both providers:

```python
    auth_providers = []
    if firebase_project_id and firebase_api_key:
        auth_providers.append(
            {
                "type": "firebase",
                "name": provider_names["firebase"],
                "label": titleize_provider(provider_names["firebase"]),
                "firebaseProjectId": firebase_project_id,
                "firebaseApiKey": firebase_api_key,
            }
        )
    if supabase_url and supabase_anon_key:
        auth_providers.append(
            {
                "type": "supabase",
                "name": provider_names["supabase"],
                "label": titleize_provider(provider_names["supabase"]),
                "supabaseUrl": supabase_url,
                "supabaseAnonKey": supabase_anon_key,
            }
        )

    payload["stacks"].append(
        {
            ...,
            "authProviders": auth_providers,
        }
    )
```

- [ ] **Step 4: Run targeted tests for config generation**

Run: `./test/render-controlplane-ui-config-test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/bootstrap-env.sh
git commit -m "fix: allow single controlplane auth provider"
```

### Task 2: Update script callers to use the shared provider validation

**Files:**
- Modify: `scripts/bootstrap-deployment-repo.sh`
- Modify: `scripts/evaluate-and-continue.sh`
- Modify: `scripts/bootstrap-controlplane-ui-companion.sh`

- [ ] **Step 1: Write the failing test scenarios in existing script tests**

Add or adjust scenarios so these script entrypoints accept Firebase-only and Supabase-only inputs, and reject partial provider pairs.

```text
bootstrap-deployment-repo Firebase-only => success
bootstrap-deployment-repo partial Supabase => fail
evaluate-and-continue Firebase-only => success
bootstrap-controlplane-ui-companion Firebase-only => success
```

- [ ] **Step 2: Replace unconditional four-variable checks with the shared helper**

Use this call pattern in each script after the existing generic stack requirements:

```bash
if ! bootstrap_env_require_controlplane_ui_auth_provider "${STACK}"; then
  exit 1
fi
```

For scripts that iterate all stacks, validate inside the existing loop:

```bash
if ! bootstrap_env_require_controlplane_ui_auth_provider "${stack}"; then
  exit 1
fi
```

- [ ] **Step 3: Run targeted script tests**

Run:

```bash
./test/bootstrap-deployment-repo-test.sh
./test/evaluate-and-continue-test.sh
./test/bootstrap-controlplane-ui-companion-test.sh
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/bootstrap-deployment-repo.sh scripts/evaluate-and-continue.sh scripts/bootstrap-controlplane-ui-companion.sh
git commit -m "fix: validate optional controlplane auth providers"
```

### Task 3: Expand regression tests for single-provider stacks

**Files:**
- Modify: `test/bootstrap-deployment-repo-test.sh`
- Modify: `test/evaluate-and-continue-test.sh`
- Modify: `test/bootstrap-controlplane-ui-companion-test.sh`
- Modify: `test/render-controlplane-ui-config-test.sh`

- [ ] **Step 1: Add Firebase-only and Supabase-only fixtures**

Follow the existing inline env fixture style, for example:

```bash
FIREBASE_API_KEY_DEVO=public-firebase-key-devo
FIREBASE_PROJECT_ID_DEVO=firebase-project-devo
SUPABASE_URL_DEVO=
SUPABASE_ANON_KEY_DEVO=
```

and the inverse:

```bash
FIREBASE_API_KEY_DEVO=
FIREBASE_PROJECT_ID_DEVO=
SUPABASE_URL_DEVO=https://devo-project.supabase.co
SUPABASE_ANON_KEY_DEVO=public-supabase-key-devo
```

- [ ] **Step 2: Add assertions for dynamic `authProviders` output**

Use existing `assert_file_contains` and `assert_log_contains` helpers to verify only the configured provider appears:

```bash
assert_file_contains "${output_file}" '"authProviders":[{"type":"firebase"'
assert_file_not_contains "${output_file}" '"type":"supabase"'
```

and the reverse for Supabase-only cases.

- [ ] **Step 3: Add assertions for partial provider failures**

Verify the targeted error messages from the new helper:

```bash
assert_log_contains "${log_file}" "Firebase control plane UI config for stack devo must include both FIREBASE_PROJECT_ID_DEVO and FIREBASE_API_KEY_DEVO"
assert_log_contains "${log_file}" "Supabase control plane UI config for stack devo must include both SUPABASE_URL_DEVO and SUPABASE_ANON_KEY_DEVO"
```

- [ ] **Step 4: Run the focused regression suite**

Run:

```bash
./test/bootstrap-deployment-repo-test.sh
./test/evaluate-and-continue-test.sh
./test/bootstrap-controlplane-ui-companion-test.sh
./test/render-controlplane-ui-config-test.sh
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/bootstrap-deployment-repo-test.sh test/evaluate-and-continue-test.sh test/bootstrap-controlplane-ui-companion-test.sh test/render-controlplane-ui-config-test.sh
git commit -m "test: cover optional controlplane auth providers"
```

### Task 4: Re-validate the internal demo repository

**Files:**
- Modify: `../ltbase-private-deployment-demo01/.env`
- Verify: `../ltbase-private-deployment-demo01/scripts/bootstrap-deployment-repo.sh`

- [ ] **Step 1: Keep the demo repo on Firebase-only input**

Ensure these values remain present in `../ltbase-private-deployment-demo01/.env`:

```bash
CONTROLPLANE_UI_DOMAIN=demo01-admin.ltbase.dev
CONTROLPLANE_UI_PAGES_PROJECT=ltbase-private-deployment-demo01-controlplane-ui
FIREBASE_API_KEY_DEVO=firebase_key
FIREBASE_PROJECT_ID_DEVO=firebase_project
SUPABASE_URL_DEVO=
SUPABASE_ANON_KEY_DEVO=
LTBASE_RELEASE_ID=v1.0.23
```

- [ ] **Step 2: Sync the changed template files into the demo repo if needed**

Copy or re-sync only the modified script files that own this behavior so the validation repo matches the updated template behavior before rerunning bootstrap.

- [ ] **Step 3: Re-run bootstrap**

Run: `./scripts/bootstrap-deployment-repo.sh --env-file .env --stack devo --infra-dir infra`

Expected: script proceeds past provider validation and writes repo variables/secrets or fails later for a different verified reason.

- [ ] **Step 4: Commit if requested**

```bash
git add scripts/bootstrap-deployment-repo.sh scripts/lib/bootstrap-env.sh scripts/bootstrap-controlplane-ui-companion.sh scripts/evaluate-and-continue.sh test/bootstrap-deployment-repo-test.sh test/evaluate-and-continue-test.sh test/bootstrap-controlplane-ui-companion-test.sh test/render-controlplane-ui-config-test.sh
git commit -m "fix: allow single controlplane auth provider"
```
