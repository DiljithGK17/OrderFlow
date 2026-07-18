# OrderFlow Command Reference

This document serves as a cheat sheet for all the terminal commands used to deploy, test, and operate the OrderFlow Platform.

---

## 1. Infrastructure Deployment

**Initialize Terraform:**
```bash
cd infra/envs/dev
terraform init
```

**Deploy Infrastructure (Make shortcut):**
*Must be run from the repository root directory.*
```bash
make up
```
*(This command runs `terraform apply -auto-approve` under the hood).*

**Destroy Infrastructure:**
```bash
make down
```

**Taint a Resource (Force Recreation):**
*If a specific resource is failing or stuck, you can taint it to force Terraform to recreate it on the next apply.*
```bash
cd infra/envs/dev
terraform taint module.alb.aws_lb.this
terraform taint module.observability.aws_instance.ops
```

---

## 2. API Gateway & Invocation

**Find your API Gateway URL via CLI:**
*Fetches the raw Invoke URL directly from AWS.*
```bash
aws apigatewayv2 get-apis --query "Items[0].ApiEndpoint" --output text
```

**Test the `/orders` Endpoint:**
*Creates a new order. Replace `<URL>` with the output from the command above.*
```bash
curl -X POST <URL>/orders \
  -H "Content-Type: application/json" \
  -d '{"customerId": "cust-8899", "sku": "prod-1", "quantity": 2}'
```
*Expected Output: `{"orderId": "uuid-here", "status": "PENDING"}`*

---

## 3. Observability Access (Grafana)

Because Grafana is hosted on a private EC2 instance inside the VPC, you must use AWS Systems Manager (SSM) to securely tunnel into the machine.

**Install the SSM Plugin (Ubuntu/Debian):**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
rm session-manager-plugin.deb
```

**Start the Port-Forwarding Session:**
*This command dynamically looks up the EC2 instance ID and forwards port 3000 to your local machine.*
```bash
AWS_DEFAULT_REGION=us-east-1 aws ssm start-session \
  --target $(AWS_DEFAULT_REGION=us-east-1 aws ec2 describe-instances --filters "Name=tag:Name,Values=orderflow-ops-ec2" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
```
*After running this, open `http://localhost:3000` in your web browser.*

---

## 4. AWS Credentials Management

If you open a new terminal window or restart your computer, you **must** export your KodeKloud AWS Sandbox credentials before running any Terraform or AWS CLI commands.

**Export Credentials:**
```bash
export AWS_ACCESS_KEY_ID="<YOUR_ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<YOUR_SECRET_KEY>"
export AWS_DEFAULT_REGION="us-east-1"
```

**Verify Active Identity:**
*Check which AWS account you are currently authenticated against.*
```bash
aws sts get-caller-identity
```
