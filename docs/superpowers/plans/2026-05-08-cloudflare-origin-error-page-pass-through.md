# Cloudflare Origin Error Page Pass-through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Cloudflare Origin Error Page Pass-through through the Pulumi blueprint for every configured LTBase deployment stack.

**Architecture:** Add a small Cloudflare zone setting helper in `infra/internal/dns` and wire it from `infra/cmd/ltbase-infra/main.go`. Keep the Cloudflare setting id and value centralized and unit-tested.

**Tech Stack:** Go, Pulumi, `github.com/pulumi/pulumi-cloudflare/sdk/v6`, `go test`.

---

### Task 1: Add Cloudflare zone setting helper

**Files:**
- Modify: `infra/internal/dns/cloudflare_test.go`
- Modify: `infra/internal/dns/cloudflare.go`

- [ ] **Step 1: Write the failing test**

Add this test to `infra/internal/dns/cloudflare_test.go`:

```go
func TestOriginErrorPagePassThroughSettingArgs(t *testing.T) {
	args := originErrorPagePassThroughSettingArgs("zone-123")

	if got := args.ZoneId; got != "zone-123" {
		t.Fatalf("ZoneId = %q, want zone-123", got)
	}
	if got := args.SettingId; got != "origin_error_page_pass_thru" {
		t.Fatalf("SettingId = %q, want origin_error_page_pass_thru", got)
	}
	if got := args.Value; got != "on" {
		t.Fatalf("Value = %q, want on", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/dns`

Expected: FAIL because `originErrorPagePassThroughSettingArgs` is undefined.

- [ ] **Step 3: Write minimal implementation**

In `infra/internal/dns/cloudflare.go`, add constants and a helper that returns `cloudflare.ZoneSettingArgs`:

```go
const (
	originErrorPagePassThroughSettingID = "origin_error_page_pass_thru"
	cloudflareSettingOn                 = "on"
)

func originErrorPagePassThroughSettingArgs(zoneID string) cloudflare.ZoneSettingArgs {
	return cloudflare.ZoneSettingArgs{
		ZoneId:    pulumi.String(zoneID),
		SettingId: pulumi.String(originErrorPagePassThroughSettingID),
		Value:     pulumi.String(cloudflareSettingOn),
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/dns`

Expected: PASS.

### Task 2: Wire setting into the Pulumi program

**Files:**
- Modify: `infra/internal/dns/cloudflare.go`
- Modify: `infra/cmd/ltbase-infra/main.go`

- [ ] **Step 1: Add exported constructor**

In `infra/internal/dns/cloudflare.go`, add:

```go
func NewOriginErrorPagePassThrough(ctx *pulumi.Context, logicalName string, zoneID string, opts ...pulumi.ResourceOption) (*cloudflare.ZoneSetting, error) {
	args := originErrorPagePassThroughSettingArgs(zoneID)
	return cloudflare.NewZoneSetting(ctx, logicalName, &args, opts...)
}
```

- [ ] **Step 2: Wire the constructor**

In `infra/cmd/ltbase-infra/main.go`, import `lychee.technology/ltbase/infra/internal/dns` and call:

```go
if _, err := dns.NewOriginErrorPagePassThrough(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "cloudflare-origin-error-page-pass-through"), cfg.CloudflareZoneID); err != nil {
	return err
}
ctx.Log.Info("ltbase-infra: declared Cloudflare origin error page pass-through setting", nil)
```

Place it after provider setup and before service resources.

- [ ] **Step 3: Run full verification**

Run: `gofmt -w infra/internal/dns/cloudflare.go infra/internal/dns/cloudflare_test.go infra/cmd/ltbase-infra/main.go`

Run: `go test ./...`

Expected: all infra Go packages pass.
