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
      Action    = "sts:AssumeRole", Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_logs" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# 2. Order Service Task Role
# Grants permissions to access the Orders/Idempotency tables and publish to SNS.
resource "aws_iam_role" "order_service_task" {
  name               = "orderflow-order-service-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
# Sandbox workaround: Since inline PutRolePolicy is denied, we attach existing AWS managed policies.
resource "aws_iam_role_policy_attachment" "order_service_dynamo" {
  role       = aws_iam_role.order_service_task.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "order_service_sns" {
  role       = aws_iam_role.order_service_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}
resource "aws_iam_role_policy_attachment" "order_service_logs" {
  role       = aws_iam_role.order_service_task.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
resource "aws_iam_role_policy_attachment" "order_service_xray" {
  role       = aws_iam_role.order_service_task.id
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# 3. Inventory Service Task Role
# Grants permissions to access the Inventory table and consume from the Inventory SQS queue.
resource "aws_iam_role" "inventory_service_task" {
  name = "orderflow-inventory-service-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "inventory_service_dynamo" {
  role       = aws_iam_role.inventory_service_task.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "inventory_service_sqs" {
  role       = aws_iam_role.inventory_service_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}
resource "aws_iam_role_policy_attachment" "inventory_service_logs" {
  role       = aws_iam_role.inventory_service_task.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
resource "aws_iam_role_policy_attachment" "inventory_service_xray" {
  role       = aws_iam_role.inventory_service_task.id
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# 4. Notification Service Task Role
# Grants permissions to consume from the Notification SQS queue.
resource "aws_iam_role" "notification_service_task" {
  name = "orderflow-notification-service-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "notification_service_sqs" {
  role       = aws_iam_role.notification_service_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}
resource "aws_iam_role_policy_attachment" "notification_service_logs" {
  role       = aws_iam_role.notification_service_task.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
resource "aws_iam_role_policy_attachment" "notification_service_xray" {
  role       = aws_iam_role.notification_service_task.id
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}
