output "dynamodb_table" {
  description = "Name of the single DynamoDB table for this environment."
  value       = aws_dynamodb_table.main.name
}

output "api_base_url" {
  description = "Base URL of the HTTP API (routes are under /v1). The client token is not an output; see infra/README.md."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "client_token_parameter" {
  description = "SSM parameter name holding the x-wad-client token (the value is never output)."
  value       = aws_ssm_parameter.client_token.name
}
