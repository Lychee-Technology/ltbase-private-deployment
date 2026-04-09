package dns

import "testing"

func TestRecordProxiedDefaultsFalse(t *testing.T) {
	if recordProxied(RecordArgs{}) {
		t.Fatal("recordProxied() = true, want false")
	}
}

func TestRecordProxiedRespectsExplicitTrue(t *testing.T) {
	if !recordProxied(RecordArgs{Proxied: true}) {
		t.Fatal("recordProxied() = false, want true")
	}
}
