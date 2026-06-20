package artifact

import "path/filepath"

type Release struct {
	ID                            string
	Directory                     string
	DataPlaneZip                  string
	ControlPlaneZip               string
	AuthServiceZip                string
	FormaCdcZip                   string
	ControlPlaneUITarball         string
	GovernanceOntologyCompilerZip string
	ManifestPath                  string
}

func NewRelease(releaseID, assetRoot string) Release {
	directory := filepath.Join(assetRoot, releaseID)
	return Release{
		ID:                            releaseID,
		Directory:                     directory,
		DataPlaneZip:                  filepath.Join(directory, "ltbase-dataplane-lambda.zip"),
		ControlPlaneZip:               filepath.Join(directory, "ltbase-controlplane-lambda.zip"),
		AuthServiceZip:                filepath.Join(directory, "ltbase-authservice-lambda.zip"),
		FormaCdcZip:                   filepath.Join(directory, "ltbase-forma-cdc-lambda.zip"),
		ControlPlaneUITarball:         filepath.Join(directory, "ltbase-controlplane-ui.tar.gz"),
		GovernanceOntologyCompilerZip: filepath.Join(directory, "ltbase-governance-ontology-compiler.zip"),
		ManifestPath:                  filepath.Join(directory, "manifest.json"),
	}
}
