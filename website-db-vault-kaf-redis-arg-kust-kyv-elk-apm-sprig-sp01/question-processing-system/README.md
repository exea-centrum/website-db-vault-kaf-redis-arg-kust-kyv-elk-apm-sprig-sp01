# 🎓 System Przetwarzania Pytań

Kompletny system przetwarzania pytań dla ćwiczeń z wykładowcą.

## 📊 Architektura

```
┌──────────┐    ┌───────┐    ┌───────┐    ┌────────────┐
│ FastAPI  │───▶│ Redis │───▶│ Kafka │───▶│ PostgreSQL │
│  (Web)   │    │       │    │       │    │            │
└──────────┘    └───────┘    └───────┘    └────────────┘
                                        ▲
                                  ┌─────┴──────┐
                                  │  Message   │
                                  │  Processor │
                                  └────────────┘
```

## 📦 Zawartość (41 zasobów Kubernetes)

### Core Applications
- ✅ FastAPI (web UI + producer)
- ✅ Redis to Kafka Bridge
- ✅ Message Processor (Kafka → PostgreSQL)
- ✅ Spring Boot App

### Infrastructure
- ✅ PostgreSQL (DB + ClusterIP service)
- ✅ Redis
- ✅ Kafka (KRaft mode)
- ✅ Vault (secrets management)
- ✅ Spark (Master + Worker)

### Monitoring Stack (Full LGTM)
- ✅ Prometheus + ServiceMonitors
- ✅ Grafana (datasources + dashboards)
- ✅ Loki + Promtail (logs)
- ✅ Tempo (tracing)
- ✅ Exporters: Postgres, Kafka, Node

### Tools
- ✅ pgAdmin (PostgreSQL GUI)
- ✅ Kafka UI

### Kubernetes Resources
- ✅ Namespace, ConfigMaps, Secrets
- ✅ ServiceAccounts (kafka-job-sa, question-system-sa)
- ✅ HPA (Horizontal Pod Autoscaler)
- ✅ PDB (Pod Disruption Budget)
- ✅ Network Policies
- ✅ Ingress (main + spark)
- ✅ Kyverno Policy
- ✅ Kafka Topic Job

## 🚀 Quick Start

### 1. Zbuduj obrazy
```bash
cd scripts
./build-images.sh
```

### 2. Wdróż do Kubernetes
```bash
./deploy.sh
```

### 3. Uruchom port forwarding
```bash
./port-forward.sh
```

### 4. Otwórz aplikację
- **FastAPI**: http://localhost:8000
- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **Kafka UI**: http://localhost:9091
- **pgAdmin**: http://localhost:5050
- **Spark UI**: http://localhost:8081
- **Vault**: http://localhost:8200 (token: root)

## 📝 Przykład użycia

### Wyślij pytanie przez curl
```bash
curl -X POST http://localhost:8000/api/questions \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Jak działa Kafka?",
    "author": "Jan Kowalski"
  }'
```

### Sprawdź w PostgreSQL
```bash
kubectl exec -it deployment/postgres-db -n question-system -- \
  psql -U postgres -d questions_db -c "SELECT * FROM questions;"
```

### Sprawdź logi
```bash
kubectl logs -f deployment/fastapi-app -n question-system
kubectl logs -f deployment/message-processor -n question-system
kubectl logs -f deployment/redis-to-kafka -n question-system
```

## 🧹 Czyszczenie
```bash
./scripts/cleanup.sh
```

## 📚 Dla studentów

Projekt demonstruje:
1. **Microservices** - rozdzielone komponenty
2. **Message Queues** - Redis i Kafka
3. **Event-Driven Architecture** - asynchroniczne przetwarzanie
4. **Kubernetes** - deployment, scaling, monitoring
5. **Observability** - metryki, logi, tracing (LGTM stack)
6. **Security** - network policies, secrets, RBAC, Kyverno

## 🔑 Domyślne hasła

| Service | Username | Password |
|---------|----------|----------|
| Grafana | admin | admin |
| pgAdmin | admin@example.com | admin |
| Vault | - | root |
| PostgreSQL | postgres | postgres_secure_password |
| Redis | - | redis_secure_password |

**UWAGA**: Zmień hasła przed użyciem produkcyjnym!

## 📄 Licencja
MIT
