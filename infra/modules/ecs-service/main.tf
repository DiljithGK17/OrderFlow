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
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # Container Definitions — FluentBit sidecar for multi-destination log routing
  container_definitions = jsonencode([
    # Main application container — logs via awsfirelens to FluentBit
    {
      name         = var.service_name
      image        = "${var.ecr_repository_url}:latest"
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      environment  = [for k, v in var.environment_variables : { name = k, value = v }]
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name              = "cloudwatch_logs"
          region            = "us-east-1"
          log_group_name    = "/ecs/${var.service_name}"
          log_stream_prefix = "ecs/"
          auto_create_group = "true"
        }
      }
    },
    # FluentBit sidecar — receives logs from awsfirelens and routes to CloudWatch
    {
      name      = "log-router"
      image     = "amazon/aws-for-fluent-bit:stable"
      essential = true
      firelensConfiguration = {
        type = "fluentbit"
        options = {
          enable-ecs-log-metadata = "true"
        }
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/fluent-bit"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
}

# 2. ECS Service
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = true
  }

  # Dynamic block: Only create the load_balancer block if a target_group_arn was passed in.
  # The inventory and notification services will skip this block entirely.
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.service_name
      container_port   = 8080
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
