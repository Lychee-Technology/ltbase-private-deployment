package services

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/cloudwatch"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/dsql"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/dynamodb"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/iam"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/kms"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/lambda"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/s3"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/artifact"
	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/naming"
)

type RuntimeResources struct {
	RuntimeBucket *s3.BucketV2
	Table         *dynamodb.Table
	DSQL          *DSQLResources
	AuthKey       *kms.Key
}

type DSQLResources struct {
	Cluster *dsql.Cluster
}

type LambdaService struct {
	Function *lambda.Function
	Alias    *lambda.Alias
	Role     *iam.Role
}

type ServiceSet struct {
	DataPlane    *LambdaService
	ControlPlane *LambdaService
	AuthService  *LambdaService
	FormaCdc     *LambdaService
}

const authServiceKMSAliasProject = "ltbase-oidc-discovery"

func NewRuntimeResources(ctx *pulumi.Context, cfg config.StackConfig, providers Providers) (*RuntimeResources, error) {
	dsqlResources, err := NewDSQLResources(ctx, cfg, providers)
	if err != nil {
		return nil, err
	}
	runtimeBucket, err := s3.NewBucketV2(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "runtime"), &s3.BucketV2Args{
		Bucket: pulumi.String(cfg.RuntimeBucket),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	if err := secureBucket(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "runtime"), runtimeBucket, providers); err != nil {
		return nil, err
	}
	table, err := dynamodb.NewTable(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "table"), &dynamodb.TableArgs{
		Name:                pulumi.String(cfg.TableName),
		BillingMode:         pulumi.String("PAY_PER_REQUEST"),
		HashKey:             pulumi.String("PK"),
		RangeKey:            pulumi.String("SK"),
		Attributes:          dynamodb.TableAttributeArray{&dynamodb.TableAttributeArgs{Name: pulumi.String("PK"), Type: pulumi.String("S")}, &dynamodb.TableAttributeArgs{Name: pulumi.String("SK"), Type: pulumi.String("S")}},
		Ttl:                 &dynamodb.TableTtlArgs{AttributeName: pulumi.String("ttl"), Enabled: pulumi.Bool(true)},
		PointInTimeRecovery: &dynamodb.TablePointInTimeRecoveryArgs{Enabled: pulumi.Bool(true)},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	authKey, err := kms.NewKey(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "auth-kms"), &kms.KeyArgs{
		CustomerMasterKeySpec: pulumi.String("RSA_2048"),
		KeyUsage:              pulumi.String("SIGN_VERIFY"),
		DeletionWindowInDays:  pulumi.Int(7),
		Description:           pulumi.String(fmt.Sprintf("LTBase authservice signing key for %s", cfg.Stack)),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = kms.NewAlias(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "auth-kms-alias"), &kms.AliasArgs{
		Name:        pulumi.String(authServiceKMSAliasName(cfg)),
		TargetKeyId: authKey.KeyId,
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	return &RuntimeResources{
		RuntimeBucket: runtimeBucket,
		Table:         table,
		DSQL:          dsqlResources,
		AuthKey:       authKey,
	}, nil
}

func authServiceKMSAliasName(cfg config.StackConfig) string {
	return "alias/" + naming.ResourceName(authServiceKMSAliasProject, cfg.Stack, "authservice")
}

func NewLambdaServices(ctx *pulumi.Context, cfg config.StackConfig, runtime *RuntimeResources, providers Providers) (*ServiceSet, error) {
	release := artifact.NewRelease(cfg.ReleaseID, cfg.ReleaseAssetDir)
	commonEnv := commonLambdaEnv(cfg, runtime.Table.Name, runtime.RuntimeBucket.Bucket)
	providerCfg, err := loadAuthProviderConfig(ctx.RootDirectory(), cfg.AuthProviderConfigFile)
	if err != nil {
		return nil, err
	}
	providerNames := authProviderNames(providerCfg)
	dataPlane, err := newLambdaService(ctx, cfg, providers, lambdaSpec{
		Name:         "data-plane",
		ArtifactPath: release.DataPlaneZip,
		Memory:       1024,
		Timeout:      30,
		AliasName:    naming.AliasName(cfg.Stack),
		Env: mergeEnv(commonEnv, pulumi.StringMap{
			"LTBASE_API_BASE_URL": pulumi.String("https://" + cfg.APIDomain),
			"GEMINI_API_KEY":      cfg.GeminiAPIKey,
			"GEMINI_MODEL":        pulumi.String(cfg.GeminiModel),
		}),
		AllowKMS: false,
	}, runtime)
	if err != nil {
		return nil, err
	}
	controlPlane, err := newLambdaService(ctx, cfg, providers, lambdaSpec{
		Name:         "control-plane",
		ArtifactPath: release.ControlPlaneZip,
		Memory:       512,
		Timeout:      30,
		AliasName:    naming.AliasName(cfg.Stack),
		Env:          commonEnv,
		AllowKMS:     false,
	}, runtime)
	if err != nil {
		return nil, err
	}
	authEnv := authLambdaEnv(cfg, providerNames, runtime.AuthKey.KeyId, runtime.Table.Name, runtime.RuntimeBucket.Bucket)
	authService, err := newLambdaService(ctx, cfg, providers, lambdaSpec{
		Name:         "authservice",
		ArtifactPath: release.AuthServiceZip,
		Memory:       512,
		Timeout:      30,
		AliasName:    naming.AliasName(cfg.Stack),
		Env:          authEnv,
		AllowKMS:     true,
	}, runtime)
	if err != nil {
		return nil, err
	}
	formaEnv := mergeEnv(commonEnv, pulumi.StringMap{
		"FORMA_CDC_S3_REGION": pulumi.String(cfg.AWSRegion),
	})
	formaCdc, err := newLambdaService(ctx, cfg, providers, lambdaSpec{
		Name:         "forma-cdc",
		ArtifactPath: release.FormaCdcZip,
		Memory:       2048,
		Timeout:      300,
		AliasName:    naming.AliasName(cfg.Stack),
		Env:          formaEnv,
		AllowKMS:     false,
	}, runtime)
	if err != nil {
		return nil, err
	}
	return &ServiceSet{DataPlane: dataPlane, ControlPlane: controlPlane, AuthService: authService, FormaCdc: formaCdc}, nil
}

func authLambdaEnv(cfg config.StackConfig, providerNames []string, authKeyID pulumi.StringInput, tableName pulumi.StringInput, bucketName pulumi.StringInput) pulumi.StringMap {
	return mergeEnv(commonLambdaEnv(cfg, tableName, bucketName), pulumi.StringMap{
		"AUTH_SIGNER_MODE":          pulumi.String("kms"),
		"AUTH_KMS_KEY_ID":           authKeyID,
		"AUTH_STAGE":                pulumi.String(cfg.AuthStage),
		"AUTH_JWKS_FILE_PATH":       pulumi.String("/var/task/jwt/jwks.json"),
		"AUTH_DEFAULT_API_BASE_URL": pulumi.String("https://" + cfg.APIDomain),
		"AUTH_PROVIDERS":            pulumi.String(strings.Join(providerNames, ",")),
	})
}

type lambdaSpec struct {
	Name         string
	ArtifactPath string
	Memory       int
	Timeout      int
	AliasName    string
	Env          pulumi.StringMap
	AllowKMS     bool
}

func newLambdaService(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, spec lambdaSpec, runtime *RuntimeResources) (*LambdaService, error) {
	role, err := newLambdaRole(ctx, cfg, providers, spec, runtime)
	if err != nil {
		return nil, err
	}
	logGroupName := pulumi.Sprintf("/aws/lambda/%s", naming.ResourceName(cfg.Project, cfg.Stack, spec.Name))
	_, err = cloudwatch.NewLogGroup(ctx, naming.ResourceName(cfg.Project, cfg.Stack, spec.Name+"-logs"), &cloudwatch.LogGroupArgs{
		Name:            logGroupName,
		RetentionInDays: pulumi.Int(14),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	function, err := lambda.NewFunction(ctx, naming.ResourceName(cfg.Project, cfg.Stack, spec.Name), &lambda.FunctionArgs{
		Name:    pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, spec.Name)),
		Role:    role.Arn,
		Runtime: pulumi.String("provided.al2023"),
		Handler: pulumi.String("bootstrap"),
		Code:    pulumi.NewFileArchive(spec.ArtifactPath),
		Architectures: pulumi.StringArray{
			pulumi.String("arm64"),
		},
		Publish:    pulumi.Bool(true),
		MemorySize: pulumi.Int(spec.Memory),
		Timeout:    pulumi.Int(spec.Timeout),
		Environment: &lambda.FunctionEnvironmentArgs{
			Variables: spec.Env,
		},
	}, pulumi.Provider(providers.AWS), pulumi.DependsOn([]pulumi.Resource{role}))
	if err != nil {
		return nil, err
	}
	aliasOpts := []pulumi.ResourceOption{pulumi.Provider(providers.AWS)}
	if cfg.Stack == "prod" && spec.Name != "forma-cdc" {
		aliasOpts = append(aliasOpts, pulumi.IgnoreChanges([]string{"functionVersion"}))
	}
	alias, err := lambda.NewAlias(ctx, naming.ResourceName(cfg.Project, cfg.Stack, spec.Name+"-alias"), &lambda.AliasArgs{
		Name:            pulumi.String(spec.AliasName),
		Description:     pulumi.String("Live alias for " + spec.Name),
		FunctionName:    function.Name,
		FunctionVersion: function.Version,
	}, aliasOpts...)
	if err != nil {
		return nil, err
	}
	return &LambdaService{Function: function, Alias: alias, Role: role}, nil
}

func newLambdaRole(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, spec lambdaSpec, runtime *RuntimeResources) (*iam.Role, error) {
	assumePolicy, err := iam.GetPolicyDocument(ctx, &iam.GetPolicyDocumentArgs{
		Statements: []iam.GetPolicyDocumentStatement{
			{
				Actions: []string{"sts:AssumeRole"},
				Principals: []iam.GetPolicyDocumentStatementPrincipal{
					{Type: "Service", Identifiers: []string{"lambda.amazonaws.com"}},
				},
			},
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	role, err := iam.NewRole(ctx, naming.ResourceName(cfg.Project, cfg.Stack, spec.Name+"-role"), &iam.RoleArgs{
		Name:             pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, spec.Name+"-role")),
		AssumeRolePolicy: pulumi.String(assumePolicy.Json),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = iam.NewRolePolicyAttachment(ctx, naming.ResourceName(cfg.Project, cfg.Stack, spec.Name+"-basic"), &iam.RolePolicyAttachmentArgs{
		Role:      role.Name,
		PolicyArn: pulumi.String("arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	policyJSON := lambdaPolicyDocument(runtime, spec.AllowKMS)
	_, err = iam.NewRolePolicy(ctx, naming.ResourceName(cfg.Project, cfg.Stack, spec.Name+"-inline"), &iam.RolePolicyArgs{
		Role:   role.ID(),
		Policy: policyJSON,
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	return role, nil
}

func lambdaPolicyDocument(runtime *RuntimeResources, allowKMS bool) pulumi.StringOutput {
	statements := pulumi.Array{
		pulumi.Map{
			"Effect": pulumi.String("Allow"),
			"Action": pulumi.StringArray{
				pulumi.String("dynamodb:GetItem"),
				pulumi.String("dynamodb:PutItem"),
				pulumi.String("dynamodb:UpdateItem"),
				pulumi.String("dynamodb:DeleteItem"),
				pulumi.String("dynamodb:Query"),
				pulumi.String("dynamodb:Scan"),
				pulumi.String("dynamodb:BatchWriteItem"),
				pulumi.String("dynamodb:BatchGetItem"),
				pulumi.String("dynamodb:DescribeTable"),
			},
			"Resource": pulumi.Array{
				runtime.Table.Arn,
				pulumi.Sprintf("%s/index/*", runtime.Table.Arn),
			},
		},
		pulumi.Map{
			"Effect": pulumi.String("Allow"),
			"Action": pulumi.StringArray{
				pulumi.String("s3:GetObject"),
				pulumi.String("s3:PutObject"),
				pulumi.String("s3:DeleteObject"),
			},
			"Resource": pulumi.Array{
				pulumi.Sprintf("arn:aws:s3:::%s/*", runtime.RuntimeBucket.Bucket),
			},
		},
		pulumi.Map{
			"Effect": pulumi.String("Allow"),
			"Action": pulumi.StringArray{
				pulumi.String("s3:ListBucket"),
			},
			"Resource": pulumi.Array{
				pulumi.Sprintf("arn:aws:s3:::%s", runtime.RuntimeBucket.Bucket),
			},
		},
		pulumi.Map{
			"Effect": pulumi.String("Allow"),
			"Action": pulumi.StringArray{
				pulumi.String("dsql:*"),
			},
			"Resource": pulumi.Array{
				pulumi.String("*"),
			},
		},
	}
	if allowKMS {
		statements = append(statements, pulumi.Map{
			"Effect": pulumi.String("Allow"),
			"Action": pulumi.StringArray{
				pulumi.String("kms:DescribeKey"),
				pulumi.String("kms:GetPublicKey"),
				pulumi.String("kms:Sign"),
			},
			"Resource": pulumi.Array{
				runtime.AuthKey.Arn,
			},
		})
	}
	return pulumi.JSONMarshal(pulumi.Map{
		"Version":   pulumi.String("2012-10-17"),
		"Statement": statements,
	})
}

func secureBucket(ctx *pulumi.Context, name string, bucket *s3.BucketV2, providers Providers) error {
	if _, err := s3.NewBucketVersioningV2(ctx, name+"-versioning", &s3.BucketVersioningV2Args{
		Bucket: bucket.ID(),
		VersioningConfiguration: &s3.BucketVersioningV2VersioningConfigurationArgs{
			Status: pulumi.String("Enabled"),
		},
	}, pulumi.Provider(providers.AWS)); err != nil {
		return err
	}
	if _, err := s3.NewBucketServerSideEncryptionConfigurationV2(ctx, name+"-sse", &s3.BucketServerSideEncryptionConfigurationV2Args{
		Bucket: bucket.ID(),
		Rules: s3.BucketServerSideEncryptionConfigurationV2RuleArray{
			&s3.BucketServerSideEncryptionConfigurationV2RuleArgs{
				ApplyServerSideEncryptionByDefault: &s3.BucketServerSideEncryptionConfigurationV2RuleApplyServerSideEncryptionByDefaultArgs{
					SseAlgorithm: pulumi.String("AES256"),
				},
			},
		},
	}, pulumi.Provider(providers.AWS)); err != nil {
		return err
	}
	_, err := s3.NewBucketPublicAccessBlock(ctx, name+"-public-access", &s3.BucketPublicAccessBlockArgs{
		Bucket:                bucket.ID(),
		BlockPublicAcls:       pulumi.Bool(true),
		BlockPublicPolicy:     pulumi.Bool(true),
		IgnorePublicAcls:      pulumi.Bool(true),
		RestrictPublicBuckets: pulumi.Bool(true),
	}, pulumi.Provider(providers.AWS))
	return err
}

func mergeEnv(parts ...pulumi.StringMap) pulumi.StringMap {
	out := pulumi.StringMap{}
	for _, part := range parts {
		for key, value := range part {
			out[key] = value
		}
	}
	return out
}

func commonLambdaEnv(cfg config.StackConfig, tableName pulumi.StringInput, bucketName pulumi.StringInput) pulumi.StringMap {
	out := pulumi.StringMap{
		"DYNAMODB_TABLE_NAME": tableName,
		"LTBASE_TABLE_NAME":   tableName,
		"DSQL_PORT":           pulumi.String(cfg.DSQLPort),
		"DSQL_DB":             pulumi.String(cfg.DSQLDB),
		"DSQL_USER":           pulumi.String(cfg.DSQLUser),
		"DSQL_PROJECT_SCHEMA": pulumi.String(cfg.DSQLProjectSchema),
		"FORMA_SCHEMA_DIR":    pulumi.String("/var/task/schemas"),
		"S3_BUCKET_NAME":      bucketName,
	}
	for key, value := range optionalDSQLEnv(cfg) {
		out[key] = pulumi.String(value)
	}
	return out
}

func optionalDSQLEnv(cfg config.StackConfig) map[string]string {
	out := map[string]string{}
	if cfg.DSQLEndpoint != "" {
		out["DSQL_ENDPOINT"] = cfg.DSQLEndpoint
	}
	return out
}
