package config

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	pcfg "github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const githubThumbprint = "6938fd4d98bab03faadb97b34396831e3780aea1"
const defaultReleaseAssetDir = "../../.ltbase/releases"

type StackConfig struct {
	Project                  string
	Stack                    string
	AWSRegion                string
	DeploymentAWSAccountID   string
	ReleaseAssetDir          string
	RuntimeBucket            string
	SchemaBucket             string
	TableName                string
	MTLSTruststoreFile       string
	MTLSTruststoreKey        string
	APIDomain                string
	ControlPlaneDomain       string
	AuthDomain               string
	ProjectID                string
	DeploymentProjectName    string
	AuthProviderConfigFile   string
	CloudflareZoneID         string
	CloudflareZoneName       string
	OIDCIssuerURL            string
	JWKSURL                  string
	ReleaseID                string
	FormaCdcSchedule         string
	DSQLPort                 string
	DSQLEndpoint             string
	DSQLDB                   string
	DSQLUser                 string
	DSQLProjectSchema        string
	GeminiAPIKey             pulumi.StringOutput
	GeminiModel              string
	GitHubOrg                string
	GitHubRepo               string
	ManageGitHubOIDCProvider bool
	GitHubOIDCProviderArn    string
	GitHubThumbprints        []string
	AuthStage                string
}

func Load(ctx *pulumi.Context) (StackConfig, error) {
	cfg := pcfg.New(ctx, "")
	stack := ctx.Stack()
	githubRepo := cfg.Require("githubRepo")
	out := StackConfig{
		Project:                  ctx.Project(),
		Stack:                    stack,
		AWSRegion:                valueOrDefault(cfg.Get("awsRegion"), "ap-northeast-1"),
		DeploymentAWSAccountID:   cfg.Require("deploymentAwsAccountId"),
		ReleaseAssetDir:          valueOrDefault(cfg.Get("releaseAssetDir"), defaultReleaseAssetDir),
		RuntimeBucket:            cfg.Require("runtimeBucket"),
		SchemaBucket:             valueOrDefault(cfg.Get("schemaBucket"), defaultSchemaBucket(githubRepo, stack)),
		TableName:                cfg.Require("tableName"),
		MTLSTruststoreFile:       cfg.Require("mtlsTruststoreFile"),
		MTLSTruststoreKey:        cfg.Require("mtlsTruststoreKey"),
		APIDomain:                cfg.Require("apiDomain"),
		ControlPlaneDomain:       cfg.Require("controlPlaneDomain"),
		AuthDomain:               cfg.Require("authDomain"),
		ProjectID:                cfg.Require("projectId"),
		DeploymentProjectName:    valueOrDefault(cfg.Get("deploymentProjectName"), humanizeProjectName(ctx.Project())),
		AuthProviderConfigFile:   cfg.Require("authProviderConfigFile"),
		CloudflareZoneID:         cfg.Require("cloudflareZoneId"),
		CloudflareZoneName:       strings.TrimSpace(cfg.Get("cloudflareZoneName")),
		OIDCIssuerURL:            cfg.Require("oidcIssuerUrl"),
		JWKSURL:                  cfg.Require("jwksUrl"),
		ReleaseID:                cfg.Require("releaseId"),
		FormaCdcSchedule:         valueOrDefault(cfg.Get("formaCdcSchedule"), "rate(15 minutes)"),
		DSQLPort:                 valueOrDefault(cfg.Get("dsqlPort"), "5432"),
		DSQLEndpoint:             strings.TrimSpace(cfg.Get("dsqlEndpoint")),
		DSQLDB:                   valueOrDefault(cfg.Get("dsqlDB"), "postgres"),
		DSQLUser:                 valueOrDefault(cfg.Get("dsqlUser"), "admin"),
		DSQLProjectSchema:        valueOrDefault(cfg.Get("dsqlProjectSchema"), "ltbase"),
		GeminiAPIKey:             cfg.RequireSecret("geminiApiKey"),
		GeminiModel:              valueOrDefault(cfg.Get("geminiModel"), "gemini-3.1-flash-lite"),
		GitHubOrg:                cfg.Require("githubOrg"),
		GitHubRepo:               githubRepo,
		ManageGitHubOIDCProvider: cfg.GetBool("manageGithubOidcProvider"),
		GitHubOIDCProviderArn:    strings.TrimSpace(cfg.Get("githubOidcProviderArn")),
		GitHubThumbprints:        []string{githubThumbprint},
		AuthStage:                valueOrDefault(cfg.Get("authStage"), stack),
	}
	if raw := strings.TrimSpace(cfg.Get("githubOidcThumbprints")); raw != "" {
		out.GitHubThumbprints = splitCSV(raw)
	}
	if err := out.Validate(); err != nil {
		return StackConfig{}, err
	}
	return out, nil
}

func (c StackConfig) Validate() error {
	if !c.ManageGitHubOIDCProvider && c.GitHubOIDCProviderArn == "" {
		return fmt.Errorf("githubOidcProviderArn is required when manageGithubOidcProvider is false")
	}
	if c.RuntimeBucket != "" && c.SchemaBucket != "" && c.RuntimeBucket == c.SchemaBucket {
		return fmt.Errorf("schemaBucket must differ from runtimeBucket")
	}
	return nil
}

func defaultSchemaBucket(repoName, stack string) string {
	return strings.ToLower(strings.TrimSpace(repoName)) + "-schema-" + strings.ToLower(strings.TrimSpace(stack))
}

func valueOrDefault(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return strings.TrimSpace(value)
}

func splitCSV(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func humanizeProjectName(project string) string {
	trimmed := strings.TrimSpace(project)
	if trimmed == "" {
		return "LTBase Private Deployment"
	}
	replacer := strings.NewReplacer("-", " ", "_", " ")
	parts := strings.Fields(replacer.Replace(trimmed))
	for i, part := range parts {
		lower := strings.ToLower(part)
		switch lower {
		case "ltbase":
			parts[i] = "LTBase"
		default:
			parts[i] = strings.ToUpper(lower[:1]) + lower[1:]
		}
	}
	if len(parts) == 0 {
		return "LTBase Private Deployment"
	}
	return strings.Join(parts, " ")
}
