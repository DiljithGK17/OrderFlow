# ==========================================
# IAM Roles Module
# ==========================================
# Defines the permissions for the ECS Tasks to interact with other AWS services.
# Following the principle of least privilege.

                         # From sns-sqs module

# 1. ECS Task Execution Role
# This role is assumed by the ECS service itself to pull container images from ECR 
# and write logs to CloudWatch.
resource "aws_iam_role" "ecs_task_execution" {
  name = "orderflow-ecs-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"; Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 2. Order Service Task Role
# Grants permissions to access the Orders/Idempotency tables and publish to SNS.
resource "aws_iam_role" "order_service_task" {
  name = "orderflow-order-service-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role_policy" "order_service_permissions" {
  name = "order-service-least-privilege"
  role = aws_iam_role.order_service_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"], Resource = [var.orders_table_arn, var.idempotency_table_arn] },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = var.order_events_topic_arn },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
    ]
  })
}

# 3. Inventory Service Task Role
# Grants permissions to access the Inventory table and consume from the Inventory SQS queue.
resource "aws_iam_role" "inventory_service_task" {
  name = "orderflow-inventory-service-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role_policy" "inventory_service_permissions" {
  name = "inventory-service-least-privilege"
  role = aws_iam_role.inventory_service_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:UpdateItem"], Resource = var.inventory_table_arn },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = var.inventory_queue_arn },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
    ]
  })
}

# 4. Notification Service Task Role
# Grants permissions to consume from the Notification SQS queue.
resource "aws_iam_role" "notification_service_task" {
  name = "orderflow-notification-service-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role_policy" "notification_service_permissions" {
  name = "notification-service-least-privilege"
  role = aws_iam_role.notification_service_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = var.notification_queue_arn },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
    ]
  })
}
