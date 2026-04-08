package services

import (
	"os"
	"path/filepath"
	"testing"
)

func writeProviderConfigFixture(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "providers.json")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("os.WriteFile() error = %v", err)
	}
	return path
}

func TestLoadAuthProviderConfig(t *testing.T) {
	path := writeProviderConfigFixture(t, `{
	  "providers": [
	    {
	      "name": "firebase",
	      "issuer": "https://issuer.example.com",
	      "audiences": ["aud-1"],
	      "enable_login": true,
	      "enable_id_binding": true
	    }
	  ]
	}`)

	cfg, err := loadAuthProviderConfig(path)
	if err != nil {
		t.Fatalf("loadAuthProviderConfig() error = %v", err)
	}
	if len(cfg.Providers) != 1 {
		t.Fatalf("provider count = %d, want 1", len(cfg.Providers))
	}
	if cfg.Providers[0].Name != "firebase" {
		t.Fatalf("provider name = %q, want firebase", cfg.Providers[0].Name)
	}
}

func TestLoadAuthProviderConfigRejectsDuplicateNames(t *testing.T) {
	path := writeProviderConfigFixture(t, `{
	  "providers": [
	    {"name": "firebase", "issuer": "https://issuer-1.example.com", "audiences": ["aud-1"], "enable_login": true, "enable_id_binding": true},
	    {"name": " firebase ", "issuer": "https://issuer-2.example.com", "audiences": ["aud-2"], "enable_login": true, "enable_id_binding": true}
	  ]
	}`)

	if _, err := loadAuthProviderConfig(path); err == nil {
		t.Fatal("loadAuthProviderConfig() expected duplicate provider error")
	}
}

func TestLoadAuthProviderConfigRejectsMissingIssuer(t *testing.T) {
	path := writeProviderConfigFixture(t, `{
	  "providers": [
	    {"name": "firebase", "issuer": "", "audiences": ["aud-1"], "enable_login": true, "enable_id_binding": true}
	  ]
	}`)

	if _, err := loadAuthProviderConfig(path); err == nil {
		t.Fatal("loadAuthProviderConfig() expected missing issuer error")
	}
}

func TestLoadAuthProviderConfigRejectsInvalidJSON(t *testing.T) {
	path := writeProviderConfigFixture(t, `{not-json}`)
	if _, err := loadAuthProviderConfig(path); err == nil {
		t.Fatal("loadAuthProviderConfig() expected invalid json error")
	}
}
