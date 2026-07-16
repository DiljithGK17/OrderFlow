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

**Why FluentBit (log-router) was included in the first place:**
In a production-grade microservices architecture, application containers should not handle their own log delivery — it's an operational concern, not a business one. `AWS for Fluent Bit` is a specialized log-routing sidecar that runs alongside the main application container inside the same Fargate Task. Here's what it was designed to do:
- **Multi-destination log fanout:** FluentBit can simultaneously ship the same log stream to multiple destinations — e.g., AWS CloudWatch Logs for retention, Amazon S3 for archival, and an external observability platform like Grafana Loki running on our Ops EC2 instance.
- **Log enrichment:** It can parse and restructure raw log lines (e.g., JSON logs from FastAPI) and add metadata like container name, service version, and environment before shipping.
- **awsfirelens driver:** The `awsfirelens` log driver in Docker/ECS is a special hook. Instead of writing logs to stdout and letting the OS handle them, it pipes every log line directly to the FluentBit process running as a sidecar. FluentBit then handles where those logs actually go.
- **Decoupled observability:** In production, if you want to change your log destination (e.g., switch from CloudWatch to Splunk), you only change the FluentBit config — not the application code.

**Why it failed in this sandbox:**
The FluentBit sidecar requires:
1. The ECS Task Execution Role to have `logs:CreateLogGroup`, `logs:PutLogEvents` etc. permissions.
2. A valid FluentBit output config defining *where* to send logs. Without an explicit config file mounted in, the default image has no valid output and exits immediately.
3. Because the `log-router` container was marked `essential = true`, when it crashed, ECS treated the entire Fargate Task as failed and killed all other containers (including the main application) immediately — with no error code logged because no container ever ran long enough to report one.

**Current configuration (after fix):**
The FluentBit sidecar is kept and properly configured. The key fix was providing **inline output options** directly in the main container's `awsfirelens` log configuration. This tells FluentBit exactly where to route logs using its built-in CloudWatch Logs output plugin — no custom config file required.

```hcl
# Main container — sends logs to FluentBit via awsfirelens
logConfiguration = {
  logDriver = "awsfirelens"
  options = {
    Name              = "cloudwatch_logs"   # FluentBit's built-in CloudWatch plugin
    region            = "us-east-1"
    log_group_name    = "/ecs/order-service"
    log_stream_prefix = "ecs/"
    auto_create_group = "true"             # Auto-creates log group if it doesn't exist
  }
}

# FluentBit sidecar — configured to add ECS metadata and route to output
firelensConfiguration = {
  type = "fluentbit"
  options = { enable-ecs-log-metadata = "true" }
}
# FluentBit itself logs via simple awslogs so we can debug it independently
logConfiguration = {
  logDriver = "awslogs"
  options = { awslogs-group = "/ecs/fluent-bit", awslogs-create-group = "true" ... }
}
```

- The main app container writes to `stdout` as normal.
- The `awsfirelens` driver intercepts those logs and sends them to the FluentBit process.
- FluentBit uses the inline `cloudwatch_logs` output plugin config to route them to CloudWatch.
- FluentBit itself logs via `awslogs` directly, so if it crashes we can inspect its own logs.
- `CloudWatchLogsFullAccess` remains attached to the Task Execution Role for permissions.

**Trade-off vs. plain awslogs:** Slightly more complex setup, but we retain production-grade multi-destination fanout capability — e.g., we can add a Loki output block later without touching application code.

### 11. ECS CannotStartContainerError — uvicorn not found in $PATH
**Error:** `CannotStartContainerError: exec: "uvicorn": executable file not found in $PATH`
**Why it happened:** The `Dockerfile` uses a **multi-stage build** pattern. In the builder stage, packages were installed with `pip install --target=/install`, which places all library files inside the `/install` directory. The second stage then copied those files directly into `/usr/local/lib/python3.12/site-packages`. This correctly installs the Python *library* files (like `uvicorn/`), but it does **not** copy the `uvicorn` executable script which pip normally places in `/usr/local/bin/uvicorn`. Without that binary on `$PATH`, ECS could not launch the container via the `CMD ["uvicorn", ...]` instruction.
**How we fixed it:**
1. Changed the builder stage to use a standard `pip install --no-cache-dir` (without `--target`), so pip installs packages into its default location (`/usr/local/lib` and `/usr/local/bin`).
2. Updated the final stage to copy both `/usr/local/lib` (libraries) **and** `/usr/local/bin` (executables including `uvicorn`) from the builder.
3. Changed the container `CMD` to `["python", "-m", "uvicorn", ...]` as an additional safeguard — this invokes uvicorn as a Python module rather than relying on the binary being discoverable on `$PATH`.

### 12. inventory-service & notification-service — No ECR Image / Missing Dockerfile
**Error:** ECS showed `0/2 Tasks running (Failed)` for `inventory-service` and `notification-service`. Root cause: `CannotPullContainerError` — no image existed in ECR for those two services.
**Why it happened:** The `deploy.yml` pipeline only built and pushed the `order-service` image. The `inventory-service` directory had no `Dockerfile` or `requirements.txt`. The `notification-service` directory didn't exist at all in `services/`.
**How we fixed it:**
1. Created `services/inventory-service/Dockerfile` and `requirements.txt` using the same multi-stage pattern as `order-service`, with `CMD ["python", "consumer.py"]` since it is a long-polling SQS worker, not an HTTP server.
2. Created the entire `services/notification-service/` directory with `src/consumer.py`, `Dockerfile`, and `requirements.txt`.
3. Updated `.github/workflows/deploy.yml` to build and push all three service images in the same pipeline run, and updated the `deploy-dev` job to force a new deployment on all three ECS services simultaneously.


### 13. API Gateway 503 Service Unavailable — ALB Security Group Missing Port 80
**Error:** `{"message":"Service Unavailable"}` returned by API Gateway even though all 3 ECS services showed `2/2 Tasks running`.
**Why it happened:** The ALB Security Group (`orderflow-alb-sg`) in `infra/modules/security/main.tf` only had an ingress rule for **port 443 (HTTPS)**. However, our ALB Listener is configured on **port 80 (HTTP)** — the VPC Link from API Gateway connects to the ALB over HTTP internally. Because port 80 was blocked at the security group level, the ALB never received health check traffic from the ECS tasks, so it had zero healthy targets and returned 503 to every request.
**How we fixed it:** Added a port 80 ingress rule to the ALB Security Group, allowing HTTP from `0.0.0.0/0`. The 443 rule is retained for future HTTPS/TLS support. Applied via `make up`.

### 14. 500 Internal Server Error — Missing ECS Environment Variables
**Error:** Hitting the ALB directly with `POST /orders` returned an `Internal Server Error` (500), despite the ALB target health showing as `healthy`.
**Why it happened:** The `order-service` Python application attempts to publish to SNS using `sns.publish(TopicArn=os.getenv("SNS_TOPIC_ARN"))`. However, the ECS Task Definition in `infra/modules/ecs-service/main.tf` did not define or pass any environment variables into the container. Because `os.getenv("SNS_TOPIC_ARN")` evaluated to `None`, boto3 threw an exception which resulted in a 500 crash. This same issue affected `inventory-service` and `notification-service` which were missing their `QUEUE_URL` variables.
**How we fixed it:**
1. Modified `infra/modules/sns-sqs/outputs.tf` to expose `inventory_queue_url` and `notification_queue_url`.
2. Added an `environment_variables` map variable to `infra/modules/ecs-service/variables.tf`.
3. Updated the `container_definitions` block in `infra/modules/ecs-service/main.tf` to iterate over the `environment_variables` and inject them as container env vars.
4. Passed the required ARNs, table names, and queue URLs to all three microservices in `infra/envs/dev/main.tf`.

### 15. 500 Internal Server Error — X-Ray SegmentNotFoundException
**Error:** `Internal Server Error` from `/orders` endpoint, and completely empty CloudWatch logs.
**Why it happened:** The `order-service` Python code used `aws_xray_sdk.core.xray_recorder.capture` as a decorator on the `/orders` route, and called `patch_all()` to instrument boto3. However, because we are using FastAPI, the incoming request does not automatically generate a base X-Ray Segment (unless you explicitly add the AWS X-Ray ASGI Middleware). Without a base segment, the `@xray_recorder.capture()` decorator throws a `SegmentNotFoundException` immediately before the route function even executes, causing a 500 error.
**How we fixed it:** Removed all X-Ray code (`aws_xray_sdk` imports, `patch_all()`, and the `@xray_recorder.capture` decorator) from `services/order-service/src/main.py` to simplify the application and prevent the unhandled exception.

### 16. Sandbox Account Suspension — Exceeded ECS Max Limits
**Error:** `Service: AWS ECS, ECS Clusters in the 905418031803 exceeds the max limits of 2048 units of CPU...`
**Why it happened:** We are running 3 ECS microservices (`order-service`, `inventory-service`, `notification-service`). Previously, our `ecs-service` Terraform module was configured to run a `desired_count = 2` tasks for each service. During a deployment, ECS launches the new tasks before stopping the old ones (maximum percent 200%), which means ECS briefly tries to run 4 tasks per service. With 3 services deploying simultaneously, ECS attempts to run 12 tasks at once. Since each task uses 256 CPU units, 12 tasks require 3072 CPU units, violating the KodeKloud AWS Sandbox hard limit of 2048 CPU units.
**How we fixed it:** Changed `desired_count = 1` in `infra/modules/ecs-service/main.tf`. Now, during deployment, each service will temporarily scale up to 2 tasks (6 total across all services). 6 tasks * 256 CPU = 1536 CPU units, safely below the 2048 sandbox limit.

### 17. GitHub Actions ECR Push Failure — Hardcoded AWS Account ID
**Error:** `denied: User: ... is not authorized to perform: ecr:InitiateLayerUpload on resource: arn:aws:ecr:us-east-1:905418031803:repository/orderflow/order-service`
**Why it happened:** The `.github/workflows/deploy.yml` pipeline had the AWS Account ID `905418031803` (from the previous sandbox session) hardcoded in multiple places for the ECR registry URL. When the new sandbox session was started, a new AWS Account ID was assigned. The pipeline successfully authenticated with the new account's credentials but then attempted to push the Docker images to the old account's ECR repository, resulting in an IAM access denied error.
**How we fixed it:** Replaced the hardcoded Account ID in `.github/workflows/deploy.yml` with a dynamic fetch using the AWS CLI (`ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)`). Now the pipeline automatically detects the correct ECR registry URL for whichever AWS sandbox account is currently active.
