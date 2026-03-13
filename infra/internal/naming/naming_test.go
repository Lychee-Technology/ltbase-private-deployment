package naming

import "testing"

func TestResourceName(t *testing.T) {
	got := ResourceName("ltbase_infra", "devo", "Data Plane")
	if got != "ltbase-infra-devo-data-plane" {
		t.Fatalf("ResourceName() = %q", got)
	}
}

func TestCloudflareRecordName(t *testing.T) {
	tests := []struct {
		fqdn string
		zone string
		want string
	}{
		{fqdn: "api.example.com", zone: "example.com", want: "api"},
		{fqdn: "example.com", zone: "example.com", want: "@"},
		{fqdn: "auth.other.com", zone: "example.com", want: "auth.other.com"},
	}
	for _, tt := range tests {
		if got := CloudflareRecordName(tt.fqdn, tt.zone); got != tt.want {
			t.Fatalf("CloudflareRecordName(%q, %q) = %q, want %q", tt.fqdn, tt.zone, got, tt.want)
		}
	}
}
