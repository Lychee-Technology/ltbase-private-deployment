package services

import (
	"errors"
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

	cfg, err := loadAuthProviderConfig("", path)
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

	if _, err := loadAuthProviderConfig("", path); err == nil {
		t.Fatal("loadAuthProviderConfig() expected duplicate provider error")
	}
}

func TestLoadAuthProviderConfigRejectsMissingIssuer(t *testing.T) {
	path := writeProviderConfigFixture(t, `{
	  "providers": [
	    {"name": "firebase", "issuer": "", "audiences": ["aud-1"], "enable_login": true, "enable_id_binding": true}
	  ]
	}`)

	if _, err := loadAuthProviderConfig("", path); err == nil {
		t.Fatal("loadAuthProviderConfig() expected missing issuer error")
	}
}

func TestLoadAuthProviderConfigRejectsInvalidJSON(t *testing.T) {
	path := writeProviderConfigFixture(t, `{not-json}`)
	if _, err := loadAuthProviderConfig("", path); err == nil {
		t.Fatal("loadAuthProviderConfig() expected invalid json error")
	}
}

func TestLoadAuthProviderConfigMissingFileDefaultsToEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing.json")

	cfg, err := loadAuthProviderConfig("", path)
	if err != nil {
		t.Fatalf("loadAuthProviderConfig() error = %v", err)
	}
	if len(cfg.Providers) != 0 {
		t.Fatalf("provider count = %d, want 0", len(cfg.Providers))
	}

	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("os.Stat() error = %v, want not exist", err)
	}
}

func TestResolveAuthProviderConfigPathUsesPulumiRoot(t *testing.T) {
	rootDir := filepath.Join("blueprint", "infra")
	if got := resolveAuthProviderConfigPath(rootDir, "infra/auth-providers.devo.json"); got != filepath.Join(rootDir, "auth-providers.devo.json") {
		t.Fatalf("resolveAuthProviderConfigPath() = %q", got)
	}
	if got := resolveAuthProviderConfigPath(rootDir, "auth-providers.devo.json"); got != filepath.Join(rootDir, "auth-providers.devo.json") {
		t.Fatalf("resolveAuthProviderConfigPath() = %q", got)
	}
}

func TestLoadAuthProviderConfigSupportsPulumiRootDirectory(t *testing.T) {
	repoRoot := t.TempDir()
	infraDir := filepath.Join(repoRoot, "infra")
	if err := os.MkdirAll(infraDir, 0o755); err != nil {
		t.Fatalf("os.MkdirAll() error = %v", err)
	}
	configPath := filepath.Join(infraDir, "auth-providers.devo.json")
	if err := os.WriteFile(configPath, []byte(`{"providers": []}`), 0o600); err != nil {
		t.Fatalf("os.WriteFile() error = %v", err)
	}

	cfg, err := loadAuthProviderConfig(infraDir, "infra/auth-providers.devo.json")
	if err != nil {
		t.Fatalf("loadAuthProviderConfig() error = %v", err)
	}
	if len(cfg.Providers) != 0 {
		t.Fatalf("provider count = %d, want 0", len(cfg.Providers))
	}
}
