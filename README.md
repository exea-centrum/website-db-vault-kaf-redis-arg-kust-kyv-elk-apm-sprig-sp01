# Davtro Apartments – platforma wynajmu krotkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
Namespace: `davtro`

## Architektura
1. **Frontend** (SPA) → Nginx
2. **FastAPI** → PostgreSQL + Redis (cache) + Kafka (producent)
3. **message-processor** (consumer) → Kafka → email + PostgreSQL update
4. **Spring Boot** → panel raportowy / admin
5. **Spark** → analityka marketingowa z Kafka
6. **Vault** → sekrety (dev-mode, do produkcji HA)
7. **Observability** → Prometheus + Grafana + Loki + Tempo

## Lokalne uruchomienie (dev)
```bash
cd backend-fastapi
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## K8s / ArgoCD
```bash
kubectl apply -f argocd/application.yaml -n argocd
```
Push do `main` → GitHub Actions buduje obrazy → Kustomize aktualizuje tagi → ArgoCD sync.

## WAZNE – przed produkcja
- Zamien Vault dev-mode na oficjalny Helm chart (HA + auto-unseal)
- Skonfiguruj ArgoCD Vault Plugin (AVP) dla sekretow
- Skonfiguruj realny SMTP w secretach
- Zainstaluj Prometheus Operator jesli chcesz uzyc ServiceMonitor
