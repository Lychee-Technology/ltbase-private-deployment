package services

import (
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws"
)

type Providers struct {
	AWS *aws.Provider
}

type Domains struct {
	API          string
	ControlPlane string
	Auth         string
}
