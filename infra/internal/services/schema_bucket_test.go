package services

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/dynamodb"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/kms"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/s3"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/config"
)

func TestNewRuntimeResourcesProvisionsAndSecuresDedicatedSchemaBucket(t *testing.T) {
	mocks := &runtimeResourceMocks{}
	cfg := testStackConfig()

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		providers, err := newMockProviders(ctx)
		if err != nil {
			return err
		}
		_, err = NewRuntimeResources(ctx, cfg, providers)
		return err
	}, pulumi.WithMocks("ltbase-infra", "devo", mocks))
	if err != nil {
		t.Fatalf("NewRuntimeResources() error = %v", err)
	}

	bucket := mocks.resourceByName("aws:s3/bucketV2:BucketV2", "ltbase-infra-devo-schema")
	if bucket == nil {
		t.Fatal("expected dedicated schema bucket resource")
	}
	if got := stringInput(bucket.Inputs, "bucket"); got != cfg.SchemaBucket {
		t.Fatalf("schema bucket name = %q", got)
	}

	versioning := mocks.resourceByName("aws:s3/bucketVersioningV2:BucketVersioningV2", "ltbase-infra-devo-schema-versioning")
	if versioning == nil {
		t.Fatal("expected schema bucket versioning resource")
	}
	if got := nestedStringInput(versioning.Inputs, "versioningConfiguration", "status"); got != "Enabled" {
		t.Fatalf("schema bucket versioning status = %q", got)
	}

	sse := mocks.resourceByName("aws:s3/bucketServerSideEncryptionConfigurationV2:BucketServerSideEncryptionConfigurationV2", "ltbase-infra-devo-schema-sse")
	if sse == nil {
		t.Fatal("expected schema bucket SSE resource")
	}
	if got := nestedArrayStringInput(sse.Inputs, 0, "rules", "applyServerSideEncryptionByDefault", "sseAlgorithm"); got != "AES256" {
		t.Fatalf("schema bucket sse algorithm = %q", got)
	}

	publicAccess := mocks.resourceByName("aws:s3/bucketPublicAccessBlock:BucketPublicAccessBlock", "ltbase-infra-devo-schema-public-access")
	if publicAccess == nil {
		t.Fatal("expected schema bucket public access block resource")
	}
	for _, key := range []string{"blockPublicAcls", "blockPublicPolicy", "ignorePublicAcls", "restrictPublicBuckets"} {
		if !boolInput(publicAccess.Inputs, key) {
			t.Fatalf("schema bucket %s = false", key)
		}
	}
}

func TestNewLambdaRolePolicyGrantsReadOnlySchemaBucketAccess(t *testing.T) {
	mocks := &runtimeResourceMocks{}
	runtime := testRuntimeResources()
	cfg := testStackConfig()

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		providers, err := newMockProviders(ctx)
		if err != nil {
			return err
		}
		for _, spec := range []lambdaSpec{
			{
				Name:            "data-plane",
				AllowSchemaRead: true,
			},
			{
				Name:            "control-plane",
				AllowSchemaRead: true,
			},
		} {
			if _, err := newLambdaRole(ctx, cfg, providers, spec, runtime); err != nil {
				return err
			}
		}
		return nil
	}, pulumi.WithMocks("ltbase-infra", "devo", mocks))
	if err != nil {
		t.Fatalf("newLambdaRole() error = %v", err)
	}

	for _, name := range []string{"ltbase-infra-devo-data-plane-inline", "ltbase-infra-devo-control-plane-inline"} {
		policy := mocks.resourceByName("aws:iam/rolePolicy:RolePolicy", name)
		if policy == nil {
			t.Fatalf("expected inline policy %s", name)
		}
		assertSchemaReadOnlyStatement(t, stringInput(policy.Inputs, "policy"), "customer-ltbase-schema-devo")
	}
}

func TestNewLambdaServicesWireSchemaEnvAndReadOnlyPolicy(t *testing.T) {
	mocks := &runtimeResourceMocks{}
	runtime := testRuntimeResources()
	cfg := testStackConfig()
	rootDir := t.TempDir()
	writeAuthProviderConfig(t, rootDir)

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		providers, err := newMockProviders(ctx)
		if err != nil {
			return err
		}
		cfg.ReleaseAssetDir = "."
		cfg.ReleaseID = "test-release"
		cfg.AuthProviderConfigFile = "auth-providers.test.json"
		_, err = NewLambdaServices(ctx, cfg, runtime, providers)
		return err
	}, pulumi.WithMocks("ltbase-infra", "devo", mocks), withRootDirectory(rootDir))
	if err != nil {
		t.Fatalf("NewLambdaServices() error = %v", err)
	}

	for _, name := range []string{"ltbase-infra-devo-data-plane", "ltbase-infra-devo-control-plane"} {
		fn := mocks.resourceByName("aws:lambda/function:Function", name)
		if fn == nil {
			t.Fatalf("expected lambda function %s", name)
		}
		assertSchemaEnvContract(t, fn.Inputs, "customer-ltbase-schema-devo")
	}
	assertSchemaEnvPrefix(t, mocks.resourceByName("aws:lambda/function:Function", "ltbase-infra-devo-data-plane").Inputs, schemaAppliedPrefix)
	assertSchemaEnvPrefix(t, mocks.resourceByName("aws:lambda/function:Function", "ltbase-infra-devo-control-plane").Inputs, schemaPublishedPrefix)
	assertSchemaPublishedPrefix(t, mocks.resourceByName("aws:lambda/function:Function", "ltbase-infra-devo-data-plane").Inputs, schemaPublishedPrefix)
	assertSchemaPublishedPrefix(t, mocks.resourceByName("aws:lambda/function:Function", "ltbase-infra-devo-control-plane").Inputs, schemaPublishedPrefix)

	for _, name := range []string{"ltbase-infra-devo-data-plane-inline", "ltbase-infra-devo-control-plane-inline"} {
		policy := mocks.resourceByName("aws:iam/rolePolicy:RolePolicy", name)
		if policy == nil {
			t.Fatalf("expected inline policy %s", name)
		}
		assertSchemaReadOnlyStatement(t, stringInput(policy.Inputs, "policy"), "customer-ltbase-schema-devo")
	}
}

type runtimeResourceMocks struct {
	resources []mockResource
}

type mockResource struct {
	Token  string
	Name   string
	Inputs resource.PropertyMap
}

func (m *runtimeResourceMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return resource.PropertyMap{}, nil
}

func (m *runtimeResourceMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	inputs := args.Inputs.Copy()
	m.resources = append(m.resources, mockResource{Token: args.TypeToken, Name: args.Name, Inputs: inputs})
	state := inputs.Copy()
	state[resource.PropertyKey("name")] = resource.NewStringProperty(args.Name)
	state[resource.PropertyKey("arn")] = resource.NewStringProperty("arn:mock:" + args.Name)
	state[resource.PropertyKey("bucket")] = firstDefinedString(inputs, "bucket", args.Name)
	return args.Name + "-id", state, nil
}

func (m *runtimeResourceMocks) resourceByName(token, name string) *mockResource {
	for i := range m.resources {
		resource := &m.resources[i]
		if resource.Token == token && resource.Name == name {
			return resource
		}
	}
	return nil
}

func newMockProviders(ctx *pulumi.Context) (Providers, error) {
	provider, err := aws.NewProvider(ctx, "aws-provider", &aws.ProviderArgs{
		Region: pulumi.String("ap-northeast-1"),
	})
	if err != nil {
		return Providers{}, err
	}
	return Providers{AWS: provider}, nil
}

func withRootDirectory(root string) pulumi.RunOption {
	return func(info *pulumi.RunInfo) {
		info.RootDirectory = root
	}
}

func writeAuthProviderConfig(t *testing.T, rootDir string) {
	t.Helper()
	content := []byte(`{"providers":[{"name":"firebase","issuer":"https://issuer.example.com","audiences":["ltbase"],"enable_login":true}]}`)
	if err := os.WriteFile(filepath.Join(rootDir, "auth-providers.test.json"), content, 0o600); err != nil {
		t.Fatalf("os.WriteFile(auth provider config) error = %v", err)
	}
}

func testStackConfig() config.StackConfig {
	return config.StackConfig{
		Project:                  "ltbase-infra",
		Stack:                    "devo",
		RuntimeBucket:            "customer-ltbase-runtime-devo",
		SchemaBucket:             "customer-ltbase-schema-devo",
		TableName:                "customer-ltbase-devo",
		DeploymentAWSAccountID:   "123456789012",
		ProjectID:                "33333333-3333-4333-8333-333333333333",
		DeploymentProjectName:    "Customer Ltbase",
		APIDomain:                "api.devo.example.com",
		DSQLPort:                 "5432",
		DSQLDB:                   "postgres",
		DSQLUser:                 "admin",
		DSQLProjectSchema:        "ltbase",
		ManageGitHubOIDCProvider: true,
	}
}

func testRuntimeResources() *RuntimeResources {
	return &RuntimeResources{
		RuntimeBucket: &s3.BucketV2{Bucket: pulumi.String("customer-ltbase-runtime-devo").ToStringOutput(), Arn: pulumi.String("arn:aws:s3:::customer-ltbase-runtime-devo").ToStringOutput()},
		SchemaBucket:  &s3.BucketV2{Bucket: pulumi.String("customer-ltbase-schema-devo").ToStringOutput(), Arn: pulumi.String("arn:aws:s3:::customer-ltbase-schema-devo").ToStringOutput()},
		Table:         &dynamodb.Table{Arn: pulumi.String("arn:aws:dynamodb:ap-northeast-1:123456789012:table/customer-ltbase-devo").ToStringOutput()},
		AuthKey:       &kms.Key{Arn: pulumi.String("arn:aws:kms:ap-northeast-1:123456789012:key/test").ToStringOutput()},
	}
}

func assertSchemaReadOnlyStatement(t *testing.T, policyJSON string, bucket string) {
	t.Helper()
	var policy struct {
		Statement []struct {
			Action   []string `json:"Action"`
			Resource []string `json:"Resource"`
		} `json:"Statement"`
	}
	if err := json.Unmarshal([]byte(policyJSON), &policy); err != nil {
		t.Fatalf("json.Unmarshal(policy) error = %v", err)
	}

	objectArn := "arn:aws:s3:::" + bucket + "/*"
	bucketArn := "arn:aws:s3:::" + bucket
	var foundObject bool
	var foundList bool
	for _, statement := range policy.Statement {
		if containsString(statement.Resource, objectArn) {
			foundObject = true
			if !containsString(statement.Action, "s3:GetObject") {
				t.Fatalf("schema object actions = %v", statement.Action)
			}
			if containsString(statement.Action, "s3:PutObject") || containsString(statement.Action, "s3:DeleteObject") {
				t.Fatalf("schema object actions should be read-only: %v", statement.Action)
			}
		}
		if containsString(statement.Resource, bucketArn) {
			foundList = true
			if !containsString(statement.Action, "s3:ListBucket") {
				t.Fatalf("schema bucket actions = %v", statement.Action)
			}
			if containsString(statement.Action, "s3:PutObject") || containsString(statement.Action, "s3:DeleteObject") {
				t.Fatalf("schema bucket actions should be read-only: %v", statement.Action)
			}
		}
	}
	if !foundObject {
		t.Fatalf("missing schema object statement in %s", policyJSON)
	}
	if !foundList {
		t.Fatalf("missing schema list statement in %s", policyJSON)
	}
}

func assertSchemaEnvContract(t *testing.T, inputs resource.PropertyMap, bucket string) {
	t.Helper()
	variables := nestedObjectInput(inputs, "environment", "variables")
	if got := propertyString(variables[resource.PropertyKey("FORMA_SCHEMA_SOURCE")]); got != "s3" {
		t.Fatalf("FORMA_SCHEMA_SOURCE = %q", got)
	}
	if got := propertyString(variables[resource.PropertyKey("FORMA_SCHEMA_BUCKET")]); got != bucket {
		t.Fatalf("FORMA_SCHEMA_BUCKET = %q", got)
	}
	if got := propertyString(variables[resource.PropertyKey("FORMA_SCHEMA_PUBLISHED_PREFIX")]); got != schemaPublishedPrefix {
		t.Fatalf("FORMA_SCHEMA_PUBLISHED_PREFIX = %q", got)
	}
	if got := propertyString(variables[resource.PropertyKey("FORMA_SCHEMA_CACHE_DIR")]); got != schemaCacheDir {
		t.Fatalf("FORMA_SCHEMA_CACHE_DIR = %q", got)
	}
}

func assertSchemaEnvPrefix(t *testing.T, inputs resource.PropertyMap, want string) {
	t.Helper()
	variables := nestedObjectInput(inputs, "environment", "variables")
	if got := propertyString(variables[resource.PropertyKey("FORMA_SCHEMA_PREFIX")]); got != want {
		t.Fatalf("FORMA_SCHEMA_PREFIX = %q, want %q", got, want)
	}
}

func assertSchemaPublishedPrefix(t *testing.T, inputs resource.PropertyMap, want string) {
	t.Helper()
	variables := nestedObjectInput(inputs, "environment", "variables")
	if got := propertyString(variables[resource.PropertyKey("FORMA_SCHEMA_PUBLISHED_PREFIX")]); got != want {
		t.Fatalf("FORMA_SCHEMA_PUBLISHED_PREFIX = %q, want %q", got, want)
	}
}

func stringInput(inputs resource.PropertyMap, key string) string {
	value, ok := inputs[resource.PropertyKey(key)]
	if !ok {
		return ""
	}
	return propertyString(value)
}

func nestedStringInput(inputs resource.PropertyMap, key string, nestedKeys ...string) string {
	value, ok := inputs[resource.PropertyKey(key)]
	if !ok || !value.IsObject() {
		return ""
	}
	current := value.ObjectValue()
	for i, nestedKey := range nestedKeys {
		nestedValue, ok := current[resource.PropertyKey(nestedKey)]
		if !ok {
			return ""
		}
		if i == len(nestedKeys)-1 {
			return propertyString(nestedValue)
		}
		if !nestedValue.IsObject() {
			return ""
		}
		current = nestedValue.ObjectValue()
	}
	return ""
}

func nestedArrayStringInput(inputs resource.PropertyMap, index int, key string, nestedKeys ...string) string {
	value, ok := inputs[resource.PropertyKey(key)]
	if !ok || !value.IsArray() {
		return ""
	}
	items := value.ArrayValue()
	if index >= len(items) || !items[index].IsObject() {
		return ""
	}
	current := items[index].ObjectValue()
	for i, nestedKey := range nestedKeys {
		nestedValue, ok := current[resource.PropertyKey(nestedKey)]
		if !ok {
			return ""
		}
		if i == len(nestedKeys)-1 {
			return propertyString(nestedValue)
		}
		if !nestedValue.IsObject() {
			return ""
		}
		current = nestedValue.ObjectValue()
	}
	return ""
}

func nestedObjectInput(inputs resource.PropertyMap, key string, nestedKeys ...string) resource.PropertyMap {
	value, ok := inputs[resource.PropertyKey(key)]
	if !ok || !value.IsObject() {
		return resource.PropertyMap{}
	}
	current := value.ObjectValue()
	for _, nestedKey := range nestedKeys {
		nestedValue, ok := current[resource.PropertyKey(nestedKey)]
		if !ok || !nestedValue.IsObject() {
			return resource.PropertyMap{}
		}
		current = nestedValue.ObjectValue()
	}
	return current
}

func boolInput(inputs resource.PropertyMap, key string) bool {
	value, ok := inputs[resource.PropertyKey(key)]
	return ok && value.IsBool() && value.BoolValue()
}

func propertyString(value resource.PropertyValue) string {
	if value.IsString() {
		return value.StringValue()
	}
	if value.IsOutput() {
		return propertyString(value.OutputValue().Element)
	}
	return ""
}

func firstDefinedString(inputs resource.PropertyMap, key string, fallback string) resource.PropertyValue {
	if value, ok := inputs[resource.PropertyKey(key)]; ok {
		return value
	}
	return resource.NewStringProperty(fallback)
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
