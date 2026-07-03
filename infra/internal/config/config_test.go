package config

import (
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

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

func TestCorsAllowOriginsOrDefaultUsesWildcardWhenUnset(t *testing.T) {
	got := corsAllowOriginsOrDefault("")
	if len(got) != 1 || got[0] != "*" {
		t.Fatalf("corsAllowOriginsOrDefault(\"\") = %#v", got)
	}
}

func TestCorsAllowOriginsOrDefaultSplitsCSV(t *testing.T) {
	got := corsAllowOriginsOrDefault("https://api.example.com, https://admin.example.com")
	if len(got) != 2 {
		t.Fatalf("corsAllowOriginsOrDefault() length = %d", len(got))
	}
	if got[0] != "https://api.example.com" || got[1] != "https://admin.example.com" {
		t.Fatalf("corsAllowOriginsOrDefault() = %#v", got)
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
		FirebaseAPIKey:           pulumi.String("public-firebase-key").ToStringOutput(),
		FirebaseProjectID:        "firebase-project-id",
		SupabaseURL:              "https://project.supabase.co",
		SupabaseAnonKey:          "public-anon-key",
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
	if cfg.FirebaseAPIKey == (pulumi.StringOutput{}) || cfg.FirebaseProjectID == "" || cfg.SupabaseURL == "" || cfg.SupabaseAnonKey == "" {
		t.Fatal("browser-safe auth provider config should be preserved")
	}
	if cfg.MTLSTruststoreFile == "" {
		t.Fatal("MTLSTruststoreFile should be preserved")
	}
	if cfg.MTLSTruststoreKey == "" {
		t.Fatal("MTLSTruststoreKey should be preserved")
	}
}

func TestDefaultSchemaBucketUsesCanonicalRepoBasedName(t *testing.T) {
	devo := defaultSchemaBucket("customer-ltbase", "devo")
	prod := defaultSchemaBucket("customer-ltbase", "prod")

	if devo != "customer-ltbase-schema-devo" {
		t.Fatalf("defaultSchemaBucket() devo = %q", devo)
	}
	if prod != "customer-ltbase-schema-prod" {
		t.Fatalf("defaultSchemaBucket() prod = %q", prod)
	}
	if devo == prod {
		t.Fatal("defaultSchemaBucket() should vary per stack")
	}
}

func TestValidateRejectsSchemaBucketMatchingRuntimeBucket(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: true,
		RuntimeBucket:            "customer-ltbase-runtime-devo",
		SchemaBucket:             "customer-ltbase-runtime-devo",
	}

	if err := cfg.Validate(); err == nil {
		t.Fatal("Validate() expected error when schemaBucket matches runtimeBucket")
	}
}

func TestLoadDefaultsCapabilityModes(t *testing.T) {
	var got StackConfig
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		var err error
		got, err = Load(ctx)
		return err
	}, pulumi.WithMocks("ltbase-infra", "devo", configLoadMocks{}), withConfig(requiredConfig(nil)))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if got.LTSearchMode != "auto" {
		t.Fatalf("Load() LTSearchMode = %q, want auto", got.LTSearchMode)
	}
	if got.CDCMode != "auto" {
		t.Fatalf("Load() CDCMode = %q, want auto", got.CDCMode)
	}
	if got.LTFlowMode != "auto" {
		t.Fatalf("Load() LTFlowMode = %q, want auto", got.LTFlowMode)
	}
	if got.SemanticMode != "auto" {
		t.Fatalf("Load() SemanticMode = %q, want auto", got.SemanticMode)
	}
	if got.GovernanceMode != "auto" {
		t.Fatalf("Load() GovernanceMode = %q, want auto", got.GovernanceMode)
	}
	if got.GovernanceActionMode != "off" {
		t.Fatalf("Load() GovernanceActionMode = %q, want off", got.GovernanceActionMode)
	}
}

func TestLoadAcceptsCapabilityModeOverrides(t *testing.T) {
	overrides := map[string]string{
		"ltsearchMode":         "off",
		"cdcMode":              "on",
		"ltflowMode":           "off",
		"semanticMode":         "on",
		"governanceMode":       "off",
		"governanceActionMode": "on",
	}
	var got StackConfig
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		var err error
		got, err = Load(ctx)
		return err
	}, pulumi.WithMocks("ltbase-infra", "devo", configLoadMocks{}), withConfig(requiredConfig(overrides)))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	want := map[string]string{
		"LTSearchMode":         "off",
		"CDCMode":              "on",
		"LTFlowMode":           "off",
		"SemanticMode":         "on",
		"GovernanceMode":       "off",
		"GovernanceActionMode": "on",
	}
	gotModes := map[string]string{
		"LTSearchMode":         got.LTSearchMode,
		"CDCMode":              got.CDCMode,
		"LTFlowMode":           got.LTFlowMode,
		"SemanticMode":         got.SemanticMode,
		"GovernanceMode":       got.GovernanceMode,
		"GovernanceActionMode": got.GovernanceActionMode,
	}
	for key, wantValue := range want {
		if gotModes[key] != wantValue {
			t.Fatalf("Load() %s = %q, want %q", key, gotModes[key], wantValue)
		}
	}
}

func TestValidateRejectsInvalidCapabilityMode(t *testing.T) {
	cfg := StackConfig{
		ManageGitHubOIDCProvider: true,
		LTSearchMode:             "enabled",
		CDCMode:                  "auto",
		LTFlowMode:               "auto",
		SemanticMode:             "auto",
		GovernanceMode:           "auto",
		GovernanceActionMode:     "off",
	}

	err := cfg.Validate()
	if err == nil {
		t.Fatal("Validate() expected invalid capability mode error")
	}
	if !strings.Contains(err.Error(), "ltsearchMode") {
		t.Fatalf("Validate() error = %q, want ltsearchMode", err.Error())
	}
}

type configLoadMocks struct{}

func (configLoadMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return resource.PropertyMap{}, nil
}

func (configLoadMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "-id", args.Inputs, nil
}

func withConfig(values map[string]string) pulumi.RunOption {
	return func(info *pulumi.RunInfo) {
		info.Config = values
	}
}

func requiredConfig(overrides map[string]string) map[string]string {
	values := map[string]string{
		"githubRepo":              "customer-ltbase",
		"deploymentAwsAccountId":  "123456789012",
		"runtimeBucket":           "customer-ltbase-runtime-devo",
		"tableName":               "customer-ltbase-control-plane-devo",
		"mtlsTruststoreFile":      "infra/certs/cloudflare-origin-pull-ca.pem",
		"mtlsTruststoreKey":       "mtls/cloudflare-origin-pull-ca.pem",
		"apiDomain":               "api.devo.example.com",
		"controlPlaneDomain":      "control.devo.example.com",
		"authDomain":              "auth.devo.example.com",
		"projectId":               "33333333-3333-4333-8333-333333333333",
		"authProviderConfigFile":  "infra/auth-providers.devo.json",
		"firebaseApiKey":          "firebase-public-key",
		"firebaseProjectId":       "firebase-project-id",
		"supabaseUrl":             "https://project.supabase.co",
		"supabaseAnonKey":         "supabase-public-anon-key",
		"cloudflareZoneId":        "zone-id",
		"oidcIssuerUrl":           "https://oidc.example.com/devo",
		"jwksUrl":                 "https://oidc.example.com/devo/.well-known/jwks.json",
		"releaseId":               "v0.0.0-test",
		"geminiApiKey":            "gemini-key",
		"githubOrg":               "Lychee-Technology",
		"githubOidcProviderArn":   "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com",
		"controlPlaneCorsOrigins": "https://admin.devo.example.com",
	}
	for key, value := range overrides {
		values[key] = value
	}
	out := map[string]string{}
	for key, value := range values {
		out["ltbase-infra:"+key] = value
	}
	return out
}
