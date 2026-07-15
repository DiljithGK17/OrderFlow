# ==========================================
# ECS Service & Task Definition Module
# ==========================================
# This is a REUSABLE module designed to be instantiated 3 times (for order-service, 
# inventory-service, and notification-service).

# 1. ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # Container Definitions
  container_definitions = jsonencode([
    {
      name = var.service_name
      image = "${var.ecr_repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      environment = [{ name = "AWS_XRAY_DAEMON_ADDRESS", value = "127.0.0.1:2000" }]
      logConfiguration = { logDriver = "awsfirelens" }
    },
    {
      name = "nginx"
      image = "nginx:1.27-alpine"
      essential = true
      portMappings = [{ containerPort = 80, protocol = "tcp" }]
    },
    {
      name = "log-router"
      image = "amazon/aws-for-fluent-bit:stable"
      essential = true
      firelensConfiguration = { type = "fluentbit" }
    },
    {
      name = "xray-daemon"
      image = "amazon/aws-xray-daemon:latest"
      essential = false
      portMappings = [{ containerPort = 2000, protocol = "udp" }]
    }
  ])
}

# 2. ECS Service
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 2 
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = "ENABLED"
  }

  # Dynamic block: Only create the load_balancer block if a target_group_arn was passed in.
  # The inventory and notification services will skip this block entirely.
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name    = "nginx"
      container_port    = 80
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker { enable = true; rollback = true }
}
