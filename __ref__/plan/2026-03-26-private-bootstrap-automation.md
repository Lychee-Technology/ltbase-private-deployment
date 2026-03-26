# Private Deployment Bootstrap Automation Plan

- Add a root `env.template` with placeholders for AWS, GitHub, DNS, release, and secret values.
- Add root `.gitignore` rules for `.env` files and generated bootstrap outputs.
- Implement `scripts/bootstrap-pulumi-backend.sh` to provision or reuse the S3 backend bucket, KMS key/alias, and emit policy/output artifacts.
- Implement `scripts/bootstrap-deployment-repo.sh` to apply GitHub vars/secrets and initialize Pulumi stack config from local env files.
- Update `docs/BOOTSTRAP.md` and `docs/CUSTOMER_ONBOARDING.md` to use the new scripted flow.
- Verify with shell-script tests and command-level checks.
