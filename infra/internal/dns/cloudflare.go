package dns

import (
	"github.com/pulumi/pulumi-cloudflare/sdk/v6/go/cloudflare"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"lychee.technology/ltbase/infra/internal/naming"
)

type RecordArgs struct {
	Name     pulumi.StringPtrInput
	ZoneID   string
	ZoneName string
	Target   pulumi.StringPtrInput
}

func NewCNAME(ctx *pulumi.Context, logicalName string, args RecordArgs, opts ...pulumi.ResourceOption) (*cloudflare.DnsRecord, error) {
	recordName := args.Name.ToStringPtrOutput().ApplyT(func(value *string) string {
		if value == nil {
			return "@"
		}
		return naming.CloudflareRecordName(*value, args.ZoneName)
	}).(pulumi.StringOutput)
	return cloudflare.NewDnsRecord(ctx, logicalName, &cloudflare.DnsRecordArgs{
		ZoneId:  pulumi.String(args.ZoneID),
		Name:    recordName,
		Type:    pulumi.String("CNAME"),
		Content: args.Target,
		Ttl:     pulumi.Float64(1),
		Proxied: pulumi.Bool(false),
	}, opts...)
}
