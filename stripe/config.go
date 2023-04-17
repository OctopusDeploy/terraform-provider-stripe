package stripe

import (
	"log"

	stripe "github.com/stripe/stripe-go/v73"
	"github.com/stripe/stripe-go/v73/client"
)

// Config stores Stripe's API configuration
type Config struct {
	APIToken string
}

// Client returns a new Client for accessing Stripe.
func (c *Config) Client() (*client.API, error) {
	stripe.SetAppInfo(&stripe.AppInfo{
		Name: "terraform-provider-stripe",
	})

	client := &client.API{}
	client.Init(c.APIToken, nil)
	log.Printf("[INFO] Stripe Client configured.")

	return client, nil
}
