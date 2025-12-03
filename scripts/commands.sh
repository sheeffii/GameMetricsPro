#!/bin/bash
# GameMetrics Infrastructure - Quick Commands Reference

cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║          GameMetrics Infrastructure Commands                  ║
╚══════════════════════════════════════════════════════════════╝

🚀 DEPLOYMENT
  Deploy Everything:
    bash scripts/deploy-infrastructure.sh

  Check Status:
    bash scripts/check-status.sh

  Test Kafka:
    bash scripts/quick-kafka-test.sh

  Destroy All:
    bash scripts/teardown-infrastructure.sh

📊 KAFKA OPERATIONS
  Port-forward Kafka UI:
    kubectl port-forward -n kafka svc/kafka-ui 8080:8080
    Then open: http://localhost:8080

  List Topics:
    kubectl get kafkatopic -n kafka

  Send Test Message:
    echo '{"test":"data"}' | kubectl exec -i -n kafka gamemetrics-kafka-broker-0 -- \
      bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic player.events.raw

  Read Messages:
    kubectl exec -n kafka gamemetrics-kafka-broker-0 -- \
      bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
      --topic player.events.raw --from-beginning --max-messages 10

🔧 KUBERNETES
  View Pods:
    kubectl get pods -n kafka

  View Logs:
    kubectl logs -n kafka -l strimzi.io/cluster=gamemetrics-kafka

  Describe Kafka:
    kubectl describe kafka gamemetrics-kafka -n kafka

  Exec into Broker:
    kubectl exec -it -n kafka gamemetrics-kafka-broker-0 -- bash

💾 TERRAFORM
  Plan Changes:
    cd terraform/environments/dev && terraform plan

  Apply Changes:
    cd terraform/environments/dev && terraform apply

  View Outputs:
    cd terraform/environments/dev && terraform output

📝 NEXT STEPS
  1. Update RDS password in k8s/secrets/db-secrets.yaml
  2. Build Docker image: cd services/event-ingestion-service && docker build -t event-ingestion:latest .
  3. Push to ECR and deploy services
  4. Test end-to-end event flow

EOF
