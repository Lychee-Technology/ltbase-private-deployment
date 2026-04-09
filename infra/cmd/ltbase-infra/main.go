package main

import (
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/cloudwatch"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/iam"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/lambda"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	infraConfig "lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/naming"
	"lychee.technology/ltbase/infra/internal/services"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		ctx.Log.Info("ltbase-infra: starting Pulumi program", nil)
		cfg, err := infraConfig.Load(ctx)
		if err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: loaded stack config", nil)
		awsProvider, err := aws.NewProvider(ctx, "aws-provider", &aws.ProviderArgs{
			Region: pulumi.String(cfg.AWSRegion),
		})
		if err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: created AWS provider", nil)
		providers := services.Providers{AWS: awsProvider}
		if err := ensureGitHubOIDC(ctx, cfg, providers); err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: ensured GitHub OIDC resources", nil)
		runtime, err := services.NewRuntimeResources(ctx, cfg, providers)
		if err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: declared runtime resources", nil)
		lambdas, err := services.NewLambdaServices(ctx, cfg, runtime, providers)
		if err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: declared lambda services", nil)
		if _, err = services.NewAPIs(ctx, cfg, providers, runtime, lambdas); err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: declared API resources", nil)
		canaries, err := services.NewCanaryDeployments(ctx, cfg, providers, lambdas)
		if err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: declared canary resources", nil)
		if err := wireFormaSchedule(ctx, cfg, providers, lambdas); err != nil {
			return err
		}
		ctx.Log.Info("ltbase-infra: declared forma schedule", nil)
		ctx.Export("runtimeBucket", runtime.RuntimeBucket.Bucket)
		ctx.Export("tableName", runtime.Table.Name)
		ctx.Export("dsqlClusterArn", runtime.DSQL.Cluster.Arn)
		ctx.Export("dsqlClusterIdentifier", runtime.DSQL.Cluster.Identifier)
		ctx.Export("dsqlVpcEndpointServiceName", runtime.DSQL.Cluster.VpcEndpointServiceName)
		ctx.Export("authKmsKeyArn", runtime.AuthKey.Arn)
		ctx.Export("dataPlaneFunctionName", lambdas.DataPlane.Function.Name)
		ctx.Export("dataPlaneAliasName", lambdas.DataPlane.Alias.Name)
		ctx.Export("dataPlaneTargetVersion", lambdas.DataPlane.Function.Version)
		ctx.Export("dataPlaneCurrentVersion", lambdas.DataPlane.Alias.FunctionVersion)
		ctx.Export("controlPlaneFunctionName", lambdas.ControlPlane.Function.Name)
		ctx.Export("controlPlaneAliasName", lambdas.ControlPlane.Alias.Name)
		ctx.Export("controlPlaneTargetVersion", lambdas.ControlPlane.Function.Version)
		ctx.Export("controlPlaneCurrentVersion", lambdas.ControlPlane.Alias.FunctionVersion)
		ctx.Export("authServiceFunctionName", lambdas.AuthService.Function.Name)
		ctx.Export("authServiceAliasName", lambdas.AuthService.Alias.Name)
		ctx.Export("authServiceTargetVersion", lambdas.AuthService.Function.Version)
		ctx.Export("authServiceCurrentVersion", lambdas.AuthService.Alias.FunctionVersion)
		ctx.Export("formaCdcFunctionName", lambdas.FormaCdc.Function.Name)
		if canaries.DataPlane != nil {
			ctx.Export("dataPlaneDeploymentAppName", canaries.DataPlane.Application.Name)
			ctx.Export("dataPlaneDeploymentGroupName", canaries.DataPlane.DeploymentGroup.DeploymentGroupName)
			ctx.Export("controlPlaneDeploymentAppName", canaries.ControlPlane.Application.Name)
			ctx.Export("controlPlaneDeploymentGroupName", canaries.ControlPlane.DeploymentGroup.DeploymentGroupName)
			ctx.Export("authServiceDeploymentAppName", canaries.AuthService.Application.Name)
			ctx.Export("authServiceDeploymentGroupName", canaries.AuthService.DeploymentGroup.DeploymentGroupName)
		}
		return nil
	})
}

func ensureGitHubOIDC(ctx *pulumi.Context, cfg infraConfig.StackConfig, providers services.Providers) error {
	var providerArn pulumi.StringInput
	if cfg.ManageGitHubOIDCProvider {
		provider, err := iam.NewOpenIdConnectProvider(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "github-oidc"), &iam.OpenIdConnectProviderArgs{
			ClientIdLists: pulumi.StringArray{pulumi.String("sts.amazonaws.com")},
			ThumbprintLists: pulumi.StringArray{
				pulumi.String(cfg.GitHubThumbprints[0]),
			},
			Url: pulumi.String("https://token.actions.githubusercontent.com"),
		}, pulumi.Provider(providers.AWS))
		if err != nil {
			return err
		}
		providerArn = provider.Arn
		ctx.Export("githubOidcProviderArn", provider.Arn)
	} else {
		providerArn = pulumi.String(cfg.GitHubOIDCProviderArn)
	}
	_, err := newGitHubDeployRole(ctx, cfg, providers, "devo", providerArn, []string{
		"repo:" + cfg.GitHubOrg + "/" + cfg.GitHubRepo + ":pull_request",
		"repo:" + cfg.GitHubOrg + "/" + cfg.GitHubRepo + ":ref:refs/heads/main",
		"repo:" + cfg.GitHubOrg + "/" + cfg.GitHubRepo + ":environment:devo",
	})
	if err != nil {
		return err
	}
	_, err = newGitHubDeployRole(ctx, cfg, providers, "prod", providerArn, []string{
		"repo:" + cfg.GitHubOrg + "/" + cfg.GitHubRepo + ":environment:prod",
	})
	return err
}

func newGitHubDeployRole(ctx *pulumi.Context, cfg infraConfig.StackConfig, providers services.Providers, env string, providerArn pulumi.StringInput, subs []string) (*iam.Role, error) {
	policy := pulumi.All(providerArn).ApplyT(func(args []interface{}) (string, error) {
		arn := args[0].(string)
		doc := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"` + arn + `"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},"StringLike":{"token.actions.githubusercontent.com:sub":[`
		for i, sub := range subs {
			if i > 0 {
				doc += ","
			}
			doc += `"` + sub + `"`
		}
		doc += `]}}}]}`
		return doc, nil
	}).(pulumi.StringOutput)
	role, err := iam.NewRole(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "github-"+env+"-role"), &iam.RoleArgs{
		Name:             pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, "github-"+env+"-role")),
		AssumeRolePolicy: policy,
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = iam.NewRolePolicyAttachment(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "github-"+env+"-admin"), &iam.RolePolicyAttachmentArgs{
		Role:      role.Name,
		PolicyArn: pulumi.String("arn:aws:iam::aws:policy/AdministratorAccess"),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	if env == cfg.Stack {
		ctx.Export(env+"DeployRoleArn", role.Arn)
	}
	return role, nil
}

func wireFormaSchedule(ctx *pulumi.Context, cfg infraConfig.StackConfig, providers services.Providers, lambdas *services.ServiceSet) error {
	rule, err := cloudwatch.NewEventRule(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "forma-cdc-schedule"), &cloudwatch.EventRuleArgs{
		Name:               pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, "forma-cdc-schedule")),
		ScheduleExpression: pulumi.String(cfg.FormaCdcSchedule),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return err
	}
	_, err = cloudwatch.NewEventTarget(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "forma-cdc-target"), &cloudwatch.EventTargetArgs{
		Arn:  lambdas.FormaCdc.Alias.Arn,
		Rule: rule.Name,
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return err
	}
	_, err = cloudwatch.NewMetricAlarm(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "forma-cdc-errors"), &cloudwatch.MetricAlarmArgs{
		Name:               pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, "forma-cdc-errors")),
		Namespace:          pulumi.String("AWS/Lambda"),
		MetricName:         pulumi.String("Errors"),
		Statistic:          pulumi.String("Sum"),
		ComparisonOperator: pulumi.String("GreaterThanThreshold"),
		Threshold:          pulumi.Float64(1),
		EvaluationPeriods:  pulumi.Int(1),
		Period:             pulumi.Int(300),
		Dimensions: pulumi.StringMap{
			"FunctionName": lambdas.FormaCdc.Function.Name,
			"Resource":     pulumi.Sprintf("%s:%s", lambdas.FormaCdc.Function.Name, lambdas.FormaCdc.Alias.Name),
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return err
	}
	_, err = lambda.NewPermission(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "forma-cdc-events-permission"), &lambda.PermissionArgs{
		Action:    pulumi.String("lambda:InvokeFunction"),
		Function:  lambdas.FormaCdc.Function.Name,
		Qualifier: lambdas.FormaCdc.Alias.Name,
		Principal: pulumi.String("events.amazonaws.com"),
		SourceArn: rule.Arn,
	}, pulumi.Provider(providers.AWS))
	return err
}
