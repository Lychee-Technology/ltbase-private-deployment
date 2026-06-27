package services

import (
	"strings"
	"testing"
)

func TestAPIRouteSpecsHaveNoBusinessCatchAlls(t *testing.T) {
	routes := buildAPIRouteSpecs()
	for _, r := range routes {
		if r.RouteKey == "OPTIONS /" || r.RouteKey == "OPTIONS /{proxy+}" {
			continue
		}
		if strings.Contains(r.RouteKey, "ANY") || strings.Contains(r.RouteKey, "{proxy+}") {
			t.Fatalf("route %q should not use ANY or {proxy+}", r.RouteKey)
		}
		if r.AuthorizerName != "LTBase" {
			t.Fatalf("route %q authorizer = %q, want LTBase", r.RouteKey, r.AuthorizerName)
		}
	}
}

func TestAPIRouteSpecsIncludePreflight(t *testing.T) {
	routes := buildAPIRouteSpecs()
	foundOptionsRoot := false
	foundOptionsProxy := false
	for _, r := range routes {
		if r.RouteKey == "OPTIONS /" {
			foundOptionsRoot = true
			if r.AuthorizerName != "" {
				t.Fatal("OPTIONS / should have empty authorizer")
			}
		}
		if r.RouteKey == "OPTIONS /{proxy+}" {
			foundOptionsProxy = true
			if r.AuthorizerName != "" {
				t.Fatal("OPTIONS /{proxy+} should have empty authorizer")
			}
		}
	}
	if !foundOptionsRoot {
		t.Fatal("missing OPTIONS / preflight route")
	}
	if !foundOptionsProxy {
		t.Fatal("missing OPTIONS /{proxy+} preflight route")
	}
}

func TestAPIRouteSpecsCoverKeyRoutes(t *testing.T) {
	routes := buildAPIRouteSpecs()
	routeSet := make(map[string]bool)
	for _, r := range routes {
		routeSet[r.RouteKey] = true
	}
	mustExist := []string{
		"GET /api/ai/v1/notes",
		"POST /api/ai/v1/notes",
		"GET /api/ai/v1/notes/{note_id}",
		"PUT /api/ai/v1/notes/{note_id}",
		"DELETE /api/ai/v1/notes/{note_id}",
		"GET /api/ai/v1/notes/{note_id}/model_sync",
		"POST /api/ai/v1/notes/{note_id}/model_sync",
		"POST /api/ai/v1/sessions",
		"GET /api/ai/v1/sessions/{session_id}",
		"POST /api/ai/v1/agent/sessions",
		"POST /api/ai/v1/intent-to-action/plans",
		"POST /api/ai/v1/governance/actions/execute",
		"POST /api/ai/v1/compliance/decisions",
		"GET /api/v1/deepping",
		"GET /api/v1/semantic/resources",
		"POST /api/sys/v1/discovery/reachable",
		"GET /api/sys/v1/ontology/object-types",
		"GET /api/sys/v1/governance/claims",
		"POST /api/sys/v1/governance/evidence",
		"GET /api/sys/v1/compliance/entities/{entity}",
		"GET /api/ltflow/v1/tasks",
		"POST /api/ltflow/v1/instances",
		"OPTIONS /{proxy+}",
	}
	for _, key := range mustExist {
		if !routeSet[key] {
			t.Fatalf("missing route %q", key)
		}
	}
}

func TestControlPlaneRouteSpecsHaveNoBusinessCatchAlls(t *testing.T) {
	routes := buildControlPlaneRouteSpecs()
	for _, r := range routes {
		if r.RouteKey == "OPTIONS /" || r.RouteKey == "OPTIONS /{proxy+}" {
			continue
		}
		if strings.Contains(r.RouteKey, "ANY") || strings.Contains(r.RouteKey, "{proxy+}") {
			t.Fatalf("route %q should not use ANY or {proxy+}", r.RouteKey)
		}
		if r.AuthorizerName != "LTBase" {
			t.Fatalf("route %q authorizer = %q, want LTBase", r.RouteKey, r.AuthorizerName)
		}
	}
}

func TestControlPlaneRouteSpecsEveryRouteHasHTTPMethod(t *testing.T) {
	routes := buildControlPlaneRouteSpecs()
	for _, r := range routes {
		if r.RouteKey == "OPTIONS /" || r.RouteKey == "OPTIONS /{proxy+}" {
			continue
		}
		parts := strings.SplitN(r.RouteKey, " ", 2)
		if len(parts) != 2 {
			t.Fatalf("route %q missing HTTP method prefix", r.RouteKey)
		}
		method := strings.ToUpper(parts[0])
		validMethods := map[string]bool{
			"GET": true, "POST": true, "PUT": true,
			"PATCH": true, "DELETE": true, "OPTIONS": true,
		}
		if !validMethods[method] {
			t.Fatalf("route %q has invalid HTTP method %q", r.RouteKey, method)
		}
	}
}

func TestControlPlaneRouteSpecsCoverBothPrefixes(t *testing.T) {
	routes := buildControlPlaneRouteSpecs()
	routeSet := make(map[string]bool)
	for _, r := range routes {
		routeSet[r.RouteKey] = true
	}
	// Every key path must appear under both prefixes with some valid HTTP method.
	keySuffixes := []string{
		"/status", "/schema/status", "/workflows",
		"/repair/dry-run", "/repair/apply",
		"/catalogs/capabilities", "/catalogs/action-templates", "/catalogs/assistant-roles",
		"/compliance-profile",
		"/auth-config", "/auth/config",
		"/referrals", "/referrals/{code}", "/referrals/{code}/disable",
		"/auth/referrals", "/auth/referrals/{code}", "/auth/referrals/{code}/disable",
		"/auth/users", "/auth/users/{user_id}", "/auth/users/{user_id}/roles/{role_id}",
		"/auth/roles", "/auth/roles/{role_id}",
		"/auth/policies", "/auth/policies/{policy_id}",
		"/auth/binding-policies", "/auth/binding-policies/{policy_id}",
		"/auth/principals/{principal_type}/{principal_id}/policies",
		"/auth/principals/{principal_type}/{principal_id}/policies/{policy_id}",
		"/org/units", "/org/units/{ou_id}", "/org/units/{ou_id}/users",
		"/org/units/{ou_id}/users/{user_id}",
		"/org/units/{ou_id}/policies", "/org/units/{ou_id}/policies/{policy_id}",
		"/org/users/{user_id}/manager", "/org/users/{user_id}/direct-reports",
		"/org/charts",
	}
	for _, suffix := range keySuffixes {
		foundV1 := false
		foundLegacy := false
		for key := range routeSet {
			if !strings.HasPrefix(key, "OPTIONS") {
				if strings.HasSuffix(key, "/api/v1"+suffix) {
					foundV1 = true
				}
				if strings.HasSuffix(key, "/api/control-plane/v1"+suffix) {
					foundLegacy = true
				}
			}
		}
		if !foundV1 {
			t.Fatalf("no route for suffix /api/v1%s", suffix)
		}
		if !foundLegacy {
			t.Fatalf("no route for suffix /api/control-plane/v1%s", suffix)
		}
	}
}

func TestControlPlaneRouteSpecsIncludePreflight(t *testing.T) {
	routes := buildControlPlaneRouteSpecs()
	foundOptionsRoot := false
	foundOptionsProxy := false
	for _, r := range routes {
		if r.RouteKey == "OPTIONS /" {
			foundOptionsRoot = true
			if r.AuthorizerName != "" {
				t.Fatal("OPTIONS / should have empty authorizer")
			}
		}
		if r.RouteKey == "OPTIONS /{proxy+}" {
			foundOptionsProxy = true
			if r.AuthorizerName != "" {
				t.Fatal("OPTIONS /{proxy+} should have empty authorizer")
			}
		}
	}
	if !foundOptionsRoot {
		t.Fatal("missing OPTIONS / preflight route")
	}
	if !foundOptionsProxy {
		t.Fatal("missing OPTIONS /{proxy+} preflight route")
	}
}

func TestAuthRouteSpecsIncludeRevokeAndProfile(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
			{Name: "apple", Issuer: "https://apple.example.com", Audiences: []string{"aud-2"}, EnableLogin: true, EnableIDBinding: false},
		},
	}
	routes := buildAuthRouteSpecs(providerCfg)

	check := func(wantKey, wantAuth string) {
		t.Helper()
		found := false
		for _, r := range routes {
			if r.RouteKey == wantKey {
				found = true
				if r.AuthorizerName != wantAuth {
					t.Fatalf("route %q authorizer = %q, want %q", wantKey, r.AuthorizerName, wantAuth)
				}
				break
			}
		}
		if !found {
			t.Fatalf("route %q not found in %d routes", wantKey, len(routes))
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

func TestAuthRouteSpecsNoBusinessCatchAlls(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
		},
	}
	routes := buildAuthRouteSpecs(providerCfg)
	for _, r := range routes {
		if r.RouteKey == "OPTIONS /" || r.RouteKey == "OPTIONS /{proxy+}" {
			continue
		}
		if strings.Contains(r.RouteKey, "ANY") || strings.Contains(r.RouteKey, "{proxy+}") {
			t.Fatalf("route %q should not use ANY or {proxy+}", r.RouteKey)
		}
	}
}

func assertUniqueRouteSuffixes(t *testing.T, routes []routeSpec) {
	t.Helper()
	suffixes := ensureUniqueRouteResourceSuffixes(routes)
	seen := make(map[string]string) // suffix -> first routeKey
	for i, s := range suffixes {
		if prev, exists := seen[s]; exists {
			t.Fatalf("suffix collision: %q used by both %q and %q", s, prev, routes[i].RouteKey)
		}
		seen[s] = routes[i].RouteKey
	}
	if len(suffixes) != len(routes) {
		t.Fatalf("suffix count = %d, want %d", len(suffixes), len(routes))
	}
}

func TestRouteSuffixesAreUniquePerBuilder(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
		},
	}
	// Each builder runs on its own API Gateway, so per-builder uniqueness is the
	// production-relevant guarantee.
	assertUniqueRouteSuffixes(t, buildAPIRouteSpecs())
	assertUniqueRouteSuffixes(t, buildControlPlaneRouteSpecs())
	assertUniqueRouteSuffixes(t, buildAuthRouteSpecs(providerCfg))
}

func TestRouteSuffixesAreUniqueForAllRouteBuilders(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
		},
	}
	// The merged set never occurs in production (the builders run on separate
	// gateways); it is an intentional stress test of the dedup logic.
	allRoutes := append(buildAPIRouteSpecs(), buildControlPlaneRouteSpecs()...)
	allRoutes = append(allRoutes, buildAuthRouteSpecs(providerCfg)...)
	assertUniqueRouteSuffixes(t, allRoutes)
}

func TestCORSConfigurationIncludesPatch(t *testing.T) {
	config := httpAPICorsConfigForOrigins([]string{"https://example.com"})
	methods := config.AllowMethods
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

func TestPreflightRoutesNoAuthorizer(t *testing.T) {
	routes := preflightRoutes()
	if len(routes) != 2 {
		t.Fatalf("preflight route count = %d, want 2", len(routes))
	}
	for _, r := range routes {
		if r.AuthorizerName != "" {
			t.Fatalf("preflight route %q has authorizer %q, want empty", r.RouteKey, r.AuthorizerName)
		}
	}
}
