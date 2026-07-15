# ==========================================
# Governance & Security Add-Ons Module
# ==========================================
# This module provisions tools for auditing, compliance, and security scanning.
# It elevates the project from a simple demo to an enterprise-grade setup.

# 1. CloudTrail
# Records every API call made in the AWS account. This is essential for auditing 
# (e.g., finding out who deleted a database or changed a security group).
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "orderflow-cloudtrail-${var.env}-xyz123" # S3 bucket to store the logs
}

resource "aws_cloudtrail" "this" {
  name                          = "orderflow-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false # Kept false to reduce costs in sandbox
}

# 2. AWS Config IAM Role
# Grants AWS Config permission to read the configuration of resources in the account.
resource "aws_iam_role" "config_role" {
  name = "orderflow-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "config.amazonaws.com" } }]
  })
}

# Attach AWS managed policy for AWS Config
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# 3. AWS Config Recorder
# Turns on the continuous recording of resource configurations.
resource "aws_config_configuration_recorder" "this" {
  name     = "orderflow-recorder"
  role_arn = aws_iam_role.config_role.arn
}

# 4. AWS Config Rules
# Compliance checks that run continuously.
# Rule 1: Checks that no S3 buckets are public.
resource "aws_config_config_rule" "s3_not_public" {
  name = "s3-bucket-public-read-prohibited"
  source { owner = "AWS"; source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED" }
}

# Rule 2: Checks that all EBS volumes attached to EC2 instances are encrypted.
resource "aws_config_config_rule" "ebs_encrypted" {
  name = "encrypted-volumes"
  source { owner = "AWS"; source_identifier = "ENCRYPTED_VOLUMES" }
}
