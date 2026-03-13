package services

import (
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/acm"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/apigatewayv2"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/cloudwatch"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/lambda"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/dns"
	"lychee.technology/ltbase/infra/internal/naming"
)

type APISet struct {
	API          *apigatewayv2.Api
	ControlPlane *apigatewayv2.Api
	Auth         *apigatewayv2.Api
	Certificate  *acm.CertificateValidation
}

func NewAPIs(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, lambdas *ServiceSet) (*APISet, error) {
	apiCert, err := newValidatedCertificate(ctx, cfg, providers, "api", cfg.APIDomain)
	if err != nil {
		return nil, err
	}
	controlCert, err := newValidatedCertificate(ctx, cfg, providers, "control", cfg.ControlPlaneDomain)
	if err != nil {
		return nil, err
	}
	authCert, err := newValidatedCertificate(ctx, cfg, providers, "auth", cfg.AuthDomain)
	if err != nil {
		return nil, err
	}
	api, err := newHTTPAPI(ctx, cfg, providers, "api", cfg.APIDomain, apiCert, lambdas.DataPlane)
	if err != nil {
		return nil, err
	}
	controlPlane, err := newHTTPAPI(ctx, cfg, providers, "control", cfg.ControlPlaneDomain, controlCert, lambdas.ControlPlane)
	if err != nil {
		return nil, err
	}
	auth, err := newHTTPAPI(ctx, cfg, providers, "auth", cfg.AuthDomain, authCert, lambdas.AuthService)
	if err != nil {
		return nil, err
	}
	return &APISet{API: api, ControlPlane: controlPlane, Auth: auth, Certificate: apiCert}, nil
}

func newHTTPAPI(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, suffix, domain string, cert *acm.CertificateValidation, service *LambdaService) (*apigatewayv2.Api, error) {
	api, err := apigatewayv2.NewApi(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-api"), &apigatewayv2.ApiArgs{
		Name:         pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-api")),
		ProtocolType: pulumi.String("HTTP"),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	integration, err := apigatewayv2.NewIntegration(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-integration"), &apigatewayv2.IntegrationArgs{
		ApiId:                api.ID(),
		IntegrationType:      pulumi.String("AWS_PROXY"),
		IntegrationMethod:    pulumi.String("POST"),
		IntegrationUri:       service.Alias.InvokeArn,
		PayloadFormatVersion: pulumi.String("2.0"),
		TimeoutMilliseconds:  pulumi.Int(30000),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = apigatewayv2.NewRoute(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-route"), &apigatewayv2.RouteArgs{
		ApiId:    api.ID(),
		RouteKey: pulumi.String("ANY /{proxy+}"),
		Target:   pulumi.Sprintf("integrations/%s", integration.ID()),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = apigatewayv2.NewRoute(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-root"), &apigatewayv2.RouteArgs{
		ApiId:    api.ID(),
		RouteKey: pulumi.String("ANY /"),
		Target:   pulumi.Sprintf("integrations/%s", integration.ID()),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	logGroup, err := cloudwatch.NewLogGroup(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-api-logs"), &cloudwatch.LogGroupArgs{
		Name:            pulumi.String("/aws/apigateway/" + naming.ResourceName(cfg.Project, cfg.Stack, suffix)),
		RetentionInDays: pulumi.Int(14),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	stage, err := apigatewayv2.NewStage(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-stage"), &apigatewayv2.StageArgs{
		ApiId:      api.ID(),
		Name:       pulumi.String("$default"),
		AutoDeploy: pulumi.Bool(true),
		AccessLogSettings: &apigatewayv2.StageAccessLogSettingsArgs{
			DestinationArn: logGroup.Arn,
			Format:         pulumi.String(`{"requestId":"$context.requestId","status":"$context.status","routeKey":"$context.routeKey"}`),
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	domainName, err := apigatewayv2.NewDomainName(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-domain"), &apigatewayv2.DomainNameArgs{
		DomainName: pulumi.String(domain),
		DomainNameConfiguration: &apigatewayv2.DomainNameDomainNameConfigurationArgs{
			CertificateArn: cert.CertificateArn,
			EndpointType:   pulumi.String("REGIONAL"),
			SecurityPolicy: pulumi.String("TLS_1_2"),
		},
	}, pulumi.Provider(providers.AWS), pulumi.DependsOn([]pulumi.Resource{cert}))
	if err != nil {
		return nil, err
	}
	_, err = apigatewayv2.NewApiMapping(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-mapping"), &apigatewayv2.ApiMappingArgs{
		ApiId:      api.ID(),
		DomainName: domainName.ID(),
		Stage:      stage.ID(),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	_, err = lambda.NewPermission(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-invoke-permission"), &lambda.PermissionArgs{
		Action:    pulumi.String("lambda:InvokeFunction"),
		Function:  service.Function.Name,
		Principal: pulumi.String("apigateway.amazonaws.com"),
		Qualifier: service.Alias.Name,
		SourceArn: api.ExecutionArn.ApplyT(func(arn string) string { return arn + "/*/*" }).(pulumi.StringOutput),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	targetDomain := domainName.DomainNameConfiguration.TargetDomainName().Elem()
	if _, err = dns.NewCNAME(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-dns"), dns.RecordArgs{
		Name:     pulumi.StringPtr(domain),
		ZoneID:   cfg.CloudflareZoneID,
		ZoneName: cfg.CloudflareZoneName,
		Target:   targetDomain,
	}); err != nil {
		return nil, err
	}
	return api, nil
}

func newValidatedCertificate(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, suffix, domain string) (*acm.CertificateValidation, error) {
	cert, err := acm.NewCertificate(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-cert"), &acm.CertificateArgs{
		DomainName:       pulumi.String(domain),
		ValidationMethod: pulumi.String("DNS"),
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	option := cert.DomainValidationOptions.Index(pulumi.Int(0))
	record, err := dns.NewCNAME(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-cert-validation"), dns.RecordArgs{
		Name:     option.ResourceRecordName(),
		ZoneID:   cfg.CloudflareZoneID,
		ZoneName: cfg.CloudflareZoneName,
		Target:   option.ResourceRecordValue(),
	})
	if err != nil {
		return nil, err
	}
	return acm.NewCertificateValidation(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-cert-check"), &acm.CertificateValidationArgs{
		CertificateArn: cert.Arn,
		ValidationRecordFqdns: pulumi.StringArray{
			option.ResourceRecordName().Elem(),
		},
	}, pulumi.Provider(providers.AWS), pulumi.DependsOn([]pulumi.Resource{record}))
}
