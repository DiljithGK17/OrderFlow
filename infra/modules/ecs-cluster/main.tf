# ==========================================
# ECS Cluster Module
# ==========================================
# This module provisions the ECS Cluster which acts as a logical grouping for our tasks.
# It also provisions the Elastic Container Registry (ECR) repositories for our images.

# 1. ECS Cluster
# The cluster where all our microservices will run. 
# ContainerInsights is enabled for deep visibility into performance metrics in CloudWatch.
resource "aws_ecs_cluster" "this" {
  name = "orderflow-${var.env}"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# 2. Capacity Providers
# We associate the FARGATE and FARGATE_SPOT capacity providers to the cluster.
# Fargate abstracts away the underlying EC2 instances, making this a serverless compute layer.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# 3. ECR Repositories
# Repositories for our 3 microservices.
resource "aws_ecr_repository" "order_service" {
  name = "orderflow/order-service"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "inventory_service" {
  name = "orderflow/inventory-service"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "notification_service" {
  name = "orderflow/notification-service"
  image_scanning_configuration {
    scan_on_push = true
  }
}
