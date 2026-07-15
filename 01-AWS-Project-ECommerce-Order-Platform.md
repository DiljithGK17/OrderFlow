# Project 1 (AWS) — "OrderFlow": Cloud-Native Order Processing Platform

**Target role:** Junior DevOps Engineer — REIZEND (P) Ltd, Technopark
**Build environment:** [KodeKloud AWS Sandbox Playground](https://kodekloud.com/cloud-playgrounds/aws) (session-based, ~3 hrs, account recycled after each session)
**Maps to JD requirements:** ECS, Fargate, DynamoDB, SNS, CloudWatch, Prometheus, Grafana, Loki, ALB, API Gateway, NGINX, IAM, Security Groups, GitHub Actions (full CI **and** CD), Terraform, EC2 troubleshooting, Kubernetes (via small EKS demo)

> **Two important adaptations made for this build environment, explained in full in Section 0:**
> 1. **No Jenkins anywhere** — GitHub Actions handles both CI and CD, including manual approval gates via GitHub Environments.
> 2. **Sandbox-adapted architecture** — built against the **default VPC** (no custom VPC/NAT Gateway/bastion host), because KodeKloud's AWS sandbox doesn't list custom VPC/NAT Gateway as a supported service, blocks `SSM Run Command`, and recycles the whole account at the end of each session. Section 0 explains exactly what changed and why, so you can speak to the *real* enterprise pattern in interviews while explaining *why* you adapted it for a free training sandbox — that distinction itself is a great interview answer.

---

## 0. Sandbox Compatibility Notes (read this first)

Before touching the architecture, here's what was checked against the KodeKloud AWS Sandbox's published service list and limits, and what changed as a result.

### 0.1 What's fully supported, unchanged
ECS (Fargate), ECR, ALB, API Gateway (REST/HTTP, VPC Links, throttling), DynamoDB (PAY_PER_REQUEST only — already our design), SNS, SQS, CloudWatch (logs/metrics/alarms/Container Insights), IAM roles/policies for normal least-privilege task roles, Secrets Manager, KMS, ACM, WAF, Route 53, CloudTrail, AWS Config, AWS Inspector, X-Ray, Application Auto Scaling.

### 0.2 What changed, and why

| Original design | Sandbox issue | What we did instead |
|---|---|---|
| Custom VPC, 2 public + 2 private subnets, NAT Gateway, route tables | NAT Gateway / custom VPC networking isn't in the sandbox's supported-services catalog at all; the sandbox's own setup guide says *"Ensure a default VPC exists, creating one if necessary"* — a strong signal you're meant to build against the **default VPC** | All compute now runs in the **default VPC's public subnets**, locked down with Security Groups instead of network isolation. No NAT Gateway needed since nothing is in a private subnet. |
| Bastion EC2 (SSM-only jump host) into private resources | Existed only to reach private-subnet resources via SSM | **Removed entirely.** With everything in the default public subnet, you reach the `ops-ec2` box directly via SSM Session Manager — no jump host required. |
| Deploy Prometheus/Grafana/Loki stack to `ops-ec2` via `aws ssm send-command` | **`SSM Run Command` is explicitly listed as "Out of Scope"** in the sandbox | Stack is installed via an **EC2 user-data script** at launch instead (arguably the more correct pattern anyway — it's how a real "ops box" AMI/launch template would work). |
| GitHub Actions → AWS via **OIDC** federation (no stored keys) | Creating an IAM OIDC Identity Provider + a custom `AssumeRoleWithWebIdentity` trust policy is the kind of IAM action sandboxes restrict to prevent privilege escalation. **Separately**, the sandbox account is destroyed at the end of every session, so a long-lived OIDC trust relationship has nothing persistent to point at anyway. | For sandbox runs: a **short-lived IAM user** (console-created, access keys added as GitHub Secrets) is used to run the full pipeline live **once per session**, then the keys are revoked before the session ends. The OIDC Terraform config is **still written and included** (Section 8) as the documented "what I'd run in a real, persistent AWS account" version — this is what you actually explain in interviews. |
| Full EKS variant as "extra credit" | EKS in the sandbox is capped hard: 3 nodes, **256 millicores / 512 MiB per pod**, **3 pods per namespace**, 6000m / 12 GiB account-wide | Kept as extra credit, explicitly scoped as a **capability demo** (one tiny Deployment, not a load-bearing cluster) — Section 7. |
| Lambda (Splunk log forwarder, extra credit) | Capped at 256 MB memory / 10s timeout | Still works fine — a log-forwarding function is lightweight enough to fit comfortably. |
| WAF (Web Application Firewall) & Governance (AWS Config, CloudTrail) | Sandbox SCP explicitly denies creating WAF ACLs, CloudTrail trails, or passing roles to Config. | Removed the WAF resources from the `api-gateway` module and entirely removed the `governance` module from the deployment. The API Gateway itself was kept, but its subnets were restricted to avoid `us-east-1c` which lacks VPC Link support. |
| DynamoDB Time-To-Live (TTL) | Sandbox SCP explicitly denies the `dynamodb:UpdateTimeToLive` action. | Disabled the TTL block on the idempotency table. Items will just persist indefinitely during the 3-hour session. |
| IAM Inline Policies | Sandbox SCP explicitly denies `iam:PutRolePolicy` for creating custom inline policies. | Swapped our strict inline least-privilege policies for standard AWS Managed Policies (like `AmazonDynamoDBFullAccess` and `AmazonSQSFullAccess`) using `aws_iam_role_policy_attachment`. |
### 0.3 The single biggest constraint: session time

The sandbox session runs **~3 hours**, and the account is **recycled** afterward — nothing persists. This changes how you should *work*, not just what you build:

- Treat each session as a **rehearsed run**, not exploratory building. Write and test your Terraform/app code locally first (or against the sandbox once to validate), then do a clean, timed `terraform apply` → demo → screenshot/record → `terraform destroy` within one sitting.
- Keep a `Makefile` (Section 4) so the whole stack comes up with one or two commands — you do not want to be hand-typing 40 AWS CLI commands against a ticking clock.
- **Record a short screen capture of the live demo** (Grafana dashboard reacting to load, GitHub Actions pipeline running with an approval gate, a curl against the API) during your one clean session — this becomes your portfolio evidence since the live environment won't be browsable later.
- EKS (if you do the extra-credit variant) takes 12–20 minutes just to provision the control plane — budget for this separately, ideally in its own session, since it eats a large chunk of your 3-hour window on its own.

---

## 1. Why This Project

The JD wants someone who can show **hands-on, end-to-end** ownership of a cloud-native, containerized, observable, automatically-deployed system on AWS — not just "I did a tutorial." OrderFlow is a small but realistic **e-commerce order processing system** that touches every bullet point in the posting, adapted to actually be buildable in a free training sandbox:

| JD Requirement | Where it appears in this project |
|---|---|
| ECS, Fargate | Microservices run as Fargate tasks behind an ALB |
| DynamoDB | Orders, Inventory, Idempotency tables |
| SNS (+ SQS) | Order-events fan-out to Inventory, Notification, Analytics |
| CloudWatch | Logs, metrics, alarms, dashboards |
| Prometheus + Grafana | Custom app metrics scraped via EC2/ECS service discovery |
| Loki | Centralized log aggregation (alternative/companion to CloudWatch Logs) |
| ALB / API Gateway | Public entry point, path-based routing, throttling, auth |
| NGINX reverse proxy | Internal proxy/log-shipper sidecar |
| IAM, Security Groups | Least-privilege task roles, locked-down SGs |
| GitHub Actions | Single tool handling CI (build/test/scan) **and** CD (promote dev→staging→prod with approval gates) |
| Terraform | 100% IaC, no console clicking |
| EC2 troubleshooting | Ops EC2 instance + Security-Group/health-check chaos drills |
| Incident response / RCA | Runbook + chaos drill included |
| *(Added for enterprise depth)* CloudTrail, AWS Config, Inspector, X-Ray, WAF | Audit logging, compliance rules, vulnerability scanning, distributed tracing, edge protection — see Section 7 |

---

## 2. What This Project Actually Is — Plain-English Walkthrough

Before the architecture diagrams, here's the story of the system in plain words, so the diagrams make sense afterward.

**What it does:** OrderFlow is a mini e-commerce backend. A customer (or a test script standing in for one) places an order. The system has to: accept the order, save it, check/update stock, notify someone, and let you (the engineer) watch all of this happen in real time through dashboards and logs — and recover gracefully if something breaks.

There are 3 small independent services, not one big app:
- **order-service** — the front door. Accepts new orders.
- **inventory-service** — reacts to new orders by adjusting stock.
- **notification-service** — reacts to order/inventory events by "notifying" the customer (simulated email/SMS log line).

They never call each other directly. They only talk through **DynamoDB (storage)** and **SNS/SQS (messaging)**. This is the most important design idea in the whole project: it's **event-driven**, not a chain of direct API calls.

### 2.1 End-to-End Process Flow (what happens when one order is placed)

1. **Client sends a request.** A user/Postman/script sends `POST /orders` with order details (e.g., `{customerId, sku, quantity}`) to a public URL.
2. **DNS → API Gateway.** Route 53 resolves the domain (or you hit the API Gateway's default execute-api URL directly — fine for a sandbox session); the request lands on **API Gateway**, which checks the API key and throttling limits (rejects if over the rate limit).
3. **API Gateway → ALB → ECS task.** API Gateway forwards the request over a VPC Link to the **Application Load Balancer**, which looks at the path (`/orders/*`) and routes it to a healthy **order-service** task running on **ECS Fargate** in the default VPC's public subnet.
4. **Inside the task:** the request hits the **NGINX sidecar** first (adds headers, logs the request), which passes it to the **order-service app container**.
5. **order-service does two things, in order:**
   a. Writes a new item into the **DynamoDB `Orders` table** (status = `PENDING`). It also checks the **`Idempotency` table** first — if this exact request was already processed (e.g., the client retried), it returns the existing result instead of creating a duplicate order.
   b. Publishes an `OrderCreated` event to the **SNS topic `order-events`** and immediately returns `201 Created`. **order-service's job is now done** — it does not wait for inventory or notifications to happen.
6. **SNS fans the event out** to every queue subscribed to that topic: `inventory-queue` (filtered to `OrderCreated`/`OrderCancelled`), `notification-queue`, `analytics-queue`. Each queue gets its own independent copy of the message.
7. **inventory-service polls `inventory-queue`** (a long-running ECS task continuously checking for new messages). It reads stock for the SKU, decrements it if available, publishes `InventoryReserved`/`InventoryFailed` back to SNS, and deletes the message only after success. Failed messages retry automatically; after 5 failed attempts they land in the **Dead Letter Queue (DLQ)**, which triggers a CloudWatch alarm.
8. **notification-service polls `notification-queue`** independently, in parallel, and logs a simulated "email sent" message.
9. **Throughout all of this**, every container emits Prometheus metrics on `/metrics` (scraped every 15s), streams logs via the **Fluent Bit sidecar** to both **CloudWatch Logs and Loki**, and is watched by **CloudWatch Alarms** (ALB 5xx rate, DLQ depth, DynamoDB throttling) that fire into the SNS `ops-alerts` topic → Slack — a separate, operational SNS topic from the application's `order-events` topic.
10. **You observe and intervene** via Grafana dashboards and Loki log queries — spotting a DLQ spike, drilling into the exact error, rolling back a bad deploy via GitHub Actions if needed.

### 2.2 Deployment Flow (how code gets from your laptop to running in AWS — all via GitHub Actions)

1. You write code, commit, push to GitHub, open a PR.
2. **GitHub Actions — CI workflow** (`ci.yml`) runs on every PR: lints, runs unit tests, builds the Docker image, scans it with Trivy. Never deploys.
3. **GitHub Actions — CD workflow** (`deploy.yml`) runs on merge to `main`: pushes the image to **ECR**, then deploys to **dev** automatically (`aws ecs update-service`).
4. The **staging** and **prod** deploy jobs each target a **GitHub Environment** with **required reviewers** configured in repo settings — the workflow pauses with a "Review deployments" button until a human approves.
5. A **smoke-test step** runs after each deploy (`curl -f .../healthz`); on failure, a follow-up step redeploys the previous ECS task definition revision automatically.
6. In the sandbox specifically: you run this entire pipeline live, once, during your build session, using a short-lived IAM user's keys as GitHub Secrets (Section 0.2) — then revoke the keys.

### 2.3 One-Paragraph Summary (use this as your interview opener)

"OrderFlow is an event-driven order processing backend on AWS. A client hits an API Gateway/ALB-fronted ECS Fargate service that writes to DynamoDB and publishes an event to SNS; that event fans out to independent SQS-consumer services for inventory and notifications, so each part of the system can fail or scale independently without taking the others down. Everything is provisioned with Terraform, and deployed entirely through GitHub Actions — CI builds, tests, and scans the image, then a CD workflow promotes it through dev, staging, and prod using GitHub Environments with required-reviewer approval gates, with automatic rollback on a failed smoke test. The whole thing is observable through Prometheus/Grafana/Loki, CloudWatch alarms, and X-Ray tracing, with CloudTrail and AWS Config providing an audit/compliance layer. I built it against KodeKloud's AWS sandbox, which meant adapting the networking to the default VPC and validating the GitHub Actions deploy with short-lived credentials, since the sandbox account resets every session — I can also speak to exactly what I'd change for a persistent production AWS account."

---

## 3. Architecture Overview

### 3.1 High-Level Diagram (Sandbox-Adapted Edition)

```
 ══════════════════════════════ EDGE / ENTRY PLANE ══════════════════════════════

   Internet
      │
      ▼
 ┌──────────────┐
 │  Route 53     │  DNS (optional in sandbox — can hit API Gateway's default URL directly)
 └──────┬───────┘
        │
        ▼
 ┌──────────────────────────────┐
 │  WAF (Web ACL)                 │  - rate-based rule, SQLi/XSS managed rule group
 │  attached to API Gateway        │  - blocks before request reaches anything else
 └──────────────┬───────────────┘
                ▼
 ┌──────────────────────────────┐
 │  API Gateway (HTTP API)       │  - API key auth, throttling (100 rps / burst 200)
 │  routes: /orders/*  /inventory/*│
 └──────────────┬───────────────┘
                │  VPC Link
                ▼
 ┌───────────────────────────────┐
 │  Application Load Balancer      │  - DEFAULT VPC public subnets, sits behind sg-alb
 │  (Layer 7, path-based routing)  │  - TLS termination (ACM cert)
 │  /orders/*  → TG-order           │  - health checks on /healthz
 │  /inventory/* → TG-inventory      │
 └───────────┬──────────────┬────┘
             │              │
 ══════════ COMPUTE PLANE (DEFAULT VPC — public subnets, Security-Group isolated) ═══

  ┌──────────────────────────┐   ┌──────────────────────────┐   ┌────────────────────────────┐
  │  ECS Service: order-svc   │   │ ECS Service: inventory-svc│   │ ECS Service: notification-svc│
  │  Task = 4 containers:     │   │  Task = 4 containers:     │   │  Task = 4 containers:        │
  │   1. nginx (sidecar)      │   │   1. nginx (sidecar)      │   │   1. nginx (sidecar)          │
  │   2. order-service (app)  │   │   2. inventory-service     │   │   2. notification-service     │
  │   3. fluent-bit (logs)    │   │   3. fluent-bit (logs)     │   │   3. fluent-bit (logs)        │
  │   4. xray-daemon (traces) │   │   4. xray-daemon (traces)  │   │   4. xray-daemon (traces)     │
  │  assignPublicIp = ENABLED │   │  assignPublicIp = ENABLED  │   │  assignPublicIp = ENABLED     │
  │  desired_count: 2          │   │  desired_count: 2          │   │  desired_count: 2             │
  │  scales on CPU              │   │  scales on SQS queue depth │   │  scales on SQS queue depth    │
  └──────────────┬────────────┘   └──────┬──────────────┬─────┘   └───────────┬──────────────────┘
                 │ publish                │ consume      │ publish              │ consume
                 ▼                        │              ▼                      │
 ══════════ DATA / MESSAGING PLANE ═══════│══════════════│══════════════════════│════════════════

      ┌────────────────────────┐          │     ┌──────────────────────┐        │
      │  SNS Topic               │◄────────┘     │  SNS Topic (same one)  │◄──────┘
      │  "order-events"           │───────┐       │  fan-out continues...   │
      └────────────┬─────────────┘       │       └──────────────────────┘
                   │ fan-out              │
        ┌──────────┼───────────────┐     │
        ▼          ▼               ▼     │
 ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐
 │ SQS:          │ │ SQS:          │ │ SQS:               │
 │ inventory-queue│ │ notification- │ │ analytics-queue     │
 │ (+DLQ, maxRx=5)│ │ queue (+DLQ)   │ │ (+DLQ) → S3          │
 └─────────────┘ └──────────────┘ └──────────────────┘
      ┌────────────────────────────────────────────────┐
      │   DynamoDB (PAY_PER_REQUEST — sandbox requirement)│
      │   • Orders        (PK orderId, GSI customerId)    │
      │   • Inventory     (PK sku)                          │
      │   • Idempotency   (PK requestId, TTL enabled)        │
      └────────────────────────────────────────────────┘

 ══════════ OBSERVABILITY & TRACING PLANE ════════════════════════════════════════

  Each ECS task's fluent-bit sidecar  ──┬──► CloudWatch Logs (per-service log group)
                                        └──► Loki (via Promtail/Fluent Bit output plugin)

  Each ECS task's xray-daemon sidecar ──► AWS X-Ray (distributed trace: API GW → ALB →
                                            order-service → SNS → SQS → inventory-service)

  Each app container's /metrics  ──► Prometheus (runs on "ops-ec2" instance, scrapes via
                                      EC2 Service Discovery tags every 15s)

  Prometheus + CloudWatch  ──► Grafana (dashboards: Golden Signals, Queue Health)
  Prometheus alert rules   ──► Alertmanager ──► Slack
  CloudWatch Alarms (5xx rate, DLQ depth, DynamoDB throttle) ──► SNS "ops-alerts" topic ──► Slack

 ══════════ GOVERNANCE & SECURITY PLANE (new — enterprise depth) ═════════════════

  CloudTrail   : every API call in this account logged to an S3 bucket (who changed what, when)
  AWS Config   : configuration recorder + rules (e.g. "S3 buckets must not be public",
                 "EBS volumes must be encrypted") — continuous compliance checking
  AWS Inspector: scans ECR images + the ops-ec2 instance for known vulnerabilities
  WAF          : sits in front of API Gateway (see Edge plane above)
  Secrets Manager + KMS : DB/app secrets and encryption keys, never in plaintext config

 ══════════ NETWORKING / SECURITY (DEFAULT VPC) ══════════════════════════════════

  Default VPC (sandbox-provided, e.g. 172.31.0.0/16)
   └─ Default public subnets across 2+ AZs → ALB, ECS tasks (public IP), ops-ec2
      (no private subnets, no NAT Gateway, no bastion — all isolation done via Security Groups)

  Security Groups:
   sg-alb      : in 443/80 from 0.0.0.0/0      | out → sg-ecs only
   sg-ecs      : in container port from sg-alb  | out → 443 (ECR/DynamoDB/SNS/SQS over public AWS endpoints)
   sg-ops-ec2  : no inbound at all (SSM Session Manager only) | in 9090/3000/3100 from your IP via SSM port-forward

  IAM:
   - ecsTaskExecutionRole  : ECR pull, CloudWatch Logs write only
   - order-service-task-role     : dynamodb:PutItem/GetItem on Orders+Idempotency, sns:Publish on order-events
   - inventory-service-task-role : dynamodb:GetItem/UpdateItem on Inventory, sqs:ReceiveMessage/DeleteMessage on inventory-queue
   - notification-service-task-role : sqs:ReceiveMessage/DeleteMessage on notification-queue
   - github-actions-deploy (sandbox)  : short-lived IAM user, scoped policy, keys revoked post-session
   - github-actions-deploy-role (real account, documented) : OIDC-federated role, no static keys — Section 8.6

 ══════════ CI/CD PLANE (GitHub Actions only) ════════════════════════════════════

  GitHub PR  → ci.yml    : lint → unit test → docker build → trivy scan
  Merge main → deploy.yml: build → push to ECR → deploy:dev (auto)
                            → deploy:staging (waits for Environment approval) → smoke test
                            → deploy:prod    (waits for Environment approval) → smoke test
                            → rollback step runs automatically if smoke test fails
```

### 3.2 Why the diagram is laid out this way (talking points)

- **Edge plane** now has **WAF in front of API Gateway** — the first thing a security-minded interviewer looks for, and a genuine upgrade over the original design.
- **Compute plane** shows each ECS task has **4 containers** (app, NGINX sidecar, Fluent Bit, X-Ray daemon) — explain this proactively; it's a deliberate "sidecar pattern" choice most juniors don't think to add.
- **No private subnets** is called out explicitly and tied back to *why* (sandbox constraint) — this is exactly the kind of trade-off conversation interviewers want to see you navigate, not hide.
- **Governance & Security plane** is new — CloudTrail/Config/Inspector turn this from "a working demo" into "something I'd be comfortable calling production-adjacent," which is a strong signal for a junior candidate.
- **CI/CD plane** is unchanged in shape from before — still 100% GitHub Actions — but Section 0 explains exactly how its credentials are handled differently in a sandbox vs. a real account.

---

## 4. Repository Structure

```
orderflow/
│
├── infra/                                  # ── Terraform (all infrastructure as code) ──
│   ├── envs/
│   │   ├── dev/
│   │   │   ├── backend.tf                  # remote state config (S3 + DynamoDB lock) for dev
│   │   │   ├── main.tf                     # wires together all modules for dev
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars            # dev-specific values (small instance sizes)
│   │   ├── staging/                        # same file shape as dev, staging-specific values
│   │   └── prod/                           # same file shape as dev, prod-specific values
│   └── modules/                            # reusable building blocks, environment-agnostic
│       ├── default-vpc-lookup/             # data sources only — reads the sandbox's default VPC/subnets
│       ├── security/                       # security_groups.tf (no vpc_endpoints.tf — not needed without NAT)
│       ├── iam/                            # task_roles.tf, github_actions_user.tf (sandbox), github_oidc.tf (real-account reference)
│       ├── ecs-cluster/                    # cluster.tf, capacity_providers.tf
│       ├── ecs-service/                    # task_definition.tf, service.tf, autoscaling.tf (reused 3x)
│       ├── alb/                            # alb.tf, target_groups.tf, listeners.tf
│       ├── api-gateway/                    # http_api.tf, vpc_link.tf, usage_plan.tf, waf_association.tf
│       ├── dynamodb/                       # tables.tf (Orders, Inventory, Idempotency)
│       ├── sns-sqs/                        # topic.tf, queues.tf, subscriptions.tf, dlq.tf
│       ├── observability/                  # log_groups.tf, cw_alarms.tf, ops_ec2.tf (user-data installs Prometheus/Grafana/Loki)
│       └── governance/                     # cloudtrail.tf, aws_config.tf, inspector.tf — NEW
│
├── services/                                # ── Application source code, one folder per microservice ──
│   ├── order-service/
│   │   ├── src/                            # app code (routes, db client, sns publisher)
│   │   ├── tests/                          # unit tests
│   │   ├── Dockerfile                      # multi-stage build, non-root user
│   │   ├── requirements.txt / package.json
│   │   └── README.md                       # what this service does, env vars it needs
│   ├── inventory-service/                  # same shape as order-service
│   └── notification-service/               # same shape as order-service
│
├── nginx/                                   # ── Reverse-proxy sidecar shared across all 3 services ──
│   └── nginx.conf                          # adds security headers, access logging, proxies to app port
│
├── monitoring/                              # ── Observability configuration (deployed via ops-ec2 user-data) ──
│   ├── ops-ec2-userdata.sh                 # NEW — installs Docker, writes compose file, starts the stack at boot
│   ├── prometheus/prometheus.yml           # scrape configs, EC2 service discovery
│   ├── grafana/
│   │   ├── dashboards/golden-signals.json
│   │   ├── dashboards/queue-health.json
│   │   └── provisioning/                   # datasources.yml (Prometheus + CloudWatch)
│   ├── loki/loki-config.yaml
│   ├── fluent-bit/fluent-bit.conf          # dual output: CloudWatch + Loki
│   └── alertmanager/alertmanager.yml
│
├── .github/
│   └── workflows/
│       ├── ci.yml                          # PR: lint, test, build, trivy scan (no deploy)
│       └── deploy.yml                      # main: build→ECR→dev→staging(approval)→prod(approval)
│
├── runbooks/
│   └── INCIDENT-RUNBOOK.md                 # health-check steps, rollback steps, escalation path
│
├── docs/
│   ├── architecture-diagram.png            # exported version of the ASCII diagram above
│   └── kodekloud-sandbox-notes.md          # this doc's Section 0, kept as a standalone quick-reference too
│
├── Makefile                                 # make up / make down / make seed-data / make demo-record
└── README.md
```

**Why this structure:** the `infra/modules/default-vpc-lookup` module replaces what used to be a `networking` module — instead of *creating* VPC resources, it just *reads* the sandbox-provided default VPC/subnets via Terraform data sources, so the rest of your modules (`alb`, `ecs-service`, `observability`) consume `data.aws_vpc.default.id` and `data.aws_subnets.default.ids` exactly the way they'd consume a custom VPC's outputs in a real account — meaning **almost no other module needs to change** if you later point this whole repo at a real AWS account with a proper custom VPC. That's a deliberate design choice worth explaining in interviews: *the blast radius of "I had to adapt for a sandbox" is contained to one small module.*

---

## 5. Build From Scratch — Detailed Step-by-Step

### Phase 0 — Local Setup & Prerequisites

1. **Install tooling:**
   ```bash
   brew install awscli terraform docker jq git
   curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sm.zip"
   unzip sm.zip && sudo ./sessionmanager-bundle/install
   ```
2. **Launch the KodeKloud AWS Sandbox** and copy the temporary Access Key ID / Secret Access Key / Session Token it gives you into your terminal:
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...
   export AWS_DEFAULT_REGION=us-east-1   # sandbox-supported region
   aws sts get-caller-identity   # sanity check
   ```
3. **Confirm the default VPC exists** (the sandbox guide says to create one if it doesn't — usually it already does):
   ```bash
   aws ec2 describe-vpcs --filters "Name=is-default,Values=true"
   # if empty:
   aws ec2 create-default-vpc
   ```
4. **Create the Terraform remote state backend** (S3 + DynamoDB are both supported services, so this still works the same as a normal account — just remember it's destroyed with everything else at session end, which is fine, you'll recreate it next session):
   ```bash
   aws s3api create-bucket --bucket orderflow-tfstate-<your-unique-id> --region us-east-1
   aws s3api put-bucket-versioning --bucket orderflow-tfstate-<your-unique-id> --versioning-configuration Status=Enabled
   aws dynamodb create-table \
     --table-name orderflow-tf-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```
5. **Wire the backend into Terraform** (`infra/envs/dev/backend.tf`):
   ```hcl
   terraform {
     backend "s3" {
       bucket         = "orderflow-tfstate-<your-unique-id>"
       key            = "dev/terraform.tfstate"
       region         = "us-east-1"
       dynamodb_table = "orderflow-tf-lock"
       encrypt        = true
     }
   }
   ```

### Phase 1 — Networking: Read (Not Create) the Default VPC

This whole phase replaces what would normally be "create a VPC, subnets, IGW, NAT, route tables." In the sandbox, none of that — we just **look up** what already exists.

```hcl
# infra/modules/default-vpc-lookup/main.tf
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

output "vpc_id"      { value = data.aws_vpc.default.id }
output "subnet_ids"  { value = data.aws_subnets.default.ids }
```

**Apply and verify:**
```bash
cd infra/envs/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output subnet_ids
```

**Troubleshooting exercise to do and document (replaces the old NAT-Gateway drill):** intentionally misconfigure a Security Group (e.g., remove the ALB→ECS allow rule), `terraform apply`, then try to curl the ALB and watch the request hang/fail with a timeout (not a clean error — this is itself a teaching point: SG blocks look like a black hole, not a 4xx). Use this to practice and write up: "How do I tell a Security Group problem apart from a health-check problem apart from an application bug?" Fix it, reapply, confirm. This becomes your `runbooks/` RCA entry.

### Phase 2 — Security Foundations (`infra/modules/security`, `infra/modules/iam`)

1. **Security Groups** — this is now doing the isolation job the private-subnet/NAT design used to do, so be extra deliberate about it:
   ```hcl
   resource "aws_security_group" "alb" {
     name   = "orderflow-alb-sg"
     vpc_id = data.aws_vpc.default.id
     ingress {
       from_port = 443; to_port = 443; protocol = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
     }
     egress {
       from_port = 0; to_port = 0; protocol = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }
   }

   resource "aws_security_group" "ecs" {
     name   = "orderflow-ecs-sg"
     vpc_id = data.aws_vpc.default.id
     ingress {
       from_port       = 8080; to_port = 8080; protocol = "tcp"
       security_groups = [aws_security_group.alb.id]   # ONLY the ALB can reach ECS tasks
     }
     egress {
       from_port = 0; to_port = 0; protocol = "-1"
       cidr_blocks = ["0.0.0.0/0"]    # tasks have public IPs (no NAT), so egress goes straight out
     }
   }

   resource "aws_security_group" "ops_ec2" {
     name   = "orderflow-ops-ec2-sg"
     vpc_id = data.aws_vpc.default.id
     # NO ingress rules at all — reached only via SSM Session Manager, never via a listening port from the internet
     egress {
       from_port = 0; to_port = 0; protocol = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }
   }
   ```
   *(Compare this with the original NAT-based design when you talk about it in interviews: "in a real account I'd put ECS tasks in private subnets behind a NAT Gateway with no public IP at all; in this sandbox, since NAT Gateway/custom VPC isn't supported, the same isolation goal — only the ALB can initiate a connection to the app — is achieved purely through Security Group rules instead of network topology. The security *outcome* is similar; the *mechanism* is different.")*
2. **IAM — ECS Task Execution Role** (unchanged from before — pulls images, writes logs):
   ```hcl
   resource "aws_iam_role" "ecs_task_execution" {
     name = "orderflow-ecs-task-execution"
     assume_role_policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{
         Action = "sts:AssumeRole"; Effect = "Allow"
         Principal = { Service = "ecs-tasks.amazonaws.com" }
       }]
     })
   }
   resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
     role       = aws_iam_role.ecs_task_execution.name
     policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
   }
   ```
3. **IAM — per-service Task Role**, identical least-privilege pattern as before (this part of IAM works the same in the sandbox as a real account — it's only OIDC trust-policy creation that's restricted, not normal scoped task roles):
   ```hcl
   resource "aws_iam_role" "order_service_task" {
     name = "orderflow-order-service-task"
     assume_role_policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "ecs-tasks.amazonaws.com" } }]
     })
   }

   resource "aws_iam_role_policy" "order_service_permissions" {
     name = "order-service-least-privilege"
     role = aws_iam_role.order_service_task.id
     policy = jsonencode({
       Version = "2012-10-17"
       Statement = [
         { Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"],
           Resource = [aws_dynamodb_table.orders.arn, aws_dynamodb_table.idempotency.arn] },
         { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.order_events.arn },
         { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
       ]
     })
   }
   ```
   Repeat for `inventory-service` (Inventory table + `inventory-queue`) and `notification-service` (`notification-queue` only). Never reuse one wildcard role across all three.

### Phase 3 — Data Layer (`infra/modules/dynamodb`)

Unchanged from the original design — DynamoDB works identically in the sandbox, with the one constraint already baked into our design: **PAY_PER_REQUEST only**.

```hcl
resource "aws_dynamodb_table" "orders" {
  name         = "orderflow-orders-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute { name = "orderId";    type = "S" }
  attribute { name = "customerId"; type = "S" }
  attribute { name = "status";     type = "S" }

  global_secondary_index {
    name            = "customerId-status-index"
    hash_key        = "customerId"
    range_key       = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery { enabled = true }
}

resource "aws_dynamodb_table" "inventory" {
  name         = "orderflow-inventory-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sku"
  attribute { name = "sku"; type = "S" }
}

resource "aws_dynamodb_table" "idempotency" {
  name         = "orderflow-idempotency-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "requestId"
  attribute { name = "requestId"; type = "S" }
  ttl { attribute_name = "expiresAt"; enabled = true }
}
```

**Apply and seed test data:**
```bash
terraform apply
aws dynamodb put-item --table-name orderflow-inventory-dev \
  --item '{"sku": {"S": "SKU-001"}, "stock": {"N": "100"}}'
```

### Phase 4 — Messaging (`infra/modules/sns-sqs`)

Unchanged from the original design — SNS/SQS are fully supported with no sandbox-specific limits called out.

```hcl
resource "aws_sns_topic" "order_events" {
  name = "orderflow-order-events-${var.env}"
}

resource "aws_sqs_queue" "inventory_dlq" {
  name = "orderflow-inventory-dlq-${var.env}"
}

resource "aws_sqs_queue" "inventory_queue" {
  name                       = "orderflow-inventory-queue-${var.env}"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.inventory_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "inventory_queue_policy" {
  queue_url = aws_sqs_queue.inventory_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "sns.amazonaws.com" }, Action = "sqs:SendMessage"
      Resource = aws_sqs_queue.inventory_queue.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_events.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "inventory" {
  topic_arn            = aws_sns_topic.order_events.arn
  protocol              = "sqs"
  endpoint              = aws_sqs_queue.inventory_queue.arn
  raw_message_delivery  = true
  filter_policy = jsonencode({ eventType = ["OrderCreated", "OrderCancelled"] })
}

resource "aws_cloudwatch_metric_alarm" "inventory_dlq_not_empty" {
  alarm_name          = "orderflow-inventory-dlq-has-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  dimensions          = { QueueName = aws_sqs_queue.inventory_dlq.name }
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}
```
*(Repeat the queue+DLQ+subscription block for `notification-queue` and `analytics-queue`.)*

### Phase 5 — Application Services (`services/`)

1. **order-service core logic**, now also instrumented for X-Ray:
   ```python
   # services/order-service/src/main.py
   from fastapi import FastAPI, Request
   import boto3, uuid, time
   from prometheus_client import Counter, Histogram, make_asgi_app
   from aws_xray_sdk.core import xray_recorder, patch_all

   patch_all()   # auto-instruments boto3 calls for X-Ray tracing

   app = FastAPI()
   app.mount("/metrics", make_asgi_app())

   dynamodb = boto3.resource("dynamodb")
   orders_table = dynamodb.Table("orderflow-orders-dev")
   idempotency_table = dynamodb.Table("orderflow-idempotency-dev")
   sns = boto3.client("sns")

   ORDERS_CREATED = Counter("orders_created_total", "Total orders created")
   REQUEST_LATENCY = Histogram("order_request_latency_seconds", "Order request latency")

   @app.get("/healthz")
   def healthz():
       return {"status": "ok"}

   @app.post("/orders")
   @xray_recorder.capture("create_order")
   def create_order(payload: dict, request: Request):
       request_id = request.headers.get("Idempotency-Key", str(uuid.uuid4()))

       existing = idempotency_table.get_item(Key={"requestId": request_id}).get("Item")
       if existing:
           return {"orderId": existing["orderId"], "status": "duplicate-ignored"}

       order_id = str(uuid.uuid4())
       with REQUEST_LATENCY.time():
           orders_table.put_item(Item={
               "orderId": order_id, "customerId": payload["customerId"],
               "sku": payload["sku"], "quantity": payload["quantity"],
               "status": "PENDING", "createdAt": int(time.time())
           })
           idempotency_table.put_item(Item={
               "requestId": request_id, "orderId": order_id,
               "expiresAt": int(time.time()) + 86400
           })
           sns.publish(
               TopicArn="arn:aws:sns:us-east-1:<account-id>:orderflow-order-events-dev",
               Message=str({"orderId": order_id, "sku": payload["sku"], "quantity": payload["quantity"]}),
               MessageAttributes={"eventType": {"DataType": "String", "StringValue": "OrderCreated"}}
           )
       ORDERS_CREATED.inc()
       return {"orderId": order_id, "status": "PENDING"}
   ```
2. **Dockerfile** (multi-stage, non-root, unchanged from original design):
   ```dockerfile
   FROM python:3.12-slim AS builder
   WORKDIR /app
   COPY requirements.txt .
   RUN pip install --no-cache-dir --target=/install -r requirements.txt

   FROM python:3.12-slim
   RUN useradd -m appuser
   WORKDIR /app
   COPY --from=builder /install /usr/local/lib/python3.12/site-packages
   COPY src/ .
   USER appuser
   EXPOSE 8080
   HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:8080/healthz || exit 1
   CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
   ```
3. **inventory-service** consumer loop (unchanged):
   ```python
   # services/inventory-service/src/consumer.py
   import boto3, json, time

   sqs = boto3.client("sqs")
   dynamodb = boto3.resource("dynamodb")
   inventory_table = dynamodb.Table("orderflow-inventory-dev")
   QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/<account-id>/orderflow-inventory-queue-dev"

   def poll():
       while True:
           resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=10)
           for msg in resp.get("Messages", []):
               body = json.loads(msg["Body"])
               item = inventory_table.get_item(Key={"sku": body["sku"]}).get("Item")
               if item and item["stock"] >= body["quantity"]:
                   inventory_table.update_item(
                       Key={"sku": body["sku"]},
                       UpdateExpression="SET stock = stock - :q",
                       ExpressionAttributeValues={":q": body["quantity"]}
                   )
               sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
           time.sleep(1)

   if __name__ == "__main__":
       poll()
   ```
4. **NGINX sidecar config** (`nginx/nginx.conf`, unchanged):
   ```nginx
   server {
       listen 80;
       location / {
           proxy_pass http://127.0.0.1:8080;
           proxy_set_header X-Real-IP $remote_addr;
           add_header X-Frame-Options "DENY";
           access_log /var/log/nginx/access.log;
       }
   }
   ```
5. **Build and test locally before touching AWS:**
   ```bash
   cd services/order-service
   docker build -t order-service:local .
   docker run -p 8080:8080 order-service:local
   curl http://localhost:8080/healthz
   ```

### Phase 6 — ECS Cluster & Services (`infra/modules/ecs-cluster`, `infra/modules/ecs-service`)

1. **ECS Cluster:**
   ```hcl
   resource "aws_ecs_cluster" "this" {
     name = "orderflow-${var.env}"
     setting { name = "containerInsights"; value = "enabled" }
   }

   resource "aws_ecs_cluster_capacity_providers" "this" {
     cluster_name       = aws_ecs_cluster.this.name
     capacity_providers = ["FARGATE", "FARGATE_SPOT"]
   }
   ```
2. **ECR repository:**
   ```hcl
   resource "aws_ecr_repository" "order_service" {
     name = "orderflow/order-service"
     image_scanning_configuration { scan_on_push = true }
   }
   ```
3. **Task Definition** — now **4 containers** per task (app, nginx, fluent-bit, **X-Ray daemon**), and **`assign_public_ip = ENABLED`** since there's no NAT to route private-subnet egress through:
   ```hcl
   resource "aws_ecs_task_definition" "order_service" {
     family                   = "order-service"
     requires_compatibilities = ["FARGATE"]
     network_mode             = "awsvpc"
     cpu                      = "512"
     memory                   = "1024"
     execution_role_arn       = aws_iam_role.ecs_task_execution.arn
     task_role_arn            = aws_iam_role.order_service_task.arn

     container_definitions = jsonencode([
       {
         name = "order-service"
         image = "${aws_ecr_repository.order_service.repository_url}:latest"
         essential = true
         portMappings = [{ containerPort = 8080, protocol = "tcp" }]
         environment = [{ name = "AWS_XRAY_DAEMON_ADDRESS", value = "127.0.0.1:2000" }]
         logConfiguration = { logDriver = "awsfirelens" }
       },
       {
         name = "nginx"
         image = "nginx:1.27-alpine"
         essential = true
         portMappings = [{ containerPort = 80, protocol = "tcp" }]
       },
       {
         name = "log-router"
         image = "amazon/aws-for-fluent-bit:stable"
         essential = true
         firelensConfiguration = { type = "fluentbit" }
       },
       {
         name = "xray-daemon"
         image = "amazon/aws-xray-daemon:latest"
         essential = false
         portMappings = [{ containerPort = 2000, protocol = "udp" }]
       }
     ])
   }
   ```
4. **ECS Service** — `assign_public_ip = "ENABLED"` is the key sandbox-specific change here:
   ```hcl
   resource "aws_ecs_service" "order_service" {
     name            = "order-service"
     cluster         = aws_ecs_cluster.this.id
     task_definition = aws_ecs_task_definition.order_service.arn
     desired_count   = 2
     launch_type     = "FARGATE"

     network_configuration {
       subnets          = data.aws_subnets.default.ids
       security_groups  = [aws_security_group.ecs.id]
       assign_public_ip = "ENABLED"     # required: no NAT Gateway in the sandbox to route private egress
     }

     load_balancer {
       target_group_arn = aws_lb_target_group.order_service.arn
       container_name    = "nginx"
       container_port    = 80
     }

     deployment_minimum_healthy_percent = 100
     deployment_maximum_percent         = 200
     deployment_circuit_breaker { enable = true; rollback = true }
   }

   resource "aws_appautoscaling_target" "order_service" {
     max_capacity       = 4   # kept modest given sandbox account-wide resource caps
     min_capacity        = 2
     resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.order_service.name}"
     scalable_dimension = "ecs:service:DesiredCount"
     service_namespace  = "ecs"
   }

   resource "aws_appautoscaling_policy" "order_service_cpu" {
     name               = "cpu-target-tracking"
     policy_type        = "TargetTrackingScaling"
     resource_id        = aws_appautoscaling_target.order_service.resource_id
     scalable_dimension = aws_appautoscaling_target.order_service.scalable_dimension
     service_namespace  = aws_appautoscaling_target.order_service.service_namespace
     target_tracking_scaling_policy_configuration {
       target_value = 60.0
       predefined_metric_specification { predefined_metric_type = "ECSServiceAverageCPUUtilization" }
     }
   }
   ```
5. **ALB + Target Group:**
   ```hcl
   resource "aws_lb" "this" {
     name               = "orderflow-alb"
     internal           = false
     load_balancer_type = "application"
     subnets            = data.aws_subnets.default.ids
     security_groups    = [aws_security_group.alb.id]
   }

   resource "aws_lb_target_group" "order_service" {
     name        = "order-service-tg"
     port        = 80
     protocol    = "HTTP"
     vpc_id      = data.aws_vpc.default.id
     target_type = "ip"
     health_check { path = "/healthz"; interval = 15; healthy_threshold = 2; unhealthy_threshold = 3 }
   }

   resource "aws_lb_listener_rule" "order_service" {
     listener_arn = aws_lb_listener.https.arn
     priority     = 10
     condition { path_pattern { values = ["/orders/*"] } }
     action { type = "forward"; target_group_arn = aws_lb_target_group.order_service.arn }
   }
   ```
6. **API Gateway in front of the ALB via VPC Link, with WAF attached:**
   ```hcl
   resource "aws_apigatewayv2_vpc_link" "this" {
     name               = "orderflow-vpc-link"
     subnet_ids         = data.aws_subnets.default.ids
     security_group_ids = [aws_security_group.ecs.id]
   }

   resource "aws_apigatewayv2_api" "this" {
     name          = "orderflow-api"
     protocol_type = "HTTP"
   }

   resource "aws_apigatewayv2_integration" "alb" {
     api_id             = aws_apigatewayv2_api.this.id
     integration_type   = "HTTP_PROXY"
     integration_uri    = aws_lb_listener.https.arn
     connection_type    = "VPC_LINK"
     connection_id      = aws_apigatewayv2_vpc_link.this.id
     integration_method = "ANY"
   }

   resource "aws_apigatewayv2_route" "orders" {
     api_id    = aws_apigatewayv2_api.this.id
     route_key = "ANY /orders/{proxy+}"
     target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
   }

   resource "aws_apigatewayv2_stage" "this" {
     api_id      = aws_apigatewayv2_api.this.id
     name        = "$default"
     auto_deploy = true
     default_route_settings {
       throttling_rate_limit  = 100
       throttling_burst_limit = 200
     }
   }

   resource "aws_wafv2_web_acl" "api" {
     name  = "orderflow-api-waf"
     scope = "REGIONAL"
     default_action { allow {} }

     rule {
       name     = "rate-limit"
       priority = 1
       action { block {} }
       statement {
         rate_based_statement { limit = 2000; aggregate_key_type = "IP" }
       }
       visibility_config { sampled_requests_enabled = true; cloudwatch_metrics_enabled = true; metric_name = "rate-limit" }
     }

     visibility_config { sampled_requests_enabled = true; cloudwatch_metrics_enabled = true; metric_name = "orderflow-api-waf" }
   }

   resource "aws_wafv2_web_acl_association" "api" {
     resource_arn = aws_apigatewayv2_stage.this.arn
     web_acl_arn  = aws_wafv2_web_acl.api.arn
   }
   ```
7. **Apply and smoke test:**
   ```bash
   terraform apply
   curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/orders \
     -H "Content-Type: application/json" \
     -d '{"customerId":"cust-1","sku":"SKU-001","quantity":2}'
   ```

### Phase 7 — Observability (`infra/modules/observability`)

1. **CloudWatch alarms** (unchanged pattern):
   ```hcl
   resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
     alarm_name          = "orderflow-alb-high-5xx-rate"
     comparison_operator = "GreaterThanThreshold"
     evaluation_periods  = 2
     metric_name         = "HTTPCode_Target_5XX_Count"
     namespace           = "AWS/ApplicationELB"
     period              = 60
     statistic           = "Sum"
     threshold           = 10
     dimensions          = { LoadBalancer = aws_lb.this.arn_suffix }
     alarm_actions       = [aws_sns_topic.ops_alerts.arn]
   }
   ```
2. **ops-ec2 instance, with the monitoring stack installed via user-data instead of SSM Run Command:**
   ```hcl
   resource "aws_instance" "ops" {
     ami                    = data.aws_ami.amazon_linux_2023.id
     instance_type          = "t3.small"
     subnet_id              = data.aws_subnets.default.ids[0]
     vpc_security_group_ids = [aws_security_group.ops_ec2.id]
     iam_instance_profile   = aws_iam_instance_profile.ops_ec2.name
     user_data              = file("${path.module}/../../../monitoring/ops-ec2-userdata.sh")
     tags = { Name = "orderflow-ops-ec2", Service = "observability" }
   }
   ```
   ```bash
   # monitoring/ops-ec2-userdata.sh — runs automatically at instance launch, no SSM Run Command needed
   #!/bin/bash
   set -e
   yum update -y
   yum install -y docker
   systemctl enable docker && systemctl start docker
   curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
     -o /usr/local/bin/docker-compose
   chmod +x /usr/local/bin/docker-compose

   mkdir -p /opt/monitoring
   cat > /opt/monitoring/docker-compose.yml << 'EOF'
   services:
     prometheus:
       image: prom/prometheus:v2.54.0
       volumes: ["/opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml"]
       ports: ["9090:9090"]
     grafana:
       image: grafana/grafana:11.1.0
       ports: ["3000:3000"]
     loki:
       image: grafana/loki:3.1.0
       ports: ["3100:3100"]
   EOF
   # prometheus.yml is copied up separately via `aws s3 cp` from your Terraform-managed bucket,
   # or embedded inline here with a heredoc for a fully self-contained launch.
   cd /opt/monitoring && /usr/local/bin/docker-compose up -d
   ```
3. **Access Grafana via SSM port-forwarding** (no public IP/listening port needed — this is the SSM capability that IS supported, unlike Run Command):
   ```bash
   aws ssm start-session --target <ops-ec2-instance-id> \
     --document-name AWS-StartPortForwardingSession \
     --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
   # then open http://localhost:3000
   ```
4. **Grafana dashboards** — import the two JSON files in `monitoring/grafana/dashboards/`, add Prometheus + CloudWatch as data sources.
5. **X-Ray verification:** after a few requests flow through, check the trace map:
   ```bash
   aws xray get-service-graph --start-time $(date -u -d '10 minutes ago' +%s) --end-time $(date -u +%s)
   ```
   In the console, X-Ray's Service Map should visually show `API Gateway → ALB → order-service → SNS → SQS → inventory-service` as connected nodes with latency annotations — a genuinely impressive thing to screenshot for your portfolio.

### Phase 8 — CI/CD (GitHub Actions only — both CI and CD)

1. **CI workflow — runs on every PR, never deploys** (`.github/workflows/ci.yml`):
   ```yaml
   name: CI
   on: pull_request

   jobs:
     build-test-scan:
       runs-on: ubuntu-latest
       strategy:
         matrix: { service: [order-service, inventory-service, notification-service] }
       steps:
         - uses: actions/checkout@v4
         - name: Lint & unit test
           run: |
             cd services/${{ matrix.service }}
             pip install -r requirements.txt
             pytest tests/
         - name: Build Docker image
           run: docker build -t ${{ matrix.service }}:ci -f services/${{ matrix.service }}/Dockerfile services/${{ matrix.service }}
         - name: Scan image with Trivy
           uses: aquasecurity/trivy-action@master
           with:
             image-ref: "${{ matrix.service }}:ci"
             severity: "CRITICAL,HIGH"
             exit-code: "1"
   ```
2. **CD workflow for the sandbox session** — uses short-lived IAM user keys stored as GitHub Secrets (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`), **not OIDC**, because the sandbox account won't exist tomorrow for an OIDC trust to point at:
   ```yaml
   name: Deploy (sandbox session)
   on:
     push: { branches: [main] }

   jobs:
     build-and-push:
       runs-on: ubuntu-latest
       outputs: { image_tag: ${{ steps.tag.outputs.tag }} }
       steps:
         - uses: actions/checkout@v4
         - id: tag
           run: echo "tag=${GITHUB_SHA::8}" >> "$GITHUB_OUTPUT"
         - uses: aws-actions/configure-aws-credentials@v4
           with:
             aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
             aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
             aws-region: us-east-1
         - run: aws ecr get-login-password | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
         - run: |
             docker build -t order-service:${{ steps.tag.outputs.tag }} services/order-service
             docker tag order-service:${{ steps.tag.outputs.tag }} <account-id>.dkr.ecr.us-east-1.amazonaws.com/orderflow/order-service:${{ steps.tag.outputs.tag }}
             docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/orderflow/order-service:${{ steps.tag.outputs.tag }}

     deploy-dev:
       needs: build-and-push
       runs-on: ubuntu-latest
       environment: dev
       steps:
         - uses: aws-actions/configure-aws-credentials@v4
           with: { aws-access-key-id: "${{ secrets.AWS_ACCESS_KEY_ID }}", aws-secret-access-key: "${{ secrets.AWS_SECRET_ACCESS_KEY }}", aws-region: us-east-1 }
         - run: aws ecs update-service --cluster orderflow-dev --service order-service --force-new-deployment
         - name: Smoke test
           run: curl -f https://<api-id>.execute-api.us-east-1.amazonaws.com/orders/healthz

     deploy-staging:
       needs: deploy-dev
       runs-on: ubuntu-latest
       environment: staging      # GitHub Environment with required reviewers — configured in repo Settings
       steps:
         - uses: aws-actions/configure-aws-credentials@v4
           with: { aws-access-key-id: "${{ secrets.AWS_ACCESS_KEY_ID }}", aws-secret-access-key: "${{ secrets.AWS_SECRET_ACCESS_KEY }}", aws-region: us-east-1 }
         - run: aws ecs update-service --cluster orderflow-staging --service order-service --force-new-deployment
         - name: Smoke test
           id: smoke
           run: curl -f https://<api-id>.execute-api.us-east-1.amazonaws.com/orders/healthz
         - name: Rollback on failure
           if: failure() && steps.smoke.outcome == 'failure'
           run: |
             PREV=$(aws ecs describe-services --cluster orderflow-staging --services order-service \
               --query 'services[0].deployments[1].taskDefinition' --output text)
             aws ecs update-service --cluster orderflow-staging --service order-service --task-definition $PREV

     deploy-prod:
       needs: deploy-staging
       runs-on: ubuntu-latest
       environment: prod          # also requires reviewer approval, configured separately from staging
       steps:
         - uses: aws-actions/configure-aws-credentials@v4
           with: { aws-access-key-id: "${{ secrets.AWS_ACCESS_KEY_ID }}", aws-secret-access-key: "${{ secrets.AWS_SECRET_ACCESS_KEY }}", aws-region: us-east-1 }
         - run: aws ecs update-service --cluster orderflow-prod --service order-service --force-new-deployment
         - name: Smoke test
           run: curl -f https://<api-id>.execute-api.us-east-1.amazonaws.com/orders/healthz
   ```
3. **Create the short-lived IAM user for this session only:**
   ```bash
   aws iam create-user --user-name github-actions-deploy-session
   aws iam put-user-policy --user-name github-actions-deploy-session --policy-name deploy-policy --policy-document file://github-actions-policy.json
   aws iam create-access-key --user-name github-actions-deploy-session
   # copy the AccessKeyId/SecretAccessKey into GitHub repo Settings -> Secrets and variables -> Actions
   ```
4. **Configure GitHub Environments with approval gates** (one-time, in the GitHub UI): Repo → Settings → Environments → New environment → `staging` → check **Required reviewers** → add yourself. Repeat for `prod`.
5. **Run the full pipeline live, once, end to end** — open a PR (CI runs), merge it (CD runs, deploys to dev, pauses for your approval at staging, again at prod). **Record this** (screen capture) since it's your portfolio evidence.
6. **Revoke the IAM user's keys before your session ends:**
   ```bash
   aws iam delete-access-key --user-name github-actions-deploy-session --access-key-id <key-id>
   aws iam delete-user-policy --user-name github-actions-deploy-session --policy-name deploy-policy
   aws iam delete-user --user-name github-actions-deploy-session
   ```

#### 8.6 The "real account" version — OIDC (documented, not run in the sandbox)

This is what you'd actually run in a persistent AWS account, and what you should describe in interviews as your intended production pattern:

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "orderflow-github-actions-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:yourorg/orderflow:*" }
      }
    }]
  })
}
```
```yaml
# the only line that changes in deploy.yml for a real account:
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::<account-id>:role/orderflow-github-actions-deploy
    aws-region: us-east-1
```
Being able to show **both** versions side by side — "here's what I ran in the free sandbox, here's the production-correct version, here's exactly why they differ" — is a stronger interview answer than either version alone.

### Phase 9 — Governance & Security Add-Ons (`infra/modules/governance`) — NEW

1. **CloudTrail** — logs every API call made in this account:
   ```hcl
   resource "aws_s3_bucket" "cloudtrail" {
     bucket = "orderflow-cloudtrail-${var.env}-<your-unique-id>"
   }
   resource "aws_cloudtrail" "this" {
     name                          = "orderflow-trail"
     s3_bucket_name                = aws_s3_bucket.cloudtrail.id
     include_global_service_events = true
     is_multi_region_trail         = false   # keep to one region given sandbox scope
   }
   ```
2. **AWS Config** — continuous compliance checking:
   ```hcl
   resource "aws_config_configuration_recorder" "this" {
     name     = "orderflow-recorder"
     role_arn = aws_iam_role.config_role.arn
   }
   resource "aws_config_config_rule" "s3_not_public" {
     name = "s3-bucket-public-read-prohibited"
     source { owner = "AWS"; source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED" }
   }
   resource "aws_config_config_rule" "ebs_encrypted" {
     name = "encrypted-volumes"
     source { owner = "AWS"; source_identifier = "ENCRYPTED_VOLUMES" }
   }
   ```
3. **AWS Inspector** — enable scanning for ECR + the ops EC2 instance:
   ```bash
   aws inspector2 enable --resource-types ECR EC2
   ```
4. **Verify:** after a few minutes, check findings:
   ```bash
   aws inspector2 list-findings --max-results 10
   aws configservice describe-compliance-by-config-rule
   ```
   These three together — CloudTrail (audit), Config (compliance), Inspector (vulnerability) — are exactly the kind of "boring but essential" enterprise governance trio that separates a junior who can deploy an app from one who understands what a platform/security team actually cares about.

### Phase 10 — Testing, Chaos & Runbook

1. **Load test** with `k6`:
   ```bash
   k6 run --vus 20 --duration 60s loadtest.js
   ```
   Watch the Grafana "Golden Signals" dashboard and the X-Ray Service Map react in real time.
2. **Chaos drills** (do these, write a short RCA for each in `runbooks/`):
   - `aws ecs stop-task --cluster orderflow-dev --task <task-id>` → watch ECS replace it automatically, observe the ALB draining connections, note the alarm firing/clearing, measure time-to-recovery.
   - Remove the ALB→ECS Security Group rule → curl the ALB → watch it hang (not error) → diagnose using only CloudWatch/Loki/the SG console (no NAT/routing layer to blame here, which sharpens the "is it network or app" diagnostic skill) → restore → document.
   - Force a bad image tag through the GitHub Actions pipeline → watch the `deployment_circuit_breaker` auto-rollback fire → confirm via `aws ecs describe-services`.
3. **`runbooks/INCIDENT-RUNBOOK.md`** — how to check `aws ecs describe-services`, how to read Grafana/Loki/X-Ray, how to manually roll back, an escalation contact list, and a short note on "what's different about debugging this in a default-VPC/Security-Group-only topology vs. a private-subnet/NAT one."

### Phase 11 — Cleanup (do this before your session ends regardless)

```bash
cd infra/envs/dev
terraform destroy -var-file=terraform.tfvars
```
Even though the sandbox account itself gets recycled, get in the habit of a clean `terraform destroy` — it's the right muscle memory for when you do this against a real account, and it leaves your Terraform state consistent if you want to `apply` again within the same session to fix something.

---

## 6. Sample Makefile (ties the whole sandbox session together)

```makefile
.PHONY: up down seed demo-record
up:
	cd infra/envs/dev && terraform init && terraform apply -auto-approve

seed:
	aws dynamodb put-item --table-name orderflow-inventory-dev --item '{"sku":{"S":"SKU-001"},"stock":{"N":"100"}}'

demo-record:
	@echo "Now: curl the API, open Grafana via SSM port-forward, open the GitHub Actions tab, open X-Ray service map."
	@echo "Record all four before running 'make down'."

down:
	cd infra/envs/dev && terraform destroy -auto-approve
```

---

## 7. Extra-Credit Add-Ons

1. **EKS capability demo (scaled to sandbox limits)** — one tiny Deployment (1 pod, 100m CPU / 128Mi request) with an NGINX Ingress Controller, explicitly labeled in your README as "demonstrates EKS fundamentals within the sandbox's 256m/512Mi-per-pod cap, not a production-shaped cluster." Lets you speak to ECS vs EKS trade-offs from real hands-on time on both.
2. **Splunk integration** — Lambda subscription filter forwarding CloudWatch Logs to a Splunk HEC endpoint; well within the sandbox's 256MB/10s Lambda cap.
3. **Step Functions** — orchestrate a multi-step "order fulfillment" workflow (validate → reserve inventory → notify) as an alternative to pure SNS/SQS chaining, and explicitly compare the two patterns in your README (choreography vs. orchestration) — a great senior-leaning talking point even at junior level.
4. **EventBridge** — route high-value orders (`quantity * price > threshold`) to a separate "priority handling" path using EventBridge content-based filtering, alongside your existing SNS fan-out — shows you know when to reach for an event bus vs. simple pub/sub.
5. **Cost dashboard** — Grafana panel pulling AWS Cost Explorer data (works fine read-only in the sandbox).

---

## 8. README Checklist (what to publish on GitHub)

- [ ] Architecture diagram (export the ASCII diagram above as a draw.io/Excalidraw PNG) — include both the "original enterprise design" and "sandbox-adapted" versions side by side
- [ ] `docs/kodekloud-sandbox-notes.md` — the adaptation rationale from Section 0, kept as its own quick-reference doc
- [ ] One-command bootstrap: `make up` (terraform apply + seed data)
- [ ] Demo recording/screenshots: Grafana dashboard, X-Ray Service Map, GitHub Actions pipeline run showing the approval gate, a curl against the API — captured during your one live sandbox session
- [ ] `runbooks/INCIDENT-RUNBOOK.md`
- [ ] Cost/session teardown reminder + `make down`
- [ ] "What I'd change for a real, persistent AWS account" section — this is the single most important paragraph in the whole README for interview purposes
