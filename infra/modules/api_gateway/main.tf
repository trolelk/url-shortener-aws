resource "aws_apigatewayv2_api" "http_gateway" {
  name          = "url-shortener-api-gateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "http_gateway_integration" {
  api_id             = aws_apigatewayv2_api.http_gateway.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${var.alb_dns_name}/{proxy}"
  integration_method = "ANY"
}

resource "aws_apigatewayv2_route" "http_gateway_route" {
  api_id    = aws_apigatewayv2_api.http_gateway.id
  route_key = "ANY /{proxy+}"

  target = "integrations/${aws_apigatewayv2_integration.http_gateway_integration.id}"
}

resource "aws_apigatewayv2_stage" "http_gateway_stage" {
  api_id      = aws_apigatewayv2_api.http_gateway.id
  name        = "$default"
  auto_deploy = true
}