output "state_bucket" {
  description = "S3 bucket that stores Terraform remote state. Set in each environment's backend.tf."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.lock.name
}

output "ci_role_arn" {
  description = "IAM role ARN for GitHub Actions. Set as repo variable AWS_ROLE_ARN."
  value       = aws_iam_role.ci.arn
}

output "region" {
  description = "AWS region. Set as repo variable AWS_REGION."
  value       = var.aws_region
}
