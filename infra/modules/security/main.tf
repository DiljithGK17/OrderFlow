# ==========================================
# Security Groups Module
# ==========================================
# This module creates Security Groups to isolate network traffic.
# Because we are using the public subnets of the default VPC, we use 
# these Security Groups to act as our primary network boundary.

# Passed in from the default-vpc-lookup module

# 1. Application Load Balancer (ALB) Security Group
# Allows inbound HTTPS/HTTP traffic from the public internet (0.0.0.0/0).
# Allows all outbound traffic.
resource "aws_security_group" "alb" {
  name   = "orderflow-alb-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. ECS Tasks Security Group
# Strictly limits inbound traffic to only come from the ALB Security Group (port 8080).
# This ensures users cannot bypass the API Gateway/ALB to hit the tasks directly.
resource "aws_security_group" "ecs" {
  name   = "orderflow-ecs-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Operations EC2 Instance Security Group
# No inbound rules at all. We will connect to this instance exclusively 
# via AWS Systems Manager (SSM) Session Manager, which doesn't require open ports.
resource "aws_security_group" "ops_ec2" {
  name   = "orderflow-ops-ec2-sg"
  vpc_id = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
