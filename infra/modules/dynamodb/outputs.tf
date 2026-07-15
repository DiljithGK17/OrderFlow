# ==========================================
# Outputs
# ==========================================

# Outputs for other modules (like IAM) to link policies
output "orders_table_arn" { value = aws_dynamodb_table.orders.arn }

output "idempotency_table_arn" { value = aws_dynamodb_table.idempotency.arn }

output "inventory_table_arn" { value = aws_dynamodb_table.inventory.arn }
