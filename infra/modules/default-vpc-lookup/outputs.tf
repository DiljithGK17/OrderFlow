# ==========================================
# Outputs
# ==========================================

# 3. Output the VPC ID and Subnet IDs so other modules (like ALB, ECS, Security Groups) 
# can use them for placement and networking.
output "vpc_id" { value = data.aws_vpc.default.id }

output "subnet_ids" { value = data.aws_subnets.default.ids }
