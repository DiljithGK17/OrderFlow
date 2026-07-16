# Detailed Resource Flow & Architecture 

This document breaks down the OrderFlow architecture from the exact perspective of the infrastructure resources provisioned by Terraform. It explains how a piece of data flows through the system, detailing precisely which AWS resource receives the data, how it processes it, and where it forwards it.

---

## 1. The Entry Point: API Gateway

When a user or external client makes an HTTP request to create an order (e.g., `POST /orders`), the traffic first hits the **API Gateway**.

1. **`aws_apigatewayv2_api` (HTTP API):** The outer boundary. It provides the public endpoint URL.
2. **`aws_apigatewayv2_stage` ($default):** Applies overarching rules to the API, such as rate limiting and throttling (e.g., max 100 requests per second) to prevent DDoS attacks or traffic spikes.
3. **`aws_apigatewayv2_route` (ANY /orders/{proxy+}):** Inspects the URL path of the incoming request. If it matches `/orders/*`, it captures the traffic and triggers the integration.
4. **`aws_apigatewayv2_integration` (ALB Integration):** Tells the API Gateway exactly *how* to forward the request. It wraps the HTTP request and sends it through the VPC Link.
5. **`aws_apigatewayv2_vpc_link`:** API Gateway lives in an AWS-managed network. The VPC Link securely bridges the traffic from the AWS network directly into your specific VPC subnets, without the traffic ever traversing the public internet.

---

## 2. The Traffic Distributor: Application Load Balancer (ALB)

The traffic emerges from the VPC Link into your VPC and arrives at the ALB.

6. **`aws_security_group` (alb):** Before the ALB processes the request, the security group acts as a firewall. It checks the inbound rules and ensures the traffic is allowed (HTTP/HTTPS).
7. **`aws_lb` (Application Load Balancer):** Receives the HTTP request. Its job is to distribute traffic efficiently across multiple backend containers.
8. **`aws_lb_listener` (HTTP Port 80):** A process running on the ALB that continuously listens for incoming traffic on port 80. When traffic arrives, it evaluates the Listener Rules.
9. **`aws_lb_listener_rule` (order_service):** The listener evaluates the request path. If the path starts with `/orders`, this rule activates and tells the ALB to forward the request to the specific Target Group for the Order Service.
10. **`aws_lb_target_group` (order-service-tg):** This is a dynamic list of IP addresses. It continuously polls the Fargate containers on the `/healthz` endpoint. If a container is healthy, its IP is in the target group. The ALB forwards the HTTP request to one of the healthy IP addresses in this group.

---

## 3. The Compute Layer: ECS & Fargate

The request leaves the ALB and travels to the specific Fargate container running the Order Service code.

11. **`aws_security_group` (ecs):** Before reaching the container, this firewall checks the traffic. It has a strict rule: *Only accept traffic originating from the ALB Security Group*. This prevents anyone from bypassing the API Gateway/ALB and hitting the containers directly.
12. **`aws_ecs_cluster`:** The logical boundary that groups our microservices together.
13. **`aws_ecs_service` (order-service):** Ensures that the desired number of containers (e.g., 2) are always running. If a container crashes, the ECS Service automatically starts a new one and registers its IP with the ALB's Target Group.
14. **`aws_ecs_task_definition` (order-service):** The blueprint. It tells Fargate to pull the Order Service Docker image from ECR, allocate exactly 0.25 vCPU and 512MB RAM, and expose port 8080. 
15. **Fargate Task (The actual running container):** The Node.js/Python application inside the container receives the HTTP POST request on port 8080. It processes the JSON payload to create the order.

---

## 4. The Data & Security Layer: IAM and DynamoDB

For the application code to actually save the order, it must interact with AWS services. By default, it has zero permissions.

16. **`aws_iam_role` (order_service_task_role):** This IAM role is assigned to the Fargate container. It grants the code inside the container the temporary AWS credentials needed to talk to DynamoDB and SNS.
17. **`aws_dynamodb_table` (idempotency-dev):** The application first queries this table to check if this exact order was already processed recently (to prevent accidental double-billing).
18. **`aws_dynamodb_table` (orders-dev):** If the order is new, the application writes the order payload to this NoSQL database.

---

## 5. Event-Driven Messaging: SNS Fan-Out

The Order Service does not talk directly to the Inventory or Notification services. Instead, it publishes an event.

19. **`aws_sns_topic` (order-events):** The Order Service publishes a message (e.g., `{"orderId": "123", "status": "CREATED"}`) to this topic. The Order Service's job is now done, and it returns an HTTP 200 OK response back through the ALB to the API Gateway to the user.
20. **`aws_sns_topic_subscription` (2x):** SNS takes that single message and immediately copies it (fans it out) to multiple subscribers. That counts as 2 subscription resources (one for Inventory, one for Notification). (Resources #20 & #21).

---

## 6. Asynchronous Processing: SQS and Backend Services

The copied messages arrive in queues to be processed by backend workers.

22. **`aws_sqs_queue` (inventory-queue):** Stores messages durably for the Inventory service.
23. **`aws_sqs_queue` (notification-queue):** Stores messages durably for the Notification service.
24. **`aws_iam_role` (inventory_service_task):** Grants the Inventory container access to its queue and DynamoDB.
25. **`aws_ecs_service` (inventory-service):** Runs the infinite polling loop in Fargate to pull from `inventory-queue`.
26. **`aws_ecs_task_definition` (inventory-service):** Blueprint for the Inventory container.
27. **`aws_dynamodb_table` (inventory-dev):** The Inventory Service updates the stock count in this table.
28. **`aws_iam_role` (notification_service_task):** Grants the Notification container access to its queue.
29. **`aws_ecs_service` (notification-service):** Runs the infinite polling loop in Fargate to pull from `notification-queue`.
30. **`aws_ecs_task_definition` (notification-service):** Blueprint for the Notification container.

---

## 7. Container Images & Underlying Compute Management

For Fargate to run containers, it needs to know where to get them and how to run them.

31. **`aws_ecr_repository` (order-service):** Stores the Docker image for Order Service.
32. **`aws_ecr_repository` (inventory-service):** Stores the Docker image for Inventory Service.
33. **`aws_ecr_repository` (notification-service):** Stores the Docker image for Notification Service.
34. **`aws_ecs_cluster_capacity_providers`:** Attaches the "FARGATE" capacity provider to the ECS cluster so it knows *how* to provision the underlying hardware.
35. **`aws_iam_role` (ecs_task_execution_role):** Used by the ECS Agent itself (not your app code) to pull images from ECR and send logs to CloudWatch.

---

## 8. IAM Policy Attachments

We created Roles above, but we have to strictly attach specific permission policies to them.

36. **`aws_iam_role_policy_attachment` (Execution Role -> ECS Task Execution Policy)**
37. **`aws_iam_role_policy_attachment` (Order Task -> DynamoDB Access)**
38. **`aws_iam_role_policy_attachment` (Order Task -> SNS Access)**
39. **`aws_iam_role_policy_attachment` (Order Task -> X-Ray Access)**
40. **`aws_iam_role_policy_attachment` (Inventory Task -> DynamoDB Access)**
41. **`aws_iam_role_policy_attachment` (Inventory Task -> SQS Access)**
42. **`aws_iam_role_policy_attachment` (Inventory Task -> X-Ray Access)**
43. **`aws_iam_role_policy_attachment` (Notification Task -> SQS Access)**
44. **`aws_iam_role_policy_attachment` (Notification Task -> X-Ray Access)**

---

## 9. Auto-Scaling

The architecture is designed to scale dynamically based on load.

45. **`aws_appautoscaling_target` (Order Service):** Registers the Order Service with AWS Application Auto Scaling.
46. **`aws_appautoscaling_policy` (Order Service CPU):** Tells ECS to add more order containers if CPU > 75%.
47. **`aws_appautoscaling_policy` (Order Service Memory):** Tells ECS to add more order containers if Memory > 75%.
48. **`aws_appautoscaling_target` (Inventory Service):** Registers Inventory Service.
49. **`aws_appautoscaling_policy` (Inventory Service CPU)**
50. **`aws_appautoscaling_policy` (Inventory Service Memory)**
51. **`aws_appautoscaling_target` (Notification Service):** Registers Notification Service.
52. **`aws_appautoscaling_policy` (Notification Service CPU)**
53. **`aws_appautoscaling_policy` (Notification Service Memory)**

---

## 10. Observability, Logging & Operations

If something breaks, we need to know immediately and have a place to debug it safely.

54. **`aws_cloudwatch_dashboard` (orderflow-dashboard):** Centralizes all ALB, ECS, and SQS metrics onto a single visual pane of glass.
55. **`aws_cloudwatch_metric_alarm` (alb-5xx-errors):** Continuously monitors the ALB. If it throws too many 500-level errors, this alarm triggers.
56. **`aws_security_group` (ops-ec2):** A strict, no-inbound-ports firewall for the operations box.
57. **`aws_instance` (ops-ec2):** The centralized Operations/Monitoring box. It runs a user-data script on launch to install Prometheus, Grafana, and Loki, providing us an internal tool to debug the system.

*(Note: AWS CloudWatch Log Groups are dynamically created by the ECS module for each service, but those are standard auxiliary resources tracked under the services).*

---

## 11. Post-Infrastructure Flow: The Application Lifecycle

Building the AWS infrastructure (VPC, ECS, Load Balancers, DynamoDB) is only the first half of the project. Once the infrastructure is ready, we need to deploy the actual **Application Code** into it. 

### Does this have a Frontend?
No. This is a purely **Backend API + Infrastructure** architecture. It represents an enterprise-grade Microservices backend. Clients (like web applications, mobile apps, or Postman) will send HTTP JSON payloads to the API Gateway. 

### Where is the Application Code?
The core business logic lives entirely inside the `services/` directory. Each microservice (e.g., `services/order-service`) contains raw Python code (FastAPI) that processes the orders, talks to DynamoDB, and publishes messages to SNS.

### What do the `monitoring` and `nginx` folders do?
- **`nginx/`**: In our ECS Task Definitions, we deploy a "Sidecar" pattern. Instead of exposing the Python application directly to the Load Balancer, we put a lightweight NGINX web server container right next to it inside the same Fargate task. NGINX receives the HTTP traffic on port 80, handles routing/proxying, and forwards it to the Python app on port 8080.
- **`monitoring/`**: Contains the startup scripts (e.g., `ops-ec2-userdata.sh`) for our Operations EC2 instance. When that EC2 instance boots up, it runs this script to automatically install and configure **Prometheus** (metrics database), **Grafana** (visual dashboards), and **Loki** (log aggregation). This gives us a dedicated, self-hosted observability platform to monitor the health of our microservices without relying solely on AWS CloudWatch.

### How does the CI/CD Pipeline Run?
The entire application deployment process is automated via GitHub Actions (`.github/workflows/deploy.yml`):
1. **Trigger:** Whenever you push code to the `main` branch, the pipeline wakes up.
2. **Authenticate:** It securely logs into your AWS account using the Sandbox credentials you saved as GitHub Secrets.
3. **The Dockerfile:** The pipeline reads the `Dockerfile` inside `services/order-service`. A Dockerfile is a set of instructions that tells the system: *"Download a base Linux environment, install Python, install the dependencies from `requirements.txt`, and copy our application code inside."* This creates a standardized, isolated package called a **Docker Image**.
4. **Push to Registry:** The pipeline pushes this Docker Image into **AWS ECR** (Elastic Container Registry), which acts as a secure storage drive in the cloud for container images.
5. **Update Compute:** Finally, the pipeline runs an AWS CLI command telling the **ECS Cluster** to update its running services. ECS gracefully shuts down the old, empty containers and spins up new containers using the brand-new Docker image we just pushed to ECR.

Once ECS spins up the new container and it passes the Load Balancer's `/healthz` health check, the application is live and ready to process real traffic!

---

## 12. Architectural Design Decisions & FAQs

### If API Gateway uses `$default` to route everything to the ALB, do we still need it?
Yes, absolutely! Even acting as a simple passthrough, the API Gateway provides critical "API Management" features that an ALB does not natively handle well:
1. **Throttling & Rate Limiting:** We configured our API Gateway Stage to restrict traffic to 100 requests/second. This protects our backend databases and compute from DDoS attacks or runaway client scripts.
2. **Authentication:** In a full production environment, API Gateway natively integrates with AWS Cognito or custom Lambda Authorizers to instantly reject unauthorized requests *before* they ever reach our VPC compute layer.
3. **Network Security:** While our Sandbox limitations forced the ALB into public subnets, a true production architecture places the ALB in *Private* subnets. The API Gateway + VPC Link acts as the only secure bridge from the public internet into your private network.

### Why did we originally include an NGINX Sidecar, and why did we remove it?
**Why we included it:** In enterprise microservices, putting a lightweight NGINX proxy right in front of Python (a "sidecar") is a best practice. Python web servers (like Uvicorn) are not heavily optimized for things like SSL termination, mitigating slow-client DDoS attacks (Slowloris), or serving static assets. NGINX acts as a hardened shield, buffering slow requests and forwarding only clean, rapid traffic to Python.

**Why we removed it:** To make NGINX proxy traffic to Python, it requires a custom `nginx.conf` file. Because ECS Fargate doesn't easily support mounting local config files, we would have had to build a custom NGINX Docker image, create a new ECR repository for it, and add it to our CI/CD pipeline. For this specific sandbox environment, that added unnecessary complexity. Modern Uvicorn is robust enough to handle direct ALB traffic for our current needs, so we simplified the architecture by removing the sidecar.

### How exactly do the ALB Health Checks work?
1. The Load Balancer has a **Target Group** (`order-service-tg`), which keeps a dynamic list of IP addresses for every running Fargate container.
2. Every 15 seconds, the Target Group automatically sends an HTTP `GET /healthz` request to those IP addresses on port 8080.
3. The FastAPI Python code explicitly defines this route (`@app.get("/healthz")`) and returns a simple `{"status": "ok"}` (HTTP 200).
4. If the ALB receives the HTTP 200 OK, it marks the container as **Healthy** and actively forwards user API traffic to it.
5. If the application crashes, hangs, or returns an error (like the 404 we saw when NGINX was misconfigured), the ALB marks it **Unhealthy**. It immediately stops sending user traffic to that container, and AWS ECS automatically kills the container and spins up a fresh replacement to heal the system.

---

## Summary
When `terraform apply` runs successfully, it provisions exactly these 57 distinct AWS resources. This represents a complete, production-ready, highly available, dynamically scalable, and observable cloud-native environment.
