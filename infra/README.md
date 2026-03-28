# LTBase Customer Infra Seed

This repository is the source of truth for the LTBase customer Pulumi blueprint.

Use the example stack files in this directory as the starting point for customer-specific `Pulumi.<stack>.yaml` values. The blueprint provisions the Aurora DSQL cluster itself and keeps the database contract focused on managed deployment inputs instead of customer-supplied host and password settings.
