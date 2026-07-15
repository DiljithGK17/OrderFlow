# ==========================================
# DynamoDB Module
# ==========================================
# Creates the NoSQL tables for the order platform.
# All tables use PAY_PER_REQUEST to avoid hourly provisioning costs in the sandbox.

# Environment name (e.g., dev, staging)

# 1. Orders Table
# Stores all orders created by the system.
resource "aws_dynamodb_table" "orders" {
  name         = "orderflow-orders-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId" # Primary Key

  attribute {
    name = "orderId"
    type = "S"
  }
  attribute {
    name = "customerId"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }

  # Global Secondary Index (GSI) allows querying orders by customer and status
  global_secondary_index {
    name            = "customerId-status-index"
    hash_key        = "customerId"
    range_key       = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery { enabled = true } # For automated backups/recovery
}

# 2. Inventory Table
# Keeps track of stock levels for each SKU.
resource "aws_dynamodb_table" "inventory" {
  name         = "orderflow-inventory-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sku" # Primary Key
  attribute {
    name = "sku"
    type = "S"
  }
}

# 3. Idempotency Table
# Prevents duplicate processing of the same request.
# Uses DynamoDB TTL (Time-To-Live) to automatically delete old idempotency records.
resource "aws_dynamodb_table" "idempotency" {
  name         = "orderflow-idempotency-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "requestId" # Primary Key
  attribute {
    name = "requestId"
    type = "S"
  }
}
