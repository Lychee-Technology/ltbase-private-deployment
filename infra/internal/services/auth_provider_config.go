package services

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type controlPlaneUIProviderNamesResult struct {
	Firebase string
	Supabase string
}

type AuthProviderConfig struct {
	Providers []AuthProvider `json:"providers"`
}

type AuthProvider struct {
	Name            string   `json:"name"`
	Issuer          string   `json:"issuer"`
	Audiences       []string `json:"audiences"`
	EnableLogin     bool     `json:"enable_login"`
	EnableIDBinding bool     `json:"enable_id_binding"`
}

func loadAuthProviderConfig(rootDir, path string) (AuthProviderConfig, error) {
	raw, err := os.ReadFile(resolveAuthProviderConfigPath(rootDir, path))
	if err != nil {
		if os.IsNotExist(err) {
			return AuthProviderConfig{}, nil
		}
		return AuthProviderConfig{}, fmt.Errorf("read auth provider config: %w", err)
	}
	var cfg AuthProviderConfig
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return AuthProviderConfig{}, fmt.Errorf("parse auth provider config: %w", err)
	}
	seen := map[string]struct{}{}
	for i := range cfg.Providers {
		provider := &cfg.Providers[i]
		provider.Name = strings.ToLower(strings.TrimSpace(provider.Name))
		provider.Issuer = strings.TrimSpace(provider.Issuer)
		if provider.Name == "" {
			return AuthProviderConfig{}, fmt.Errorf("provider name is required")
		}
		if provider.Issuer == "" {
			return AuthProviderConfig{}, fmt.Errorf("provider %q issuer is required", provider.Name)
		}
		if len(provider.Audiences) == 0 {
			return AuthProviderConfig{}, fmt.Errorf("provider %q audiences are required", provider.Name)
		}
		for j := range provider.Audiences {
			provider.Audiences[j] = strings.TrimSpace(provider.Audiences[j])
			if provider.Audiences[j] == "" {
				return AuthProviderConfig{}, fmt.Errorf("provider %q audience is required", provider.Name)
			}
		}
		if _, ok := seen[provider.Name]; ok {
			return AuthProviderConfig{}, fmt.Errorf("duplicate provider %q", provider.Name)
		}
		seen[provider.Name] = struct{}{}
	}
	return cfg, nil
}

func resolveAuthProviderConfigPath(rootDir, path string) string {
	cleaned := filepath.Clean(path)
	if filepath.IsAbs(cleaned) || rootDir == "" {
		return cleaned
	}
	if strings.HasPrefix(cleaned, "infra/") {
		return filepath.Join(rootDir, strings.TrimPrefix(cleaned, "infra/"))
	}
	return filepath.Join(rootDir, cleaned)
}

func authProviderNames(cfg AuthProviderConfig) []string {
	names := make([]string, 0, len(cfg.Providers))
	for _, provider := range cfg.Providers {
		names = append(names, provider.Name)
	}
	sort.Strings(names)
	return names
}

func controlPlaneUIProviderNames(cfg AuthProviderConfig, firebaseProjectID string, supabaseURL string) controlPlaneUIProviderNamesResult {
	result := controlPlaneUIProviderNamesResult{
		Firebase: "firebase",
		Supabase: "supabase",
	}

	firebaseIssuer := strings.TrimSpace(firebaseProjectID)
	if firebaseIssuer != "" {
		firebaseIssuer = "https://securetoken.google.com/" + firebaseIssuer
	}
	supabaseIssuer := strings.TrimRight(strings.TrimSpace(supabaseURL), "/")
	if supabaseIssuer != "" {
		supabaseIssuer += "/auth/v1"
	}

	for _, provider := range cfg.Providers {
		if !provider.EnableLogin {
			continue
		}
		issuer := strings.TrimRight(strings.TrimSpace(provider.Issuer), "/")
		switch {
		case result.Firebase == "firebase" && issuer == firebaseIssuer:
			result.Firebase = provider.Name
		case result.Supabase == "supabase" && issuer == supabaseIssuer:
			result.Supabase = provider.Name
		}
	}

	return result
}

func titleizeKey(value string) string {
	parts := strings.Split(strings.ReplaceAll(strings.TrimSpace(value), "_", "-"), "-")
	titled := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		part = strings.ToLower(part)
		titled = append(titled, strings.ToUpper(part[:1])+part[1:])
	}
	return strings.Join(titled, " ")
}
