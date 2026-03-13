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
}
