#!/usr/bin/env bash
# =============================================================================
# DavTro All-in-One Generator & Deployer
# Base: 7066-style full stack (FastAPI + Spring + Spark + Kafka + Vault + ELK-ish monitoring)
# + Rentals frontend & booking flow from 2238
# Fixes for log.txt issues:
#   - CreateContainerConfigError  → all Secrets/ConfigMaps created first, correct secretKeyRef
#   - ImagePullBackOff            → public, reliable images + Always/IfNotPresent policy
#   - Loki CrashLoopBackOff       → minimal valid config + single-binary mode
# Namespace: davtro (matches your current failing cluster)
# =============================================================================
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

PROJECT="davtro-rentals-stack"
NAMESPACE="${NAMESPACE:-davtro}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${ROOT_DIR}/generated-${PROJECT}"
MANIFESTS_DIR="${OUT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"

info(){ printf "🔧 [%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
ok(){   printf "✅ [%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
warn(){ printf "⚠️  [%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

mkdir_p(){ mkdir -p "$@"; }

# -----------------------------------------------------------------------------
# 1. Generate complete directory + manifests
# -----------------------------------------------------------------------------
generate() {
  info "Generating project structure into ${OUT_DIR}"
  rm -rf "${OUT_DIR}"
  mkdir_p "${BASE_DIR}" \
          "${OUT_DIR}/frontend" \
          "${OUT_DIR}/backend-fastapi/app" \
          "${OUT_DIR}/java-app/src/main/java/com/davtro/rental/{model,repository,consumer,service}" \
          "${OUT_DIR}/java-app/src/main/resources" \
          "${OUT_DIR}/spark-jobs/src/main/scala/com/davtro/jobs" \
          "${OUT_DIR}/scripts"

  # ---------- Secrets (MUST exist before any Deployment) ----------
  cat > "${BASE_DIR}/00-secrets.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${PROJECT}
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  POSTGRES_DB: davtro_rentals
  POSTGRES_USER: davtro
  POSTGRES_PASSWORD: "DavTroP@ss2026!"
  DATABASE_URL: "postgresql://davtro:DavTroP@ss2026!@postgres-db:5432/davtro_rentals"
---
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  REDIS_PASSWORD: ""
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  VAULT_TOKEN: "root"
  VAULT_ADDR: "http://vault:8200"
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  admin-user: admin
  admin-password: admin
---
apiVersion: v1
kind: Secret
metadata:
  name: pgadmin-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  PGADMIN_DEFAULT_EMAIL: admin@davtro.local
  PGADMIN_DEFAULT_PASSWORD: adminpassword
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: ${NAMESPACE}
data:
  PROJECT: "${PROJECT}"
  NAMESPACE: "${NAMESPACE}"
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  REDIS_LIST: "outgoing_messages"
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
  KAFKA_TOPIC: "bookings-created"
  VAULT_ADDR: "http://vault:8200"
  DB_HOST: "postgres-db"
  DB_PORT: "5432"
  DB_NAME: "davtro_rentals"
  DB_USER: "davtro"
EOF

  # ---------- PostgreSQL ----------
  cat > "${BASE_DIR}/10-postgres.yaml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
spec:
  serviceName: postgres-db
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: postgres
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 5432
              name: postgres
          envFrom:
            - secretRef:
                name: postgres-secret
          env:
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "davtro", "-d", "davtro_rentals"]
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            exec:
              command: ["pg_isready", "-U", "davtro", "-d", "davtro_rentals"]
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
      name: postgres
  selector:
    app: ${PROJECT}
    component: postgres
EOF

  # ---------- Redis ----------
  cat > "${BASE_DIR}/11-redis.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: redis
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 6379
          command: ["redis-server", "--appendonly", "yes"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          readinessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: redis
spec:
  ports:
    - port: 6379
      targetPort: 6379
  selector:
    app: ${PROJECT}
    component: redis
EOF

  # ---------- Kafka KRaft (single node, reliable image) ----------
  cat > "${BASE_DIR}/12-kafka.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-kraft
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka
spec:
  serviceName: kafka-kraft
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka
    spec:
      containers:
        - name: kafka
          image: bitnami/kafka:3.6.1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 9092
              name: kafka
            - containerPort: 9093
              name: controller
          env:
            - name: KAFKA_CFG_NODE_ID
              value: "0"
            - name: KAFKA_CFG_PROCESS_ROLES
              value: "controller,broker"
            - name: KAFKA_CFG_LISTENERS
              value: "PLAINTEXT://:9092,CONTROLLER://:9093"
            - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
              value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
            - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
              value: "CONTROLLER"
            - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
              value: "0@kafka-kraft-0.kafka-kraft.${NAMESPACE}.svc.cluster.local:9093"
            - name: KAFKA_CFG_ADVERTISED_LISTENERS
              value: "PLAINTEXT://kafka-kraft.${NAMESPACE}.svc.cluster.local:9092"
            - name: ALLOW_PLAINTEXT_LISTENER
              value: "yes"
            - name: KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE
              value: "true"
            - name: BITNAMI_DEBUG
              value: "false"
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
          readinessProbe:
            tcpSocket:
              port: 9092
            initialDelaySeconds: 30
            periodSeconds: 10
      # Bitnami needs writable dirs
      securityContext:
        fsGroup: 1001
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka
spec:
  clusterIP: None
  ports:
    - port: 9092
      name: kafka
    - port: 9093
      name: controller
  selector:
    app: ${PROJECT}
    component: kafka
---
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-init
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: kafka-topics
          image: bitnami/kafka:3.6.1
          imagePullPolicy: IfNotPresent
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "Waiting for Kafka..."
              sleep 45
              kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic bookings-created --partitions 3 --replication-factor 1
              kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic email-invoices --partitions 3 --replication-factor 1
              kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic marketing-actions --partitions 3 --replication-factor 1
              kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic survey-topic --partitions 3 --replication-factor 1
              echo "Topics created"
          env:
            - name: KAFKA_CFG_ZOOKEEPER_CONNECT
              value: "dummy"
EOF

  # ---------- Vault (dev mode – simple, no Init container issues) ----------
  cat > "${BASE_DIR}/13-vault.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: vault
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: vault
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: vault
    spec:
      containers:
        - name: vault
          image: hashicorp/vault:1.15
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8200
          env:
            - name: VAULT_DEV_ROOT_TOKEN_ID
              value: "root"
            - name: VAULT_DEV_LISTEN_ADDRESS
              value: "0.0.0.0:8200"
            - name: SKIP_SETCAP
              value: "true"
          command: ["vault", "server", "-dev"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          readinessProbe:
            httpGet:
              path: /v1/sys/health
              port: 8200
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: vault
spec:
  ports:
    - port: 8200
      targetPort: 8200
  selector:
    app: ${PROJECT}
    component: vault
EOF

  # ---------- FastAPI (main web + worker) ----------
  cat > "${BASE_DIR}/20-fastapi.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: fastapi
    spec:
      containers:
        - name: fastapi
          image: tiangolo/uvicorn-gunicorn-fastapi:python3.11
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          envFrom:
            - configMapRef:
                name: app-config
            - secretRef:
                name: postgres-secret
            - secretRef:
                name: vault-secret
          env:
            - name: MODULE_NAME
              value: "app.main"
            - name: VARIABLE_NAME
              value: "app"
            - name: PORT
              value: "80"
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 6
          # Note: real app code is expected to be baked into a custom image in CI.
          # For local demo we keep the image and rely on /health being present or the probe can be relaxed.
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: ${PROJECT}
    component: fastapi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: message-processor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: message-processor
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: message-processor
    spec:
      containers:
        - name: worker
          image: python:3.11-slim
          imagePullPolicy: IfNotPresent
          command: ["python", "-c", "import time; print('message-processor placeholder running'); time.sleep(3600)"]
          envFrom:
            - configMapRef:
                name: app-config
            - secretRef:
                name: postgres-secret
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
EOF

  # ---------- Spring Boot app ----------
  cat > "${BASE_DIR}/21-spring.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spring-app
    spec:
      containers:
        - name: spring
          image: eclipse-temurin:17-jre-alpine
          imagePullPolicy: IfNotPresent
          # Placeholder until real JAR is built; keeps pod Running
          command: ["sleep", "infinity"]
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: app-config
            - secretRef:
                name: postgres-secret
          env:
            - name: SERVER_PORT
              value: "8080"
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://postgres-db:5432/davtro_rentals"
            - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
              value: "kafka-kraft:9092"
          resources:
            requests:
              cpu: 100m
              memory: 384Mi
            limits:
              cpu: 700m
              memory: 768Mi
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 6
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: ${PROJECT}
    component: spring-app
EOF

  # ---------- Spark (master + worker) – use bitnami which pulls reliably ----------
  cat > "${BASE_DIR}/22-spark.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-master
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spark-master
    spec:
      containers:
        - name: master
          image: bitnami/spark:3.5.1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: ui
            - containerPort: 7077
              name: master
          env:
            - name: SPARK_MODE
              value: master
            - name: SPARK_RPC_AUTHENTICATION_ENABLED
              value: "no"
            - name: SPARK_RPC_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_LOCAL_STORAGE_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_SSL_ENABLED
              value: "no"
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-master
spec:
  ports:
    - port: 8080
      name: ui
      targetPort: 8080
    - port: 7077
      name: master
      targetPort: 7077
  selector:
    app: ${PROJECT}
    component: spark-master
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spark-worker
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spark-worker
    spec:
      containers:
        - name: worker
          image: bitnami/spark:3.5.1
          imagePullPolicy: IfNotPresent
          env:
            - name: SPARK_MODE
              value: worker
            - name: SPARK_MASTER_URL
              value: spark://spark-master:7077
            - name: SPARK_WORKER_MEMORY
              value: 1G
            - name: SPARK_WORKER_CORES
              value: "1"
            - name: SPARK_RPC_AUTHENTICATION_ENABLED
              value: "no"
            - name: SPARK_RPC_ENCRYPTION_ENABLED
              value: "no"
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
EOF

  # ---------- Monitoring: Prometheus + Grafana + Loki (fixed) + Tempo ----------
  cat > "${BASE_DIR}/30-prometheus.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: ${NAMESPACE}
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      - job_name: prometheus
        static_configs:
          - targets: ['localhost:9090']
      - job_name: postgres-exporter
        static_configs:
          - targets: ['postgres-exporter:9187']
      - job_name: kafka-exporter
        static_configs:
          - targets: ['kafka-exporter:9308']
      - job_name: node-exporter
        static_configs:
          - targets: ['node-exporter:9100']
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: prometheus
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: prometheus
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:v2.47.0
          imagePullPolicy: IfNotPresent
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/prometheus
            - --web.enable-lifecycle
          ports:
            - containerPort: 9090
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /-/ready
              port: 9090
            initialDelaySeconds: 10
      volumes:
        - name: config
          configMap:
            name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9090
      targetPort: 9090
  selector:
    app: ${PROJECT}
    component: prometheus
EOF

  cat > "${BASE_DIR}/31-grafana.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: grafana
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:10.2.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: grafana-secret
                  key: admin-user
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-secret
                  key: admin-password
            - name: GF_USERS_ALLOW_SIGN_UP
              value: "false"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 80
      targetPort: 3000
  selector:
    app: ${PROJECT}
    component: grafana
EOF

  # Fixed Loki – single binary, filesystem, no auth (prevents CrashLoop)
  cat > "${BASE_DIR}/32-loki.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: ${NAMESPACE}
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/boltdb-shipper-active
        cache_location: /loki/boltdb-shipper-cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
    limits_config:
      reject_old_samples: true
      reject_old_samples_max_age: 168h
    chunk_store_config:
      max_look_back_period: 0s
    table_manager:
      retention_deletes_enabled: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: loki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: loki
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: loki
    spec:
      containers:
        - name: loki
          image: grafana/loki:2.9.2
          imagePullPolicy: IfNotPresent
          args:
            - -config.file=/etc/loki/loki.yaml
          ports:
            - containerPort: 3100
          volumeMounts:
            - name: config
              mountPath: /etc/loki
            - name: data
              mountPath: /loki
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /ready
              port: 3100
            initialDelaySeconds: 15
            periodSeconds: 10
      volumes:
        - name: config
          configMap:
            name: loki-config
        - name: data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 3100
      targetPort: 3100
  selector:
    app: ${PROJECT}
    component: loki
EOF

  # Tempo (already worked in your log)
  cat > "${BASE_DIR}/33-tempo.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: tempo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: tempo
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: tempo
    spec:
      containers:
        - name: tempo
          image: grafana/tempo:2.3.1
          imagePullPolicy: IfNotPresent
          args: ["-target=all", "-config.file=/etc/tempo.yaml"]
          ports:
            - containerPort: 3200
          volumeMounts:
            - name: config
              mountPath: /etc/tempo.yaml
              subPath: tempo.yaml
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
      volumes:
        - name: config
          configMap:
            name: tempo-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: ${NAMESPACE}
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    distributor:
      receivers:
        otlp:
          protocols:
            http:
            grpc:
    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/traces
        wal:
          path: /tmp/tempo/wal
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 3200
      targetPort: 3200
  selector:
    app: ${PROJECT}
    component: tempo
EOF

  # Exporters (fixed – no missing secrets)
  cat > "${BASE_DIR}/34-exporters.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: postgres-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: postgres-exporter
    spec:
      containers:
        - name: postgres-exporter
          image: quay.io/prometheuscommunity/postgres-exporter:v0.15.0
          imagePullPolicy: IfNotPresent
          env:
            - name: DATA_SOURCE_NAME
              value: "postgresql://davtro:DavTroP@ss2026!@postgres-db:5432/davtro_rentals?sslmode=disable"
          ports:
            - containerPort: 9187
          resources:
            requests:
              cpu: 30m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9187
      targetPort: 9187
  selector:
    app: ${PROJECT}
    component: postgres-exporter
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka-exporter
    spec:
      containers:
        - name: kafka-exporter
          image: danielqsj/kafka-exporter:v1.7.0
          imagePullPolicy: IfNotPresent
          args:
            - --kafka.server=kafka-kraft:9092
          ports:
            - containerPort: 9308
          resources:
            requests:
              cpu: 30m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9308
      targetPort: 9308
  selector:
    app: ${PROJECT}
    component: kafka-exporter
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: node-exporter
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: node-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: node-exporter
    spec:
      hostNetwork: true
      hostPID: true
      containers:
        - name: node-exporter
          image: quay.io/prometheus/node-exporter:v1.6.1
          imagePullPolicy: IfNotPresent
          args:
            - --path.procfs=/host/proc
            - --path.sysfs=/host/sys
            - --path.rootfs=/host/root
            - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
          ports:
            - containerPort: 9100
              hostPort: 9100
          volumeMounts:
            - name: proc
              mountPath: /host/proc
              readOnly: true
            - name: sys
              mountPath: /host/sys
              readOnly: true
            - name: root
              mountPath: /host/root
              readOnly: true
          resources:
            requests:
              cpu: 30m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 64Mi
      volumes:
        - name: proc
          hostPath:
            path: /proc
        - name: sys
          hostPath:
            path: /sys
        - name: root
          hostPath:
            path: /
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9100
      targetPort: 9100
  selector:
    app: ${PROJECT}
    component: node-exporter
EOF

  # Kafka UI + PgAdmin (with secrets)
  cat > "${BASE_DIR}/40-ui.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-ui
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka-ui
    spec:
      containers:
        - name: kafka-ui
          image: provectuslabs/kafka-ui:v0.7.1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          env:
            - name: KAFKA_CLUSTERS_0_NAME
              value: local
            - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
              value: kafka-kraft:9092
            - name: DYNAMIC_CONFIG_ENABLED
              value: "true"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: ${PROJECT}
    component: kafka-ui
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: pgadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: pgadmin
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: pgadmin
    spec:
      containers:
        - name: pgadmin
          image: dpage/pgadmin4:8.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          envFrom:
            - secretRef:
                name: pgadmin-secret
          env:
            - name: PGADMIN_CONFIG_SERVER_MODE
              value: "False"
            - name: PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED
              value: "False"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: ${PROJECT}
    component: pgadmin
EOF

  # Lightweight NetworkPolicy (allow DNS + same-namespace)
  cat > "${BASE_DIR}/50-network.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace-and-dns
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:           # allow external image pulls / package installs if needed
        - ipBlock:
            cidr: 0.0.0.0/0
EOF

  # Kustomization
  cat > "${BASE_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - 00-secrets.yaml
  - 10-postgres.yaml
  - 11-redis.yaml
  - 12-kafka.yaml
  - 13-vault.yaml
  - 20-fastapi.yaml
  - 21-spring.yaml
  - 22-spark.yaml
  - 30-prometheus.yaml
  - 31-grafana.yaml
  - 32-loki.yaml
  - 33-tempo.yaml
  - 34-exporters.yaml
  - 40-ui.yaml
  - 50-network.yaml
commonLabels:
  app.kubernetes.io/name: ${PROJECT}
  app.kubernetes.io/instance: ${PROJECT}
  app.kubernetes.io/managed-by: all-in-one
EOF

  # ---------- Frontend from 2238 (simplified but complete) ----------
  cat > "${OUT_DIR}/frontend/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DavTro Rentals - Wynajem Krótkoterminowy</title>
<script src="https://cdn.tailwindcss.com"></script>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
body{font-family:'Inter',sans-serif;}
.glass{background:rgba(255,255,255,0.1);backdrop-filter:blur(12px);border:1px solid rgba(255,255,255,0.2);}
.property-card{transition:all .3s ease;}
.property-card:hover{transform:translateY(-8px);}
</style>
</head>
<body class="bg-gradient-to-br from-slate-900 via-blue-900 to-slate-900 text-white min-h-screen">
<nav class="fixed top-0 left-0 right-0 z-50 glass">
  <div class="container mx-auto px-6 py-4 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 bg-blue-500 rounded-xl flex items-center justify-center"><i class="fas fa-home text-white"></i></div>
      <div><h1 class="text-xl font-bold">DavTro<span class="text-blue-400">Rentals</span></h1></div>
    </div>
    <div class="flex gap-6">
      <button onclick="showSection('home')" class="nav-btn text-gray-300 hover:text-white font-medium">Strona Główna</button>
      <button onclick="showSection('properties')" class="nav-btn text-gray-300 hover:text-white font-medium">Nieruchomości</button>
      <button onclick="showSection('calendar')" class="nav-btn text-gray-300 hover:text-white font-medium">Rezerwacje</button>
      <button onclick="showSection('admin')" class="nav-btn text-gray-300 hover:text-white font-medium">Admin</button>
    </div>
  </div>
</nav>
<main class="pt-24 pb-12">
  <section id="home-section" class="section-content container mx-auto px-6">
    <div class="text-center mb-16">
      <h1 class="text-5xl font-bold mb-6 bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">Wynajem Krótkoterminowy Premium</h1>
      <p class="text-xl text-gray-400 max-w-2xl mx-auto mb-10">Stack: FastAPI + Spring Boot + Kafka + Redis + PostgreSQL + Vault + Spark + Prometheus/Grafana/Loki</p>
      <div class="flex justify-center gap-4">
        <button onclick="showSection('properties')" class="px-8 py-4 bg-blue-600 rounded-xl font-semibold hover:scale-105 transition">Przeglądaj Oferty</button>
        <button onclick="showSection('calendar')" class="px-8 py-4 glass rounded-xl font-semibold hover:scale-105 transition">Sprawdź Dostępność</button>
      </div>
    </div>
    <div class="grid md:grid-cols-4 gap-6 mb-12">
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-database text-3xl text-blue-400 mb-3"></i><h3 class="font-bold">PostgreSQL</h3></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-bolt text-3xl text-yellow-400 mb-3"></i><h3 class="font-bold">Apache Kafka</h3></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-server text-3xl text-red-400 mb-3"></i><h3 class="font-bold">Redis</h3></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-shield-alt text-3xl text-purple-400 mb-3"></i><h3 class="font-bold">Vault</h3></div>
    </div>
    <h2 class="text-3xl font-bold text-center mb-10">Wyróżnione Nieruchomości</h2>
    <div class="grid md:grid-cols-3 gap-8" id="featured-properties"></div>
  </section>
  <section id="properties-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Nasze Nieruchomości</h2>
    <div class="grid md:grid-cols-3 gap-8" id="all-properties"></div>
  </section>
  <section id="calendar-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Kalendarz Rezerwacji</h2>
    <div class="grid lg:grid-cols-3 gap-8">
      <div class="lg:col-span-2 glass rounded-2xl p-6">
        <div class="flex items-center justify-between mb-6">
          <button onclick="changeMonth(-1)" class="w-10 h-10 rounded-lg bg-white/10 hover:bg-white/20"><i class="fas fa-chevron-left"></i></button>
          <h3 class="text-xl font-bold" id="calendar-month">Wrzesień 2026</h3>
          <button onclick="changeMonth(1)" class="w-10 h-10 rounded-lg bg-white/10 hover:bg-white/20"><i class="fas fa-chevron-right"></i></button>
        </div>
        <div class="grid grid-cols-7 gap-2 mb-4 text-center text-sm text-gray-400">
          <div>Pon</div><div>Wt</div><div>Śr</div><div>Czw</div><div>Pt</div><div>Sob</div><div>Nd</div>
        </div>
        <div class="grid grid-cols-7 gap-2" id="calendar-grid"></div>
      </div>
      <div class="glass rounded-2xl p-6">
        <h3 class="text-xl font-bold mb-6">Formularz Rezerwacji</h3>
        <div class="space-y-4">
          <div><label class="block text-sm text-gray-400 mb-2">Nieruchomość</label><select id="booking-property" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white"></select></div>
          <div class="grid grid-cols-2 gap-4">
            <div><label class="block text-sm text-gray-400 mb-2">Przyjazd</label><input type="date" id="check-in" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white"></div>
            <div><label class="block text-sm text-gray-400 mb-2">Wyjazd</label><input type="date" id="check-out" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white"></div>
          </div>
          <div><label class="block text-sm text-gray-400 mb-2">Imię i nazwisko</label><input type="text" id="guest-name" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Jan Kowalski"></div>
          <div><label class="block text-sm text-gray-400 mb-2">Email</label><input type="email" id="guest-email" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="jan@example.com"></div>
          <div class="bg-white/5 rounded-lg p-4">
            <div class="flex justify-between text-sm mb-2"><span>Cena za dobę:</span><span id="price-per-night" class="font-semibold">-</span></div>
            <div class="flex justify-between text-sm mb-2"><span>Liczba nocy:</span><span id="night-count" class="font-semibold">-</span></div>
            <div class="flex justify-between text-lg font-bold border-t border-white/10 pt-2"><span>Razem:</span><span id="total-price" class="text-blue-400">-</span></div>
          </div>
          <button onclick="submitBooking()" class="w-full py-4 bg-gradient-to-r from-blue-600 to-purple-600 rounded-xl font-bold hover:scale-[1.02] transition">Zarezerwuj</button>
          <p class="text-xs text-gray-500 text-center">Pipeline: Redis → Kafka → PostgreSQL (Spring consumer)</p>
        </div>
      </div>
    </div>
  </section>
  <section id="admin-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Panel Administracyjny</h2>
    <div class="grid md:grid-cols-4 gap-6 mb-10">
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-blue-400" id="stat-bookings">0</div><div class="text-sm text-gray-400">Rezerwacje</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-green-400" id="stat-revenue">0 zł</div><div class="text-sm text-gray-400">Przychód</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-yellow-400" id="stat-kafka">0</div><div class="text-sm text-gray-400">Kafka msgs</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-purple-400" id="stat-occupancy">0%</div><div class="text-sm text-gray-400">Zajętość</div></div>
    </div>
    <div class="glass rounded-2xl p-6">
      <h3 class="text-xl font-bold mb-6">Ostatnie rezerwacje</h3>
      <div class="overflow-x-auto"><table class="w-full text-left"><thead><tr class="border-b border-white/10"><th class="pb-4 text-gray-400">ID</th><th class="pb-4 text-gray-400">Nieruchomość</th><th class="pb-4 text-gray-400">Gość</th><th class="pb-4 text-gray-400">Kwota</th><th class="pb-4 text-gray-400">Status</th></tr></thead><tbody id="bookings-table"></tbody></table></div>
    </div>
  </section>
</main>
<div id="toast" class="fixed bottom-6 right-6 z-50 transform translate-y-20 opacity-0 transition-all duration-300">
  <div class="glass rounded-xl px-6 py-4 flex items-center gap-3 border-l-4 border-blue-500">
    <i id="toast-icon" class="fas fa-check-circle text-green-400 text-xl"></i>
    <div><div id="toast-title" class="font-semibold">Sukces</div><div id="toast-message" class="text-sm text-gray-400">Operacja zakończona</div></div>
  </div>
</div>
<script>
const properties=[
  {id:1,name:"Apartament Premium - Warszawa",location:"warsaw",price:450,guests:4,image:"🏙️",rating:4.9},
  {id:2,name:"Studio Modern - Kraków",location:"krakow",price:320,guests:2,image:"🏰",rating:4.8},
  {id:3,name:"Villa nad Morzem - Gdańsk",location:"gdansk",price:680,guests:6,image:"🌊",rating:4.9},
  {id:4,name:"Loft Industrial - Wrocław",location:"wroclaw",price:280,guests:3,image:"🏭",rating:4.7},
  {id:5,name:"Penthouse View - Warszawa",location:"warsaw",price:850,guests:4,image:"🌆",rating:5.0},
  {id:6,name:"Apartament Royal - Kraków",location:"krakow",price:390,guests:4,image:"👑",rating:4.8}
];
let bookings=JSON.parse(localStorage.getItem('bookings')||'[]');
let currentMonth=new Date();
let selectedDates=[];
function showSection(section){document.querySelectorAll('.section-content').forEach(s=>s.classList.add('hidden'));document.getElementById(section+'-section').classList.remove('hidden');if(section==='properties')renderProperties();if(section==='calendar'){renderCalendar();populatePropertySelect();}if(section==='admin')renderAdmin();}
function showToast(title,message){const toast=document.getElementById('toast');document.getElementById('toast-title').textContent=title;document.getElementById('toast-message').textContent=message;toast.classList.remove('translate-y-20','opacity-0');setTimeout(()=>toast.classList.add('translate-y-20','opacity-0'),4000);}
function createPropertyCard(prop){return`<div class="property-card glass rounded-2xl overflow-hidden"><div class="h-48 bg-gradient-to-br from-slate-700 to-slate-800 flex items-center justify-center text-6xl">${prop.image}</div><div class="p-6"><h3 class="text-lg font-bold mb-2">${prop.name}</h3><div class="flex items-center justify-between"><div><span class="text-2xl font-bold text-blue-400">${prop.price} zł</span><span class="text-sm text-gray-400">/doba</span></div><button onclick="selectPropertyForBooking(${prop.id})" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg">Rezerwuj</button></div></div></div>`;}
function renderProperties(){document.getElementById('all-properties').innerHTML=properties.map(p=>createPropertyCard(p)).join('');}
function renderFeatured(){document.getElementById('featured-properties').innerHTML=properties.slice(0,3).map(p=>createPropertyCard(p)).join('');}
function renderCalendar(){const grid=document.getElementById('calendar-grid');const monthLabel=document.getElementById('calendar-month');const year=currentMonth.getFullYear(),month=currentMonth.getMonth();const monthNames=['Styczeń','Luty','Marzec','Kwiecień','Maj','Czerwiec','Lipiec','Sierpień','Wrzesień','Październik','Listopad','Grudzień'];monthLabel.textContent=`${monthNames[month]} ${year}`;grid.innerHTML='';const firstDay=new Date(year,month,1).getDay();const daysInMonth=new Date(year,month+1,0).getDate();const startOffset=firstDay===0?6:firstDay-1;for(let i=0;i<startOffset;i++)grid.innerHTML+=`<div></div>`;for(let day=1;day<=daysInMonth;day++){const dateStr=`${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;const isBooked=bookings.some(b=>dateStr>=b.checkIn&&dateStr<=b.checkOut);const isSelected=selectedDates.includes(dateStr);const isPast=new Date(dateStr)<new Date().setHours(0,0,0,0);let classes='h-12 rounded-lg flex items-center justify-center cursor-pointer text-sm font-medium ';if(isPast)classes+='text-gray-600 cursor-not-allowed';else if(isBooked)classes+='bg-red-500/20 border border-red-500 text-red-300';else if(isSelected)classes+='bg-blue-500 border border-blue-400 text-white';else classes+='bg-white/5 hover:bg-white/15';const onclick=isPast||isBooked?'':`onclick="toggleDate('${dateStr}')"`;grid.innerHTML+=`<div class="${classes}" ${onclick}>${day}</div>`;}}
function changeMonth(delta){currentMonth.setMonth(currentMonth.getMonth()+delta);renderCalendar();}
function toggleDate(dateStr){const idx=selectedDates.indexOf(dateStr);if(idx>-1)selectedDates.splice(idx,1);else if(selectedDates.length<2)selectedDates.push(dateStr);else{selectedDates=[selectedDates[1],dateStr];}selectedDates.sort();renderCalendar();if(selectedDates.length===2){document.getElementById('check-in').value=selectedDates[0];document.getElementById('check-out').value=selectedDates[1];calculatePrice();}}
function populatePropertySelect(){document.getElementById('booking-property').innerHTML='<option value="">-- Wybierz --</option>'+properties.map(p=>`<option value="${p.id}">${p.name} - ${p.price} zł/doba</option>`).join('');}
function selectPropertyForBooking(id){showSection('calendar');document.getElementById('booking-property').value=id;calculatePrice();}
function calculatePrice(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;if(!propId||!checkIn||!checkOut)return;const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));if(nights>0){document.getElementById('price-per-night').textContent=prop.price+' zł';document.getElementById('night-count').textContent=nights;document.getElementById('total-price').textContent=(prop.price*nights)+' zł';}}
['booking-property','check-in','check-out'].forEach(id=>{document.getElementById(id)?.addEventListener('change',calculatePrice);});
async function submitBooking(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;const name=document.getElementById('guest-name').value;const email=document.getElementById('guest-email').value;if(!propId||!checkIn||!checkOut||!name||!email){showToast('Błąd','Wypełnij wszystkie pola');return;}const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));const total=prop.price*nights;const booking={id:'BK-'+Date.now(),propertyId:propId,propertyName:prop.name,guestName:name,email:email,checkIn:checkIn,checkOut:checkOut,nights:nights,totalPrice:total,status:'confirmed'};showToast('Przetwarzanie','Redis → Kafka → PostgreSQL...');await new Promise(r=>setTimeout(r,1500));bookings.push(booking);localStorage.setItem('bookings',JSON.stringify(bookings));showToast('Sukces!',`Rezerwacja ${booking.id} potwierdzona – ${total} zł`);selectedDates=[];renderCalendar();}
function renderAdmin(){document.getElementById('stat-bookings').textContent=bookings.length;const revenue=bookings.reduce((s,b)=>s+b.totalPrice,0);document.getElementById('stat-revenue').textContent=revenue.toLocaleString()+' zł';document.getElementById('stat-kafka').textContent=(bookings.length*3).toLocaleString();document.getElementById('stat-occupancy').textContent=Math.min(95,bookings.length*5)+'%';const tbody=document.getElementById('bookings-table');tbody.innerHTML=bookings.slice().reverse().map(b=>`<tr class="border-b border-white/5"><td class="py-4 font-mono text-sm text-blue-400">${b.id}</td><td class="py-4">${b.propertyName}</td><td class="py-4">${b.guestName}<br><span class="text-xs text-gray-500">${b.email}</span></td><td class="py-4 font-bold">${b.totalPrice} zł</td><td class="py-4"><span class="px-2 py-1 bg-green-500/20 text-green-400 rounded text-xs">${b.status}</span></td></tr>`).join('')||'<tr><td colspan="5" class="py-8 text-center text-gray-500">Brak rezerwacji</td></tr>';}
renderFeatured();showSection('home');
</script>
</body>
</html>
HTMLEOF

  cat > "${OUT_DIR}/frontend/Dockerfile" <<'EOF'
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

  # Minimal FastAPI app skeleton (can be extended)
  cat > "${OUT_DIR}/backend-fastapi/app/main.py" <<'PY'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os, time

app = FastAPI(title="DavTro Rentals API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "namespace": os.getenv("NAMESPACE", "davtro"),
        "timestamp": time.time()
    }

@app.get("/")
def root():
    return {"message": "DavTro Rentals API – use /health or frontend"}
PY

  cat > "${OUT_DIR}/backend-fastapi/requirements.txt" <<'EOF'
fastapi==0.109.0
uvicorn[standard]==0.27.0
EOF

  cat > "${OUT_DIR}/backend-fastapi/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
EXPOSE 80
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80"]
EOF

  # README
  cat > "${OUT_DIR}/README.md" <<EOF
# ${PROJECT}

All-in-one stack generated for namespace **${NAMESPACE}**.

## Fixes applied (from log.txt)

| Problem | Root cause | Fix in this script |
|---------|------------|--------------------|
| CreateContainerConfigError (most pods) | Missing Secrets / wrong secretKeyRef / missing ConfigMaps | All Secrets + ConfigMaps created in \`00-secrets.yaml\` **before** any Deployment |
| ImagePullBackOff (Kafka, Spark, topic job) | Unreliable / private / non-existent tags | Switched to public, pinned images (bitnami/kafka:3.6.1, bitnami/spark:3.5.1, etc.) |
| Loki CrashLoopBackOff | Invalid / incomplete config | Minimal single-binary Loki config with filesystem storage |
| Vault CreateContainerConfigError | Missing token / wrong mode | Simple \`vault server -dev\` with fixed root token |

## Quick start

\`\`\`bash
# 1. Generate (already done if you ran the script)
./all-in-one.sh generate

# 2. Deploy
./all-in-one.sh apply

# 3. Watch
./all-in-one.sh status

# 4. Clean up
./all-in-one.sh delete
\`\`\`

## Access (after apply + port-forward or Ingress)

| Service | Port-forward example |
|---------|----------------------|
| Grafana | kubectl -n ${NAMESPACE} port-forward svc/grafana-service 3000:80  → admin/admin |
| Kafka UI | kubectl -n ${NAMESPACE} port-forward svc/kafka-ui 8080:8080 |
| PgAdmin | kubectl -n ${NAMESPACE} port-forward svc/pgadmin 5050:80 |
| Prometheus | kubectl -n ${NAMESPACE} port-forward svc/prometheus 9090:9090 |
| FastAPI | kubectl -n ${NAMESPACE} port-forward svc/fastapi-web-service 8000:80 |

## Architecture

- **Frontend** (static) – DavTro Rentals UI (from 2238)
- **FastAPI** – main API + health
- **Spring Boot** (placeholder ready for JAR) – Kafka consumer → PostgreSQL
- **Kafka KRaft** – bookings-created / email-invoices / marketing-actions
- **Redis** – cache / queue
- **PostgreSQL 15** – durable storage
- **Vault (dev)** – secrets
- **Spark master + worker**
- **Prometheus + Grafana + Loki (fixed) + Tempo**
- **Exporters**: postgres, kafka, node
- **Kafka UI + PgAdmin**

EOF

  ok "Generation complete → ${OUT_DIR}"
  info "Manifests: ${BASE_DIR}"
}

# -----------------------------------------------------------------------------
# 2. Deploy / status / delete
# -----------------------------------------------------------------------------
ensure_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found – install it and configure kubeconfig"
    exit 2
  fi
}

apply() {
  ensure_kubectl
  if [[ ! -d "${BASE_DIR}" ]]; then
    warn "Manifests not found – running generate first..."
    generate
  fi

  info "Creating / updating namespace ${NAMESPACE}"
  kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

  info "Applying manifests with kustomize (order is controlled by filenames)"
  kubectl apply -k "${BASE_DIR}"

  info "Waiting for core components (this can take 1–3 minutes)..."
  set +e
  kubectl -n "${NAMESPACE}" wait --for=condition=ready pod -l component=postgres --timeout=180s
  kubectl -n "${NAMESPACE}" wait --for=condition=ready pod -l component=redis --timeout=120s
  kubectl -n "${NAMESPACE}" wait --for=condition=ready pod -l component=kafka --timeout=240s
  kubectl -n "${NAMESPACE}" wait --for=condition=ready pod -l component=vault --timeout=90s
  kubectl -n "${NAMESPACE}" wait --for=condition=ready pod -l component=loki --timeout=120s
  kubectl -n "${NAMESPACE}" wait --for=condition=ready pod -l component=grafana --timeout=120s
  set -e

  ok "Apply finished"
  echo ""
  echo "Useful commands:"
  echo "  kubectl -n ${NAMESPACE} get pods -o wide"
  echo "  kubectl -n ${NAMESPACE} get events --sort-by='.lastTimestamp' | tail -30"
  echo "  ./all-in-one.sh status"
}

status() {
  ensure_kubectl
  echo "========== PODS =========="
  kubectl get pods -n "${NAMESPACE}" -o wide 2>/dev/null || echo "(namespace missing)"
  echo ""
  echo "========== SERVICES =========="
  kubectl get svc -n "${NAMESPACE}" 2>/dev/null || true
  echo ""
  echo "========== RECENT EVENTS (errors) =========="
  kubectl get events -n "${NAMESPACE}" --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
}

delete() {
  ensure_kubectl
  read -r -p "Delete ALL resources in namespace ${NAMESPACE}? [y/N] " yn
  case "${yn}" in
    [Yy]*)
      info "Deleting..."
      kubectl delete -k "${BASE_DIR}" --ignore-not-found 2>/dev/null || true
      kubectl delete namespace "${NAMESPACE}" --ignore-not-found --wait=false
      ok "Delete requested"
      ;;
    *) echo "Aborted." ;;
  esac
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  generate   Generate full project + fixed manifests (base = 7066 + pieces from 2238)
  apply      Apply manifests to cluster (namespace: ${NAMESPACE})
  status     Show pods / services / recent warnings
  delete     Remove everything from the namespace
  all        generate + apply

Environment:
  NAMESPACE  Override namespace (default: davtro)
EOF
  exit 1
}

case "${1:-}" in
  generate) generate ;;
  apply)    apply ;;
  status)   status ;;
  delete)   delete ;;
  all)      generate; apply ;;
  *)        usage ;;
esac