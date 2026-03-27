# LTBase Private Deployment Template

This directory is the customer-facing seed for the future `ltbase-private-deployment` repository.

It contains:

- thin wrapper workflows that call the public reusable deployment workflows
- onboarding docs for customer-owned secrets, variables, and bootstrap steps
- bootstrap scripts for backend, KMS, GitHub Actions configuration, and Pulumi stack setup
- sample stack configuration files for the forked Pulumi blueprint

Bootstrap entrypoints:

- `env.template`
- `scripts/render-bootstrap-policies.sh`
- `scripts/create-deployment-repo.sh`
- `scripts/bootstrap-aws-foundation.sh`
- `scripts/bootstrap-pulumi-backend.sh`
- `scripts/bootstrap-deployment-repo.sh`
- `scripts/bootstrap-all.sh`

Primary docs:

- customer runbook: [`docs/CUSTOMER_ONBOARDING.md`](/Users/ruoshi/code/Lychee/ltbase.api/templates/ltbase-private-deployment/docs/CUSTOMER_ONBOARDING.md)
- bootstrap checklist: [`docs/BOOTSTRAP.md`](/Users/ruoshi/code/Lychee/ltbase.api/templates/ltbase-private-deployment/docs/BOOTSTRAP.md)

The Pulumi Go program itself still lives in the source repository root at [`infra/`](/Users/ruoshi/code/Lychee/ltbase.api/infra). When the standalone blueprint repository is created, copy that directory in as the repository's `infra/` implementation.
