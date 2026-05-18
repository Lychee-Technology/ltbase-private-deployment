package services

import (
	"encoding/json"

	"lychee.technology/ltbase/infra/internal/config"
)

const controlPlaneUIOIDCClientID = "ltbase-controlplane-ui"

type controlPlaneUIStackConfig struct {
	Key                 string                       `json:"key"`
	Label               string                       `json:"label"`
	ProjectID           string                       `json:"projectId"`
	AuthBaseURL         string                       `json:"authBaseUrl"`
	ControlPlaneBaseURL string                       `json:"controlPlaneBaseUrl"`
	APIBaseURL          string                       `json:"apiBaseUrl"`
	OIDCClientID        string                       `json:"oidcClientId"`
	AuthProviders       []controlPlaneUIAuthProvider `json:"authProviders"`
}

type controlPlaneUIAuthProvider struct {
	Type              string `json:"type"`
	Name              string `json:"name"`
	Label             string `json:"label"`
	FirebaseProjectID string `json:"firebaseProjectId,omitempty"`
	FirebaseAPIKey    string `json:"firebaseApiKey,omitempty"`
	SupabaseURL       string `json:"supabaseUrl,omitempty"`
	SupabaseAnonKey   string `json:"supabaseAnonKey,omitempty"`
}

func controlPlaneUIStackConfigJSON(rootDir string, cfg config.StackConfig) (string, error) {
	providerCfg, err := loadAuthProviderConfig(rootDir, cfg.AuthProviderConfigFile)
	if err != nil {
		return "", err
	}

	providerNames := controlPlaneUIProviderNames(providerCfg, cfg.FirebaseProjectID, cfg.SupabaseURL)
	payload := controlPlaneUIStackConfig{
		Key:                 cfg.Stack,
		Label:               titleizeKey(cfg.Stack),
		ProjectID:           cfg.ProjectID,
		AuthBaseURL:         "https://" + cfg.AuthDomain,
		ControlPlaneBaseURL: "https://" + cfg.ControlPlaneDomain,
		APIBaseURL:          APIBaseURL(cfg),
		OIDCClientID:        controlPlaneUIOIDCClientID,
		AuthProviders: []controlPlaneUIAuthProvider{
			{Type: "firebase", Name: providerNames.Firebase, Label: titleizeKey(providerNames.Firebase), FirebaseProjectID: cfg.FirebaseProjectID, FirebaseAPIKey: cfg.FirebaseAPIKey},
			{Type: "supabase", Name: providerNames.Supabase, Label: titleizeKey(providerNames.Supabase), SupabaseURL: cfg.SupabaseURL, SupabaseAnonKey: cfg.SupabaseAnonKey},
		},
	}

	raw, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func ControlPlaneUIStackConfigJSON(rootDir string, cfg config.StackConfig) (string, error) {
	return controlPlaneUIStackConfigJSON(rootDir, cfg)
}
