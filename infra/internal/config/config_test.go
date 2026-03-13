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

func TestValidateRequiresDSQLHostOrEndpoint(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: true,
	}
	if err := cfg.Validate(); err == nil {
		t.Fatal("Validate() expected error for missing dsql host and endpoint")
	}
}

func TestValidateRequiresOIDCProviderArnWhenNotManaged(t *testing.T) {
	cfg := StackConfig{
		DSQLHost:                 "db.example.internal",
		ManageGitHubOIDCProvider: false,
	}
	if err := cfg.Validate(); err == nil {
		t.Fatal("Validate() expected error for missing githubOidcProviderArn")
	}
}

func TestValidateAcceptsManagedProvider(t *testing.T) {
	cfg := StackConfig{
		DSQLHost:                 "db.example.internal",
		ManageGitHubOIDCProvider: true,
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate() unexpected error: %v", err)
	}
}
