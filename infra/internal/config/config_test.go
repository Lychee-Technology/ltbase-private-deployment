package config

import "testing"

func TestValueOrDefault(t *testing.T) {
	if got := valueOrDefault(" ", "fallback"); got != "fallback" {
		t.Fatalf("valueOrDefault() = %q", got)
	}
}

func TestSplitCSV(t *testing.T) {
	got := splitCSV("a, b,,c")
	if len(got) != 3 {
		t.Fatalf("splitCSV() length = %d", len(got))
	}
}

func TestValidateRequiresOIDCProviderArnWhenNotManaged(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: false,
	}
	if err := cfg.Validate(); err == nil {
		t.Fatal("Validate() expected error for missing githubOidcProviderArn")
	}
}

func TestValidateAcceptsManagedProvider(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: true,
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate() unexpected error: %v", err)
	}
}

func TestValueOrDefaultKeepsManagedDSQLDefaults(t *testing.T) {
	if got := valueOrDefault("", "postgres"); got != "postgres" {
		t.Fatalf("default db = %q", got)
	}
	if got := valueOrDefault("", "admin"); got != "admin" {
		t.Fatalf("default user = %q", got)
	}
}

func TestValidateAllowsOptionalDSQLEndpoint(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: true,
		DSQLEndpoint:             "",
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate() unexpected error: %v", err)
	}
}

func TestReleaseAssetDirDefaultTargetsRepoRoot(t *testing.T) {
	if got := defaultReleaseAssetDir; got != "../../.ltbase/releases" {
		t.Fatalf("default release asset dir = %q", got)
	}
}

func TestValidateAllowsProjectIDAndAuthProviderConfigFile(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: true,
		ProjectID:                "11111111-1111-4111-8111-111111111111",
		AuthProviderConfigFile:   "infra/auth-providers.devo.json",
		MTLSTruststoreFile:       "infra/certs/cloudflare-origin-pull-ca.pem",
		MTLSTruststoreKey:        "mtls/cloudflare-origin-pull-ca.pem",
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate() unexpected error: %v", err)
	}
	if cfg.ProjectID == "" {
		t.Fatal("ProjectID should be preserved")
	}
	if cfg.AuthProviderConfigFile == "" {
		t.Fatal("AuthProviderConfigFile should be preserved")
	}
	if cfg.MTLSTruststoreFile == "" {
		t.Fatal("MTLSTruststoreFile should be preserved")
	}
	if cfg.MTLSTruststoreKey == "" {
		t.Fatal("MTLSTruststoreKey should be preserved")
	}
}
