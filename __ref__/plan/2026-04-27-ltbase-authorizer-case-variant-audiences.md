# LTBase Authorizer: Add Case-Variant Audiences

**Date:** 2026-04-27
**Goal:** Make the data plane API Gateway JWT authorizer accept the project ID as audience in original, uppercase, and lowercase forms (deduplicated).

**Change:** `ltbaseAuthorizerSpec` currently sets `Audiences: []string{cfg.ProjectID}`. After this change it will include `project_id`, `upper(project_id)`, and `lower(project_id)` with duplicates removed.

**Files:**
- Modify: `infra/internal/services/apigateway.go`
- Modify: `infra/internal/services/apigateway_test.go`

**Rationale:** JWT `aud` claim casing can vary across clients and identity providers. By accepting all three forms, the authorizer covers common casing mismatches without requiring clients to normalize.
