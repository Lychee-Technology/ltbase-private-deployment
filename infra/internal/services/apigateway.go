package services

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/acm"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/apigatewayv2"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/cloudwatch"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/lambda"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/s3"
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

func APIBaseURL(cfg config.StackConfig) string {
	return "https://" + strings.TrimSpace(cfg.APIDomain)
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

func NewAPIs(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, runtime *RuntimeResources, lambdas *ServiceSet) (*APISet, error) {
	providerCfg, err := loadAuthProviderConfig(ctx.RootDirectory(), cfg.AuthProviderConfigFile)
	if err != nil {
		return nil, err
	}
	truststore, err := newMTLSTruststore(ctx, cfg, providers, runtime)
	if err != nil {
		return nil, err
	}
	domains := buildHTTPAPIDomainConfigs(cfg, truststore)
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
	api, err := newHTTPAPI(ctx, cfg, providers, domains["api"].Suffix, domains["api"].Domain, apiCert, domains["api"].Truststore, lambdas.DataPlane, buildAPIRouteSpecs(), []authorizerSpec{ltbaseAuthorizerSpec(cfg)})
	if err != nil {
		return nil, err
	}
	controlPlane, err := newHTTPAPI(ctx, cfg, providers, domains["control"].Suffix, domains["control"].Domain, controlCert, domains["control"].Truststore, lambdas.ControlPlane, buildControlPlaneRouteSpecs(), []authorizerSpec{ltbaseAuthorizerSpec(cfg)})
	if err != nil {
		return nil, err
	}
	auth, err := newHTTPAPI(ctx, cfg, providers, domains["auth"].Suffix, domains["auth"].Domain, authCert, domains["auth"].Truststore, lambdas.AuthService, buildAuthRouteSpecs(providerCfg), buildAuthAuthorizerSpecs(cfg, providerCfg))
	if err != nil {
		return nil, err
	}
	return &APISet{API: api, ControlPlane: controlPlane, Auth: auth, Certificate: apiCert}, nil
}

type mtlsTruststore struct {
	URI     string
	Version pulumi.StringOutput
}

type httpAPIConfig struct {
	DisableExecuteAPIEndpoint bool
}

type httpAPIDomainConfig struct {
	Suffix     string
	Domain     string
	Truststore mtlsTruststore
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

func legacyRouteAliasName(cfg config.StackConfig, suffix string, spec routeSpec) string {
	if suffix != "control" {
		return ""
	}

	switch spec.RouteKey {
	case "ANY /":
		return naming.ResourceName(cfg.Project, cfg.Stack, "control-root")
	case "ANY /{proxy+}":
		return naming.ResourceName(cfg.Project, cfg.Stack, "control-route")
	default:
		return ""
	}
}

func routeAliases(cfg config.StackConfig, suffix string, spec routeSpec) []pulumi.Alias {
	legacyName := legacyRouteAliasName(cfg, suffix, spec)
	if legacyName == "" {
		return nil
	}

	return []pulumi.Alias{{Name: pulumi.String(legacyName)}}
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

func newHTTPAPI(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, suffix, domain string, cert *acm.CertificateValidation, truststore mtlsTruststore, service *LambdaService, routes []routeSpec, authorizers []authorizerSpec) (*apigatewayv2.Api, error) {
	settings := httpAPISettings()
	api, err := apigatewayv2.NewApi(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-api"), &apigatewayv2.ApiArgs{
		Name:                      pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-api")),
		ProtocolType:              pulumi.String("HTTP"),
		DisableExecuteApiEndpoint: pulumi.BoolPtr(settings.DisableExecuteAPIEndpoint),
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
		options := []pulumi.ResourceOption{pulumi.Provider(providers.AWS)}
		if aliases := routeAliases(cfg, suffix, spec); len(aliases) > 0 {
			options = append(options, pulumi.Aliases(aliases))
		}
		_, err = apigatewayv2.NewRoute(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-route-"+routeResourceNameSuffix(spec.RouteKey)), args, options...)
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
		MutualTlsAuthentication: &apigatewayv2.DomainNameMutualTlsAuthenticationArgs{
			TruststoreUri:     pulumi.String(truststore.URI),
			TruststoreVersion: truststore.Version.ToStringPtrOutput(),
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
	apiDNSRecord := apiDomainRecordArgs(cfg, domain, targetDomain)
	if _, err = dns.NewCNAME(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-dns"), apiDNSRecord); err != nil {
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
	record, err := dns.NewCNAME(ctx, naming.ResourceName(cfg.Project, cfg.Stack, suffix+"-cert-validation"), certificateValidationRecordArgs(cfg, option.ResourceRecordName(), option.ResourceRecordValue()))
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

func httpAPISettings() httpAPIConfig {
	return httpAPIConfig{DisableExecuteAPIEndpoint: true}
}

func buildHTTPAPIDomainConfigs(cfg config.StackConfig, truststore mtlsTruststore) map[string]httpAPIDomainConfig {
	return map[string]httpAPIDomainConfig{
		"api": {
			Suffix:     "api",
			Domain:     cfg.APIDomain,
			Truststore: truststore,
		},
		"control": {
			Suffix:     "control",
			Domain:     cfg.ControlPlaneDomain,
			Truststore: truststore,
		},
		"auth": {
			Suffix:     "auth",
			Domain:     cfg.AuthDomain,
			Truststore: truststore,
		},
	}
}

func apiDomainRecordArgs(cfg config.StackConfig, domain string, target pulumi.StringPtrInput) dns.RecordArgs {
	return dns.RecordArgs{
		Name:     pulumi.StringPtr(domain),
		ZoneID:   cfg.CloudflareZoneID,
		ZoneName: cfg.CloudflareZoneName,
		Target:   target,
		Proxied:  true,
	}
}

func certificateValidationRecordArgs(cfg config.StackConfig, name pulumi.StringPtrInput, target pulumi.StringPtrInput) dns.RecordArgs {
	return dns.RecordArgs{
		Name:     name,
		ZoneID:   cfg.CloudflareZoneID,
		ZoneName: cfg.CloudflareZoneName,
		Target:   target,
		Proxied:  false,
	}
}

func newMTLSTruststore(ctx *pulumi.Context, cfg config.StackConfig, providers Providers, runtime *RuntimeResources) (mtlsTruststore, error) {
	path, err := resolveMTLSTruststorePath(ctx.RootDirectory(), cfg.MTLSTruststoreFile)
	if err != nil {
		return mtlsTruststore{}, err
	}
	object, err := s3.NewBucketObjectv2(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "mtls-truststore"), &s3.BucketObjectv2Args{
		Bucket:               runtime.RuntimeBucket.ID(),
		Key:                  pulumi.String(cfg.MTLSTruststoreKey),
		Source:               pulumi.NewFileAsset(path),
		ServerSideEncryption: pulumi.String("AES256"),
	}, pulumi.Provider(providers.AWS), pulumi.DependsOn([]pulumi.Resource{runtime.RuntimeBucketVersioning}))
	if err != nil {
		return mtlsTruststore{}, err
	}
	return mtlsTruststore{
		URI:     mtlsTruststoreURI(cfg.RuntimeBucket, cfg.MTLSTruststoreKey),
		Version: object.VersionId,
	}, nil
}

func resolveMTLSTruststorePath(rootDir, path string) (string, error) {
	resolved, err := filepath.Abs(resolveTruststorePath(rootDir, path))
	if err != nil {
		return "", fmt.Errorf("resolve mTLS truststore path: %w", err)
	}
	if _, err := os.Stat(resolved); err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("read mTLS truststore: %w", err)
		}
		return "", fmt.Errorf("stat mTLS truststore: %w", err)
	}
	return resolved, nil
}

func resolveTruststorePath(rootDir, path string) string {
	cleaned := filepath.Clean(path)
	if filepath.IsAbs(cleaned) || rootDir == "" {
		return cleaned
	}
	if strings.HasPrefix(cleaned, "infra/") {
		return filepath.Join(rootDir, strings.TrimPrefix(cleaned, "infra/"))
	}
	return filepath.Join(rootDir, cleaned)
}

func mtlsTruststoreURI(bucket, key string) string {
	return "s3://" + bucket + "/" + key
}
