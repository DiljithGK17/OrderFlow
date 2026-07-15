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
