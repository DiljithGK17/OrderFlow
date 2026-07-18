# ==========================================
# Variables
# ==========================================

variable "vpc_id" {}

variable "subnet_ids" { type = list(string) }

variable "ops_ec2_sg_id" {}

variable "alb_arn_suffix" {}

variable "ops_alerts_topic_arn" {}

variable "alb_dns_name" {}
