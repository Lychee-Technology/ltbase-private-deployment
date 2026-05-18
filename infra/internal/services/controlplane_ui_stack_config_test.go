package services

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"lychee.technology/ltbase/infra/internal/config"
)

func TestControlPlaneUIStackConfigJSONReusesLoginProviderNamesAndOmitsRedirectURI(t *testing.T) {
	rootDir := t.TempDir()
	configPath := filepath.Join(rootDir, "auth-providers.devo.json")
	if err := os.WriteFile(configPath, []byte(`{
	  "providers": [
	    {"name": "firebase-google", "issuer": "https://securetoken.google.com/firebase-project-devo", "audiences": ["aud-1"], "enable_login": true},
	    {"name": "supabase-google", "issuer": "https://devo-project.supabase.co/auth/v1", "audiences": ["aud-2"], "enable_login": true},
	    {"name": "ignored-no-login", "issuer": "https://securetoken.google.com/firebase-project-devo", "audiences": ["aud-3"], "enable_login": false}
	  ]
	}`), 0o600); err != nil {
		t.Fatalf("os.WriteFile() error = %v", err)
	}

	got, err := controlPlaneUIStackConfigJSON(rootDir, config.StackConfig{
		Stack:                  "devo_env",
		ProjectID:              "11111111-1111-4111-8111-111111111111",
		AuthDomain:             "auth.devo.example.com",
		ControlPlaneDomain:     "control.devo.example.com",
		APIDomain:              "api.devo.example.com",
		FirebaseProjectID:      "firebase-project-devo",
		FirebaseAPIKey:         "public-firebase-key-devo",
		SupabaseURL:            "https://devo-project.supabase.co",
		SupabaseAnonKey:        "public-supabase-key-devo",
		AuthProviderConfigFile: filepath.Base(configPath),
	})
	if err != nil {
		t.Fatalf("controlPlaneUIStackConfigJSON() error = %v", err)
	}

	var payload map[string]any
	if err := json.Unmarshal([]byte(got), &payload); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}

	if gotKey := payload["key"]; gotKey != "devo_env" {
		t.Fatalf("key = %v, want devo_env", gotKey)
	}
	if gotLabel := payload["label"]; gotLabel != "Devo Env" {
		t.Fatalf("label = %v, want Devo Env", gotLabel)
	}
	if gotOIDCClientID := payload["oidcClientId"]; gotOIDCClientID != "ltbase-controlplane-ui" {
		t.Fatalf("oidcClientId = %v, want ltbase-controlplane-ui", gotOIDCClientID)
	}
	if _, ok := payload["redirectUri"]; ok {
		t.Fatal("redirectUri should not be present")
	}

	authProviders, ok := payload["authProviders"].([]any)
	if !ok {
		t.Fatalf("authProviders type = %T, want []any", payload["authProviders"])
	}
	if len(authProviders) != 2 {
		t.Fatalf("authProviders len = %d, want 2", len(authProviders))
	}

	firstProvider, ok := authProviders[0].(map[string]any)
	if !ok {
		t.Fatalf("authProviders[0] type = %T, want map[string]any", authProviders[0])
	}
	if gotName := firstProvider["name"]; gotName != "firebase-google" {
		t.Fatalf("firebase provider name = %v, want firebase-google", gotName)
	}
	if gotLabel := firstProvider["label"]; gotLabel != "Firebase Google" {
		t.Fatalf("firebase provider label = %v, want Firebase Google", gotLabel)
	}
	if gotProjectID := firstProvider["firebaseProjectId"]; gotProjectID != "firebase-project-devo" {
		t.Fatalf("firebase project id = %v, want firebase-project-devo", gotProjectID)
	}
	if gotAPIKey := firstProvider["firebaseApiKey"]; gotAPIKey != "public-firebase-key-devo" {
		t.Fatalf("firebase api key = %v, want public-firebase-key-devo", gotAPIKey)
	}

	secondProvider, ok := authProviders[1].(map[string]any)
	if !ok {
		t.Fatalf("authProviders[1] type = %T, want map[string]any", authProviders[1])
	}
	if gotName := secondProvider["name"]; gotName != "supabase-google" {
		t.Fatalf("supabase provider name = %v, want supabase-google", gotName)
	}
	if gotLabel := secondProvider["label"]; gotLabel != "Supabase Google" {
		t.Fatalf("supabase provider label = %v, want Supabase Google", gotLabel)
	}
	if gotType := secondProvider["type"]; gotType != "supabase" {
		t.Fatalf("supabase provider type = %v, want supabase", gotType)
	}
	if gotURL := secondProvider["supabaseUrl"]; gotURL != "https://devo-project.supabase.co" {
		t.Fatalf("supabase url = %v, want https://devo-project.supabase.co", gotURL)
	}
	if gotAnonKey := secondProvider["supabaseAnonKey"]; gotAnonKey != "public-supabase-key-devo" {
		t.Fatalf("supabase anon key = %v, want public-supabase-key-devo", gotAnonKey)
	}
	if _, ok := secondProvider["redirectUri"]; ok {
		t.Fatal("provider redirectUri should not be present")
	}
}

func TestControlPlaneUIStackConfigJSONFallsBackToDefaultProviderNamesWhenMissing(t *testing.T) {
	got, err := controlPlaneUIStackConfigJSON(t.TempDir(), config.StackConfig{
		Stack:                  "prod",
		ProjectID:              "11111111-1111-4111-8111-111111111111",
		AuthDomain:             "auth.example.com",
		ControlPlaneDomain:     "control.example.com",
		APIDomain:              "api.example.com",
		FirebaseProjectID:      "firebase-project-prod",
		FirebaseAPIKey:         "public-firebase-key-prod",
		SupabaseURL:            "https://prod-project.supabase.co",
		SupabaseAnonKey:        "public-supabase-key-prod",
		AuthProviderConfigFile: "missing.json",
	})
	if err != nil {
		t.Fatalf("controlPlaneUIStackConfigJSON() error = %v", err)
	}

	var payload struct {
		Label         string `json:"label"`
		AuthProviders []struct {
			Name              string `json:"name"`
			Label             string `json:"label"`
			FirebaseProjectID string `json:"firebaseProjectId"`
			FirebaseAPIKey    string `json:"firebaseApiKey"`
			SupabaseURL       string `json:"supabaseUrl"`
			SupabaseAnonKey   string `json:"supabaseAnonKey"`
		} `json:"authProviders"`
	}
	if err := json.Unmarshal([]byte(got), &payload); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}

	if payload.Label != "Prod" {
		t.Fatalf("label = %q, want Prod", payload.Label)
	}
	if len(payload.AuthProviders) != 2 {
		t.Fatalf("authProviders len = %d, want 2", len(payload.AuthProviders))
	}
	if payload.AuthProviders[0].Name != "firebase" || payload.AuthProviders[0].Label != "Firebase" {
		t.Fatalf("firebase fallback = %#v, want firebase/Firebase", payload.AuthProviders[0])
	}
	if payload.AuthProviders[0].FirebaseProjectID != "firebase-project-prod" || payload.AuthProviders[0].FirebaseAPIKey != "public-firebase-key-prod" {
		t.Fatalf("firebase fallback browser config = %#v", payload.AuthProviders[0])
	}
	if payload.AuthProviders[1].Name != "supabase" || payload.AuthProviders[1].Label != "Supabase" {
		t.Fatalf("supabase fallback = %#v, want supabase/Supabase", payload.AuthProviders[1])
	}
	if payload.AuthProviders[1].SupabaseURL != "https://prod-project.supabase.co" || payload.AuthProviders[1].SupabaseAnonKey != "public-supabase-key-prod" {
		t.Fatalf("supabase fallback browser config = %#v", payload.AuthProviders[1])
	}
}

func TestControlPlaneUIProviderNamesFallBackWhenNoMatchingLoginProvidersExist(t *testing.T) {
	providerNames := controlPlaneUIProviderNames(AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase-ignored", Issuer: "https://securetoken.google.com/firebase-project", Audiences: []string{"aud-1"}, EnableLogin: false},
			{Name: "google-login", Issuer: "https://other.example.com/auth/v1", Audiences: []string{"aud-2"}, EnableLogin: true},
		},
	}, "firebase-project", "https://project.supabase.co")

	if providerNames.Firebase != "firebase" {
		t.Fatalf("firebase provider name = %q, want firebase", providerNames.Firebase)
	}
	if providerNames.Supabase != "supabase" {
		t.Fatalf("supabase provider name = %q, want supabase", providerNames.Supabase)
	}
}

func TestControlPlaneUIProviderNamesDoNotReuseTokenizedNamesWithoutExactIssuerMatch(t *testing.T) {
	providerNames := controlPlaneUIProviderNames(AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "firebase-google", Issuer: "https://securetoken.google.com/other-project", Audiences: []string{"aud-1"}, EnableLogin: true},
			{Name: "supabase-google", Issuer: "https://other-project.supabase.co/auth/v1", Audiences: []string{"aud-2"}, EnableLogin: true},
		},
	}, "firebase-project", "https://project.supabase.co")

	if providerNames.Firebase != "firebase" {
		t.Fatalf("firebase provider name = %q, want firebase", providerNames.Firebase)
	}
	if providerNames.Supabase != "supabase" {
		t.Fatalf("supabase provider name = %q, want supabase", providerNames.Supabase)
	}
}

func TestControlPlaneUIProviderNamesReuseExactIssuerMatches(t *testing.T) {
	providerNames := controlPlaneUIProviderNames(AuthProviderConfig{
		Providers: []AuthProvider{
			{Name: "google-login", Issuer: "https://securetoken.google.com/firebase-project", Audiences: []string{"aud-1"}, EnableLogin: true},
			{Name: "oidc-login", Issuer: "https://project.supabase.co/auth/v1", Audiences: []string{"aud-2"}, EnableLogin: true},
		},
	}, "firebase-project", "https://project.supabase.co")

	if providerNames.Firebase != "google-login" {
		t.Fatalf("firebase provider name = %q, want google-login", providerNames.Firebase)
	}
	if providerNames.Supabase != "oidc-login" {
		t.Fatalf("supabase provider name = %q, want oidc-login", providerNames.Supabase)
	}
}
