package main

import (
	"github.com/OctopusDeploy/terraform-provider-stripe/stripe"
	"github.com/hashicorp/terraform/plugin"
)

func main() {
	plugin.Serve(&plugin.ServeOpts{
		ProviderFunc: stripe.Provider})
}
