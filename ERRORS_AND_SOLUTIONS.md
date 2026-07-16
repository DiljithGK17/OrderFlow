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

### 7. ECS Crash Loop & API Gateway 404 Not Found
**Error:** `curl` returned `{"message":"Not Found"}` and ECS Services showed 0/2 Tasks running (Failed deployment).
**Why it happened:** 
1. **API Gateway Route:** The route `ANY /orders/{proxy+}` expects a trailing slash or additional path parameters. A raw `/orders` request doesn't match and gets a 404 from API Gateway.
2. **ALB Health Checks:** The ALB Target Group was trying to hit `/healthz` on port 80 against the `nginx` sidecar. Because we used the default `nginx:1.27-alpine` image without passing it a custom `nginx.conf`, it returned 404. The ALB marked the container unhealthy, causing ECS to continually kill and restart the Fargate tasks.
**How we fixed it:** 
1. Changed the API Gateway route to `$default` to forward everything, and updated the ALB Listener Rule to explicitly match `["/orders", "/orders/*"]`.
2. Removed the `nginx` container from the `ecs-service` module entirely and pointed the `load_balancer` block directly to the Python application on port 8080 (which has a working `/healthz` endpoint).

### 8. KodeKloud Sandbox Resource Limits Violation
**Error:** `Read Before Proceeding: Service AWS ECS... exceeds the max limits of 2048 units of CPU or 4096 GiB of memory...`
**Why it happened:** KodeKloud AWS sandboxes have strict quotas to prevent abuse. We had 3 services (`order`, `inventory`, `notification`) running with a `desired_count = 2` (High Availability). This equals 6 running Fargate tasks. Our Terraform configured each task with `cpu = "512"` (0.5 vCPU) and `memory = "1024"` (1GB). 6 tasks * 512 CPU = 3072 total CPU units, which exceeded their hard limit of 2048.
**How we fixed it:** In `infra/modules/ecs-service/main.tf`, we reduced the Fargate task allocation to `cpu = "256"` (0.25 vCPU) and `memory = "512"` (0.5GB). This drops our total usage across all 6 containers to 1536 CPU and 3072 Memory, safely keeping us under the sandbox limits while maintaining a highly available (2 tasks per service) deployment.

### 9. ECS CannotPullContainerError — ECR :latest tag missing
**Error:** `CannotPullContainerError: failed to resolve ref .../orderflow/order-service:latest: not found`
**Why it happened:** The ECS Task Definition references the image as `:latest`. However, the `deploy.yml` pipeline was only tagging and pushing the image with a Git SHA tag (e.g., `:af75ef2`). It never pushed a `:latest` tag to ECR, so when ECS tried to pull `:latest` it simply didn't exist. Additionally, the `docker push` command was accidentally broken across two lines in the YAML file, meaning the push never actually ran successfully on the previous session.
**How we fixed it:** Updated `.github/workflows/deploy.yml` to push two tags on every build: the specific SHA tag (for auditability) and also `:latest` (so ECS can always pull). Also fixed the broken multi-line `docker push` command that had a stray newline.

### 10. ECS Task Crash Loop — FluentBit Sidecar Failure
**Error:** `Service Unavailable` from API Gateway. ECS showed `Running: 0, Pending: 0, Desired: 2`. Stopped tasks showed all containers in `STOPPED` state with no exit code (indicating the task was killed before the containers ran).
**Why it happened:** The ECS Task Definition used `awsfirelens` as the log driver for the main `order-service` container. The `awsfirelens` driver depends entirely on the `log-router` sidecar container (`amazon/aws-for-fluent-bit:stable`) being alive and healthy first. The FluentBit sidecar was crashing on startup — likely due to missing IAM permissions or misconfigured output destinations. Because the log-router was marked `essential = true`, when it crashed, ECS immediately killed the entire Fargate task including the main application container. This happened before any container even reported a failure reason.
**How we fixed it:**
1. Removed the `log-router` (FluentBit) and `xray-daemon` sidecar containers from `infra/modules/ecs-service/main.tf` entirely.
2. Replaced the `awsfirelens` log driver with the native `awslogs` driver which ships logs directly to AWS CloudWatch Logs — zero external dependencies.
3. Added `CloudWatchLogsFullAccess` managed policy to the ECS Task Execution IAM Role in `infra/modules/iam/main.tf` so it can auto-create the log group on first run.
