package services

import (
	"regexp"
	"strings"

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

type routeSpec struct {
	RouteKey       string
	AuthorizerName string
}

type authorizerSpec struct {
	Name      string
	Issuer    string
	Audiences []string
}

var routeResourceNameCleaner = regexp.MustCompile(`[^a-z0-9]+`)

func NewAPIs(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, lambdas *ServiceSet) (*APISet, error) {
	providerCfg, err := loadAuthProviderConfig(cfg.AuthProviderConfigFile)
	if err != nil {
		return nil, err
	}
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
	api, err := newHTTPAPI(ctx, cfg, providers, "api", cfg.APIDomain, apiCert, lambdas.DataPlane, buildAPIRouteSpecs(), []authorizerSpec{ltbaseAuthorizerSpec(cfg)})
	if err != nil {
		return nil, err
	}
	controlPlane, err := newHTTPAPI(ctx, cfg, providers, "control", cfg.ControlPlaneDomain, controlCert, lambdas.ControlPlane, buildControlPlaneRouteSpecs(), []authorizerSpec{ltbaseAuthorizerSpec(cfg)})
	if err != nil {
		return nil, err
	}
	auth, err := newHTTPAPI(ctx, cfg, providers, "auth", cfg.AuthDomain, authCert, lambdas.AuthService, buildAuthRouteSpecs(providerCfg), buildAuthAuthorizerSpecs(cfg, providerCfg))
	if err != nil {
		return nil, err
	}
	return &APISet{API: api, ControlPlane: controlPlane, Auth: auth, Certificate: apiCert}, nil
}

func ltbaseAuthorizerSpec(cfg config.StackConfig) authorizerSpec {
	return authorizerSpec{
		Name:      "LTBase",
		Issuer:    cfg.OIDCIssuerURL,
		Audiences: []string{cfg.ProjectID},
	}
}

func buildAPIRouteSpecs() []routeSpec {
	return []routeSpec{
		{RouteKey: "GET /api/ai/v1/notes", AuthorizerName: "LTBase"},
		{RouteKey: "POST /api/ai/v1/notes", AuthorizerName: "LTBase"},
		{RouteKey: "GET /api/ai/v1/notes/{note_id}", AuthorizerName: "LTBase"},
		{RouteKey: "PUT /api/ai/v1/notes/{note_id}", AuthorizerName: "LTBase"},
		{RouteKey: "DELETE /api/ai/v1/notes/{note_id}", AuthorizerName: "LTBase"},
		{RouteKey: "GET /api/v1/deepping", AuthorizerName: "LTBase"},
		{RouteKey: "GET /api/v1/{schema_name}", AuthorizerName: "LTBase"},
		{RouteKey: "POST /api/v1/{schema_name}", AuthorizerName: "LTBase"},
		{RouteKey: "GET /api/v1/{schema_name}/{row_id}", AuthorizerName: "LTBase"},
		{RouteKey: "PUT /api/v1/{schema_name}/{row_id}", AuthorizerName: "LTBase"},
		{RouteKey: "DELETE /api/v1/{schema_name}/{row_id}", AuthorizerName: "LTBase"},
	}
}

func buildControlPlaneRouteSpecs() []routeSpec {
	return []routeSpec{
		{RouteKey: "ANY /", AuthorizerName: "LTBase"},
		{RouteKey: "ANY /{proxy+}", AuthorizerName: "LTBase"},
	}
}

func buildAuthAuthorizerSpecs(cfg config.StackConfig, providerCfg AuthProviderConfig) []authorizerSpec {
	specs := []authorizerSpec{ltbaseAuthorizerSpec(cfg)}
	for _, provider := range providerCfg.Providers {
		specs = append(specs, authorizerSpec{
			Name:      provider.Name,
			Issuer:    provider.Issuer,
			Audiences: provider.Audiences,
		})
	}
	return specs
}

func buildAuthRouteSpecs(providerCfg AuthProviderConfig) []routeSpec {
	routes := []routeSpec{
		{RouteKey: "GET /api/v1/auth/health"},
		{RouteKey: "POST /api/v1/auth/refresh", AuthorizerName: "LTBase"},
	}
	for _, provider := range providerCfg.Providers {
		if provider.EnableIDBinding {
			routes = append(routes, routeSpec{RouteKey: "POST /api/v1/id_bindings/" + provider.Name, AuthorizerName: provider.Name})
		}
		if provider.EnableLogin {
			routes = append(routes, routeSpec{RouteKey: "POST /api/v1/login/" + provider.Name, AuthorizerName: provider.Name})
		}
	}
	return routes
}

func newHTTPAPI(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, suffix, domain string, cert *acm.CertificateValidation, service *LambdaService, routes []routeSpec, authorizers []authorizerSpec) (*apigatewayv2.Api, error) {
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
	authorizerIDs := map[string]pulumi.StringOutput{}
	for _, spec := range authorizers {
		authorizer, err := apigatewayv2.NewAuthorizer(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-"+spec.Name+"-authorizer"), &apigatewayv2.AuthorizerArgs{
			ApiId:          api.ID(),
			AuthorizerType: pulumi.String("JWT"),
			IdentitySources: pulumi.StringArray{
				pulumi.String("$request.header.Authorization"),
			},
			JwtConfiguration: &apigatewayv2.AuthorizerJwtConfigurationArgs{
				Audiences: pulumi.ToStringArray(spec.Audiences),
				Issuer:    pulumi.StringPtr(spec.Issuer),
			},
			Name: pulumi.StringPtr(spec.Name),
		}, pulumi.Provider(providers.AWS))
		if err != nil {
			return nil, err
		}
		authorizerIDs[spec.Name] = authorizer.ID().ToStringOutput()
	}
	for i, spec := range routes {
		_ = i
		args := &apigatewayv2.RouteArgs{
			ApiId:    api.ID(),
			RouteKey: pulumi.String(spec.RouteKey),
			Target:   pulumi.Sprintf("integrations/%s", integration.ID()).ToStringPtrOutput(),
		}
		if spec.AuthorizerName != "" {
			args.AuthorizationType = pulumi.StringPtr("JWT")
			args.AuthorizerId = authorizerIDs[spec.AuthorizerName].ToStringPtrOutput()
		}
		_, err = apigatewayv2.NewRoute(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-route-"+routeResourceNameSuffix(spec.RouteKey)), args, pulumi.Provider(providers.AWS))
		if err != nil {
			return nil, err
		}
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

func routeResourceNameSuffix(routeKey string) string {
	normalized := strings.ToLower(strings.TrimSpace(routeKey))
	normalized = routeResourceNameCleaner.ReplaceAllString(normalized, "-")
	return strings.Trim(normalized, "-")
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
