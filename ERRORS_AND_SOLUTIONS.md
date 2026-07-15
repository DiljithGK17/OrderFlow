# Errors and Solutions Log

This document tracks the errors encountered during the provisioning and deployment of the OrderFlow infrastructure, specifically within the KodeKloud AWS Sandbox environment, and how they were resolved.

### 1. Terraform Syntax Errors (Semicolons)
**Error:** Multiple errors stating `The ";" character is not valid` or `Invalid single-argument block definition`.
**Why it happened:** In earlier Terraform versions or JSON, semicolons or single-line blocks were more forgiving. In standard HCL, arguments inside blocks must be separated by newlines, and `jsonencode()` requires commas.
**How we fixed it:** We ran a python script to parse the `.tf` files and replace the semicolons with newlines, converting them into standard multi-line HashiCorp Configuration Language (HCL) blocks, and ran `terraform fmt`.

### 2. Terraform Type Error (assign_public_ip)
**Error:** `Inappropriate value for attribute "assign_public_ip": a bool is required.`
**Why it happened:** AWS CloudFormation and the AWS CLI expect the string `"ENABLED"` or `"DISABLED"` for this property. Terraform strictly requires a boolean `true` or `false`.
**How we fixed it:** Changed `assign_public_ip = "ENABLED"` to `assign_public_ip = true` in the `ecs-service` module.

### 3. KodeKloud Sandbox Strict Permissions (AccessDeniedException)
**Errors:** 
- `WAFV2: CreateWebACL` -> `explicit deny in a service control policy`
- `DynamoDB: UpdateTimeToLive` -> `no identity-based policy allows...`
- `Config Service: PutConfigurationRecorder` -> `AccessDeniedException` for `iam:PassRole`
- `IAM: PutRolePolicy` -> `AccessDenied`
**Why it happened:** Educational sandbox environments (like KodeKloud) use AWS Organizations Service Control Policies (SCPs) to strictly limit what students can build to prevent huge billing costs. Advanced features like Web Application Firewalls (WAF), AWS Config, CloudTrail, DynamoDB TTL, and custom inline IAM policies are blocked.
**How we fixed it:** We adapted the infrastructure to the sandbox limitations:
1. **WAF & Governance**: Removed the WAF resources from the `api-gateway` module and completely removed the `governance` module (Config/CloudTrail) from the root environment. We kept the API Gateway itself.
2. **DynamoDB**: Disabled TTL on the DynamoDB Idempotency table.
3. **IAM**: Switched from custom inline IAM policies (`aws_iam_role_policy`) to attaching existing AWS Managed Policies (`AmazonDynamoDBFullAccess`, `AmazonSQSFullAccess`) using `aws_iam_role_policy_attachment` since the sandbox blocks custom inline policy creation.

### 4. API Gateway VPC Link Availability Zone Error
**Error:** `Subnet '...' is in Availability Zone 'use1-az3' where service is not available`
**Why it happened:** AWS API Gateway VPC Links are only supported in certain Availability Zones. The default VPC includes subnets in all zones, including `use1-az3` which lacks support for this feature in `us-east-1`.
**How we fixed it:** In `infra/envs/dev/main.tf`, we filtered the `subnet_ids` passed to the `api_gateway` module to only include the first two subnets (which are typically `us-east-1a` and `us-east-1b`) using Terraform's `slice()` function: `slice(module.default_vpc.subnet_ids, 0, 2)`.

### 5. API Gateway Integration URI Error
**Error:** `BadRequestException: For VpcLink VPC_LINK, integration uri should be a valid ELB listener ARN...`
**Why it happened:** In `infra/envs/dev/main.tf`, the API Gateway integration was accidentally pointing to the Load Balancer's ARN (`module.alb.alb_arn`), rather than the specific Listener's ARN (`module.alb.alb_listener_arn`).
**How we fixed it:** Added `alb_listener_arn` to the `alb` module outputs, and updated the `dev/main.tf` file to pass the `alb_listener_arn` into the `api-gateway` module instead of the base ALB ARN.

### 6. Docker Build Missing requirements.txt
**Error:** `ERROR: failed to calculate checksum of ref... "/requirements.txt": not found`
**Why it happened:** The `Dockerfile` for the `order-service` attempts to `COPY requirements.txt .`, but the file was missing from the repository directory, causing the GitHub Actions `docker build` step to fail.
**How we fixed it:** Created `services/order-service/requirements.txt` containing the necessary Python dependencies (`fastapi`, `uvicorn`, `boto3`, `prometheus_client`, `aws_xray_sdk`).
