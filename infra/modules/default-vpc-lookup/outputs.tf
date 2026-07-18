# ==========================================
# Outputs
# ==========================================

# 3. Output the VPC ID and Subnet IDs so other modules (like ALB, ECS, Security Groups) 
# can use them for placement and networking.
output "vpc_id" { value = data.aws_vpc.default.id }

output "subnet_ids" { 
  # Exclude subnets in 'use1-az3' (not supported by API Gateway VPC Link)
  # Exclude subnets in 'us-east-1e' (not supported by t3.small EC2 instances)
  value = [for s in data.aws_subnet.all : s.id if s.availability_zone_id != "use1-az3" && s.availability_zone != "us-east-1e"]
}
