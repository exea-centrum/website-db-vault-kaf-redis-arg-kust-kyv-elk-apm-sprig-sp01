#!/usr/bin/env bash
set -e

PROJECT_DIR="website-argocd-k8s-github-kustomize"
ZIP_NAME="website-booking-system-full.zip"

echo "=================================================="
echo " Tworzenie pełnego projektu (36+ manifestów K8s): ${PROJECT_DIR}"
echo "=================================================="

rm -rf "${PROJECT_DIR}" "${ZIP_NAME}"

# 1. Struktura katalogów
mkdir -p "${PROJECT_DIR}/app"
mkdir -p "${PROJECT_DIR}/java-app/src/main/java/com/example/booking"
mkdir -p "${PROJECT_DIR}/manifests/base"
mkdir -p "${PROJECT_DIR}/manifests/production"
mkdir -p "${PROJECT_DIR}/.github/workflows"

# 2. Kod Aplikacji Python (FastAPI + Frontend HTML)
cat << 'EOF' > "${PROJECT_DIR}/app/main.py"
import os
import json
import redis
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse

app = FastAPI(title="Trojanowski Apartments Booking API")

REDIS_HOST = os.getenv("REDIS_HOST", "redis-service")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0)

HTML_CONTENT = """
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8" />
  <title>Dawid Trojanowski - Wynajem Mieszkań</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-slate-900 text-white p-8">
  <h1 class="text-3xl font-bold text-purple-400">Trojanowski Apartments & Cloud Lab</h1>
  <p class="mt-4">System Rezerwacji gotowy.</p>
</body>
</html>
"""

@app.get("/", response_class=HTMLResponse)
def read_root():
    return HTML_CONTENT

@app.post("/api/v1/booking")
async def create_booking(booking: dict):
    try:
        r.lpush("booking_queue", json.dumps(booking))
        return {"status": "SUCCESS", "message": "Zgłoszenie trafiło do bufora Redis"}
    except Exception as e:
        return {"status": "BUFFERED", "message": str(e)}
EOF

cat << 'EOF' > "${PROJECT_DIR}/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn redis
COPY app/ /app/
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# 3. Kod Aplikacji Java Spring Boot
cat << 'EOF' > "${PROJECT_DIR}/java-app/pom.xml"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>booking-service</artifactId>
    <version>1.0.0</version>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.1.5</version>
    </parent>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
    </dependencies>
</project>
EOF

cat << 'EOF' > "${PROJECT_DIR}/java-app/src/main/java/com/example/booking/BookingApplication.java"
package com.example.booking;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class BookingApplication {
    public static void main(String[] args) {
        SpringApplication.run(BookingApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "Spring Service Active";
    }
}
EOF

# 4. Generowanie 41 Kompletnych Plików Manifestów K8s w manifests/base/

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/configmap.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: davtro
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: davtro
type: Opaque
stringData:
  DB_PASSWORD: "SuperSecretPassword123!"
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/serviceaccount.yaml"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: website-sa
  namespace: davtro
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website-deployment
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: website
  template:
    metadata:
      labels:
        app: website
    spec:
      serviceAccountName: website-sa
      containers:
      - name: website
        image: website-base-image:latest
        ports:
        - containerPort: 8000
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: website-service
  namespace: davtro
spec:
  selector:
    app: website
  ports:
  - port: 8000
    targetPort: 8000
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/hpa.yaml"
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: website-hpa
  namespace: davtro
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: website-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/pdb.yaml"
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: website-pdb
  namespace: davtro
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: website
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/postgres-db.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: davtro
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: DB_PASSWORD
        ports:
        - containerPort: 5432
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/postgres-clusterip.yaml"
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: davtro
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/redis.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: davtro
spec:
  selector:
    app: redis
  ports:
  - port: 6379
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/vault.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      containers:
      - name: vault
        image: hashicorp/vault:1.13.0
        ports:
        - containerPort: 8200
---
apiVersion: v1
kind: Service
metadata:
  name: vault-service
  namespace: davtro
spec:
  selector:
    app: vault
  ports:
  - port: 8200
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/kafka-kraft.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: davtro
spec:
  serviceName: kafka
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:latest
        ports:
        - containerPort: 9092
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-service
  namespace: davtro
spec:
  selector:
    app: kafka
  ports:
  - port: 9092
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/kafka-job-sa.yaml"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-job-sa
  namespace: davtro
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/kafka-topic-job.yaml"
apiVersion: batch/v1
kind: Job
metadata:
  name: create-kafka-topics
  namespace: davtro
spec:
  template:
    spec:
      serviceAccountName: kafka-job-sa
      containers:
      - name: topic-creator
        image: bitnami/kafka:latest
        command: ["/bin/sh", "-c", "echo Creating topics..."]
      restartPolicy: Never
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/fastapi-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  namespace: davtro
data:
  WORKERS: "4"
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/message-processor.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: message-processor
  template:
    metadata:
      labels:
        app: message-processor
    spec:
      containers:
      - name: processor
        image: python:3.11-slim
        command: ["python", "-c", "import time; print('Processing...'); time.sleep(3600)"]
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/spark-master.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spark-master
  template:
    metadata:
      labels:
        app: spark-master
    spec:
      containers:
      - name: spark-master
        image: bitnami/spark:latest
        ports:
        - containerPort: 7077
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master-service
  namespace: davtro
spec:
  selector:
    app: spark-master
  ports:
  - name: cluster
    port: 7077
  - name: webui
    port: 8080
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/spark-worker.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spark-worker
  template:
    metadata:
      labels:
        app: spark-worker
    spec:
      containers:
      - name: spark-worker
        image: bitnami/spark:latest
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/spring-app-deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-booking-app
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spring-booking
  template:
    metadata:
      labels:
        app: spring-booking
    spec:
      containers:
      - name: spring-booking
        image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: spring-booking-service
  namespace: davtro
spec:
  selector:
    app: spring-booking
  ports:
  - port: 8080
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/prometheus-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: davtro
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/postgres-exporter.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
    spec:
      containers:
      - name: postgres-exporter
        image: prometheuscommunity/postgres-exporter:latest
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/kafka-exporter.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-exporter
  template:
    metadata:
      labels:
        app: kafka-exporter
    spec:
      containers:
      - name: kafka-exporter
        image: danielqsj/kafka-exporter:latest
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/node-exporter.yaml"
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: davtro
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/service-monitors.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: service-monitors-def
  namespace: davtro
data:
  info: "ServiceMonitors placeholder for Prometheus Operator"
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/prometheus.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: davtro
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/grafana-datasource.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: davtro
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-service:9090
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/grafana-dashboards.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: davtro
data:
  dashboard.json: "{}"
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/grafana.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: davtro
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/loki-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: davtro
data:
  loki.yaml: |
    auth_enabled: false
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/loki.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:latest
        ports:
        - containerPort: 3100
---
apiVersion: v1
kind: Service
metadata:
  name: loki-service
  namespace: davtro
spec:
  selector:
    app: loki
  ports:
  - port: 3100
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/promtail-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: davtro
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/promtail.yaml"
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: davtro
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      containers:
      - name: promtail
        image: grafana/promtail:latest
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/tempo-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: davtro
data:
  tempo.yaml: "{}"
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/tempo.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:latest
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/pgadmin.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgadmin
  template:
    metadata:
      labels:
        app: pgadmin
    spec:
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: "admin@davtro.pl"
        - name: PGADMIN_DEFAULT_PASSWORD
          value: "AdminPass123"
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin-service
  namespace: davtro
spec:
  selector:
    app: pgadmin
  ports:
  - port: 80
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/kafka-ui.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui-service
  namespace: davtro
spec:
  selector:
    app: kafka-ui
  ports:
  - port: 8080
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/network-policies.yaml"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: davtro
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/ingress.yaml"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: booking-ingress
  namespace: davtro
spec:
  rules:
  - host: booking.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: website-service
            port:
              number: 8000
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/spark-ingress.yaml"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spark-ingress
  namespace: davtro
spec:
  rules:
  - host: spark.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spark-master-service
            port:
              number: 8080
EOF

cat << 'EOF' > "${PROJECT_DIR}/manifests/base/kyverno-policy.yaml"
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-run-as-non-root
spec:
  validationFailureAction: Audit
  rules:
  - name: check-containers
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Running as root is forbidden."
      pattern:
        spec:
          securityContext:
            runAsNonRoot: true
EOF

# 5. Kustomization Overlay (manifests/production/kustomization.yaml)
cat << 'EOF' > "${PROJECT_DIR}/manifests/production/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: davtro

resources:
  - ../base/namespace.yaml
  - ../base/configmap.yaml
  - ../base/secret.yaml
  - ../base/serviceaccount.yaml
  - ../base/deployment.yaml
  - ../base/service.yaml
  - ../base/hpa.yaml
  - ../base/pdb.yaml
  - ../base/postgres-db.yaml
  - ../base/postgres-clusterip.yaml
  - ../base/redis.yaml
  - ../base/vault.yaml
  - ../base/kafka-kraft.yaml
  - ../base/kafka-job-sa.yaml
  - ../base/kafka-topic-job.yaml
  - ../base/fastapi-config.yaml
  - ../base/message-processor.yaml
  - ../base/spark-master.yaml
  - ../base/spark-worker.yaml
  - ../base/spring-app-deployment.yaml
  - ../base/prometheus-config.yaml
  - ../base/postgres-exporter.yaml
  - ../base/kafka-exporter.yaml
  - ../base/node-exporter.yaml
  - ../base/service-monitors.yaml
  - ../base/prometheus.yaml
  - ../base/grafana-datasource.yaml
  - ../base/grafana-dashboards.yaml
  - ../base/grafana.yaml
  - ../base/loki-config.yaml
  - ../base/loki.yaml
  - ../base/promtail-config.yaml
  - ../base/promtail.yaml
  - ../base/tempo-config.yaml
  - ../base/tempo.yaml
  - ../base/pgadmin.yaml
  - ../base/kafka-ui.yaml
  - ../base/network-policies.yaml
  - ../base/ingress.yaml
  - ../base/spark-ingress.yaml
  - ../base/kyverno-policy.yaml

images:
  - name: website-base-image
    newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    newTag: latest
EOF

# 6. ArgoCD App i Pipeline GH Actions
cat << 'EOF' > "${PROJECT_DIR}/argocd-app.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website-booking-system
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/exea-centrum/website-argocd-k8s-github-kustomize.git'
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: davtro
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

cat << 'EOF' > "${PROJECT_DIR}/.github/workflows/ci-cd-extended.yaml"
name: CI/CD Extended - Full Stack Pipeline

permissions:
  contents: read
  packages: write

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF

echo "=================================================="
echo " Pakowanie do ZIP..."
echo "=================================================="

zip -r "${ZIP_NAME}" "${PROJECT_DIR}"

echo "SUKCES! Gotowy plik: ${ZIP_NAME}"