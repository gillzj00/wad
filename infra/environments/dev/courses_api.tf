# ---------------------------------------------------------------------------
# Courses API: GET /v1/courses and GET /v1/courses/{courseId} (ADR-0013).
# Deployed before auth exists so the app can look courses up. Two guards
# protect the provider's daily quota until the Cognito authorizer lands:
# stage throttling, and a shared client token the handler checks before any
# provider call. No other route is deployed.
# ---------------------------------------------------------------------------

locals {
  # The provider key is created out of band (docs/course-data.md); Terraform
  # only grants the function permission to read it.
  golfcourseapi_key_param = "/${var.project}/${var.env}/golfcourseapi/key"
  courses_bundle          = "${path.root}/../../../backend/dist/courses/index.mjs"
}

# Interim quota guard. The value never leaves SSM and the state: the app
# reads it with `aws ssm get-parameter --with-decryption` (infra/README.md).
resource "random_password" "client_token" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "client_token" {
  name  = "/${var.project}/${var.env}/client-token"
  type  = "SecureString"
  value = random_password.client_token.result
}

data "aws_iam_policy_document" "courses" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.main.arn, "${aws_dynamodb_table.main.arn}/index/*"]
  }
  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${local.golfcourseapi_key_param}",
      aws_ssm_parameter.client_token.arn,
    ]
  }
  # Both parameters are SecureStrings under the account's default SSM key
  # (alias/aws/ssm); decryption is only allowed through SSM.
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

module "courses" {
  source = "../../modules/lambda"

  name        = "${local.name}-courses"
  source_file = local.courses_bundle
  policy_json = data.aws_iam_policy_document.courses.json
  environment = {
    TABLE_NAME              = aws_dynamodb_table.main.name
    GOLFCOURSEAPI_KEY_PARAM = local.golfcourseapi_key_param
    CLIENT_TOKEN_PARAM      = aws_ssm_parameter.client_token.name
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-http"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "http_access" {
  name              = "/aws/apigateway/${local.name}-http"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.http_access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      ip               = "$context.identity.sourceIp"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  # Low limits on purpose: the course provider's free tier allows about 35
  # requests a day, and the app debounces search.
  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 2
  }
}

resource "aws_apigatewayv2_integration" "courses" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = module.courses.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "courses_search" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /v1/courses"
  target    = "integrations/${aws_apigatewayv2_integration.courses.id}"
}

resource "aws_apigatewayv2_route" "courses_get" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /v1/courses/{courseId}"
  target    = "integrations/${aws_apigatewayv2_integration.courses.id}"
}

resource "aws_lambda_permission" "courses_http" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.courses.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
