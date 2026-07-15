# ==========================================
# Application Load Balancer (ALB) Module
# ==========================================
# Distributes incoming traffic across the multiple ECS Tasks.

# 1. Application Load Balancer
# Placed in the public subnets so it is accessible over the internet.
resource "aws_lb" "this" {
  name               = "orderflow-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = var.security_group_ids
}

# 2. Target Group
# A logical group of targets (our ECS tasks). The ALB routes requests to this group.
# Includes health check configurations to ensure traffic is only sent to healthy containers.
resource "aws_lb_target_group" "order_service" {
  name        = "order-service-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate (awsvpc network mode)
  health_check {
    path                = "/healthz"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# 3. ALB Listener
# Listens for HTTP traffic on port 80.
# The default action is to return a 404 Not Found if the path doesn't match a rule.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# 4. Listener Rule
# Inspects the path of the incoming request. If it matches "/orders/*", 
# it forwards the request to the target group defined above.
resource "aws_lb_listener_rule" "order_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/orders", "/orders/*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.order_service.arn
  }
}
