# Explicit API Gateway Routes — Implementation Plan

> **Goal:** Replace `ANY /{proxy+}` catch-all routes with explicit `METHOD /path` routes for Data Plane, Control Plane, and AuthService APIs. Only `OPTIONS /{proxy+}` preflight routes remain unauthenticated and catch-all. Add `PATCH` to CORS allowed methods.

**Architecture:** Modify the Pulumi IaC route spec builders and their tests in `ltbase-private-deployment/infra/internal/services/apigateway.go`. Update `ltbase.api/AGENTS.md` to instruct agents to keep route specs in sync. Optionally update demo01 devo CORS config for local development.

**Repos affected:** `ltbase-private-deployment` (primary), `ltbase.api` (AGENTS.md), `ltbase-private-deployment-demo01` (config only).

---

## Task 1: Add route spec helper utilities

**Files:**
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway.go`
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway_test.go`

- [ ] **Step 1: Add helper functions**

Add helpers before the route builder functions to reduce duplication:

```go
// authorizedRoutes returns route specs with the given authorizer name applied to every route key.
func authorizedRoutes(authorizerName string, routeKeys ...string) []routeSpec {
	routes := make([]routeSpec, len(routeKeys))
	for i, key := range routeKeys {
		routes[i] = routeSpec{RouteKey: key, AuthorizerName: authorizerName}
	}
	return routes
}

// preflightRoutes returns unauthenticated OPTIONS preflight routes.
func preflightRoutes() []routeSpec {
	return []routeSpec{
		{RouteKey: "OPTIONS /"},
		{RouteKey: "OPTIONS /{proxy+}"},
	}
}

// prefixedRouteKeys prepends a prefix to each route key.
func prefixedRouteKeys(prefix string, routeKeys ...string) []string {
	out := make([]string, len(routeKeys))
	for i, key := range routeKeys {
		out[i] = prefix + key
	}
	return out
}

// controlPlaneRoutes returns routes for both /api/v1/... and /api/control-plane/v1/... prefixes.
func controlPlaneRoutes(routeKeys ...string) []routeSpec {
	var all []string
	all = append(all, prefixedRouteKeys("/api/v1", routeKeys...)...)
	all = append(all, prefixedRouteKeys("/api/control-plane/v1", routeKeys...)...)
	return authorizedRoutes("LTBase", all...)
}
```

- [ ] **Step 2: Write/build tests for helpers**

In `apigateway_test.go`, add:

```go
func TestAuthorizedRoutes(t *testing.T) {
	routes := authorizedRoutes("LTBase", "GET /x", "POST /y")
	if len(routes) != 2 {
		t.Fatalf("route count = %d, want 2", len(routes))
	}
	if routes[0].AuthorizerName != "LTBase" || routes[1].AuthorizerName != "LTBase" {
		t.Fatal("authorizer should be LTBase on all routes")
	}
}

func TestPreflightRoutesNoAuthorizer(t *testing.T) {
	routes := preflightRoutes()
	for _, r := range routes {
		if r.AuthorizerName != "" {
			t.Fatalf("preflight route %q has authorizer %q, want empty", r.RouteKey, r.AuthorizerName)
		}
	}
	if len(routes) != 2 {
		t.Fatalf("preflight route count = %d, want 2", len(routes))
	}
}

func TestPrefixedRouteKeys(t *testing.T) {
	keys := prefixedRouteKeys("/prefix", "/a", "/b")
	if len(keys) != 2 || keys[0] != "/prefix/a" || keys[1] != "/prefix/b" {
		t.Fatalf("prefixedRouteKeys = %#v", keys)
	}
}
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment
go test ./infra/internal/services
```

Expected: existing tests pass; new tests pass.

---

## Task 2: Replace Control Plane route specs

**Files:**
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway.go:153-157`
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway_test.go:39-47`

- [ ] **Step 1: Replace `buildControlPlaneRouteSpecs`**

Replace the catch-all function with explicit routes plus preflight:

```go
func buildControlPlaneRouteSpecs() []routeSpec {
	business := controlPlaneRoutes(
		"/status",
		"/schema/status",
		"/workflows",
		"/repair/dry-run",
		"/repair/apply",
		"/catalogs/capabilities",
		"/catalogs/action-templates",
		"/catalogs/assistant-roles",
		"/compliance-profile",
		"/auth-config",
		"/auth/config",
		"/referrals",
		"/referrals/{code}",
		"/referrals/{code}/disable",
		"/auth/referrals",
		"/auth/referrals/{code}",
		"/auth/referrals/{code}/disable",
		"/auth/users",
		"/auth/users/{user_id}",
		"/auth/users/{user_id}/roles/{role_id}",
		"/auth/roles",
		"/auth/roles/{role_id}",
		"/auth/policies",
		"/auth/policies/{policy_id}",
		"/auth/binding-policies",
		"/auth/binding-policies/{policy_id}",
		"/auth/principals/{principal_type}/{principal_id}/policies",
		"/auth/principals/{principal_type}/{principal_id}/policies/{policy_id}",
		"/org/units",
		"/org/units/{ou_id}",
		"/org/units/{ou_id}/users",
		"/org/units/{ou_id}/users/{user_id}",
		"/org/units/{ou_id}/policies",
		"/org/units/{ou_id}/policies/{policy_id}",
		"/org/users/{user_id}/manager",
		"/org/users/{user_id}/direct-reports",
		"/org/charts",
	)
	return append(business, preflightRoutes()...)
}
```

- [ ] **Step 2: Update test**

Replace `TestBuildControlPlaneRouteSpecs`:

```go
func TestBuildControlPlaneRouteSpecs(t *testing.T) {
	routes := buildControlPlaneRouteSpecs()
	// Verify no ANY routes for normal traffic
	for _, r := range routes {
		if r.RouteKey != "OPTIONS /" && r.RouteKey != "OPTIONS /{proxy+}" {
			if strings.Contains(r.RouteKey, "ANY") || strings.Contains(r.RouteKey, "{proxy+}") {
				t.Fatalf("normal route %q should not use ANY or {proxy+}", r.RouteKey)
			}
			if r.AuthorizerName != "LTBase" {
				t.Fatalf("route %q authorizer = %q, want LTBase", r.RouteKey, r.AuthorizerName)
			}
		} else {
			if r.AuthorizerName != "" {
				t.Fatalf("preflight route %q has authorizer %q, want empty", r.RouteKey, r.AuthorizerName)
			}
		}
	}
	// Spot-check key routes exist
	routeSet := make(map[string]bool)
	for _, r := range routes {
		routeSet[r.RouteKey] = true
	}
	mustExist := []string{
		"GET /api/v1/status",
		"POST /api/v1/repair/apply",
		"GET /api/v1/auth/config",
		"PATCH /api/v1/auth/users/{user_id}",
		"PUT /api/v1/org/units/{ou_id}/users/{user_id}",
		"OPTIONS /{proxy+}",
	}
	for _, key := range mustExist {
		if !routeSet[key] {
			t.Fatalf("missing route %q", key)
		}
	}
}
```

- [ ] **Step 3: Remove `legacyRouteAliasName` and `routeAliases`**

Since we're replacing `ANY /` and `ANY /{proxy+}` with explicit routes, the legacy alias machinery is no longer needed. Remove the functions and their tests (`TestControlRouteAliases`).

- [ ] **Step 4: Run tests**

```bash
go test ./infra/internal/services
```

---

## Task 3: Expand Data Plane route specs

**Files:**
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway.go:135-151`
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway_test.go:12-37`

- [ ] **Step 1: Replace `buildAPIRouteSpecs`**

Replace with explicit routes plus preflight:

```go
func buildAPIRouteSpecs() []routeSpec {
	business := authorizedRoutes("LTBase",
		// Notes
		"GET /api/ai/v1/notes",
		"POST /api/ai/v1/notes",
		"GET /api/ai/v1/notes/{note_id}",
		"PUT /api/ai/v1/notes/{note_id}",
		"DELETE /api/ai/v1/notes/{note_id}",
		"GET /api/ai/v1/notes/{note_id}/model_sync",
		"POST /api/ai/v1/notes/{note_id}/model_sync",
		// CRUD sessions
		"POST /api/ai/v1/sessions",
		"GET /api/ai/v1/sessions/{session_id}",
		"GET /api/ai/v1/sessions/{session_id}/messages",
		"POST /api/ai/v1/sessions/{session_id}/messages",
		"POST /api/ai/v1/operations",
		// Agent sessions
		"POST /api/ai/v1/agent/sessions",
		"GET /api/ai/v1/agent/sessions/{session_id}",
		"DELETE /api/ai/v1/agent/sessions/{session_id}",
		"GET /api/ai/v1/agent/sessions/{session_id}/turns",
		"POST /api/ai/v1/agent/sessions/{session_id}/turns",
		"GET /api/ai/v1/agent/sessions/{session_id}/turns/{turn_id}/citations",
		// Intent-to-action
		"POST /api/ai/v1/intent-to-action/plans",
		"POST /api/ai/v1/intent-to-action/executions",
		"GET /api/ai/v1/intent-to-action/executions/{execution_id}",
		// Governance action
		"POST /api/ai/v1/governance/actions/execute",
		// Compliance
		"POST /api/ai/v1/compliance/decisions",
		// Forma / metadata
		"GET /api/v1/deepping",
		"GET /api/v1/schemas",
		"GET /api/v1/tools",
		"GET /api/v1/audit_records",
		"GET /api/v1/search",
		"POST /api/v1/advanced_query",
		"GET /api/v1/{schema_name}",
		"POST /api/v1/{schema_name}",
		"DELETE /api/v1/{schema_name}",
		"GET /api/v1/{schema_name}/{row_id}",
		"PUT /api/v1/{schema_name}/{row_id}",
		"DELETE /api/v1/{schema_name}/{row_id}",
		// LTFlow
		"GET /api/ltflow/v1/tasks",
		"GET /api/ltflow/v1/tasks/{task_id}",
		"GET /api/ltflow/v1/instances",
		"POST /api/ltflow/v1/instances",
		"GET /api/ltflow/v1/instances/{instance_id}",
		"POST /api/ltflow/v1/instances/{instance_id}/events",
		"GET /api/ltflow/v1/instances/{instance_id}/history",
		// Discovery
		"POST /api/sys/v1/discovery/reachable",
		"POST /api/sys/v1/discovery/paths",
		// Ontology
		"GET /api/sys/v1/ontology/object-types",
		"GET /api/sys/v1/ontology/object-types/{type_name}",
		"GET /api/sys/v1/ontology/link-types",
		"GET /api/sys/v1/ontology/action-types",
		"GET /api/sys/v1/ontology/objects/{type_name}/{row_id}",
		"POST /api/sys/v1/ontology/objects/{type_name}/search",
		"POST /api/sys/v1/ontology/objects/{type_name}/{row_id}/reachable",
		"GET /api/sys/v1/ontology/objects/{type_name}/{row_id}/actions",
		"GET /api/sys/v1/ontology/objects/{type_name}/{row_id}/provenance",
		// Governance
		"GET /api/sys/v1/governance/entities/{entity}/capabilities",
		"GET /api/sys/v1/governance/capabilities/{capability}",
		"GET /api/sys/v1/governance/policies/{policy}/capabilities",
		"GET /api/sys/v1/governance/claims",
		"POST /api/sys/v1/governance/claims",
		"POST /api/sys/v1/governance/claims/{claim_id}/approve",
		"POST /api/sys/v1/governance/claims/{claim_id}/reject",
		"GET /api/sys/v1/governance/events",
		"POST /api/sys/v1/governance/evidence",
		"GET /api/sys/v1/governance/evidence/{evidence_id}/gaps",
		"GET /api/sys/v1/governance/evidence/{evidence_id}/expired",
		"POST /api/sys/v1/governance/evidence/{evidence_id}/validate",
		"POST /api/sys/v1/governance/monitoring/re-evaluate",
		// Compliance
		"GET /api/sys/v1/compliance/entities/{entity}",
		"GET /api/sys/v1/compliance/capabilities/{capability}",
		"GET /api/sys/v1/compliance/policies/{policy}",
		// Semantic
		"GET /api/v1/semantic/resources",
		"GET /api/v1/semantic/resources/{resource_id}",
		"GET /api/v1/semantic/lineage/{resource_id}",
	)
	return append(business, preflightRoutes()...)
}
```

Note the order: `GET /api/v1/{schema_name}` and `GET /api/v1/{schema_name}/{row_id}` must appear after `GET /api/v1/semantic/resources` etc. because API Gateway matches routes in specificity order (more static segments before parameterized ones). This is enforced naturally when routes have different static prefixes.

- [ ] **Step 2: Update `TestBuildAPIRouteSpecs`**

```go
func TestBuildAPIRouteSpecs(t *testing.T) {
	routes := buildAPIRouteSpecs()
	routeSet := make(map[string]bool)
	for _, r := range routes {
		routeSet[r.RouteKey] = true
		if r.RouteKey == "OPTIONS /" || r.RouteKey == "OPTIONS /{proxy+}" {
			if r.AuthorizerName != "" {
				t.Fatalf("preflight route %q has authorizer %q, want empty", r.RouteKey, r.AuthorizerName)
			}
			continue
		}
		if strings.Contains(r.RouteKey, "ANY") || strings.Contains(r.RouteKey, "{proxy+}") {
			t.Fatalf("normal route %q should not use ANY or {proxy+}", r.RouteKey)
		}
		if r.AuthorizerName != "LTBase" {
			t.Fatalf("route %q authorizer = %q, want LTBase", r.RouteKey, r.AuthorizerName)
		}
	}
	mustExist := []string{
		"GET /api/ai/v1/notes",
		"POST /api/ai/v1/notes",
		"GET /api/v1/deepping",
		"POST /api/ai/v1/intent-to-action/plans",
		"POST /api/sys/v1/discovery/reachable",
		"GET /api/sys/v1/governance/claims",
		"POST /api/sys/v1/governance/evidence",
		"GET /api/sys/v1/compliance/entities/{entity}",
		"GET /api/v1/semantic/resources",
		"OPTIONS /{proxy+}",
	}
	for _, key := range mustExist {
		if !routeSet[key] {
			t.Fatalf("missing route %q", key)
		}
	}
}
```

- [ ] **Step 3: Run tests**

```bash
go test ./infra/internal/services -run TestBuildAPIRouteSpecs
```

---

## Task 4: Expand AuthService route specs

**Files:**
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway.go:196-210`
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway_test.go:70-90`

- [ ] **Step 1: Update `buildAuthRouteSpecs`**

Add `revoke`, `profile`, and preflight routes:

```go
func buildAuthRouteSpecs(providerCfg AuthProviderConfig) []routeSpec {
	routes := []routeSpec{
		{RouteKey: "GET /api/v1/auth/health"},
		{RouteKey: "POST /api/v1/auth/refresh", AuthorizerName: "LTBaseRefresh"},
		{RouteKey: "POST /api/v1/auth/revoke", AuthorizerName: "LTBase"},
		{RouteKey: "GET /api/v1/auth/profile/{user_id}", AuthorizerName: "LTBase"},
	}
	for _, provider := range providerCfg.Providers {
		if provider.EnableIDBinding {
			routes = append(routes, routeSpec{RouteKey: "POST /api/v1/id_bindings/" + provider.Name, AuthorizerName: provider.Name})
		}
		if provider.EnableLogin {
			routes = append(routes, routeSpec{RouteKey: "POST /api/v1/login/" + provider.Name, AuthorizerName: provider.Name})
		}
	}
	routes = append(routes, preflightRoutes()...)
	return routes
}
```

- [ ] **Step 2: Update `TestBuildAuthRouteSpecs`**

```go
func TestBuildAuthRouteSpecs(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
			{Name: "apple", Issuer: "https://apple.example.com", Audiences: []string{"aud-2"}, EnableLogin: true, EnableIDBinding: false},
		},
	}
	routes := buildAuthRouteSpecs(providerCfg)
	routeSet := make(map[string]bool)
	for _, r := range routes {
		routeSet[r.RouteKey] = true
	}
	check := func(wantKey, wantAuth string) {
		t.Helper()
		// find route
		var auth string
		for _, r := range routes {
			if r.RouteKey == wantKey {
				auth = r.AuthorizerName
				break
			}
		}
		if auth == "" && wantAuth != "" {
			t.Fatalf("route %q not found", wantKey)
		}
		if auth != wantAuth {
			t.Fatalf("route %q authorizer = %q, want %q", wantKey, auth, wantAuth)
		}
	}
	check("GET /api/v1/auth/health", "")
	check("POST /api/v1/auth/refresh", "LTBaseRefresh")
	check("POST /api/v1/auth/revoke", "LTBase")
	check("GET /api/v1/auth/profile/{user_id}", "LTBase")
	check("POST /api/v1/login/firebase", "firebase")
	check("POST /api/v1/login/apple", "apple")
	check("POST /api/v1/id_bindings/firebase", "firebase")
	check("OPTIONS /", "")
	check("OPTIONS /{proxy+}", "")
}
```

- [ ] **Step 3: Run tests**

```bash
go test ./infra/internal/services -run TestBuildAuth
```

---

## Task 5: Fix CORS methods — add PATCH

**Files:**
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway.go:393-399`
- Modify: `ltbase-private-deployment/infra/internal/services/apigateway_test.go:211-228`

- [ ] **Step 1: Add PATCH to CORS methods**

```go
func httpAPICorsConfigForOrigins(origins []string) httpAPICorsConfig {
	return httpAPICorsConfig{
		AllowOrigins:     origins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Authorization", "Content-Type"},
		AllowCredentials: false,
	}
}
```

- [ ] **Step 2: Update CORS test**

```go
func TestHTTPAPICORSConfigurationUsesConfiguredOrigins(t *testing.T) {
	config := httpAPICorsConfigForOrigins([]string{"https://app.example.com", "https://admin.example.com"})
	if len(config.AllowOrigins) != 2 {
		t.Fatalf("allow origins length = %d", len(config.AllowOrigins))
	}
	if config.AllowOrigins[0] != "https://app.example.com" || config.AllowOrigins[1] != "https://admin.example.com" {
		t.Fatalf("allow origins = %#v", config.AllowOrigins)
	}
	methods := config.AllowMethods
	if len(methods) == 0 {
		t.Fatal("allow methods should not be empty")
	}
	hasPATCH := false
	for _, m := range methods {
		if m == "PATCH" {
			hasPATCH = true
			break
		}
	}
	if !hasPATCH {
		t.Fatalf("allow methods missing PATCH: %#v", methods)
	}
}
```

- [ ] **Step 3: Run tests**

```bash
go test ./infra/internal/services -run TestHTTPAPICORSConfiguration
```

---

## Task 6: Update `ltbase.api/AGENTS.md`

**Files:**
- Modify: `ltbase.api/AGENTS.md`

- [ ] **Step 1: Add route sync section**

After the "Key Environment Variables" table and before "Build Commands" (or at the end), add:

```md
## API Gateway Route Sync

When adding, removing, renaming, or changing the HTTP method/path of any Data Plane,
Control Plane, or AuthService API route in this repository, agents must sync the
explicit API Gateway route configuration in
[`ltbase-private-deployment/infra/internal/services/apigateway.go`](https://github.com/Lychee-Technology/ltbase-private-deployment/blob/main/infra/internal/services/apigateway.go)
and its tests in
[`apigateway_test.go`](https://github.com/Lychee-Technology/ltbase-private-deployment/blob/main/infra/internal/services/apigateway_test.go).

**Rules:**

- Every business API route must have an explicit `METHOD /path` route spec in the
  corresponding builder function (`buildAPIRouteSpecs`, `buildControlPlaneRouteSpecs`,
  `buildAuthRouteSpecs`).
- Do not rely on `ANY /{proxy+}` for normal API traffic. Generic proxy matching is
  allowed only for unauthenticated CORS preflight routes (`OPTIONS /` and
  `OPTIONS /{proxy+}`).
- Preflight routes must not carry a JWT authorizer; the API Gateway must pass them
  to the Lambda handler without authentication.
- Each builder function must be covered by a test that asserts every expected route
  exists with the correct authorizer and that no normal route uses `/{proxy+}` or `ANY`.
- For Control Plane APIs, routes must be added for both `/api/v1/...` and the legacy
  `/api/control-plane/v1/...` prefixes.
- When adding a new HTTP method (e.g., `PATCH`) that was not previously in the CORS
  allowed-methods list, update `httpAPICorsConfigForOrigins` and its test.
```

---

## Task 7: Update demo01 devo CORS for local development

**Files:**
- Modify: `ltbase-private-deployment-demo01/infra/Pulumi.devo.yaml`

- [ ] **Step 1: Add localhost origin**

Change the two CORS config lines to include `http://localhost:5173`:

```yaml
  ltbase-infra:controlPlaneCorsOrigins: https://demo01-admin.ltbase.dev,http://localhost:5173
  ltbase-infra:controlPlaneCorsAllowOrigins: https://demo01-admin.ltbase.dev,http://localhost:5173
```

- [ ] **Step 2: Verify the change is syntactically valid**

```bash
cd /Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment-demo01
# YAML is a superset of JSON; a quick parse check:
python3 -c "import yaml; yaml.safe_load(open('infra/Pulumi.devo.yaml'))"
```

- [ ] **Step 3: After all Tasks 1-6 are merged in `ltbase-private-deployment`, run Pulumi preview for demo01 devo**

```bash
pulumi preview --stack devo
```

Expected: preview shows new explicit routes replacing `ANY /` and `ANY /{proxy+}`, no unexpected deletions, and CORS config includes both `https://demo01-admin.ltbase.dev` and `http://localhost:5173`.

---

## Task 8: Full verification

- [ ] **Step 1: Run the full test suite for the infra services package**

```bash
cd /Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment
go test ./infra/internal/services -v
```

- [ ] **Step 2: Run the full infra test suite**

```bash
cd /Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment
go test ./infra/... -v
```

All tests must pass.

---

## GitHub Issues

Corresponding issues to create:

1. **ltbase-private-deployment**: "Replace catch-all API Gateway routes with explicit METHOD/path routes for Data Plane, Control Plane, and AuthService"
   Covers Tasks 1-5.

2. **ltbase.api**: "AGENTS.md: add API Gateway route sync instructions for explicit route config"
   Covers Task 6.

3. **ltbase-private-deployment-demo01**: "Allow localhost:5173 in devo Control Plane CORS configuration"
   Covers Task 7.
