package services

import (
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/cloudwatch"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/codedeploy"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/iam"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/naming"
)

type CanaryDeployment struct {
	Application     *codedeploy.Application
	DeploymentGroup *codedeploy.DeploymentGroup
	ErrorAlarm      *cloudwatch.MetricAlarm
	LatencyAlarm    *cloudwatch.MetricAlarm
}

type CanarySet struct {
	DataPlane    *CanaryDeployment
	ControlPlane *CanaryDeployment
	AuthService  *CanaryDeployment
}

func NewCanaryDeployments(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, services *ServiceSet) (*CanarySet, error) {
	if cfg.Stack != "prod" {
		return &CanarySet{}, nil
	}
	dataPlane, err := newCanaryDeployment(ctx, cfg, providers, "data-plane", services.DataPlane)
	if err != nil {
		return nil, err
	}
	controlPlane, err := newCanaryDeployment(ctx, cfg, providers, "control-plane", services.ControlPlane)
	if err != nil {
		return nil, err
	}
	authService, err := newCanaryDeployment(ctx, cfg, providers, "authservice", services.AuthService)
	if err != nil {
		return nil, err
	}
	return &CanarySet{DataPlane: dataPlane, ControlPlane: controlPlane, AuthService: authService}, nil
}

func newCanaryDeployment(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, name string, service *LambdaService) (*CanaryDeployment, error) {
	assumeRole, err := iam.GetPolicyDocument(ctx, &iam.GetPolicyDocumentArgs{
		Statements: []iam.GetPolicyDocumentStatement{
			{
				Actions: []string{"sts:AssumeRole"},
				Principals: []iam.GetPolicyDocumentStatementPrincipal{
					{Type: "Service", Identifiers: []string{"codedeploy.amazonaws.com"}},
				},
			},
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	role, err := iam.NewRole(ctx, naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-role"), &iam.RoleArgs{
		Name:             pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-role")),
		AssumeRolePolicy: pulumi.String(assumeRole.Json),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = iam.NewRolePolicyAttachment(ctx, naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-policy"), &iam.RolePolicyAttachmentArgs{
		Role:      role.Name,
		PolicyArn: pulumi.String("arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda"),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	resourceDimension := pulumi.Sprintf("%s:%s", service.Function.Name, service.Alias.Name)
	errorAlarm, err := cloudwatch.NewMetricAlarm(ctx, naming.ResourceName(cfg.Project, cfg.Stack, name+"-errors"), &cloudwatch.MetricAlarmArgs{
		Name:               pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, name+"-errors")),
		Namespace:          pulumi.String("AWS/Lambda"),
		MetricName:         pulumi.String("Errors"),
		Statistic:          pulumi.String("Sum"),
		ComparisonOperator: pulumi.String("GreaterThanThreshold"),
		Threshold:          pulumi.Float64(1),
		EvaluationPeriods:  pulumi.Int(1),
		Period:             pulumi.Int(60),
		Dimensions: pulumi.StringMap{
			"FunctionName": service.Function.Name,
			"Resource":     resourceDimension,
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	latencyAlarm, err := cloudwatch.NewMetricAlarm(ctx, naming.ResourceName(cfg.Project, cfg.Stack, name+"-latency"), &cloudwatch.MetricAlarmArgs{
		Name:               pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, name+"-latency")),
		Namespace:          pulumi.String("AWS/Lambda"),
		MetricName:         pulumi.String("Duration"),
		ExtendedStatistic:  pulumi.String("p99"),
		ComparisonOperator: pulumi.String("GreaterThanThreshold"),
		Threshold:          pulumi.Float64(5000),
		EvaluationPeriods:  pulumi.Int(1),
		Period:             pulumi.Int(60),
		Dimensions: pulumi.StringMap{
			"FunctionName": service.Function.Name,
			"Resource":     resourceDimension,
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	app, err := codedeploy.NewApplication(ctx, naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-app"), &codedeploy.ApplicationArgs{
		Name:            pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-app")),
		ComputePlatform: pulumi.String("Lambda"),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	group, err := codedeploy.NewDeploymentGroup(ctx, naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-group"), &codedeploy.DeploymentGroupArgs{
		AppName:              app.Name,
		DeploymentGroupName:  pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, name+"-codedeploy-group")),
		ServiceRoleArn:       role.Arn,
		DeploymentConfigName: pulumi.String("CodeDeployDefault.LambdaLinear10PercentEvery1Minute"),
		AlarmConfiguration: &codedeploy.DeploymentGroupAlarmConfigurationArgs{
			Enabled: pulumi.Bool(true),
			Alarms: pulumi.StringArray{
				errorAlarm.Name,
				latencyAlarm.Name,
			},
		},
		AutoRollbackConfiguration: &codedeploy.DeploymentGroupAutoRollbackConfigurationArgs{
			Enabled: pulumi.Bool(true),
			Events: pulumi.StringArray{
				pulumi.String("DEPLOYMENT_FAILURE"),
				pulumi.String("DEPLOYMENT_STOP_ON_ALARM"),
				pulumi.String("DEPLOYMENT_STOP_ON_REQUEST"),
			},
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	return &CanaryDeployment{Application: app, DeploymentGroup: group, ErrorAlarm: errorAlarm, LatencyAlarm: latencyAlarm}, nil
}
