# ==========================================
# Outputs
# ==========================================

# Output the SG IDs to attach them to the ALB, ECS services, and EC2 instance
output "alb_sg_id" { value = aws_security_group.alb.id }

output "ecs_sg_id" { value = aws_security_group.ecs.id }

output "ops_ec2_sg_id" { value = aws_security_group.ops_ec2.id }

output "vpc_link_sg_id" { value = aws_security_group.vpc_link.id }
