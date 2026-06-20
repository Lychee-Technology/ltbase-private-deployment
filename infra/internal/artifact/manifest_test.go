package artifact

import "testing"

func TestNewRelease(t *testing.T) {
	release := NewRelease("abc123", "../.ltbase/releases")
	if release.ManifestPath != "../.ltbase/releases/abc123/manifest.json" {
		t.Fatalf("ManifestPath = %q", release.ManifestPath)
	}
	if release.DataPlaneZip != "../.ltbase/releases/abc123/ltbase-dataplane-lambda.zip" {
		t.Fatalf("DataPlaneZip = %q", release.DataPlaneZip)
	}
	if release.ControlPlaneUITarball != "../.ltbase/releases/abc123/ltbase-controlplane-ui.tar.gz" {
		t.Fatalf("ControlPlaneUITarball = %q", release.ControlPlaneUITarball)
	}
	if release.GovernanceOntologyCompilerZip != "../.ltbase/releases/abc123/ltbase-governance-ontology-compiler.zip" {
		t.Fatalf("GovernanceOntologyCompilerZip = %q", release.GovernanceOntologyCompilerZip)
	}
}

func TestNewReleaseModelsAllSixArtifacts(t *testing.T) {
	release := NewRelease("v1.2.3", "../.ltbase/releases")
	expected := map[string]string{
		"ltbase-dataplane-lambda.zip":             release.DataPlaneZip,
		"ltbase-controlplane-lambda.zip":          release.ControlPlaneZip,
		"ltbase-authservice-lambda.zip":           release.AuthServiceZip,
		"ltbase-forma-cdc-lambda.zip":             release.FormaCdcZip,
		"ltbase-controlplane-ui.tar.gz":           release.ControlPlaneUITarball,
		"ltbase-governance-ontology-compiler.zip": release.GovernanceOntologyCompilerZip,
		"manifest.json":                           release.ManifestPath,
	}
	for filename, path := range expected {
		want := "../.ltbase/releases/v1.2.3/" + filename
		if path != want {
			t.Fatalf("artifact %q = %q, want %q", filename, path, want)
		}
	}
}
