package services

import (
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/dsql"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/config"
	"lychee.technology/ltbase/infra/internal/naming"
)

func NewDSQLResources(ctx *pulumi.Context, cfg config.StackConfig, providers Providers) (*DSQLResources, error) {
	cluster, err := dsql.NewCluster(ctx, naming.ResourceName(cfg.Project, cfg.Stack, "dsql"), &dsql.ClusterArgs{
		DeletionProtectionEnabled: pulumi.BoolPtr(cfg.Stack == "prod"),
		Tags: pulumi.StringMap{
			"Name":    pulumi.String(naming.ResourceName(cfg.Project, cfg.Stack, "dsql")),
			"Project": pulumi.String(cfg.Project),
			"Stack":   pulumi.String(cfg.Stack),
		},
	}, pulumi.Provider(providers.AWS))
	if err != nil {
		return nil, err
	}
	return &DSQLResources{
		Cluster: cluster,
	}, nil
}
