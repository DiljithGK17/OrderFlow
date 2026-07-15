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

# 6. Web Application Firewall (WAF)
# Protects the API Gateway against common web exploits and implements strict rate limiting.
resource "aws_wafv2_web_acl" "api" {
  name  = "orderflow-api-waf"
  scope = "REGIONAL"
  default_action { allow {} } # Allow requests by default

  # Rate limiting rule: blocks IPs sending more than 2000 requests per 5 minutes
  rule {
    name     = "rate-limit"
    priority = 1
    action { block {} }
    statement {
      rate_based_statement { limit = 2000; aggregate_key_type = "IP" }
    }
    visibility_config { sampled_requests_enabled = true; cloudwatch_metrics_enabled = true; metric_name = "rate-limit" }
  }

  visibility_config { sampled_requests_enabled = true; cloudwatch_metrics_enabled = true; metric_name = "orderflow-api-waf" }
}

# 7. WAF Association
# Attaches the WAF Web ACL to the API Gateway Stage.
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_apigatewayv2_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
