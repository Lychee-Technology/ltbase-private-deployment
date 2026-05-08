# Cloudflare Origin Error Page Pass-through Design

## Goal

Enable Cloudflare Origin Error Page Pass-through by default for LTBase private deployment stacks.

## Scope

This is a customer deployment template infrastructure change in `ltbase-private-deployment`. It belongs to the Pulumi Go blueprint under `infra/` because the template already manages Cloudflare DNS records there and stack config already requires `ltbase-infra:cloudflareZoneId`.

## Design

The Pulumi program will declare a Cloudflare zone setting for the configured zone:

- `settingId`: `origin_error_page_pass_thru`
- `value`: `on`
- `zoneId`: `cfg.CloudflareZoneID`

The setting is zone-level, so each stack that uses a Cloudflare zone declares the same desired state for its configured zone. Cloudflare documents this setting as Enterprise-limited and applicable to origin `502` and `504` responses, not `522` responses. If the zone plan or token cannot edit the setting, Pulumi should fail visibly during preview or update.

## Components

- `infra/internal/dns/cloudflare.go`: add a focused helper for the zone setting so the setting id and value are not duplicated in the Pulumi entrypoint.
- `infra/internal/dns/cloudflare_test.go`: add unit coverage for the helper arguments.
- `infra/cmd/ltbase-infra/main.go`: call the helper after loading stack config and creating providers, before service resources are declared.

## Testing

Add a Go unit test that verifies the helper emits the exact setting id, value, and zone id expected by the Cloudflare provider. Run the focused DNS package tests, then the full infra Go test suite.

## Out Of Scope

- One-off Cloudflare API mutation scripts.
- Making the setting optional.
- Changing Cloudflare API token permissions or onboarding inputs.
