# ==========================================
# Observability Module
# ==========================================
# Sets up the monitoring EC2 instance and CloudWatch alarms.

# 1. Look up the latest Amazon Linux 2023 AMI for the EC2 instance.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. Operations EC2 IAM Role
# Allows the EC2 instance to be managed by Systems Manager (SSM).
# This is crucial because our EC2 instance has no inbound ports open (no SSH).
resource "aws_iam_role" "ops_ec2" {
  name = "orderflow-ops-ec2-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ops_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ops_ec2" {
  name = "orderflow-ops-ec2-profile"
  role = aws_iam_role.ops_ec2.name
}

# 3. CloudWatch Alarm for ALB 5xx Errors
# Monitors the load balancer. If the backend tasks throw too many 5xx errors (e.g. app crash),
# it triggers an alarm and sends a notification to the operations SNS topic.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "orderflow-alb-high-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions       = [var.ops_alerts_topic_arn]
}

# 4. Operations EC2 Instance
# A small EC2 instance running in the public subnet.
# On boot, it runs the `user_data` script which installs Docker and launches 
# the Prometheus, Grafana, and Loki monitoring stack.
resource "aws_instance" "ops" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [var.ops_ec2_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ops_ec2.name

  # Injects the script that spins up the observability stack via Docker Compose
  user_data = file("${path.module}/../../../monitoring/ops-ec2-userdata.sh")

  tags = { Name = "orderflow-ops-ec2", Service = "observability" }
}
