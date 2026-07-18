#!/bin/bash
set -e
yum update -y
yum install -y docker
systemctl enable docker && systemctl start docker
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /opt/monitoring
mkdir -p /opt/monitoring/grafana/provisioning/datasources
mkdir -p /opt/monitoring/grafana/provisioning/dashboards

# Write Prometheus configuration
cat > /opt/monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'ecs-services'
    metrics_path: '/metrics'
    static_configs:
      # In a real production setup, we would use ECS Service Discovery here.
      # For this sandbox, we can scrape the ALB which forwards to our containers!
      - targets: ["${alb_dns_name}"]
EOF

# Provision Prometheus Datasource in Grafana
cat > /opt/monitoring/grafana/provisioning/datasources/datasource.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
EOF

cat > /opt/monitoring/docker-compose.yml << 'EOF'
services:
  prometheus:
    image: prom/prometheus:v2.54.0
    volumes: ["/opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml"]
    ports: ["9090:9090"]
  grafana:
    image: grafana/grafana:11.1.0
    volumes: 
      - "/opt/monitoring/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources"
    ports: ["3000:3000"]
  loki:
    image: grafana/loki:3.1.0
    ports: ["3100:3100"]
EOF
cd /opt/monitoring && /usr/local/bin/docker-compose up -d
