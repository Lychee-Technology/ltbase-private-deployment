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

	for _, key := range []string{"DSQL_PORT", "DSQL_DB", "DSQL_USER", "DSQL_PROJECT_SCHEMA", "FORMA_SCHEMA_DIR"} {
		if _, ok := env[key]; !ok {
			t.Fatalf("commonLambdaEnv() missing %s", key)
		}
	}
}

func TestAuthLambdaEnvIncludesProviderNames(t *testing.T) {
	env := authLambdaEnv(config.StackConfig{
		Stack:             "devo",
		APIDomain:         "api.devo.example.com",
		AWSRegion:         "ap-northeast-1",
		DSQLPort:          "5432",
		DSQLDB:            "postgres",
		DSQLUser:          "admin",
		DSQLProjectSchema: "ltbase",
	}, []string{"firebase", "supabase"}, pulumi.String("kms-key-id"), pulumi.String("table-name"), pulumi.String("bucket-name"))

	for _, key := range []string{"AUTH_PROVIDERS", "AUTH_SIGNER_MODE", "AUTH_KMS_KEY_ID"} {
		if _, ok := env[key]; !ok {
			t.Fatalf("authLambdaEnv() missing %s", key)
		}
	}
}

func TestRuntimeResourcesCanCarryBucketVersioningHandle(t *testing.T) {
	runtime := RuntimeResources{}
	if runtime.RuntimeBucketVersioning != nil {
		t.Fatal("RuntimeBucketVersioning should default to nil in zero value")
	}
}
