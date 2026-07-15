# Detailed Step-By-Step Guide for the AWS OrderFlow Project

This guide expands upon the project documentation to help you learn the project completely and set it up from scratch in the KodeKloud AWS Sandbox Playground. It also provides an in-depth architectural flow so you can understand exactly how these resources interact.

## Architectural Flow (How Resources Connect)
Understanding how a single user request flows through the AWS resources is critical to understanding the system.

**The "Happy Path" Order Flow:**
1. **User Request (Client):** A user sends a `POST /orders` HTTP request to create a new order.
2. **Edge Security (WAF):** The request hits the **AWS WAF (Web Application Firewall)** first. The WAF checks the IP against a rate-limiting rule (max 2000 requests / 5 mins). If it passes, it forwards the request to API Gateway.
3. **API Gateway:** The **API Gateway** acts as the front door. It applies throttling (100 req/sec) to protect the backend. It uses a **VPC Link** to privately pass the request into our VPC.
4. **Load Balancer (ALB):** The request is received by the **Application Load Balancer (ALB)**, which inspects the path (`/orders/*`). The ALB's target group points to the running ECS tasks and securely routes the request to one of the healthy containers.
5. **ECS Task (Compute):** The request arrives at an **ECS Fargate Task**. Inside this task:
   - It first hits the **NGINX Sidecar** container, which acts as a reverse proxy, adds security headers, logs the request, and passes it to the app.
   - The **Python Order Service** container processes the request.
6. **Data Storage (DynamoDB):** The Python service checks the **Idempotency DynamoDB Table** to ensure this exact request wasn't already processed. If it's new, it saves the order to the **Orders DynamoDB Table** with a `PENDING` status. 
7. **Event Fan-out (SNS to SQS):** The Python service then publishes an `OrderCreated` event to the **SNS Topic (`order-events`)**. 
   - The SNS Topic instantly fans this event out to the subscribed **Inventory SQS Queue** and **Notification SQS Queue**. The Order Service returns a `201 Created` to the user and its job is done.
8. **Asynchronous Processing (Consumers):** 
   - A separate **Inventory Service** (running in its own ECS Task) constantly polls the **Inventory SQS Queue**. It picks up the message and decrements the stock in the **Inventory DynamoDB Table**. If it crashes 5 times trying to process the message, the message is moved to a **Dead Letter Queue (DLQ)**.

**The Observability Flow:**
- Throughout this whole process, the **X-Ray Daemon Sidecar** in the ECS tasks collects distributed tracing data.
- The **Fluent-Bit Sidecar** collects all logs and ships them to **CloudWatch Logs** and **Loki**.
- The **Prometheus** server running on our **Operations EC2 Instance** continuously scrapes metric data from the containers, which is visualized in **Grafana**.

---

## Step 1: Tooling and Environment Setup
Before you begin, make sure your local environment has all the necessary tools:
- AWS CLI
- Terraform
- Docker
- jq and git
- AWS Session Manager Plugin (for accessing the EC2 instance later without a bastion host)

1. **Launch Sandbox**: Log into the KodeKloud AWS Sandbox.
2. **Export Credentials**: Copy the temporary AWS credentials provided by the sandbox and export them in your local terminal.
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...
   export AWS_DEFAULT_REGION=us-east-1
   ```
3. **Verify VPC**: Ensure the default VPC is present. If not, create it.
   ```bash
   aws ec2 create-default-vpc
   ```

## Step 2: Terraform State Backend Setup
You need a remote backend for Terraform. Run these commands locally to create an S3 bucket and a DynamoDB table for state locking.
```bash
aws s3api create-bucket --bucket orderflow-tfstate-12345 --region us-east-1
aws dynamodb create-table \
  --table-name orderflow-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```
These are referenced in `infra/envs/dev/backend.tf`.

## Step 3: Infrastructure Setup (Terraform)
We've modularized the infrastructure setup. Review the `.tf` files in `infra/modules/` — they have been extensively commented to explain what each resource does.

**To apply:**
```bash
cd infra/envs/dev
terraform init
terraform plan
terraform apply
```
*Alternatively, you can just run `make up` from the root directory.*

## Step 4: Building the Application
The application consists of three microservices:
- **Order Service**: Exposes a REST API (`/orders`). Writes to DynamoDB and publishes an event to SNS.
- **Inventory Service**: Polls the SQS inventory queue to decrement stock when an order is created.
- **Notification Service**: Polls the SQS notification queue to "send" a notification.

To test the application locally, you can use Docker:
```bash
cd services/order-service
docker build -t order-service:local .
docker run -p 8080:8080 order-service:local
```

## Step 5: CI/CD Pipeline (GitHub Actions)
The repository contains two workflows in `.github/workflows`:
1. `ci.yml`: Runs on PRs. It builds the Docker images, runs unit tests, and scans with Trivy.
2. `deploy.yml`: Runs on merge to `main`. It pushes the image to ECR and deploys to `dev`, `staging`, and `prod`.

**Important for the Sandbox**: 
- Create a temporary IAM user specifically for deployment during your session, give it access, and add the keys as GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
- Setup GitHub Environments (`staging`, `prod`) with "Required reviewers" to pause the pipeline for your approval.

## Step 6: Testing & Observability
1. **Seed Data**: Run `make seed` to add inventory data.
2. **Hit the API**: 
   ```bash
   curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/orders \
     -H "Content-Type: application/json" \
     -d '{"customerId":"cust-1","sku":"SKU-001","quantity":2}'
   ```
3. **Grafana**: Use SSM to access the monitoring instance securely.
   ```bash
   aws ssm start-session --target <ops-ec2-instance-id> \
     --document-name AWS-StartPortForwardingSession \
     --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
   ```
   Open `http://localhost:3000` to view the dashboards.
4. **X-Ray**: View the X-Ray service map in the AWS Console to see the full request trace across the microservices.

## Step 7: Teardown
Always tear down the resources at the end of your session using:
```bash
make down
```

## Extra Credit / Enterprise readiness
In a true enterprise environment:
1. Everything would run in private subnets with a NAT Gateway (bypassed here due to sandbox limitations).
2. GitHub Actions would use long-lived OIDC identities instead of temporary IAM credentials.
3. You might use Step Functions for complex order orchestration instead of pure SNS/SQS choreography.
