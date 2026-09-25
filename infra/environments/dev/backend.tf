terraform {
  backend "s3" {
    key     = "dev/terraform.tfstate"
    encrypt = true
    # bucket, region, and dynamodb_table are supplied at init time via
    # -backend-config (the bucket name includes the AWS account id created
    # during bootstrap). See infra/README.md and .github/workflows/terraform.yml.
    #
    # Local init example:
    #   terraform -chdir=infra/environments/dev init \
    #     -backend-config="bucket=wad-tfstate-<account_id>" \
    #     -backend-config="region=us-east-1" \
    #     -backend-config="dynamodb_table=wad-tflock"
  }
}
