# ==========================================
# VPC Lookup Module
# ==========================================
# This module reads the default VPC and its subnets.
# In the sandbox, creating custom VPCs/NAT Gateways is not supported, 
# so we rely on the pre-existing default VPC.

# 1. Fetch the default VPC.
data "aws_vpc" "default" {
  default = true
}

# 2. Fetch all subnets that belong to the default VPC.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id] # Links to the VPC ID retrieved above
  }
}

# 3. Fetch detailed data for each subnet to filter out unsupported AZs.
data "aws_subnet" "all" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}
