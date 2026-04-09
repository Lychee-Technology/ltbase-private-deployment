# Cloudflare to API Gateway mTLS Design

## Purpose

Add first-class support in `ltbase-private-deployment` for Cloudflare-to-AWS API Gateway mutual TLS on all three public entrypoints:

- `api`
- `auth`
- `control-plane`

The goal is to make the deployment template default to a topology where requests must traverse Cloudflare and Cloudflare must present a trusted client certificate to API Gateway.

## Background

The current template already provisions three API Gateway HTTP APIs with:

- separate custom domains
- ACM certificates validated by Cloudflare DNS
- API mappings
- Cloudflare DNS CNAME records pointing at API Gateway regional domains

It does not yet enforce mutual TLS, does not disable the default `execute-api` endpoints, and currently creates Cloudflare DNS records with `proxied=false`.

That leaves two security gaps:

1. Traffic can bypass Cloudflare and hit API Gateway directly through the default endpoint.
2. Even on the custom domain path, API Gateway does not require a client certificate from Cloudflare.

AWS HTTP API mutual TLS requires:

- a custom domain name
- a truststore in S3
- a trust relationship between API Gateway and the presented client certificate chain

Cloudflare Authenticated Origin Pulls (AOP) provides the client certificate on the Cloudflare-to-origin hop. For this first version, the template will trust Cloudflare's global AOP certificate chain instead of per-zone or per-hostname certificates.

## Scope

This design covers changes only in `ltbase-private-deployment`.

It includes:

- Pulumi config needed to support API Gateway mTLS
- uploading a built-in Cloudflare truststore PEM to S3
- enabling API Gateway mTLS on `api`, `auth`, and `control-plane` custom domains
- disabling default `execute-api` endpoints for all three HTTP APIs
- changing the Cloudflare DNS records for those hostnames to proxied records
- documentation and bootstrap examples needed to operate the feature safely
- tests for config loading, routing helpers, DNS defaults, and truststore resource wiring

It does not include:

- changes to `ltbase.api` application code
- per-zone or per-hostname Cloudflare AOP certificates
- automatic Cloudflare AOP enablement through IaC in this first version
- advanced truststore rotation automation beyond using S3 object versioning

## Decisions

### 1. mTLS is mandatory, not optional

The user explicitly chose to make this the default deployment posture. The template should therefore require the inputs and artifacts needed for mTLS rather than hide the behavior behind a per-stack feature flag.

This keeps the generated deployment repositories aligned with the intended security model and avoids an easy-to-miss split between stacks.

### 2. All three public API domains participate

Mutual TLS will be enabled for:

- `apiDomain`
- `authDomain`
- `controlPlaneDomain`

This keeps the entire API surface behind the same Cloudflare enforcement point rather than leaving one path as a bypass.

### 3. Disable all default `execute-api` endpoints

Each HTTP API resource must set `DisableExecuteApiEndpoint=true`.

This is required to make Cloudflare the only public ingress path. Without it, direct requests to the generated `{api_id}.execute-api.{region}.amazonaws.com` hostname would remain available and bypass both Cloudflare WAF and Cloudflare client certificate presentation.

The resulting direct-access failures are expected behavior and must be documented as such.

### 4. Trust Cloudflare Global AOP CA in version 1

The first version will use Cloudflare's global Authenticated Origin Pull CA chain as the API Gateway truststore.

Trade-off:

- simpler rollout and fewer customer-specific moving parts
- weaker identity guarantee than zone-level or per-hostname certificates, because it proves traffic came from Cloudflare network infrastructure, not a specific customer zone

This is acceptable for the first version because the operator explicitly chose the global path.

### 5. Ship the truststore PEM inside the repository

The truststore PEM will be tracked in the repo, under a fixed infra-owned path such as:

`infra/certs/cloudflare-origin-pull-ca.pem`

Rationale:

- deterministic builds
- no bootstrap-time network fetch dependency
- easier review of what the template trusts

The infra layer uploads this file to S3 during deployment and uses the uploaded object for API Gateway `mutualTlsAuthentication`.

### 6. Reuse the runtime bucket for the truststore object

The existing per-stack `runtimeBucket` is already created, versioned, encrypted, and private. The truststore object will live there under a stable key such as:

`mtls/cloudflare-origin-pull-ca.pem`

This avoids introducing an additional bucket for a single small object while still preserving S3 versioning for truststore updates.

### 7. Cloudflare DNS records become proxied by default

The DNS records created for API Gateway custom domains must be `proxied=true`.

Without proxying, requests would resolve directly to the API Gateway regional domain and Cloudflare would not perform the origin-side client certificate presentation.

This applies to the API hostnames only. It does not change how OIDC discovery Pages records are handled.

### 8. Cloudflare AOP enablement is a documented operator step in version 1

This version will not attempt to manage the Cloudflare Authenticated Origin Pull enablement setting via IaC.

Instead, docs and onboarding must clearly state that operators must:

- set SSL mode to `Full (strict)`
- enable Authenticated Origin Pulls for the zone

This keeps the first implementation focused on the AWS-side enforcement and the DNS path, which are the parts currently owned by the template code.

## Architecture

## File ownership

- `infra/internal/config/config.go`
  - add config fields for the truststore file path and truststore object key
- `infra/internal/services/lambda.go`
  - keep owning runtime bucket creation
- `infra/internal/services/apigateway.go`
  - own truststore upload and DomainName mTLS wiring, because this is where custom domains are built today
- `infra/internal/dns/cloudflare.go`
  - add support for choosing proxied behavior per record
- `env.template`, `infra/Pulumi.*.yaml.example`
  - expose the minimum required inputs and defaults
- `docs/onboarding/*.md`, `README.md`, `docs/BOOTSTRAP*.md`, `docs/CUSTOMER_ONBOARDING*.md`
  - explain operator expectations, failure modes, and validation steps

## Data flow

1. A truststore PEM file is stored in the repo.
2. Pulumi uploads the PEM into the stack's runtime bucket as a versioned S3 object.
3. Each API Gateway custom domain uses `MutualTlsAuthentication.TruststoreUri` pointing to that S3 object.
4. Each API Gateway HTTP API disables the default `execute-api` endpoint.
5. Cloudflare DNS records for `api`, `auth`, and `control-plane` are created as proxied records.
6. Operators enable Cloudflare AOP and keep SSL mode on `Full (strict)`.
7. Client traffic reaches Cloudflare, Cloudflare connects to API Gateway, presents its client certificate, API Gateway validates that chain against the truststore, and only then routes to Lambda.

## Configuration model

Keep the configuration minimal. The template should not introduce a large matrix of toggles.

Required behavior:

- mTLS is always on
- proxied DNS is always on for the three API hostnames
- default `execute-api` endpoints are always off

Config additions should therefore focus on stable file/object locations, not feature switches. A reasonable minimal model is:

- `mtlsTruststoreFile`
  - path to the checked-in PEM file
  - default in examples: `infra/certs/cloudflare-origin-pull-ca.pem`
- `mtlsTruststoreKey`
  - object key inside the runtime bucket
  - default in examples: `mtls/cloudflare-origin-pull-ca.pem`

If the implementation can safely derive the object key without introducing ambiguity, the object key may remain code-defined instead of user-configured.

## Error handling and operator experience

Expected failure modes must be made explicit:

- Direct access to `execute-api` endpoint fails: expected, by design.
- Cloudflare custom domain returns `526`: likely SSL mode or certificate mismatch.
- API Gateway custom domain returns `403`: likely missing AOP, bad truststore, or truststore drift.
- Cloudflare DNS resolves to unproxied origin: indicates record drift or manual change.

The docs should give operators concrete validation steps:

- confirm DNS record is proxied
- confirm Cloudflare SSL mode is `Full (strict)`
- confirm Authenticated Origin Pulls is enabled
- confirm truststore object exists in S3 and bucket versioning is enabled
- confirm the three API Gateway HTTP APIs have default endpoint disabled

## Testing

### Unit tests

Add or extend tests to cover:

- config model preserves new mTLS-related fields
- truststore path/key helper output is stable
- DNS record helper can create proxied records
- route and API helpers preserve existing route behavior while also setting `DisableExecuteApiEndpoint`

### Infra-level verification

The plan should require at least one `pulumi preview` against a sample stack and check for:

- an S3 truststore object
- mTLS configuration on all three domain resources
- disabled `execute-api` endpoint on all three API resources
- proxied Cloudflare DNS changes for the three custom domains

### Manual verification

After deployment, operators should verify:

- `curl https://<custom-domain>/...` succeeds through Cloudflare
- direct `https://<api-id>.execute-api.<region>.amazonaws.com/...` access fails
- disabling Cloudflare proxy or AOP causes origin access to fail

## Rollout constraints

This feature changes the public ingress path for every stack that adopts the updated template. That means rollout should be treated as a controlled infrastructure change, especially for production stacks.

The docs should recommend:

- validate in `devo` first
- verify Cloudflare zone settings before production apply
- expect a brief mismatch window if DNS proxying, AOP, and API Gateway mTLS are not enabled in the correct order

## Open questions resolved in this design

- Which repo owns the change? `ltbase-private-deployment`
- Which APIs are covered? `api`, `auth`, `control-plane`
- Optional or default? default and mandatory
- Cloudflare certificate mode? global AOP
- PEM source? checked in to the repo
- Should Cloudflare DNS proxy be enabled? yes
- Should `execute-api` remain available? no
