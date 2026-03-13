package config

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	pcfg "github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const githubThumbprint = "6938fd4d98bab03faadb97b34396831e3780aea1"

type StackConfig struct {
	Project                  string
	Stack                    string
	AWSRegion                string
	ReleaseAssetDir          string
	RuntimeBucket            string
	TableName                string
	APIDomain                string
	ControlPlaneDomain       string
	AuthDomain               string
	CloudflareZoneID         string
	CloudflareZoneName       string
	OIDCIssuerURL            string
	JWKSURL                  string
	ReleaseID                string
	FormaCdcSchedule         string
	DSQLEndpoint             string
	DSQLHost                 string
	DSQLPort                 string
	DSQLDB                   string
	DSQLUser                 string
	DSQLPassword             pulumi.StringOutput
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
	out := StackConfig{
		Project:                  ctx.Project(),
		Stack:                    stack,
		AWSRegion:                valueOrDefault(cfg.Get("awsRegion"), "ap-northeast-1"),
		ReleaseAssetDir:          valueOrDefault(cfg.Get("releaseAssetDir"), "../.ltbase/releases"),
		RuntimeBucket:            cfg.Require("runtimeBucket"),
		TableName:                cfg.Require("tableName"),
		APIDomain:                cfg.Require("apiDomain"),
		ControlPlaneDomain:       cfg.Require("controlPlaneDomain"),
		AuthDomain:               cfg.Require("authDomain"),
		CloudflareZoneID:         cfg.Require("cloudflareZoneId"),
		CloudflareZoneName:       strings.TrimSpace(cfg.Get("cloudflareZoneName")),
		OIDCIssuerURL:            cfg.Require("oidcIssuerUrl"),
		JWKSURL:                  cfg.Require("jwksUrl"),
		ReleaseID:                cfg.Require("releaseId"),
		FormaCdcSchedule:         valueOrDefault(cfg.Get("formaCdcSchedule"), "rate(15 minutes)"),
		DSQLEndpoint:             strings.TrimSpace(cfg.Get("dsqlEndpoint")),
		DSQLHost:                 strings.TrimSpace(cfg.Get("dsqlHost")),
		DSQLPort:                 valueOrDefault(cfg.Get("dsqlPort"), "5432"),
		DSQLDB:                   valueOrDefault(cfg.Get("dsqlDB"), "ltbase"),
		DSQLUser:                 cfg.Require("dsqlUser"),
		DSQLPassword:             cfg.RequireSecret("dsqlPassword"),
		DSQLProjectSchema:        valueOrDefault(cfg.Get("dsqlProjectSchema"), "ltbase"),
		GeminiAPIKey:             cfg.RequireSecret("geminiApiKey"),
		GeminiModel:              valueOrDefault(cfg.Get("geminiModel"), "gemini-3-flash-preview"),
		GitHubOrg:                cfg.Require("githubOrg"),
		GitHubRepo:               cfg.Require("githubRepo"),
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
	if c.DSQLEndpoint == "" && c.DSQLHost == "" {
		return fmt.Errorf("either dsqlEndpoint or dsqlHost must be configured")
	}
	if !c.ManageGitHubOIDCProvider && c.GitHubOIDCProviderArn == "" {
		return fmt.Errorf("githubOidcProviderArn is required when manageGithubOidcProvider is false")
	}
	return nil
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
