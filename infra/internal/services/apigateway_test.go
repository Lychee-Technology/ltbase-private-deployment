package services

import (
	"os"
	"path/filepath"
	"testing"

	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/dns"
)

func TestBuildAuthProviderAuthorizerSpecs(t *testing.T) {
	providerCfg := AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase", Issuer: "https://issuer.example.com", Audiences: []string{"aud-1"}, EnableLogin: true, EnableIDBinding: true},
		},
	}
	authorizers := buildAuthAuthorizerSpecs(config.StackConfig{OIDCIssuerURL: "https://oidc.example.com/devo", ProjectID: "11111111-1111-4111-8111-111111111111", AuthDomain: "auth.example.com"}, providerCfg)
	if len(authorizers) != 3 {
		t.Fatalf("authorizer count = %d, want 3", len(authorizers))
	}
	if authorizers[0].Name != "LTBase" {
		t.Fatalf("first authorizer = %q, want LTBase", authorizers[0].Name)
	}
	if authorizers[1].Name != "LTBaseRefresh" {
		t.Fatalf("second authorizer = %q, want LTBaseRefresh", authorizers[1].Name)
	}
	if authorizers[2].Name != "firebase" {
		t.Fatalf("provider authorizer = %q, want firebase", authorizers[2].Name)
	}
}

func TestRouteResourceNameIsStableFromRouteKey(t *testing.T) {
	got := routeResourceNameSuffix("POST /api/v1/id_bindings/firebase")
	if got != "post-api-v1-id-bindings-firebase" {
		t.Fatalf("routeResourceNameSuffix() = %q", got)
	}
}

func TestResolveMTLSTruststorePathUsesPulumiRoot(t *testing.T) {
	repoRoot := t.TempDir()
	infraDir := filepath.Join(repoRoot, "infra")
	truststorePath := filepath.Join(infraDir, "certs", "cloudflare-origin-pull-ca.pem")
	if err := os.MkdirAll(filepath.Dir(truststorePath), 0o755); err != nil {
		t.Fatalf("os.MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(truststorePath, []byte("pem"), 0o600); err != nil {
		t.Fatalf("os.WriteFile() error = %v", err)
	}

	got, err := resolveMTLSTruststorePath(infraDir, "infra/certs/cloudflare-origin-pull-ca.pem")
	if err != nil {
		t.Fatalf("resolveMTLSTruststorePath() error = %v", err)
	}
	if got != truststorePath {
		t.Fatalf("resolveMTLSTruststorePath() = %q, want %q", got, truststorePath)
	}
}

func TestResolveMTLSTruststorePathRejectsMissingFile(t *testing.T) {
	infraDir := filepath.Join(t.TempDir(), "infra")
	if err := os.MkdirAll(infraDir, 0o755); err != nil {
		t.Fatalf("os.MkdirAll() error = %v", err)
	}

	if _, err := resolveMTLSTruststorePath(infraDir, "infra/certs/missing.pem"); err == nil {
		t.Fatal("resolveMTLSTruststorePath() expected error for missing truststore")
	}
}

func TestMTLSTruststoreURI(t *testing.T) {
	if got := mtlsTruststoreURI("runtime-bucket", "mtls/cloudflare-origin-pull-ca.pem"); got != "s3://runtime-bucket/mtls/cloudflare-origin-pull-ca.pem" {
		t.Fatalf("mtlsTruststoreURI() = %q", got)
	}
}

func TestHTTPAPIDisableExecuteEndpointDefault(t *testing.T) {
	settings := httpAPISettings()
	if !settings.DisableExecuteAPIEndpoint {
		t.Fatal("DisableExecuteAPIEndpoint = false, want true")
	}
}

func TestBuildHTTPAPIDomainConfigsUsesSharedTruststoreForAllDomains(t *testing.T) {
	truststore := mtlsTruststore{URI: "s3://runtime-bucket/mtls/cloudflare-origin-pull-ca.pem"}
	configs := buildHTTPAPIDomainConfigs(config.StackConfig{
		APIDomain:                    "api.example.com",
		ControlPlaneDomain:           "control.example.com",
		AuthDomain:                   "auth.example.com",
		APICORSAllowOrigins:          []string{"https://app.example.com"},
		ControlPlaneCORSAllowOrigins: []string{"https://admin.example.com"},
		AuthCORSAllowOrigins:         []string{"*"},
	}, truststore)

	for _, key := range []string{"api", "control", "auth"} {
		cfg, ok := configs[key]
		if !ok {
			t.Fatalf("missing domain config for %s", key)
		}
		if cfg.Truststore.URI != truststore.URI {
			t.Fatalf("domain %s truststore uri = %q, want %q", key, cfg.Truststore.URI, truststore.URI)
		}
	}
	if configs["api"].Domain != "api.example.com" {
		t.Fatalf("api domain = %q", configs["api"].Domain)
	}
	if configs["control"].Domain != "control.example.com" {
		t.Fatalf("control domain = %q", configs["control"].Domain)
	}
	if configs["auth"].Domain != "auth.example.com" {
		t.Fatalf("auth domain = %q", configs["auth"].Domain)
	}
	if configs["api"].Suffix != "api" || configs["control"].Suffix != "control" || configs["auth"].Suffix != "auth" {
		t.Fatal("unexpected suffix mapping in buildHTTPAPIDomainConfigs()")
	}
	if got := configs["api"].CORSAllowOrigins; len(got) != 1 || got[0] != "https://app.example.com" {
		t.Fatalf("api cors origins = %#v", got)
	}
	if got := configs["control"].CORSAllowOrigins; len(got) != 1 || got[0] != "https://admin.example.com" {
		t.Fatalf("control cors origins = %#v", got)
	}
	if got := configs["auth"].CORSAllowOrigins; len(got) != 1 || got[0] != "*" {
		t.Fatalf("auth cors origins = %#v", got)
	}
}

func TestHTTPAPICORSConfigurationUsesConfiguredOrigins(t *testing.T) {
	config := httpAPICorsConfigForOrigins([]string{"https://app.example.com", "https://admin.example.com"})
	if len(config.AllowOrigins) != 2 {
		t.Fatalf("allow origins length = %d", len(config.AllowOrigins))
	}
	if config.AllowOrigins[0] != "https://app.example.com" || config.AllowOrigins[1] != "https://admin.example.com" {
		t.Fatalf("allow origins = %#v", config.AllowOrigins)
	}
	if len(config.AllowMethods) == 0 {
		t.Fatal("allow methods should not be empty")
	}
	hasPATCH := false
	for _, m := range config.AllowMethods {
		if m == "PATCH" {
			hasPATCH = true
			break
		}
	}
	if !hasPATCH {
		t.Fatalf("allow methods missing PATCH: %#v", config.AllowMethods)
	}
	if len(config.AllowHeaders) == 0 {
		t.Fatal("allow headers should not be empty")
	}
	if config.AllowCredentials {
		t.Fatal("allow credentials = true, want false")
	}
}

func TestLTBaseAuthorizerSpecUsesIssuerAndProjectID(t *testing.T) {
	spec := ltbaseAuthorizerSpec(config.StackConfig{
		OIDCIssuerURL: "https://oidc.example.com/devo",
		ProjectID:     "11111111-1111-4111-8111-111111111111",
	})
	if spec.Name != "LTBase" {
		t.Fatalf("ltbaseAuthorizerSpec() name = %q", spec.Name)
	}
	if spec.Issuer != "https://oidc.example.com/devo" {
		t.Fatalf("ltbaseAuthorizerSpec() issuer = %q", spec.Issuer)
	}
	if len(spec.Audiences) != 1 || spec.Audiences[0] != "11111111-1111-4111-8111-111111111111" {
		t.Fatalf("ltbaseAuthorizerSpec() audiences = %#v", spec.Audiences)
	}
}

func TestLTBaseProjectAudiencesAllLower(t *testing.T) {
	aud := ltbaseProjectAudiences("a1b2c3d4-e5f6-7890-abcd-ef1234567890")
	if len(aud) != 2 {
		t.Fatalf("ltbaseProjectAudiences(all-lower) len = %d, want 2; got %#v", len(aud), aud)
	}
	if aud[0] != "a1b2c3d4-e5f6-7890-abcd-ef1234567890" {
		t.Fatalf("original = %q", aud[0])
	}
	if aud[1] != "A1B2C3D4-E5F6-7890-ABCD-EF1234567890" {
		t.Fatalf("upper = %q", aud[1])
	}
}

func TestLTBaseProjectAudiencesAllUpper(t *testing.T) {
	aud := ltbaseProjectAudiences("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
	if len(aud) != 2 {
		t.Fatalf("ltbaseProjectAudiences(all-upper) len = %d, want 2; got %#v", len(aud), aud)
	}
	if aud[0] != "A1B2C3D4-E5F6-7890-ABCD-EF1234567890" {
		t.Fatalf("original = %q", aud[0])
	}
	if aud[1] != "a1b2c3d4-e5f6-7890-abcd-ef1234567890" {
		t.Fatalf("lower = %q", aud[1])
	}
}

func TestLTBaseProjectAudiencesMixedCase(t *testing.T) {
	aud := ltbaseProjectAudiences("A1b2C3d4-E5f6-7890-AbcD-Ef1234567890")
	if len(aud) != 3 {
		t.Fatalf("ltbaseProjectAudiences(mixed-case) len = %d, want 3; got %#v", len(aud), aud)
	}
	if aud[0] != "A1b2C3d4-E5f6-7890-AbcD-Ef1234567890" {
		t.Fatalf("original = %q", aud[0])
	}
	if aud[1] != "A1B2C3D4-E5F6-7890-ABCD-EF1234567890" {
		t.Fatalf("upper = %q", aud[1])
	}
	if aud[2] != "a1b2c3d4-e5f6-7890-abcd-ef1234567890" {
		t.Fatalf("lower = %q", aud[2])
	}
}

func TestLTBaseProjectAudiencesNoDuplicates(t *testing.T) {
	aud := ltbaseProjectAudiences("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
	if len(aud) != 2 {
		t.Fatalf("ltbaseProjectAudiences(all-lower) len = %d, want 2; got %#v", len(aud), aud)
	}
	if aud[0] != "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" {
		t.Fatalf("original = %q", aud[0])
	}
	if aud[1] != "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" {
		t.Fatalf("upper = %q", aud[1])
	}
}

func TestLTBaseRefreshAuthorizerSpecUsesAuthDomain(t *testing.T) {
	spec := ltbaseRefreshAuthorizerSpec(config.StackConfig{
		OIDCIssuerURL: "https://oidc.example.com/devo",
		AuthDomain:    "auth.example.com",
	})
	if spec.Name != "LTBaseRefresh" {
		t.Fatalf("ltbaseRefreshAuthorizerSpec() name = %q", spec.Name)
	}
	if spec.Issuer != "https://oidc.example.com/devo" {
		t.Fatalf("ltbaseRefreshAuthorizerSpec() issuer = %q", spec.Issuer)
	}
	if len(spec.Audiences) != 1 || spec.Audiences[0] != "https://auth.example.com" {
		t.Fatalf("ltbaseRefreshAuthorizerSpec() audiences = %#v", spec.Audiences)
	}
}

func TestAPIDomainDNSRecordIsProxied(t *testing.T) {
	args := apiDomainRecordArgs(config.StackConfig{
		CloudflareZoneID:   "zone-id",
		CloudflareZoneName: "example.com",
	}, "api.example.com", nil)
	if !args.Proxied {
		t.Fatal("apiDomainRecordArgs() proxied = false, want true")
	}
}

func TestCertificateValidationDNSRecordIsNotProxied(t *testing.T) {
	args := certificateValidationRecordArgs(config.StackConfig{
		CloudflareZoneID:   "zone-id",
		CloudflareZoneName: "example.com",
	}, nil, nil)
	if args.Proxied {
		t.Fatal("certificateValidationRecordArgs() proxied = true, want false")
	}
	if args.ZoneID != "zone-id" {
		t.Fatalf("certificateValidationRecordArgs() zone id = %q", args.ZoneID)
	}
	if args.ZoneName != "example.com" {
		t.Fatalf("certificateValidationRecordArgs() zone name = %q", args.ZoneName)
	}
	_ = dns.RecordArgs{}
}

func TestAPIBaseURLUsesAPIDomain(t *testing.T) {
	if got := APIBaseURL(config.StackConfig{APIDomain: "api.example.com"}); got != "https://api.example.com" {
		t.Fatalf("apiBaseURL() = %q", got)
	}
}
