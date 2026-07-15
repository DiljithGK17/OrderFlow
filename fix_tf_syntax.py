import os

replacements = {
    "infra/modules/alb/main.tf": [
        ('path = "/healthz"; interval = 15; healthy_threshold = 2; unhealthy_threshold = 3', 'path = "/healthz"\n    interval = 15\n    healthy_threshold = 2\n    unhealthy_threshold = 3'),
        ('condition { path_pattern { values = ["/orders/*"] } }', 'condition {\n    path_pattern {\n      values = ["/orders/*"]\n    }\n  }'),
        ('action { type = "forward"; target_group_arn = aws_lb_target_group.order_service.arn }', 'action {\n    type = "forward"\n    target_group_arn = aws_lb_target_group.order_service.arn\n  }'),
        ('fixed_response { content_type = "text/plain"; message_body = "Not Found"; status_code  = "404" }', 'fixed_response {\n      content_type = "text/plain"\n      message_body = "Not Found"\n      status_code  = "404"\n    }')
    ],
    "infra/modules/api-gateway/main.tf": [
        ('default_action { allow {} }', 'default_action {\n    allow {}\n  }'),
        ('action { block {} }', 'action {\n      block {}\n    }'),
        ('rate_based_statement { limit = 2000; aggregate_key_type = "IP" }', 'rate_based_statement {\n        limit = 2000\n        aggregate_key_type = "IP"\n      }'),
        ('visibility_config { sampled_requests_enabled = true; cloudwatch_metrics_enabled = true; metric_name = "rate-limit" }', 'visibility_config {\n      sampled_requests_enabled = true\n      cloudwatch_metrics_enabled = true\n      metric_name = "rate-limit"\n    }'),
        ('visibility_config { sampled_requests_enabled = true; cloudwatch_metrics_enabled = true; metric_name = "orderflow-api-waf" }', 'visibility_config {\n    sampled_requests_enabled = true\n    cloudwatch_metrics_enabled = true\n    metric_name = "orderflow-api-waf"\n  }')
    ],
    "infra/modules/dynamodb/main.tf": [
        ('attribute { name = "orderId";    type = "S" }', 'attribute {\n    name = "orderId"\n    type = "S"\n  }'),
        ('attribute { name = "customerId"; type = "S" }', 'attribute {\n    name = "customerId"\n    type = "S"\n  }'),
        ('attribute { name = "status";     type = "S" }', 'attribute {\n    name = "status"\n    type = "S"\n  }'),
        ('attribute { name = "sku"; type = "S" }', 'attribute {\n    name = "sku"\n    type = "S"\n  }'),
        ('attribute { name = "requestId"; type = "S" }', 'attribute {\n    name = "requestId"\n    type = "S"\n  }')
    ],
    "infra/modules/ecs-cluster/main.tf": [
        ('setting { name = "containerInsights"; value = "enabled" }', 'setting {\n    name = "containerInsights"\n    value = "enabled"\n  }'),
        ('image_scanning_configuration { scan_on_push = true }', 'image_scanning_configuration {\n    scan_on_push = true\n  }')
    ],
    "infra/modules/ecs-service/main.tf": [
        ('deployment_circuit_breaker { enable = true; rollback = true }', 'deployment_circuit_breaker {\n    enable = true\n    rollback = true\n  }')
    ],
    "infra/modules/governance/main.tf": [
        ('Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "config.amazonaws.com" } }]', 'Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "config.amazonaws.com" } }]'),
        ('source { owner = "AWS"; source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED" }', 'source {\n    owner = "AWS"\n    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"\n  }'),
        ('source { owner = "AWS"; source_identifier = "ENCRYPTED_VOLUMES" }', 'source {\n    owner = "AWS"\n    source_identifier = "ENCRYPTED_VOLUMES"\n  }')
    ],
    "infra/modules/iam/main.tf": [
        ('Action = "sts:AssumeRole"; Effect = "Allow"', 'Action = "sts:AssumeRole", Effect = "Allow"'),
        ('Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]', 'Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]') # Fix missing commas if any
    ],
    "infra/modules/observability/main.tf": [
        ('Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "ec2.amazonaws.com" } }]', 'Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]')
    ],
    "infra/modules/security/main.tf": [
        ('from_port = 443; to_port = 443; protocol = "tcp"', 'from_port = 443\n    to_port = 443\n    protocol = "tcp"'),
        ('from_port = 80;  to_port = 80;  protocol = "tcp"', 'from_port = 80\n    to_port = 80\n    protocol = "tcp"'),
        ('from_port = 8080; to_port = 8080; protocol = "tcp"', 'from_port = 8080\n    to_port = 8080\n    protocol = "tcp"'),
        ('from_port = 9090; to_port = 9090; protocol = "tcp"', 'from_port = 9090\n    to_port = 9090\n    protocol = "tcp"'),
        ('from_port = 3000; to_port = 3000; protocol = "tcp"', 'from_port = 3000\n    to_port = 3000\n    protocol = "tcp"'),
        ('from_port = 3100; to_port = 3100; protocol = "tcp"', 'from_port = 3100\n    to_port = 3100\n    protocol = "tcp"'),
        ('from_port = 0;   to_port = 0;   protocol = "-1"', 'from_port = 0\n    to_port = 0\n    protocol = "-1"')
    ]
}

for filepath, reps in replacements.items():
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            content = f.read()
        for old, new in reps:
            content = content.replace(old, new)
        with open(filepath, 'w') as f:
            f.write(content)
