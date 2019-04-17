provider "aws" {
  version = "~> 2.6"

  region = "us-east-1"
}

module "shopify-lambda" {
  source       = "modules/shopify-lambda"
  domain       = "bluemage.ca"
  subdomain    = "shopify-app"
  shop         = "bluemage-test-shop"
  secrets_path = "prod/shop/credentials"
}
