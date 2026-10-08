# ---------------------------------------------------------------------------
# Live relay: a WebSocket API that fans a phone's messages out to the other
# phones in the same room (ADR-0014). Deployed before auth exists, behind the
# same shared client token as the courses API; the messages are opaque to the
# server. Replaced by the authoritative round sync of docs/api.md once auth
# (M1) and the rounds API are deployed.
# ---------------------------------------------------------------------------

locals {
  live_bundle = "${path.root}/../../../backend/dist/live/index.mjs"
}

resource "aws_apigatewayv2_api" "live" {
  name                       = "${local.name}-live"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

data "aws_iam_policy_document" "live" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.main.arn]
  }
  # Posting to the connections of this API's stages.
  statement {
    actions   = ["execute-api:ManageConnections"]
    resources = ["${aws_apigatewayv2_api.live.execution_arn}/*/*/@connections/*"]
  }
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.client_token.arn]
  }
  # The token is a SecureString under the account's default SSM key
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

module "live" {
  source = "../../modules/lambda"

  name        = "${local.name}-live"
  source_file = local.live_bundle
  policy_json = data.aws_iam_policy_document.live.json
  environment = {
    TABLE_NAME         = aws_dynamodb_table.main.name
    CLIENT_TOKEN_PARAM = aws_ssm_parameter.client_token.name
  }
}

# One integration for the three routes: the function switches on the route
# key and, on $default, on the frame's action.
resource "aws_apigatewayv2_integration" "live" {
  api_id             = aws_apigatewayv2_api.live.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = module.live.invoke_arn
}

resource "aws_apigatewayv2_route" "live_connect" {
  api_id    = aws_apigatewayv2_api.live.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.live.id}"
}

resource "aws_apigatewayv2_route" "live_disconnect" {
  api_id    = aws_apigatewayv2_api.live.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.live.id}"
}

resource "aws_apigatewayv2_route" "live_default" {
  api_id    = aws_apigatewayv2_api.live.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.live.id}"
}

# The body the function returns on $default (subscribed, published, pong,
# error) is sent back to the sender only when the route has a response.
resource "aws_apigatewayv2_route_response" "live_default" {
  api_id             = aws_apigatewayv2_api.live.id
  route_id           = aws_apigatewayv2_route.live_default.id
  route_response_key = "$default"
}

# Unlike an HTTP API, a WebSocket API writes its access logs through the
# account-level CloudWatch role of API Gateway (one per region).
data "aws_iam_policy_document" "apigateway_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigateway_logs" {
  name               = "${local.name}-apigateway-logs"
  assume_role_policy = data.aws_iam_policy_document.apigateway_logs_assume.json
}

resource "aws_iam_role_policy_attachment" "apigateway_logs" {
  role       = aws_iam_role.apigateway_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigateway_logs.arn

  depends_on = [aws_iam_role_policy_attachment.apigateway_logs]
}

resource "aws_cloudwatch_log_group" "live_access" {
  name              = "/aws/apigateway/${local.name}-live"
  retention_in_days = 14
}

# A WebSocket API cannot use the $default stage name.
resource "aws_apigatewayv2_stage" "live" {
  api_id      = aws_apigatewayv2_api.live.id
  name        = "live"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.live_access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      ip               = "$context.identity.sourceIp"
      routeKey         = "$context.routeKey"
      eventType        = "$context.eventType"
      connectionId     = "$context.connectionId"
      status           = "$context.status"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  # A round is four phones sending a frame every few seconds at most.
  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_lambda_permission" "live_ws" {
  statement_id  = "AllowWebSocketApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.live.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.live.execution_arn}/*/*"
}
