package services

import (
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/s3"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/naming"
)

const schemaAppliedPrefix = "schemas/applied"
const schemaPublishedPrefix = "schemas/published"
const schemaCacheDir = "/tmp/ltbase-schemas"

func newSchemaBucket(ctx *pulumi.Context, cfg config.StackConfig, providers Providers) (*s3.BucketV2, *s3.BucketVersioningV2, error) {
	bucket, err := s3.NewBucketV2(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "schema"), &s3.BucketV2Args{
		Bucket: pulumi.String(cfg.SchemaBucket),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, nil, err
	}
	versioning, err := secureBucket(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "schema"), bucket, providers)
	if err != nil {
		return nil, nil, err
	}
	return bucket, versioning, nil
}

func schemaLambdaEnv(schemaBucket pulumi.StringInput, runtimePrefix pulumi.StringInput) pulumi.StringMap {
	return pulumi.StringMap{
		"FORMA_SCHEMA_SOURCE":           pulumi.String("s3"),
		"FORMA_SCHEMA_BUCKET":           schemaBucket,
		"FORMA_SCHEMA_PREFIX":           runtimePrefix,
		"FORMA_SCHEMA_PUBLISHED_PREFIX": pulumi.String(schemaPublishedPrefix),
		"FORMA_SCHEMA_CACHE_DIR":        pulumi.String(schemaCacheDir),
	}
}
