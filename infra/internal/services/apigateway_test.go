package services

import (
	"testing"

	"lychee.technology/ltbase/infra/internal/config"
)

func TestBuildAPIRouteSpecs(t *testing.T) {
	routes := buildAPIRouteSpecs()
	if len(routes) != 11 {
		t.Fatalf("route count = %d, want 11", len(routes))
	}
	if routes[0].RouteKey != "GET /api/ai/v1/notes" {
		t.Fatalf("first route = %q", routes[0].RouteKey)
	}
	for _, route := range routes {
		if route.AuthorizerName != "LTBase" {
			t.Fatalf("route %q authorizer = %q, want LTBase", route.RouteKey, route.AuthorizerName)
		}
	}
}

func TestBuildControlPlaneRouteSpecs(t *testing.T) {
	routes := buildControlPlaneRouteSpecs()
	if len(routes) != 2 {
		t.Fatalf("route count = %d, want 2", len(routes))
	}
	if routes[0].RouteKey != "ANY /" || routes[1].RouteKey != "ANY /{proxy+}" {
		t.Fatalf("unexpected control routes: %#v", routes)
	}
}

func TestBuildAuthProviderAuthorizerSpecs(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
		},
	}
	authorizers := buildAuthAuthorizerSpecs(config.StackConfig{OIDCIssuerURL: "https://oidc.example.com/devo", ProjectID: "11111111-1111-4111-8111-111111111111"}, providerCfg)
	if len(authorizers) != 2 {
		t.Fatalf("authorizer count = %d, want 2", len(authorizers))
	}
	if authorizers[0].Name != "LTBase" {
		t.Fatalf("first authorizer = %q, want LTBase", authorizers[0].Name)
	}
	if authorizers[1].Name != "firebase" {
		t.Fatalf("provider authorizer = %q, want firebase", authorizers[1].Name)
	}
}

func TestBuildAuthRouteSpecs(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
			{Name: "apple", Issuer: "https://apple.example.com", Audiences: []string{"aud-2"}, EnableLogin: true, EnableIDBinding: false},
		},
	}
	routes := buildAuthRouteSpecs(providerCfg)
	if len(routes) != 5 {
		t.Fatalf("route count = %d, want 5", len(routes))
	}
	if routes[0].RouteKey != "GET /api/v1/auth/health" || routes[0].AuthorizerName != "" {
		t.Fatalf("unexpected health route: %#v", routes[0])
	}
	if routes[1].RouteKey != "POST /api/v1/auth/refresh" || routes[1].AuthorizerName != "LTBase" {
		t.Fatalf("unexpected refresh route: %#v", routes[1])
	}
	if routes[4].RouteKey != "POST /api/v1/login/apple" {
		t.Fatalf("unexpected final route: %#v", routes[4])
	}
}

func TestRouteResourceNameIsStableFromRouteKey(t *testing.T) {
	got := routeResourceNameSuffix("POST /api/v1/id_bindings/firebase")
	if got != "post-api-v1-id-bindings-firebase" {
		t.Fatalf("routeResourceNameSuffix() = %q", got)
	}
}

func TestControlRouteAliases(t *testing.T) {
	cfg := config.StackConfig{Project: "ltbase-infra", Stack: "devo"}
	tests := []struct {
		name     string
		suffix   string
		routeKey string
		want     string
	}{
		{name: "control root", suffix: "control", routeKey: "ANY /", want: "ltbase-infra-devo-control-root"},
		{name: "control proxy", suffix: "control", routeKey: "ANY /{proxy+}", want: "ltbase-infra-devo-control-route"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := legacyRouteAliasName(cfg, tt.suffix, routeSpec{RouteKey: tt.routeKey}); got != tt.want {
				t.Fatalf("legacyRouteAliasName() = %q, want %q", got, tt.want)
			}
		})
	}

	if got := legacyRouteAliasName(cfg, "api", routeSpec{RouteKey: "ANY /"}); got != "" {
		t.Fatalf("non-control alias = %q, want empty", got)
	}
}
