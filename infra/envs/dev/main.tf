# ==========================================
# Root Environment (dev) - Main Module
# ==========================================
# This file ties together all the modularized Terraform code.

module "default_vpc" {
  source = "../../modules/default-vpc-lookup"
}

module "security" {
  source = "../../modules/security"
  vpc_id = module.default_vpc.vpc_id
}

module "dynamodb" {
  source = "../../modules/dynamodb"
  env = var.env
}

module "sns_sqs" {
  source = "../../modules/sns-sqs"
  env = var.env
  ops_alerts_topic_arn = "arn:aws:sns:us-east-1:123456789012:orderflow-ops-alerts" 
}

module "iam" {
  source = "../../modules/iam"
  orders_table_arn       = module.dynamodb.orders_table_arn
  idempotency_table_arn  = module.dynamodb.idempotency_table_arn
  inventory_table_arn    = module.dynamodb.inventory_table_arn
  order_events_topic_arn = module.sns_sqs.order_events_topic_arn
  inventory_queue_arn    = module.sns_sqs.inventory_queue_arn
  notification_queue_arn = module.sns_sqs.notification_queue_arn
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"
  env = var.env
}

module "alb" {
  source = "../../modules/alb"
  subnet_ids         = module.default_vpc.subnet_ids
  security_group_ids = [module.security.alb_sg_id]
  vpc_id             = module.default_vpc.vpc_id
}

module "api_gateway" {
  source = "../../modules/api-gateway"
  subnet_ids         = module.default_vpc.subnet_ids
  security_group_ids = [module.security.ecs_sg_id]
  alb_listener_arn   = module.alb.alb_arn
}

# ==========================================
# The 3 Microservices (reusing the ecs-service module)
# ==========================================

# 1. Order Service (Fronted by ALB)
module "order_service" {
  source             = "../../modules/ecs-service"
  env                = var.env
  cluster_id         = module.ecs_cluster.cluster_id
  subnet_ids         = module.default_vpc.subnet_ids
  security_group_ids = [module.security.ecs_sg_id]
  execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn      = module.iam.order_service_task_role_arn
  
  service_name       = "order-service"
  ecr_repository_url = module.ecs_cluster.order_service_repo_url
  target_group_arn   = module.alb.order_service_tg_arn # Requires ALB
}

# 2. Inventory Service (Backend SQS Consumer)
module "inventory_service" {
  source             = "../../modules/ecs-service"
  env                = var.env
  cluster_id         = module.ecs_cluster.cluster_id
  subnet_ids         = module.default_vpc.subnet_ids
  security_group_ids = [module.security.ecs_sg_id]
  execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn      = module.iam.inventory_service_task_role_arn
  
  service_name       = "inventory-service"
  ecr_repository_url = module.ecs_cluster.inventory_service_repo_url
  # No target_group_arn passed, it runs asynchronously behind the scenes
}

# 3. Notification Service (Backend SQS Consumer)
module "notification_service" {
  source             = "../../modules/ecs-service"
  env                = var.env
  cluster_id         = module.ecs_cluster.cluster_id
  subnet_ids         = module.default_vpc.subnet_ids
  security_group_ids = [module.security.ecs_sg_id]
  execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn      = module.iam.notification_service_task_role_arn
  
  service_name       = "notification-service"
  ecr_repository_url = module.ecs_cluster.notification_service_repo_url
  # No target_group_arn passed
}

# ==========================================
# Observability & Governance Add-ons
# ==========================================
module "observability" {
  source               = "../../modules/observability"
  vpc_id               = module.default_vpc.vpc_id
  subnet_ids           = module.default_vpc.subnet_ids
  ops_ec2_sg_id        = module.security.ops_ec2_sg_id
  alb_arn_suffix       = module.alb.alb_arn_suffix
  ops_alerts_topic_arn = "arn:aws:sns:us-east-1:123456789012:orderflow-ops-alerts" 
}

module "governance" {
  source = "../../modules/governance"
  env    = var.env
}
