# ==========================================
# Outputs
# ==========================================

output "cluster_id" { value = aws_ecs_cluster.this.id }

output "cluster_name" { value = aws_ecs_cluster.this.name }

output "order_service_repo_url" { value = aws_ecr_repository.order_service.repository_url }

output "inventory_service_repo_url" { value = aws_ecr_repository.inventory_service.repository_url }

output "notification_service_repo_url" { value = aws_ecr_repository.notification_service.repository_url }
