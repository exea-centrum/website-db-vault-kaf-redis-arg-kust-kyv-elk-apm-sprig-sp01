#  - Complete Monitoring Stack with Spring Boot, Spark & ELK

## 🛠️ Quick Start

```bash
# Generate all files
./lmarena.sh generate

# Deploy to Kubernetes
kubectl apply -k manifests/base

# Watch pods
kubectl -n davtro get pods -w

# Access applications:
# Main App: http://app..local
# New Survey: http://app..local/new-survey
# Spring Boot API: http://spring..local
# Spark UI: http://spark..local
# Kibana: http://kibana..local
# Grafana: http://grafana..local (admin/admin)
# PgAdmin: http://pgadmin..local (admin@example.com/adminpassword)
# Kafka UI: http://kafka-ui..local

# Initialize Vault
kubectl wait --for=condition=complete job/vault-init -n davtro

# Initialize MongoDB
kubectl wait --for=condition=complete job/mongodb-init -n davtro
```

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://app..local | - |
| New Survey (Spring Boot) | http://app..local/new-survey | - |
| Spring Boot API | http://spring..local | - |
| Spark Master UI | http://spark..local | - |
| Kibana | http://kibana..local | - |
| Grafana | http://grafana..local | admin/admin |
| PgAdmin | http://pgadmin..local | admin@example.com/adminpassword |
| Kafka UI | http://kafka-ui..local | - |

## 🏗️ Architecture Components:

### 1. **Python FastAPI Stack** (Original)
- **FastAPI Application** - Main web application with Vault integration
- **PostgreSQL** - Relational database for survey data
- **Redis** - Message queue for async processing
- **Kafka** - Event streaming platform
- **Vault** - Secrets management
- **Monitoring Stack** - Prometheus, Grafana, Loki, Tempo

### 2. **Java Spring Boot Stack** (New)
- **Spring Boot API** - REST API for new survey with MongoDB
- **MongoDB** - NoSQL database for survey responses
- **Apache Spark** - Real-time data processing and analytics
- **ELK Stack** - Elasticsearch, Logstash, Kibana for logging

### 3. **JavaScript Frontend** (New)
- **Modern JavaScript UI** - Interactive survey with React-like components
- **Chart.js** - Data visualization for survey statistics
- **Tailwind CSS** - Modern styling

## 🔧 Integration Details:

1. **Hybrid Architecture** - Python FastAPI + Java Spring Boot + JavaScript frontend
2. **Multiple Databases** - PostgreSQL (relational) + MongoDB (NoSQL)
3. **Real-time Processing** - Kafka + Apache Spark for data streaming
4. **Centralized Logging** - ELK Stack for logs from all components
5. **Unified Monitoring** - Prometheus + Grafana for all services
6. **Secrets Management** - HashiCorp Vault for all credentials

## 📊 Monitoring Stack:

- **Prometheus** - metrics collection from all services
- **Grafana** - unified dashboards with all datasources
- **Loki** - centralized log aggregation
- **Tempo** - distributed tracing
- **Postgres Exporter** - PostgreSQL metrics
- **MongoDB Exporter** - MongoDB metrics
- **Kafka Exporter** - Kafka metrics
- **Node Exporter** - system metrics

## 🔐 Security:

- All passwords in Vault
- Network policies for service communication
- Proper security contexts for databases
- Health checks and resource limits for all containers
- TLS/SSL ready configuration

## 🚀 Deployment Scripts:

```bash
# Full deployment
./deploy-extended.sh

# Check status
kubectl get pods -n davtro
kubectl get svc -n davtro
kubectl get ingress -n davtro
```

## 🔄 CI/CD Pipeline:

GitHub Actions automatically builds and deploys:
1. **Python FastAPI application**
2. **Spring Boot Java application**
3. **Apache Spark jobs**
4. **Deploys to Kubernetes**

## 📈 Data Flow:

1. User submits survey via JavaScript frontend
2. Data sent to Spring Boot API via FastAPI proxy
3. Spring Boot saves to MongoDB and sends to Kafka
4. Apache Spark processes data in real-time
5. Results saved to MongoDB analytics collections
6. Logs sent to ELK Stack
7. Metrics collected by Prometheus
8. Visualizations in Grafana and Kibana

## 🐛 Troubleshooting:

```bash
# Check logs
kubectl logs -f deployment/fastapi-web-app -n davtro
kubectl logs -f deployment/spring-app -n davtro
kubectl logs -f deployment/spark-master -n davtro

# Check database connections
kubectl exec -it deployment/fastapi-web-app -n davtro -- python -c "import psycopg2; psycopg2.connect('dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432')"
kubectl exec -it deployment/spring-app -n davtro -- curl http://localhost:8080/actuator/health

# Restart deployments
kubectl rollout restart deployment/fastapi-web-app -n davtro
kubectl rollout restart deployment/spring-app -n davtro
```

## 📚 Documentation:

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [ELK Stack Documentation](https://www.elastic.co/guide/index.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
