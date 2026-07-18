# Observability Architecture

This document outlines how observability (Metrics, Logs, and Traces) is architected, collected, and visualized in the OrderFlow platform.

---

## 1. The Observability Stack
We run a dedicated `t3.small` EC2 Operations Instance (`orderflow-ops-ec2`) within our private VPC. This instance runs a Docker Compose stack containing:
- **Prometheus:** Time-series database for scraping and storing metrics.
- **Grafana:** Dashboarding tool used to query Prometheus and visualize the data.
- **Loki (Optional):** Log aggregation system.

---

## 2. Metrics Flow: Exposing, Collecting, and Visualizing

The lifecycle of a metric from generation to visualization happens in three distinct phases:

### Phase 1: Exposing (FastAPI)
Inside the `order-service` ECS Fargate container, we use the `prometheus_client` library. 
When a new order is processed, Python increments an in-memory counter (`ORDERS_CREATED.inc()`). The library automatically mounts an HTTP endpoint at `/metrics` which exposes the current state of these numbers in plain text.

### Phase 2: Collecting (Prometheus via ALB)
Every 15 seconds, the Prometheus container on the Ops EC2 instance executes a "scrape".
1. Prometheus sends an HTTP GET request to `http://<ALB_DNS>/metrics`.
2. The Application Load Balancer (ALB) receives the request and forwards it to port 8080 on the ECS container.
3. The ECS container responds with the text-based metrics.
4. Prometheus ingests these metrics and stores them in its time-series database.

### Phase 3: Visualizing (Grafana)
Grafana is connected to Prometheus as a Data Source. When you open a dashboard, Grafana executes a PromQL query (e.g., `orders_created_total`). Prometheus searches its database and returns the timeline of that metric, which Grafana then renders as a chart to your browser via the SSM Port-Forwarding tunnel.

---

## 3. Alternative Metrics Flow: True Production (ECS Service Discovery)

In our sandbox, we scrape metrics through the ALB due to IAM permission restrictions. However, in a normal, unrestricted production environment, scraping via a Load Balancer is strongly discouraged because the ALB randomly routes requests, preventing Prometheus from tracking individual container health.

Here is how the flow *would* happen using **ECS Service Discovery**:

1. **Service Registration:** When an ECS Fargate task launches, AWS CloudMap (Service Discovery) automatically registers the internal IP address of that specific container.
2. **Dynamic Discovery:** Prometheus is configured with `ecs_sd_configs` (ECS Service Discovery) instead of a static target. It continuously queries the AWS API to fetch the active IP addresses of all healthy containers.
3. **Direct Scrape:** Prometheus bypasses the ALB entirely. It sends HTTP GET requests directly to the internal IP of each individual container (e.g., `http://10.0.1.55:8080/metrics`).
4. **Result:** Prometheus can track metrics on a per-container basis, allowing for accurate aggregations, alerting on dead containers, and seamless horizontal scaling.

---

## 4. Prometheus EC2 Configuration & TSDB Storage

Prometheus is deployed on the Ops EC2 instance using a fully automated initialization process:

### Configuration Injection
When the EC2 instance boots, the `user_data` script (`monitoring/ops-ec2-userdata.sh`) executes. 
1. It creates a local directory at `/opt/monitoring`.
2. It dynamically writes the `prometheus.yml` configuration file, injecting the Terraform-provided ALB DNS name.
3. When `docker-compose` launches the Prometheus container, it uses a **bind mount** (`volumes: ["/opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml"]`) to map the configuration file from the EC2 host directly into the container's filesystem.

### Time-Series Database (TSDB) Storage
Prometheus stores its metrics data in a highly optimized, custom Time-Series Database (TSDB). 
- **How it works:** Data is stored in 2-hour blocks consisting of a metadata file, an index (for fast label querying), and compressed chunks of time-series data.
- **Where it lives:** By default, Prometheus stores this data at `/prometheus` inside the Docker container. 
- **Production Consideration:** In our current sandbox setup, this data is ephemeral—if the Prometheus Docker container is destroyed, the historical metrics are lost. In a true production environment, we would attach an **Amazon EBS (Elastic Block Store) Volume** to the EC2 instance and bind-mount it to the `/prometheus` directory. This ensures metrics data persists permanently across container restarts and instance upgrades.

---

## 5. Distributed Tracing (AWS X-Ray)

While Prometheus handles aggregate numbers (Metrics), AWS X-Ray tracks the lifecycle of a *single* request (Tracing) as it bounces between API Gateway, ECS, DynamoDB, SNS, and SQS.

Here is how X-Ray is configured in detail:

### 1. The ADOT Sidecar
In `infra/modules/ecs-service/main.tf`, we configured the ECS Task Definition to run a second container alongside the Python application: the **AWS Distro for OpenTelemetry (ADOT)** collector. This pattern is known as a "Sidecar".

### 2. Application Instrumentation
The Python application is wrapped with OpenTelemetry libraries (`opentelemetry-instrumentation-fastapi`, `boto3-instrumentation`). 
When a request arrives, the app automatically generates a unique "Trace ID". As the app queries DynamoDB or publishes to SNS, it injects this Trace ID into the HTTP headers of those outbound requests, measuring exactly how many milliseconds each step takes.

### 3. Data Handoff
Instead of sending this data directly to AWS (which would slow down the application), the Python app sends the raw telemetry data over localhost to the ADOT sidecar container (`localhost:4317`).

### 4. IAM Permissions & AWS X-Ray
The ADOT sidecar batches the data and securely forwards it to the AWS X-Ray backend API. For this to work, we attached the `AWSXRayDaemonWriteAccess` managed IAM policy to the ECS Task Role (`infra/modules/ecs-service/main.tf`). 

### 5. Visualization
AWS CloudWatch digests these traces, stitches together the matching Trace IDs, and renders the interactive "Service Map" you see in the AWS Console, calculating the end-to-end latency and identifying bottlenecks in the distributed architecture.
