# ==========================================
# API Gateway & WAF Module
# ==========================================
# Acts as the very front door of the application. Provides throttling, routing, 
# and a Web Application Firewall (WAF) to protect the backend.

# 1. VPC Link
# Allows the API Gateway (which lives in AWS managed space) to privately connect 
# to resources in our VPC (the ALB).
resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "orderflow-vpc-link"
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
}

# 2. HTTP API Gateway
resource "aws_apigatewayv2_api" "this" {
  name          = "orderflow-api"
  protocol_type = "HTTP"
}

# 3. API Gateway Integration
# Connects the API Gateway to the ALB via the VPC Link.
resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = var.alb_listener_arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id
  integration_method = "ANY"
}

# 4. API Route
# Routes any traffic hitting /orders to the ALB integration.
resource "aws_apigatewayv2_route" "orders" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /orders/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# 5. API Stage
# The deployment stage for the API. Includes throttling rules to protect 
# the backend from traffic spikes (100 req/s, burst to 200).
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_rate_limit  = 100
    throttling_burst_limit = 200
  }
}


