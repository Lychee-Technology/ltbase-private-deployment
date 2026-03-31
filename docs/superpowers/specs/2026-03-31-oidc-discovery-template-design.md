# OIDC Discovery Template Repository Design

Issue: Lychee-Technology/ltbase-private-deployment#13

## Purpose

Create and populate the `Lychee-Technology/ltbase-oidc-discovery-template` repository. Customer companion repos are generated from this template by `bootstrap-oidc-discovery-companion.sh`. Each companion repo serves OIDC discovery documents (openid-configuration and jwks.json) for all stacks in the customer's deployment via Cloudflare Pages.

## Background

The auth signing KMS key is created by the Pulumi infra layer during deployment. Its alias follows the naming convention `alias/ltbase-infra-<stack>-authservice` (derived by `naming.ResourceName("ltbase-infra", stack, "authservice")`). This alias already exists in the infra code — no new Pulumi resources are needed.

The companion repo is bootstrapped by `bootstrap-oidc-discovery-companion.sh`, which:
- Creates the repo from the template
- Creates a Cloudflare Pages project connected to the repo
- Attaches a custom domain to the Pages project
- Creates per-stack IAM roles with `kms:GetPublicKey` and `kms:DescribeKey` permissions
- Sets two repo variables: `OIDC_DISCOVERY_DOMAIN` and `OIDC_DISCOVERY_STACK_CONFIG`

The template repo is currently empty (exists on GitHub but has no commits). It needs to be populated and marked as a template.

## Repository Visibility

Public. The template contains no secrets — only workflow definitions and utility scripts. Customers can inspect it before companion repos are generated.

## Repository Structure

```
ltbase-oidc-discovery-template/
  .github/
    workflows/
      publish-discovery.yml
  scripts/
    generate-jwks.py
  README.md
```

Three files total, plus the workflow. Minimal by design.

## Workflow: publish-discovery.yml

### Trigger

`workflow_dispatch` with one input:
- `target_stack`: string, default `"all"`. Accepts `"all"` or a specific stack name (e.g., `"devo"`, `"prod"`).

### Permissions

```yaml
permissions:
  contents: write    # commit generated files
  id-token: write    # assume IAM roles via OIDC
```

### Inputs from Repo Variables

- `vars.OIDC_DISCOVERY_DOMAIN` — custom domain (e.g., `oidc.customer.example.com`)
- `vars.OIDC_DISCOVERY_STACK_CONFIG` — JSON mapping stacks to AWS credentials and KMS alias:

```json
{
  "devo": {
    "aws_region": "ap-northeast-1",
    "aws_role_arn": "arn:aws:iam::123456789012:role/customer-ltbase-oidc-discovery-devo",
    "kms_auth_key_alias": "alias/ltbase-infra-devo-authservice"
  },
  "prod": {
    "aws_region": "us-west-2",
    "aws_role_arn": "arn:aws:iam::210987654321:role/customer-ltbase-oidc-discovery-prod",
    "kms_auth_key_alias": "alias/ltbase-infra-prod-authservice"
  }
}
```

### Job Structure

Single job `publish` that:

1. Checks out the repo.
2. Parses `OIDC_DISCOVERY_STACK_CONFIG` to determine target stacks (all or filtered to `target_stack`).
3. For each stack:
   a. Configures AWS credentials via `aws-actions/configure-aws-credentials` using the stack's `aws_role_arn` and `aws_region`.
   b. Calls `aws kms get-public-key --key-id <kms_auth_key_alias> --output json` to retrieve the DER-encoded RSA public key and key ID.
   c. Runs `scripts/generate-jwks.py` to convert the DER public key to a JWKS document.
   d. Writes `<stack>/.well-known/jwks.json`.
   e. Writes `<stack>/.well-known/openid-configuration` with issuer and jwks_uri.
4. Commits all generated files and pushes to the default branch.
5. Cloudflare Pages auto-deploys on push.

### Stack Iteration

The workflow uses a matrix strategy would be awkward here because each stack needs different AWS credentials and the final commit must combine all stacks. Instead, a single job iterates stacks sequentially in a shell loop. This keeps the commit atomic.

## Script: generate-jwks.py

A Python3 script (no dependencies beyond stdlib) that:

1. Reads a base64-encoded DER public key and a key ID from command-line arguments or stdin.
2. Parses the DER-encoded SubjectPublicKeyInfo using Python's `cryptography`-free approach: manually decode the ASN.1 DER to extract the RSA modulus and exponent. Python3 stdlib has no built-in ASN.1 parser, but the SubjectPublicKeyInfo structure for RSA keys is fixed and can be parsed with minimal code.

   Alternative: use `openssl` CLI to extract modulus/exponent. This is available on all GitHub runners and avoids DER parsing entirely:
   ```
   echo <base64-der> | base64 -d | openssl rsa -pubin -inform DER -text -noout
   ```
   However, parsing the text output is fragile.

   Chosen approach: use Python3 with the DER structure. RSA SubjectPublicKeyInfo has a well-known ASN.1 layout. The script decodes the outer SEQUENCE, skips the algorithm identifier, then decodes the BIT STRING containing the RSA public key (modulus + exponent). This is ~60 lines and has zero dependencies.

3. Outputs a JWKS JSON document:
```json
{
  "keys": [
    {
      "kty": "RSA",
      "alg": "RS256",
      "use": "sig",
      "kid": "<kms-key-id>",
      "n": "<base64url-encoded-modulus>",
      "e": "<base64url-encoded-exponent>"
    }
  ]
}
```

## Output Documents

### `<stack>/.well-known/jwks.json`

Standard RFC 7517 JWKS. Single key per stack. Format matches what `buildRSAJWKS` produces in `ltbase.api/internal/authservice/signer.go`.

### `<stack>/.well-known/openid-configuration`

Minimal OpenID Provider Configuration:
```json
{
  "issuer": "https://<OIDC_DISCOVERY_DOMAIN>/<stack>",
  "jwks_uri": "https://<OIDC_DISCOVERY_DOMAIN>/<stack>/.well-known/jwks.json",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
```

Note: the API's `LTBaseJWTIssuerBase` is hardcoded to `https://oidc.ltbase.dev` in the Go source. The `issuer` field here uses the customer's domain. These may differ intentionally — the discovery documents serve external consumers, while the API's issuer validation uses its own constant. This is a known divergence, not a bug.

## Changes to ltbase-private-deployment

### bootstrap-env.sh

Update `bootstrap_env_oidc_discovery_stack_config_json` to include `kms_auth_key_alias` per stack. The alias follows the convention `alias/ltbase-infra-<stack>-authservice`. This is derived from the fixed Pulumi project name `ltbase-infra` and the stack name.

Add a new env var `PULUMI_PROJECT` (default: `ltbase-infra`) to `bootstrap_env_load` so the alias can be derived without hardcoding. The env.template should document it.

The updated stack config JSON becomes:
```json
{
  "devo": {
    "aws_region": "ap-northeast-1",
    "aws_role_arn": "arn:aws:iam::...",
    "kms_auth_key_alias": "alias/ltbase-infra-devo-authservice"
  }
}
```

### bootstrap-oidc-discovery-companion-test.sh

Update to verify the `kms_auth_key_alias` field is present in the stack config JSON.

### env.template

Add `PULUMI_PROJECT=ltbase-infra` with comment explaining it controls the KMS alias derivation.

## Template Repo README

The README should document:
- Purpose of the companion repo
- Required repo variables (`OIDC_DISCOVERY_DOMAIN`, `OIDC_DISCOVERY_STACK_CONFIG`)
- How to run the publish workflow
- What the workflow produces
- That no secrets are needed (IAM roles use GitHub OIDC federation)

Bilingual: English and Chinese, matching the private-deployment docs convention.

## Testing

### In the template repo

`test/generate-jwks-test.sh`: unit test for `generate-jwks.py` using a known RSA public key. Verifies:
- Output is valid JSON
- Contains `kty`, `alg`, `use`, `kid`, `n`, `e` fields
- `n` and `e` are base64url-encoded (no padding)
- Round-trip: decoded modulus matches the input key's modulus

### In ltbase-private-deployment

- Update `bootstrap-oidc-discovery-companion-test.sh` to check `kms_auth_key_alias` in stack config
- Existing `evaluate-and-continue-test.sh` tests are unaffected

### Integration

After first deployment, manually run `publish-discovery.yml` and verify:
- `https://<domain>/<stack>/.well-known/jwks.json` returns valid JWKS
- `https://<domain>/<stack>/.well-known/openid-configuration` returns valid configuration

## Scope Boundary

This spec covers:
- Populating the template repo with workflow, script, README, and test
- Marking the repo as a template on GitHub
- Making the repo public
- Updating `bootstrap-env.sh` to include `kms_auth_key_alias` in stack config
- Adding `PULUMI_PROJECT` to env.template

This spec does NOT cover:
- Changes to the Pulumi infra code (the KMS alias already exists)
- Changes to the API source code
- Automated key rotation workflows
- Multi-key JWKS support (single key per stack is sufficient)
