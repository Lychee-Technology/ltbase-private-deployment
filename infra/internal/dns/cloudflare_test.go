package dns

import (
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

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

func TestOriginErrorPagePassThroughSettingArgs(t *testing.T) {
	args := originErrorPagePassThroughSettingArgs("zone-123")

	if got := pulumiStringValue(t, args.ZoneId); got != "zone-123" {
		t.Fatalf("ZoneId = %q, want zone-123", got)
	}
	if got := pulumiStringValue(t, args.SettingId); got != "origin_error_page_pass_thru" {
		t.Fatalf("SettingId = %q, want origin_error_page_pass_thru", got)
	}
	if got := pulumiStringValue(t, args.Value); got != "on" {
		t.Fatalf("Value = %q, want on", got)
	}
}

func pulumiStringValue(t *testing.T, input interface{}) string {
	t.Helper()
	value, ok := input.(pulumi.String)
	if !ok {
		t.Fatalf("input type = %T, want pulumi.String", input)
	}
	return string(value)
}
