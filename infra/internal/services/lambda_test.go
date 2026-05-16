package services

import (
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/naming"
)

func TestAuthServiceKMSAliasNameUsesFixedOIDCDiscoveryProject(t *testing.T) {
	got := authServiceKMSAliasName(config.StackConfig{Project: "ltbase-infra", Stack: "devo"})
	want := "alias/" + naming.ResourceName("ltbase-oidc-discovery", "devo", "authservice")
	if got != want {
		t.Fatalf("authServiceKMSAliasName() = %q, want %q", got, want)
	}
}

func TestOptionalDSQLEnvOmitsEndpointWhenUnset(t *testing.T) {
	env := optionalDSQLEnv(config.StackConfig{})
	if _, ok := env["DSQL_ENDPOINT"]; ok {
		t.Fatal("optionalDSQLEnv() unexpectedly set DSQL_ENDPOINT")
	}
}

func TestOptionalDSQLEnvIncludesExplicitEndpoint(t *testing.T) {
	env := optionalDSQLEnv(config.StackConfig{DSQLEndpoint: "db.example.internal"})
	if got := env["DSQL_ENDPOINT"]; got != "db.example.internal" {
		t.Fatalf("optionalDSQLEnv() DSQL_ENDPOINT = %q", got)
	}
}

func TestCommonLambdaEnvOmitsReservedAWSRegion(t *testing.T) {
	env := commonLambdaEnv(config.StackConfig{
		AWSRegion:         "us-east-2",
		DSQLPort:          "5432",
		DSQLDB:            "postgres",
		DSQLUser:          "admin",
		DSQLProjectSchema: "ltbase",
	}, pulumi.String("table-name"), pulumi.String("bucket-name"))

	if _, ok := env["AWS_REGION"]; ok {
		t.Fatal("commonLambdaEnv() unexpectedly sets reserved AWS_REGION")
	}
	if _, ok := env["FORMA_SCHEMA_DIR"]; ok {
		t.Fatal("commonLambdaEnv() unexpectedly sets packaged FORMA_SCHEMA_DIR")
	}
	if _, ok := env["FORMA_SCHEMA_SOURCE"]; ok {
		t.Fatal("commonLambdaEnv() unexpectedly sets schema source contract")
	}

	for _, key := range []string{"DSQL_PORT", "DSQL_DB", "DSQL_USER", "DSQL_PROJECT_SCHEMA"} {
		if _, ok := env[key]; !ok {
			t.Fatalf("commonLambdaEnv() missing %s", key)
		}
	}
}

func TestDataPlaneLambdaEnvIncludesSchemaSourceContract(t *testing.T) {
	env := dataPlaneLambdaEnv(config.StackConfig{
		APIDomain:         "api.devo.example.com",
		GeminiModel:       "gemini-3.1-flash-lite",
		DSQLPort:          "5432",
		DSQLDB:            "postgres",
		DSQLUser:          "admin",
		DSQLProjectSchema: "ltbase",
	}, pulumi.String("table-name"), pulumi.String("runtime-bucket"), pulumi.String("schema-bucket"), pulumi.String("gemini-key"))

	for _, key := range []string{"FORMA_SCHEMA_SOURCE", "FORMA_SCHEMA_BUCKET", "FORMA_SCHEMA_PREFIX", "FORMA_SCHEMA_PUBLISHED_PREFIX", "FORMA_SCHEMA_CACHE_DIR"} {
		if _, ok := env[key]; !ok {
			t.Fatalf("dataPlaneLambdaEnv() missing %s", key)
		}
	}
}

func TestAuthLambdaEnvIncludesProviderNames(t *testing.T) {
	env := authLambdaEnv(config.StackConfig{
		Stack:             "devo",
		APIDomain:         "api.devo.example.com",
		AuthDomain:        "auth.devo.example.com",
		AWSRegion:         "ap-northeast-1",
		DSQLPort:          "5432",
		DSQLDB:            "postgres",
		DSQLUser:          "admin",
		DSQLProjectSchema: "ltbase",
		OIDCIssuerURL:     "https://oidc.example.com/devo",
	}, []string{"firebase", "supabase"}, pulumi.String("kms-key-id"), pulumi.String("table-name"), pulumi.String("bucket-name"))

	for _, key := range []string{"AUTH_PROVIDERS", "AUTH_SIGNER_MODE", "AUTH_KMS_KEY_ID", "AUTH_ISSUER", "AUTH_REFRESH_AUD", "AUTH_JWKS_URL"} {
		if _, ok := env[key]; !ok {
			t.Fatalf("authLambdaEnv() missing %s", key)
		}
	}
	if env["AUTH_ISSUER"] != pulumi.String("https://oidc.example.com/devo") {
		t.Fatalf("authLambdaEnv() AUTH_ISSUER = %v, want https://oidc.example.com/devo", env["AUTH_ISSUER"])
	}
	if env["AUTH_REFRESH_AUD"] != pulumi.String("https://auth.devo.example.com") {
		t.Fatalf("authLambdaEnv() AUTH_REFRESH_AUD = %v, want https://auth.devo.example.com", env["AUTH_REFRESH_AUD"])
	}
}

func TestAuthLambdaEnvIncludesProjectID(t *testing.T) {
	env := authLambdaEnv(config.StackConfig{
		Stack:             "devo",
		ProjectID:         "33333333-3333-4333-8333-333333333333",
		APIDomain:         "api.devo.example.com",
		AWSRegion:         "ap-northeast-1",
		DSQLPort:          "5432",
		DSQLDB:            "postgres",
		DSQLUser:          "admin",
		DSQLProjectSchema: "ltbase",
	}, []string{"firebase"}, pulumi.String("kms-key-id"), pulumi.String("table-name"), pulumi.String("bucket-name"))

	if _, ok := env["PROJECT_ID"]; !ok {
		t.Fatal("authLambdaEnv() missing PROJECT_ID")
	}
}

func TestControlPlaneLambdaEnvIncludesBootstrapProjectConfig(t *testing.T) {
	env := controlPlaneLambdaEnv(config.StackConfig{
		Stack:                  "devo",
		Project:                "customer-ltbase",
		APIDomain:              "api.devo.example.com",
		ProjectID:              "33333333-3333-4333-8333-333333333333",
		DeploymentProjectName:  "Customer Ltbase",
		DeploymentAWSAccountID: "123456789012",
		DSQLPort:               "5432",
		DSQLDB:                 "postgres",
		DSQLUser:               "admin",
		DSQLProjectSchema:      "ltbase",
	}, pulumi.String("table-name"), pulumi.String("bucket-name"), pulumi.String("schema-bucket"))

	for _, key := range []string{"PROJECT_ID", "PROJECT_NAME", "ACCOUNT_ID", "API_BASE_URL", "FORMA_SCHEMA_SOURCE", "FORMA_SCHEMA_BUCKET", "FORMA_SCHEMA_PREFIX", "FORMA_SCHEMA_PUBLISHED_PREFIX", "FORMA_SCHEMA_CACHE_DIR"} {
		if _, ok := env[key]; !ok {
			t.Fatalf("controlPlaneLambdaEnv() missing %s", key)
		}
	}
}

func TestRuntimeResourcesCanCarryBucketVersioningHandle(t *testing.T) {
	runtime := RuntimeResources{}
	if runtime.RuntimeBucketVersioning != nil {
		t.Fatal("RuntimeBucketVersioning should default to nil in zero value")
	}
}
