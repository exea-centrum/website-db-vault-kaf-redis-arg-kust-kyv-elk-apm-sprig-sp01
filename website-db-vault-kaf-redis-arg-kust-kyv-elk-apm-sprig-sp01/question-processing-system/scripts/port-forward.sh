#!/bin/bash
echo "🔌 Port forwarding..."
echo "FastAPI:     http://localhost:8000"
echo "Grafana:     http://localhost:3000 (admin/admin)"
echo "Prometheus:  http://localhost:9090"
echo "Kafka UI:    http://localhost:9090"
echo "pgAdmin:     http://localhost:5050 (admin@example.com/admin)"
echo "Spark UI:    http://localhost:8080"
echo "Vault:       http://localhost:8200 (token: root)"
echo ""
kubectl port-forward svc/fastapi-service 8000:80 -n question-system &
kubectl port-forward svc/grafana 3000:3000 -n question-system &
kubectl port-forward svc/prometheus 9090:9090 -n question-system &
kubectl port-forward svc/kafka-ui 9091:8080 -n question-system &
kubectl port-forward svc/pgadmin 5050:80 -n question-system &
kubectl port-forward svc/spark-master 8081:8080 -n question-system &
kubectl port-forward svc/vault 8200:8200 -n question-system &
wait
