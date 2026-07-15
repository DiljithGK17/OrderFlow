# ==========================================
# Variables
# ==========================================

variable "orders_table_arn" {}

# From dynamodb module
variable "idempotency_table_arn" {}

# From dynamodb module
variable "inventory_table_arn" {}

# From dynamodb module
variable "order_events_topic_arn" {}

# From sns-sqs module
variable "inventory_queue_arn" {}

# From sns-sqs module
variable "notification_queue_arn" {}
