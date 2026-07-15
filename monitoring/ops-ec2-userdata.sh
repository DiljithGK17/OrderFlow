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
cd /opt/monitoring && /usr/local/bin/docker-compose up -d
