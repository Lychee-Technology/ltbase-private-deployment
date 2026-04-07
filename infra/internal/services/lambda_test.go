package services

import (
	"testing"

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
