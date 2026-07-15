# ==========================================
# SNS & SQS Messaging Module
# ==========================================
# Implements the Event-Driven architecture (Pub/Sub pattern).
# The order-service publishes events to SNS, and multiple SQS queues subscribe to fan-out the workload.

# An SNS topic ARN for operations alerts

# 1. Order Events SNS Topic
# The central hub where the order-service publishes 'OrderCreated' events.
resource "aws_sns_topic" "order_events" {
  name = "orderflow-order-events-${var.env}"
}

# 2. Inventory Queue & DLQ
resource "aws_sqs_queue" "inventory_dlq" {
  name = "orderflow-inventory-dlq-${var.env}"
}

resource "aws_sqs_queue" "inventory_queue" {
  name                       = "orderflow-inventory-queue-${var.env}"
  visibility_timeout_seconds = 30
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.inventory_dlq.arn, maxReceiveCount = 5 })
}

resource "aws_sqs_queue_policy" "inventory_queue_policy" {
  queue_url = aws_sqs_queue.inventory_queue.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "sns.amazonaws.com" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.inventory_queue.arn, Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_events.arn } } }]
  })
}

resource "aws_sns_topic_subscription" "inventory" {
  topic_arn            = aws_sns_topic.order_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.inventory_queue.arn
  raw_message_delivery = true
  filter_policy        = jsonencode({ eventType = ["OrderCreated", "OrderCancelled"] })
}

# 3. Notification Queue & DLQ (for notification-service)
resource "aws_sqs_queue" "notification_dlq" {
  name = "orderflow-notification-dlq-${var.env}"
}

resource "aws_sqs_queue" "notification_queue" {
  name                       = "orderflow-notification-queue-${var.env}"
  visibility_timeout_seconds = 30
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn, maxReceiveCount = 5 })
}

resource "aws_sqs_queue_policy" "notification_queue_policy" {
  queue_url = aws_sqs_queue.notification_queue.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "sns.amazonaws.com" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.notification_queue.arn, Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_events.arn } } }]
  })
}

resource "aws_sns_topic_subscription" "notification" {
  topic_arn            = aws_sns_topic.order_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.notification_queue.arn
  raw_message_delivery = true
  # Listen for same events
  filter_policy = jsonencode({ eventType = ["OrderCreated", "OrderCancelled"] })
}

# 4. CloudWatch Alarm for DLQ
resource "aws_cloudwatch_metric_alarm" "inventory_dlq_not_empty" {
  alarm_name          = "orderflow-inventory-dlq-has-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  dimensions          = { QueueName = aws_sqs_queue.inventory_dlq.name }
  alarm_actions       = [var.ops_alerts_topic_arn]
}
