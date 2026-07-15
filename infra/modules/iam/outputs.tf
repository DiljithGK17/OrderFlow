# ==========================================
# Outputs
# ==========================================

output "ecs_task_execution_role_arn" { value = aws_iam_role.ecs_task_execution.arn }

output "order_service_task_role_arn" { value = aws_iam_role.order_service_task.arn }

output "inventory_service_task_role_arn" { value = aws_iam_role.inventory_service_task.arn }

output "notification_service_task_role_arn" { value = aws_iam_role.notification_service_task.arn }
