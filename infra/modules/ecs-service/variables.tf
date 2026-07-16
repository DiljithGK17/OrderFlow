# ==========================================
# Variables
# ==========================================

variable "env" {}

variable "cluster_id" {}

variable "subnet_ids" { type = list(string) }

variable "security_group_ids" { type = list(string) }

variable "execution_role_arn" {}

variable "task_role_arn" {}

variable "ecr_repository_url" {}

# Variables to make this generic
variable "service_name" { type = string }

variable "target_group_arn" {
  type    = string
  default = null # Optional: Because inventory and notification services don't use the ALB
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}
