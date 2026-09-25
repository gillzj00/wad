output "dynamodb_table" {
  description = "Name of the single DynamoDB table for this environment."
  value       = aws_dynamodb_table.main.name
}
