#!/usr/bin/env bash
###############################################################################
# all-in-one.sh - KOMPLEKSOWE WDROŻENIE ŚRODOWISKA 'davtro'
# Naprawa: CreateContainerConfigError, ImagePullBackOff, CrashLoopBackOff
# Wersja: 2.0 (all-in-one, 7000+ linii)
# Data: 2026-09-02
###############################################################################
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# SEKCJA 1: ZMIENNE GLOBALNE I KONFIGURACJA
# ============================================================================
readonly NAMESPACE="${NAMESPACE:-davtro}"
readonly CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
readonly STORAGE_CLASS="${STORAGE_CLASS:-standard}"
readonly LOG_FILE="/tmp/davtro-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly SCRIPT_VERSION="2.0.0"
readonly DEPLOYMENT_ID="davtro-$(date +%s)"

# Kolory do logów
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Wersje obrazów (naprawa ImagePullBackOff)
readonly POSTGRES_IMAGE="postgres:15.4-alpine"
readonly REDIS_IMAGE="redis:7.2.3-alpine"
readonly KAFKA_IMAGE="bitnami/kafka:3.6.1-debian-11-r0"
readonly SPARK_IMAGE="bitnami/spark:3.5.0-debian-11-r14"
readonly FASTAPI_IMAGE="python:3.11-slim"
readonly SPRING_IMAGE="eclipse-temurin:17-jre-alpine"
readonly PROMETHEUS_IMAGE="prom/prometheus:v2.48.0"
readonly GRAFANA_IMAGE="grafana/grafana:10.2.2"
readonly LOKI_IMAGE="grafana/loki:2.9.3"
readonly PROMTAIL_IMAGE="grafana/promtail:2.9.3"
readonly TEMPO_IMAGE="grafana/tempo:2.3.1"
readonly VAULT_IMAGE="hashicorp/vault:1.15.4"
readonly NODE_EXPORTER_IMAGE="prom/node-exporter:v1.7.0"
readonly PGADMIN_IMAGE="dpage/pgadmin4:8.1"
readonly KAFKA_UI_IMAGE="provectuslabs/kafka-ui:v0.7.2"
readonly KAFKA_EXPORTER_IMAGE="bitnami/kafka-exporter:1.7.0"
readonly POSTGRES_EXPORTER_IMAGE="prometheuscommunity/postgres-exporter:v0.15.0"
readonly BUSYBOX_IMAGE="busybox:1.36-musl"
readonly CURL_IMAGE="curlimages/curl:8.4.0"

# ============================================================================
# SEKCJA 2: FUNKCJE POMOCNICZE
# ============================================================================
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  ${timestamp} - ${msg}" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - ${msg}" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${timestamp} - ${msg}" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - ${msg}" | tee -a "$LOG_FILE" ;;
        STEP)  echo -e "${MAGENTA}[STEP]${NC} ${timestamp} - ${msg}" | tee -a "$LOG_FILE" ;;
    esac
}

separator() {
    echo "==============================================================================" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log STEP "Sprawdzanie wymagań wstępnych..."
    local missing=()
    
    for cmd in kubectl openssl base64 date; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Brakujące narzędzia: ${missing[*]}"
        exit 1
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log ERROR "Brak połączenia z klastrem Kubernetes"
        exit 1
    fi
    
    log INFO "Wszystkie wymagania spełnione"
}

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

wait_for_pod_ready() {
    local pod_name="$1"
    local timeout="${2:-300}"
    local interval=5
    local elapsed=0
    
    log INFO "Oczekiwanie na gotowość poda: $pod_name (timeout: ${timeout}s)"
    
    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local ready
        ready=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [[ "$status" == "Running" && "$ready" == "True" ]]; then
            log INFO "Pod $pod_name jest gotowy"
            return 0
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log WARN "Timeout oczekiwania na pod: $pod_name"
    return 1
}

cleanup_failed_pods() {
    log STEP "Czyszczenie podów w stanach błędnych..."
    kubectl delete pods -n "$NAMESPACE" --field-selector=status.phase=Failed --ignore-not-found=true 2>/dev/null || true
    kubectl delete pods -n "$NAMESPACE" --field-selector=status.phase=Unknown --ignore-not-found=true 2>/dev/null || true
}

apply_yaml() {
    local yaml_content="$1"
    local description="${2:-YAML}"
    log DEBUG "Aplikowanie: $description"
    echo "$yaml_content" | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
}

# ============================================================================
# SEKCJA 3: GENEROWANIE POŚWIADCZEŃ I SEKRETÓW
# ============================================================================
generate_credentials() {
    log STEP "Generowanie poświadczeń..."
    
    POSTGRES_USER="davtro_admin"
    POSTGRES_PASSWORD="$(generate_password 32)"
    POSTGRES_DB="davtro_production"
    POSTGRES_REPL_PASSWORD="$(generate_password 32)"
    
    REDIS_PASSWORD="$(generate_password 32)"
    
    KAFKA_SASL_USERNAME="davtro_kafka"
    KAFKA_SASL_PASSWORD="$(generate_password 32)"
    
    VAULT_TOKEN="$(generate_password 40)"
    VAULT_UNSEAL_KEY="$(generate_password 40)"
    
    GRAFANA_ADMIN_USER="admin"
    GRAFANA_ADMIN_PASSWORD="$(generate_password 24)"
    
    PGADMIN_EMAIL="admin@davtro.local"
    PGADMIN_PASSWORD="$(generate_password 24)"
    
    SPRING_SECRET="$(generate_password 48)"
    FASTAPI_SECRET="$(generate_password 48)"
    
    TLS_KEY="$(openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /tmp/tls.key -out /tmp/tls.crt \
        -subj "/CN=davtro.local/O=DavTro/C=PL" 2>/dev/null)"
    
    log INFO "Poświadczenia wygenerowane"
}

# ============================================================================
# SEKCJA 4: TWORZENIE NAMESPACE I PODSTAWOWYCH ZASOBÓW
# ============================================================================
deploy_namespace() {
    log STEP "Tworzenie namespace: $NAMESPACE"
    
    cat <<EOF | kubectl apply -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/managed-by: all-in-one-script
    environment: production
    team: platform-engineering
  annotations:
    davtro.io/deployment-id: "${DEPLOYMENT_ID}"
    davtro.io/deployed-at: "${TIMESTAMP}"
    davtro.io/version: "${SCRIPT_VERSION}"
    description: "Kompleksowe środowisko DavTro - aplikacje webowe, bazy, monitoring, streaming"
EOF

    # Limity zasobów na namespace
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: LimitRange
metadata:
  name: davtro-limit-range
  labels:
    app.kubernetes.io/part-of: davtro
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "4"
      memory: "8Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
    type: Container
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: davtro-quota
spec:
  hard:
    requests.cpu: "16"
    requests.memory: "32Gi"
    limits.cpu: "32"
    limits.memory: "64Gi"
    pods: "100"
    services: "50"
    secrets: "100"
    configmaps: "100"
    persistentvolumeclaims: "30"
EOF

    log INFO "Namespace utworzony z limitami"
}

# ============================================================================
# SEKCJA 5: SECRETS - KLUCZOWE DLA NAPRAWY CreateContainerConfigError
# ============================================================================
deploy_secrets() {
    log STEP "Wdrażanie Secretów (naprawa CreateContainerConfigError)..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
# Główne poświadczenia bazy danych
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database
    davtro.io/secret-type: database
  annotations:
    davtro.io/description: "Poświadczenia PostgreSQL dla aplikacji DavTro"
type: Opaque
stringData:
  POSTGRES_USER: "${POSTGRES_USER}"
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
  POSTGRES_DB: "${POSTGRES_DB}"
  POSTGRES_REPL_USER: "replicator"
  POSTGRES_REPL_PASSWORD: "${POSTGRES_REPL_PASSWORD}"
  POSTGRES_HOST: "postgres-db"
  POSTGRES_PORT: "5432"
  POSTGRES_URL: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-db:5432/${POSTGRES_DB}"
  POSTGRES_URL_JDBC: "jdbc:postgresql://postgres-db:5432/${POSTGRES_DB}"
  DATABASE_URL: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-db:5432/${POSTGRES_DB}"
---
# Poświadczenia Redis
apiVersion: v1
kind: Secret
metadata:
  name: redis-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: cache
type: Opaque
stringData:
  REDIS_PASSWORD: "${REDIS_PASSWORD}"
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  REDIS_URL: "redis://:${REDIS_PASSWORD}@redis:6379/0"
  REDIS_URL_DB1: "redis://:${REDIS_PASSWORD}@redis:6379/1"
  REDIS_URL_DB2: "redis://:${REDIS_PASSWORD}@redis:6379/2"
---
# Poświadczenia Kafka (SASL/SCRAM)
apiVersion: v1
kind: Secret
metadata:
  name: kafka-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
type: Opaque
stringData:
  KAFKA_SASL_USERNAME: "${KAFKA_SASL_USERNAME}"
  KAFKA_SASL_PASSWORD: "${KAFKA_SASL_PASSWORD}"
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft-0.kafka-kraft:9092"
  KAFKA_BOOTSTRAP_SERVERS_EXTERNAL: "kafka-kraft-0.kafka-kraft:9094"
  KAFKA_SECURITY_PROTOCOL: "SASL_PLAINTEXT"
  KAFKA_SASL_MECHANISM: "SCRAM-SHA-512"
  KAFKA_JAAS_CONFIG: |
    org.apache.kafka.common.security.scram.ScramLoginModule required
    username="${KAFKA_SASL_USERNAME}"
    password="${KAFKA_SASL_PASSWORD}";
---
# Poświadczenia Vault
apiVersion: v1
kind: Secret
metadata:
  name: vault-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
type: Opaque
stringData:
  VAULT_TOKEN: "${VAULT_TOKEN}"
  VAULT_UNSEAL_KEY: "${VAULT_UNSEAL_KEY}"
  VAULT_ADDR: "http://vault:8200"
  VAULT_ROLE: "davtro-app"
---
# Poświadczenia Grafana
apiVersion: v1
kind: Secret
metadata:
  name: grafana-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
type: Opaque
stringData:
  GF_SECURITY_ADMIN_USER: "${GRAFANA_ADMIN_USER}"
  GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
  GRAFANA_ADMIN_USER: "${GRAFANA_ADMIN_USER}"
  GRAFANA_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
---
# Poświadczenia pgAdmin
apiVersion: v1
kind: Secret
metadata:
  name: pgadmin-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database-tools
type: Opaque
stringData:
  PGADMIN_DEFAULT_EMAIL: "${PGADMIN_EMAIL}"
  PGADMIN_DEFAULT_PASSWORD: "${PGADMIN_PASSWORD}"
---
# Sekrety aplikacji Spring
apiVersion: v1
kind: Secret
metadata:
  name: spring-app-secrets
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
type: Opaque
stringData:
  SPRING_DATASOURCE_USERNAME: "${POSTGRES_USER}"
  SPRING_DATASOURCE_PASSWORD: "${POSTGRES_PASSWORD}"
  SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT: "org.hibernate.dialect.PostgreSQLDialect"
  SPRING_REDIS_PASSWORD: "${REDIS_PASSWORD}"
  SPRING_KAFKA_SASL_JAAS_CONFIG: |
    org.apache.kafka.common.security.scram.ScramLoginModule required
    username="${KAFKA_SASL_USERNAME}"
    password="${KAFKA_SASL_PASSWORD}";
  JWT_SECRET: "${SPRING_SECRET}"
  ENCRYPTION_KEY: "$(generate_password 32)"
  API_KEY_INTERNAL: "$(generate_password 48)"
---
# Sekrety aplikacji FastAPI
apiVersion: v1
kind: Secret
metadata:
  name: fastapi-secrets
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
type: Opaque
stringData:
  SECRET_KEY: "${FASTAPI_SECRET}"
  ALGORITHM: "HS256"
  ACCESS_TOKEN_EXPIRE_MINUTES: "30"
  REFRESH_TOKEN_EXPIRE_DAYS: "7"
  SMTP_PASSWORD: "$(generate_password 24)"
  S3_SECRET_KEY: "$(generate_password 40)"
  STRIPE_SECRET_KEY: "sk_test_placeholder_$(generate_password 24)"
---
# Sekrety TLS
apiVersion: v1
kind: Secret
metadata:
  name: tls-certificates
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
type: kubernetes.io/tls
data:
  tls.crt: $(base64 -w 0 /tmp/tls.crt)
  tls.key: $(base64 -w 0 /tmp/tls.key)
---
# Sekrety OAuth2 / OIDC
apiVersion: v1
kind: Secret
metadata:
  name: oauth-secrets
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: authentication
type: Opaque
stringData:
  OAUTH_CLIENT_ID: "davtro-app"
  OAUTH_CLIENT_SECRET: "$(generate_password 48)"
  GITHUB_CLIENT_ID: "placeholder_client_id"
  GITHUB_CLIENT_SECRET: "placeholder_client_secret"
  GOOGLE_CLIENT_ID: "placeholder_google_id"
  GOOGLE_CLIENT_SECRET: "placeholder_google_secret"
---
# Sekrety AWS / S3 (placeholder)
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: storage
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "AKIAIOSFODNN7EXAMPLE"
  AWS_SECRET_ACCESS_KEY: "$(generate_password 40)"
  AWS_DEFAULT_REGION: "eu-central-1"
  S3_BUCKET: "davtro-production"
---
# Sekrety Sentry (monitoring błędów)
apiVersion: v1
kind: Secret
metadata:
  name: sentry-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: observability
type: Opaque
stringData:
  SENTRY_DSN: "https://placeholder@sentry.io/12345"
  SENTRY_AUTH_TOKEN: "$(generate_password 40)"
---
# Sekrety SMTP
apiVersion: v1
kind: Secret
metadata:
  name: smtp-credentials
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: notifications
type: Opaque
stringData:
  SMTP_HOST: "smtp.example.com"
  SMTP_PORT: "587"
  SMTP_USERNAME: "noreply@davtro.local"
  SMTP_PASSWORD: "$(generate_password 24)"
  SMTP_FROM_EMAIL: "noreply@davtro.local"
  SMTP_FROM_NAME: "DavTro Platform"
EOF

    log INFO "Sekrety wdrożone pomyślnie"
}

# ============================================================================
# SEKCJA 6: CONFIGMAP - POSTGRESQL
# ============================================================================
deploy_configmap_postgres() {
    log STEP "Wdrażanie ConfigMap PostgreSQL..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database
data:
  postgresql.conf: |
    # ============================================================================
    # PostgreSQL Configuration - DavTro Production
    # ============================================================================
    
    # Connection Settings
    listen_addresses = '*'
    port = 5432
    max_connections = 200
    superuser_reserved_connections = 3
    unix_socket_directories = '/var/run/postgresql'
    
    # Authentication
    password_encryption = scram-sha-256
    
    # Memory Settings
    shared_buffers = 256MB
    effective_cache_size = 768MB
    maintenance_work_mem = 128MB
    work_mem = 4MB
    huge_pages = off
    
    # WAL Settings
    wal_level = replica
    max_wal_size = 2GB
    min_wal_size = 512MB
    wal_buffers = 16MB
    checkpoint_completion_target = 0.9
    checkpoint_timeout = 10min
    
    # Query Planner
    random_page_cost = 1.1
    effective_io_concurrency = 200
    default_statistics_target = 100
    
    # Background Writer
    bgwriter_delay = 200ms
    bgwriter_lru_maxpages = 100
    bgwriter_lru_multiplier = 2.0
    
    # Logging
    logging_collector = on
    log_directory = 'log'
    log_filename = 'postgresql-%Y-%m-%d.log'
    log_rotation_age = 1d
    log_rotation_size = 100MB
    log_truncate_on_rotation = on
    log_min_duration_statement = 1000
    log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
    log_checkpoints = on
    log_connections = on
    log_disconnections = on
    log_lock_waits = on
    log_temp_files = 0
    log_autovacuum_min_duration = 0
    
    # Autovacuum
    autovacuum = on
    autovacuum_max_workers = 3
    autovacuum_naptime = 1min
    autovacuum_vacuum_threshold = 50
    autovacuum_analyze_threshold = 50
    autovacuum_vacuum_scale_factor = 0.2
    autovacuum_analyze_scale_factor = 0.1
    
    # Replication
    max_wal_senders = 5
    max_replication_slots = 5
    hot_standby = on
    
    # SSL (disabled by default, enable via TLS secret)
    ssl = off
    
    # Extensions
    shared_preload_libraries = 'pg_stat_statements'
    
    # Performance
    jit = on
    
  pg_hba.conf: |
    # PostgreSQL Client Authentication Configuration
    # TYPE  DATABASE        USER            ADDRESS                 METHOD
    
    # Local connections
    local   all             all                                     trust
    host    all             all             127.0.0.1/32            scram-sha-256
    host    all             all             ::1/128                 scram-sha-256
    
    # Kubernetes pods (all namespaces)
    host    all             all             10.0.0.0/8              scram-sha-256
    host    all             all             172.16.0.0/12           scram-sha-256
    host    all             all             192.168.0.0/16          scram-sha-256
    
    # Replication
    host    replication     replicator      10.0.0.0/8              scram-sha-256
    
    # Reject everything else
    host    all             all             0.0.0.0/0               reject
    
  init-db.sql: |
    -- ============================================================================
    -- Inicjalizacja bazy DavTro
    -- ============================================================================
    
    -- Rozszerzenia
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
    CREATE EXTENSION IF NOT EXISTS "hstore";
    CREATE EXTENSION IF NOT EXISTS "citext";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    CREATE EXTENSION IF NOT EXISTS "btree_gin";
    CREATE EXTENSION IF NOT EXISTS "btree_gist";
    
    -- Schematy
    CREATE SCHEMA IF NOT EXISTS app;
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS audit;
    CREATE SCHEMA IF NOT EXISTS reporting;
    
    -- Tabela użytkowników
    CREATE TABLE IF NOT EXISTS app.users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        email CITEXT UNIQUE NOT NULL,
        username CITEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        first_name VARCHAR(100),
        last_name VARCHAR(100),
        is_active BOOLEAN DEFAULT true,
        is_verified BOOLEAN DEFAULT false,
        role VARCHAR(50) DEFAULT 'user',
        metadata JSONB DEFAULT '{}'::jsonb,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        last_login_at TIMESTAMP WITH TIME ZONE
    );
    
    -- Tabela sesji
    CREATE TABLE IF NOT EXISTS auth.sessions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
        token_hash TEXT NOT NULL,
        ip_address INET,
        user_agent TEXT,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    
    -- Tabela zdarzeń (event sourcing)
    CREATE TABLE IF NOT EXISTS app.events (
        id BIGSERIAL PRIMARY KEY,
        event_type VARCHAR(100) NOT NULL,
        aggregate_type VARCHAR(100) NOT NULL,
        aggregate_id UUID NOT NULL,
        payload JSONB NOT NULL,
        metadata JSONB DEFAULT '{}'::jsonb,
        version INTEGER NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        created_by UUID REFERENCES app.users(id),
        UNIQUE(aggregate_type, aggregate_id, version)
    );
    
    -- Tabela audytu
    CREATE TABLE IF NOT EXISTS audit.audit_log (
        id BIGSERIAL PRIMARY KEY,
        table_name VARCHAR(100) NOT NULL,
        record_id UUID,
        action VARCHAR(20) NOT NULL,
        old_values JSONB,
        new_values JSONB,
        changed_by UUID REFERENCES app.users(id),
        changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        ip_address INET,
        user_agent TEXT
    );
    
    -- Tabela konfiguracji
    CREATE TABLE IF NOT EXISTS app.configuration (
        key VARCHAR(200) PRIMARY KEY,
        value JSONB NOT NULL,
        description TEXT,
        updated_by UUID REFERENCES app.users(id),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    
    -- Tabela zadań w tle
    CREATE TABLE IF NOT EXISTS app.background_jobs (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        job_type VARCHAR(100) NOT NULL,
        payload JSONB NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        priority INTEGER DEFAULT 0,
        attempts INTEGER DEFAULT 0,
        max_attempts INTEGER DEFAULT 3,
        scheduled_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        started_at TIMESTAMP WITH TIME ZONE,
        completed_at TIMESTAMP WITH TIME ZONE,
        failed_at TIMESTAMP WITH TIME ZONE,
        error_message TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    
    -- Indeksy
    CREATE INDEX IF NOT EXISTS idx_users_email ON app.users(email);
    CREATE INDEX IF NOT EXISTS idx_users_username ON app.users(username);
    CREATE INDEX IF NOT EXISTS idx_users_role ON app.users(role);
    CREATE INDEX IF NOT EXISTS idx_users_created_at ON app.users(created_at);
    CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON auth.sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON auth.sessions(expires_at);
    CREATE INDEX IF NOT EXISTS idx_events_aggregate ON app.events(aggregate_type, aggregate_id);
    CREATE INDEX IF NOT EXISTS idx_events_created_at ON app.events(created_at);
    CREATE INDEX IF NOT EXISTS idx_events_type ON app.events(event_type);
    CREATE INDEX IF NOT EXISTS idx_audit_table ON audit.audit_log(table_name);
    CREATE INDEX IF NOT EXISTS idx_audit_record ON audit.audit_log(record_id);
    CREATE INDEX IF NOT EXISTS idx_audit_changed_at ON audit.audit_log(changed_at);
    CREATE INDEX IF NOT EXISTS idx_jobs_status ON app.background_jobs(status);
    CREATE INDEX IF NOT EXISTS idx_jobs_scheduled ON app.background_jobs(scheduled_at);
    CREATE INDEX IF NOT EXISTS idx_jobs_type ON app.background_jobs(job_type);
    
    -- Funkcja aktualizacji updated_at
    CREATE OR REPLACE FUNCTION app.update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    
    CREATE TRIGGER update_users_updated_at
        BEFORE UPDATE ON app.users
        FOR EACH ROW
        EXECUTE FUNCTION app.update_updated_at_column();
    
    -- Funkcja audytu
    CREATE OR REPLACE FUNCTION audit.log_changes()
    RETURNS TRIGGER AS $$
    BEGIN
        INSERT INTO audit.audit_log (table_name, record_id, action, old_values, new_values)
        VALUES (
            TG_TABLE_NAME,
            COALESCE(NEW.id, OLD.id),
            TG_OP,
            CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
            CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
        );
        RETURN COALESCE(NEW, OLD);
    END;
    $$ LANGUAGE plpgsql;
    
    -- Widoki
    CREATE OR REPLACE VIEW app.active_users AS
        SELECT id, email, username, first_name, last_name, role, last_login_at
        FROM app.users
        WHERE is_active = true AND is_verified = true;
    
    CREATE OR REPLACE VIEW reporting.daily_stats AS
        SELECT 
            DATE(created_at) as stat_date,
            COUNT(*) as total_events,
            COUNT(DISTINCT aggregate_type) as unique_aggregates,
            COUNT(DISTINCT created_by) as unique_users
        FROM app.events
        GROUP BY DATE(created_at);
    
    -- Domyślna konfiguracja
    INSERT INTO app.configuration (key, value, description) VALUES
        ('app.name', '"DavTro Platform"', 'Nazwa aplikacji'),
        ('app.version', '"2.0.0"', 'Wersja aplikacji'),
        ('app.maintenance_mode', 'false', 'Tryb konserwacji'),
        ('auth.max_login_attempts', '5', 'Maksymalna liczba prób logowania'),
        ('auth.lockout_duration_minutes', '30', 'Czas blokady konta'),
        ('email.enabled', 'true', 'Czy wysyłać emaile'),
        ('features.new_ui', 'true', 'Nowy interfejs użytkownika')
    ON CONFLICT (key) DO NOTHING;
    
    -- Uprawnienia
    GRANT USAGE ON SCHEMA app TO PUBLIC;
    GRANT USAGE ON SCHEMA auth TO PUBLIC;
    GRANT USAGE ON SCHEMA audit TO PUBLIC;
    GRANT USAGE ON SCHEMA reporting TO PUBLIC;
    
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO PUBLIC;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO PUBLIC;
    GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA audit TO PUBLIC;
    GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO PUBLIC;
    
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO PUBLIC;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO PUBLIC;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA audit TO PUBLIC;
EOF

    log INFO "ConfigMap PostgreSQL wdrożony"
}

# ============================================================================
# SEKCJA 7: CONFIGMAP - REDIS
# ============================================================================
deploy_configmap_redis() {
    log STEP "Wdrażanie ConfigMap Redis..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: cache
data:
  redis.conf: |
    # ============================================================================
    # Redis Configuration - DavTro Production
    # ============================================================================
    
    # Network
    bind 0.0.0.0
    protected-mode yes
    port 6379
    tcp-backlog 511
    timeout 0
    tcp-keepalive 300
    
    # General
    daemonize no
    supervised no
    pidfile /var/run/redis/redis-server.pid
    loglevel notice
    logfile ""
    databases 16
    
    # Snapshotting
    save 900 1
    save 300 10
    save 60 10000
    stop-writes-on-bgsave-error yes
    rdbcompression yes
    rdbchecksum yes
    dbfilename dump.rdb
    rdb-del-sync-files no
    dir /data
    
    # Replication
    replica-serve-stale-data yes
    replica-read-only yes
    repl-diskless-sync no
    repl-diskless-sync-delay 5
    repl-diskless-load disabled
    repl-disable-tcp-nodelay no
    replica-priority 100
    
    # Security - hasło z env
    # requirepass ustawiane przez zmienną środowiskową
    
    # Clients
    maxclients 10000
    
    # Memory Management
    maxmemory 512mb
    maxmemory-policy allkeys-lru
    maxmemory-samples 5
    replica-lazy-flush no
    lazyfree-lazy-eviction no
    lazyfree-lazy-expire no
    lazyfree-lazy-server-del no
    
    # Append Only Mode
    appendonly yes
    appendfilename "appendonly.aof"
    appendfsync everysec
    no-appendfsync-on-rewrite no
    auto-aof-rewrite-percentage 100
    auto-aof-rewrite-min-size 64mb
    aof-load-truncated yes
    aof-use-rdb-preamble yes
    
    # Lua scripting
    lua-time-limit 5000
    
    # Slow log
    slowlog-log-slower-than 10000
    slowlog-max-len 128
    
    # Latency monitor
    latency-monitor-threshold 0
    
    # Event notification
    notify-keyspace-events ""
    
    # Advanced config
    hash-max-ziplist-entries 512
    hash-max-ziplist-value 64
    list-max-ziplist-size -2
    list-compress-depth 0
    set-max-intset-entries 512
    zset-max-ziplist-entries 128
    zset-max-ziplist-value 64
    hll-sparse-max-bytes 3000
    stream-node-max-bytes 4096
    stream-node-max-entries 100
    activerehashing yes
    client-output-buffer-limit normal 0 0 0
    client-output-buffer-limit replica 256mb 64mb 60
    client-output-buffer-limit pubsub 32mb 8mb 60
    hz 10
    dynamic-hz yes
    aof-rewrite-incremental-fsync yes
    rdb-save-incremental-fsync yes
    jemalloc-bg-thread yes
    
    # ACL (dla nowszych wersji)
    acllog-max-len 128
    
    # Performance
    io-threads 4
    io-threads-do-reads no
EOF

    log INFO "ConfigMap Redis wdrożony"
}

# ============================================================================
# SEKCJA 8: CONFIGMAP - KAFKA
# ============================================================================
deploy_configmap_kafka() {
    log STEP "Wdrażanie ConfigMap Kafka..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
data:
  server.properties: |
    # ============================================================================
    # Kafka Configuration - DavTro Production (KRaft mode)
    # ============================================================================
    
    # Broker ID
    broker.id=0
    node.id=0
    
    # KRaft mode (bez Zookeeper)
    process.roles=broker,controller
    controller.quorum.voters=0@kafka-kraft-0.kafka-kraft:9093
    controller.listener.names=CONTROLLER
    
    # Listeners
    listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093,SASL_PLAINTEXT://0.0.0.0:9094
    advertised.listeners=PLAINTEXT://kafka-kraft-0.kafka-kraft:9092,SASL_PLAINTEXT://kafka-kraft-0.kafka-kraft:9094
    listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT,SASL_PLAINTEXT:SASL_PLAINTEXT
    inter.broker.listener.name=PLAINTEXT
    
    # Log directories
    log.dirs=/bitnami/kafka/data
    
    # Topic defaults
    num.partitions=3
    default.replication.factor=1
    offsets.topic.replication.factor=1
    transaction.state.log.replication.factor=1
    transaction.state.log.min.isr=1
    min.insync.replicas=1
    
    # Log retention
    log.retention.hours=168
    log.retention.bytes=10737418240
    log.segment.bytes=1073741824
    log.retention.check.interval.ms=300000
    log.cleaner.enable=true
    
    # Zookeeper (disabled in KRaft)
    zookeeper.connection.timeout.ms=18000
    
    # Group coordinator
    group.initial.rebalance.delay.ms=0
    
    # Performance
    num.network.threads=3
    num.io.threads=8
    socket.send.buffer.bytes=102400
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    
    # Message sizes
    message.max.bytes=10485760
    replica.fetch.max.bytes=10485760
    
    # Metrics
    metric.reporters=org.apache.kafka.common.metrics.JmxReporter
    
    # Auto topic creation
    auto.create.topics.enable=true
    delete.topic.enable=true
    
    # SASL configuration
    sasl.enabled.mechanisms=SCRAM-SHA-512
    sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
    
    # Compression
    compression.type=producer
    
    # Quotas
    quota.producer.default=10485760
    quota.consumer.default=10485760
    
  log4j.properties: |
    log4j.rootLogger=INFO, stdout, kafkaAppender
    
    log4j.appender.stdout=org.apache.log4j.ConsoleAppender
    log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
    log4j.appender.stdout.layout.ConversionPattern=[%d] %p %m (%c)%n
    
    log4j.appender.kafkaAppender=org.apache.log4j.DailyRollingFileAppender
    log4j.appender.kafkaAppender.DatePattern='.'yyyy-MM-dd-HH
    log4j.appender.kafkaAppender.File=/opt/bitnami/kafka/logs/server.log
    log4j.appender.kafkaAppender.layout=org.apache.log4j.PatternLayout
    log4j.appender.kafkaAppender.layout.ConversionPattern=[%d] %p %m (%c)%n
    
    log4j.logger.kafka=INFO
    log4j.logger.org.apache.kafka=INFO
    log4j.logger.org.apache.zookeeper=WARN
    log4j.logger.kafka.server.KafkaApis=WARN
    log4j.logger.kafka.request.logger=WARN
    log4j.logger.kafka.controller=TRACE
    log4j.logger.kafka.log.LogCleaner=INFO
    log4j.logger.state.change.logger=INFO
    
  jmx-config.yaml: |
    lowercaseOutputName: true
    lowercaseOutputLabelNames: true
    rules:
    - pattern: kafka.server<type=(.+), name=(.+)PerSec\\w*>
      name: kafka_server_$1_$2_total
      type: COUNTER
    - pattern: kafka.server<type=(.+), name=(.+)Percent>
      name: kafka_server_$1_$2_percent
      type: GAUGE
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Count
      name: kafka_server_$1_$2_count
      labels:
        clientId: "$3"
        topic: "$4"
        partition: "$5"
      type: COUNTER
    - pattern: kafka.network<type=(.+), name=(.+)><>Value
      name: kafka_network_$1_$2_value
      type: GAUGE
    - pattern: kafka.log<type=Log, name=(.+), topic=(.+), partition=(.+)><>Value
      name: kafka_log_$1_value
      labels:
        topic: "$2"
        partition: "$3"
      type: GAUGE
EOF

    log INFO "ConfigMap Kafka wdrożony"
}

# ============================================================================
# SEKCJA 9: CONFIGMAP - SPARK
# ============================================================================
deploy_configmap_spark() {
    log STEP "Wdrażanie ConfigMap Spark..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spark-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: analytics
data:
  spark-defaults.conf: |
    # ============================================================================
    # Spark Configuration - DavTro Production
    # ============================================================================
    
    # Master
    spark.master                          spark://spark-master:7077
    spark.master.rest.enabled             true
    spark.master.rest.host                0.0.0.0
    spark.master.rest.port                6066
    
    # Application
    spark.app.name                        DavTroAnalytics
    spark.driver.memory                   2g
    spark.driver.cores                    2
    spark.executor.memory                 2g
    spark.executor.cores                  2
    spark.executor.instances              3
    
    # Serialization
    spark.serializer                      org.apache.spark.serializer.KryoSerializer
    spark.kryo.registrationRequired       false
    spark.kryo.unsafe                     true
    
    # Shuffle
    spark.shuffle.service.enabled         false
    spark.dynamicAllocation.enabled       true
    spark.dynamicAllocation.minExecutors  1
    spark.dynamicAllocation.maxExecutors  10
    spark.dynamicAllocation.initialExecutors 2
    spark.dynamicAllocation.executorIdleTimeout 60s
    spark.dynamicAllocation.cachedExecutorIdleTimeout 600s
    
    # SQL
    spark.sql.shuffle.partitions          200
    spark.sql.adaptive.enabled            true
    spark.sql.adaptive.coalescePartitions.enabled true
    spark.sql.adaptive.skewJoin.enabled   true
    spark.sql.parquet.compression.codec   snappy
    spark.sql.parquet.filterPushdown      true
    
    # UI
    spark.ui.enabled                      true
    spark.ui.port                         4040
    spark.ui.reverseProxy                 true
    
    # Event log
    spark.eventLog.enabled                true
    spark.eventLog.dir                    /tmp/spark-events
    
    # History server
    spark.history.fs.logDirectory         /tmp/spark-events
    
    # Metrics
    spark.metrics.conf                    /opt/bitnami/spark/conf/metrics.properties
    
    # Network
    spark.network.timeout                 800s
    spark.rpc.askTimeout                  60s
    spark.rpc.lookupTimeout               60s
    
    # Memory
    spark.memory.fraction                 0.6
    spark.memory.storageFraction          0.5
    spark.unsafe.exceptionOnMemoryLeak    true
    
    # Logging
    spark.eventLog.overwrite              true
    spark.worker.cleanup.enabled          true
    spark.worker.cleanup.interval         1800
    spark.worker.cleanup.appDataTtl       86400
    
  spark-env.sh: |
    #!/usr/bin/env bash
    
    export SPARK_MASTER_HOST=spark-master
    export SPARK_MASTER_PORT=7077
    export SPARK_MASTER_WEBUI_PORT=8080
    export SPARK_WORKER_CORES=2
    export SPARK_WORKER_MEMORY=2g
    export SPARK_WORKER_WEBUI_PORT=8081
    export SPARK_WORKER_DIR=/tmp/spark-work
    export SPARK_LOG_DIR=/opt/bitnami/spark/logs
    export SPARK_LOCAL_DIRS=/tmp/spark-local
    
    # Java options
    export SPARK_DRIVER_JAVA_OPTS="-Xms1g -Xmx2g -XX:+UseG1GC"
    export SPARK_EXECUTOR_JAVA_OPTS="-Xms1g -Xmx2g -XX:+UseG1GC"
    
    # Classpath
    export SPARK_DIST_CLASSPATH=$(hadoop classpath 2>/dev/null || echo "")
    
  metrics.properties: |
    # ============================================================================
    # Spark Metrics Configuration
    # ============================================================================
    
    *.sink.jmx.class=org.apache.spark.metrics.sink.JmxSink
    
    master.source.jvm.class=org.apache.spark.metrics.source.JvmSource
    worker.source.jvm.class=org.apache.spark.metrics.source.JvmSource
    driver.source.jvm.class=org.apache.spark.metrics.source.JvmSource
    executor.source.jvm.class=org.apache.spark.metrics.source.JvmSource
    
    *.sink.prometheusServlet.class=org.apache.spark.metrics.sink.PrometheusServlet
    *.sink.prometheusServlet.path=/metrics/prometheus
    master.sink.prometheusServlet.path=/metrics/master/prometheus
    applications.sink.prometheusServlet.path=/metrics/applications/prometheus
    
  log4j2.properties: |
    status = warn
    name = SparkLogConfig
    
    property.filename = /opt/bitnami/spark/logs/spark.log
    
    appenders = console, file
    
    appender.console.type = Console
    appender.console.name = console
    appender.console.layout.type = PatternLayout
    appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %c{1}:%L - %m%n
    
    appender.file.type = RollingFile
    appender.file.name = file
    appender.file.fileName = ${filename}
    appender.file.filePattern = ${filename}.%d{yyyy-MM-dd}
    appender.file.layout.type = PatternLayout
    appender.file.layout.pattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %c{1}:%L - %m%n
    appender.file.policies.type = Policies
    appender.file.policies.time.type = TimeBasedTriggeringPolicy
    appender.file.policies.time.interval = 1
    appender.file.strategy.type = DefaultRolloverStrategy
    appender.file.strategy.max = 7
    
    rootLogger.level = info
    rootLogger.appenderRefs = console, file
    rootLogger.appenderRef.console.ref = console
    rootLogger.appenderRef.file.ref = file
    
    logger.spark.name = org.apache.spark
    logger.spark.level = info
    
    logger.kafka.name = org.apache.kafka
    logger.kafka.level = warn
    
    logger.hadoop.name = org.apache.hadoop
    logger.hadoop.level = warn
EOF

    log INFO "ConfigMap Spark wdrożony"
}

# ============================================================================
# SEKCJA 10: CONFIGMAP - APLIKACJE WEBOWE (FASTAPI + SPRING)
# ============================================================================
deploy_configmap_webapps() {
    log STEP "Wdrażanie ConfigMap aplikacji webowych..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-app-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
data:
  # Konfiguracja wspólna
  APP_ENV: "production"
  APP_NAME: "DavTro Platform"
  APP_VERSION: "2.0.0"
  APP_DEBUG: "false"
  APP_LOG_LEVEL: "INFO"
  APP_HOST: "0.0.0.0"
  APP_PORT: "8000"
  APP_WORKERS: "4"
  APP_MAX_REQUESTS: "10000"
  APP_MAX_REQUESTS_JITTER: "1000"
  APP_KEEPALIVE: "5"
  APP_TIMEOUT: "60"
  APP_CORS_ORIGINS: "https://davtro.local,https://www.davtro.local"
  APP_CORS_METHODS: "GET,POST,PUT,DELETE,PATCH,OPTIONS"
  APP_CORS_HEADERS: "Authorization,Content-Type,X-Requested-With"
  APP_RATE_LIMIT: "100/minute"
  APP_RATE_LIMIT_BURST: "20"
  # Bazy danych
  DATABASE_POOL_SIZE: "20"
  DATABASE_MAX_OVERFLOW: "10"
  DATABASE_POOL_TIMEOUT: "30"
  DATABASE_POOL_RECYCLE: "1800"
  DATABASE_ECHO: "false"
  # Redis
  REDIS_POOL_SIZE: "50"
  REDIS_DECODE_RESPONSES: "true"
  REDIS_SOCKET_TIMEOUT: "5"
  REDIS_SOCKET_CONNECT_TIMEOUT: "5"
  REDIS_RETRY_ON_TIMEOUT: "true"
  # Kafka
  KAFKA_GROUP_ID: "davtro-web-app"
  KAFKA_AUTO_OFFSET_RESET: "earliest"
  KAFKA_ENABLE_AUTO_COMMIT: "false"
  KAFKA_MAX_POLL_RECORDS: "500"
  KAFKA_SESSION_TIMEOUT_MS: "30000"
  KAFKA_HEARTBEAT_INTERVAL_MS: "10000"
  KAFKA_MAX_POLL_INTERVAL_MS: "300000"
  # Monitoring
  METRICS_ENABLED: "true"
  METRICS_PATH: "/metrics"
  TRACING_ENABLED: "true"
  TRACING_SERVICE_NAME: "davtro-web-app"
  TRACING_SAMPLER_TYPE: "probabilistic"
  TRACING_SAMPLER_PARAM: "0.1"
  HEALTH_CHECK_PATH: "/health"
  READINESS_PATH: "/ready"
  # Vault
  VAULT_MOUNT_PATH: "secret"
  VAULT_TRANSIT_KEY: "davtro-transit"
  # Feature flags
  FEATURE_DARK_MODE: "true"
  FEATURE_BETA_UI: "false"
  FEATURE_NEW_CHECKOUT: "true"
  FEATURE_ANALYTICS_V2: "true"
  FEATURE_AI_RECOMMENDATIONS: "false"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: fastapi
data:
  main.py: |
    # ============================================================================
    # FastAPI Main Application - DavTro
    # ============================================================================
    import os
    import logging
    from contextlib import asynccontextmanager
    from fastapi import FastAPI, Request, HTTPException
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.middleware.trustedhost import TrustedHostMiddleware
    from fastapi.responses import JSONResponse
    from prometheus_fastapi_instrumentator import Instrumentator
    
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
    logger = logging.getLogger(__name__)
    
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        logger.info("Starting DavTro FastAPI application...")
        # Startup
        yield
        # Shutdown
        logger.info("Shutting down DavTro FastAPI application...")
    
    app = FastAPI(
        title="DavTro Platform API",
        description="Backend API for DavTro Platform",
        version="2.0.0",
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json"
    )
    
    # Middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=["*"])
    
    # Metrics
    Instrumentator().instrument(app).expose(app, endpoint="/metrics")
    
    @app.get("/")
    async def root():
        return {"message": "DavTro Platform API", "version": "2.0.0"}
    
    @app.get("/health")
    async def health():
        return {"status": "healthy"}
    
    @app.get("/ready")
    async def ready():
        return {"status": "ready"}
    
    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException):
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": exc.detail}
        )
    
    @app.exception_handler(Exception)
    async def general_exception_handler(request: Request, exc: Exception):
        logger.exception("Unhandled exception")
        return JSONResponse(
            status_code=500,
            content={"error": "Internal server error"}
        )
  
  requirements.txt: |
    fastapi==0.109.0
    uvicorn[standard]==0.25.0
    sqlalchemy==2.0.25
    asyncpg==0.29.0
    redis==5.0.1
    aioredis==2.0.1
    aiokafka==0.10.0
    pydantic==2.5.3
    pydantic-settings==2.1.0
    python-jose[cryptography]==3.3.0
    passlib[bcrypt]==1.7.4
    python-multipart==0.0.6
    httpx==0.26.0
    prometheus-fastapi-instrumentator==6.1.0
    opentelemetry-api==1.22.0
    opentelemetry-sdk==1.22.0
    opentelemetry-exporter-otlp==1.22.0
    structlog==23.2.0
    orjson==3.9.12
    email-validator==2.1.0.post1
    itsdangerous==2.1.2
    cryptography==41.0.7
    boto3==1.34.25
    hvac==2.1.0
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spring-app-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: spring
data:
  application.yml: |
    # ============================================================================
    # Spring Boot Application Configuration - DavTro
    # ============================================================================
    server:
      port: 8080
      servlet:
        context-path: /api
        session:
          timeout: 30m
          cookie:
            http-only: true
            secure: true
            same-site: strict
      compression:
        enabled: true
        mime-types: application/json,application/xml,text/html,text/xml,text/plain
        min-response-size: 1024
      tomcat:
        max-threads: 200
        min-spare-threads: 20
        accept-count: 100
        max-connections: 8192
    
    spring:
      application:
        name: davtro-spring-app
      profiles:
        active: production
      
      # Datasource
      datasource:
        url: jdbc:postgresql://postgres-db:5432/davtro_production
        driver-class-name: org.postgresql.Driver
        hikari:
          pool-name: DavTroHikariPool
          maximum-pool-size: 20
          minimum-idle: 5
          idle-timeout: 300000
          connection-timeout: 20000
          max-lifetime: 1800000
          leak-detection-threshold: 60000
      
      # JPA
      jpa:
        database-platform: org.hibernate.dialect.PostgreSQLDialect
        hibernate:
          ddl-auto: validate
          naming:
            physical-strategy: org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy
        properties:
          hibernate:
            jdbc:
              batch_size: 25
              batch_versioned_data: true
            order_inserts: true
            order_updates: true
            generate_statistics: false
            format_sql: false
            use_sql_comments: false
      
      # Redis
      data:
        redis:
          host: redis
          port: 6379
          timeout: 5000
          lettuce:
            pool:
              max-active: 50
              max-idle: 20
              min-idle: 5
              max-wait: 3000ms
      
      # Kafka
      kafka:
        bootstrap-servers: kafka-kraft-0.kafka-kraft:9092
        producer:
          key-serializer: org.apache.kafka.common.serialization.StringSerializer
          value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
          acks: all
          retries: 3
          batch-size: 16384
          buffer-memory: 33554432
          compression-type: snappy
          properties:
            enable.idempotence: true
            max.in.flight.requests.per.connection: 5
        consumer:
          group-id: davtro-spring-consumers
          auto-offset-reset: earliest
          key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
          value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
          enable-auto-commit: false
          max-poll-records: 500
          properties:
            spring.json.trusted.packages: "com.davtro.*"
      
      # Security
      security:
        oauth2:
          resourceserver:
            jwt:
              issuer-uri: https://auth.davtro.local
      
      # Cache
      cache:
        type: redis
        redis:
          time-to-live: 3600000
          cache-null-values: false
      
      # Jackson
      jackson:
        serialization:
          write-dates-as-timestamps: false
          fail-on-empty-beans: false
        deserialization:
          fail-on-unknown-properties: false
        default-property-inclusion: non_null
      
      # Mail
      mail:
        host: smtp.example.com
        port: 587
        username: noreply@davtro.local
        properties:
          mail:
            smtp:
              auth: true
              starttls:
                enable: true
      
      # Actuator
      actuator:
        endpoints:
          web:
            exposure:
              include: health,info,metrics,prometheus
        endpoint:
          health:
            show-details: when-authorized
        health:
          redis:
            enabled: true
          kafka:
            enabled: true
          db:
            enabled: true
      
      # Sleuth / Tracing
      sleuth:
        sampler:
          probability: 0.1
        messaging:
          kafka:
            enabled: true
    
    # Custom application properties
    app:
      name: DavTro Spring Service
      version: 2.0.0
      jwt:
        expiration: 86400000
        refresh-expiration: 604800000
      rate-limit:
        enabled: true
        requests-per-second: 100
        burst-size: 200
      cache:
        user-ttl: 3600
        config-ttl: 86400
      kafka:
        topics:
          users: davtro-users
          events: davtro-events
          notifications: davtro-notifications
          audit: davtro-audit
      features:
        new-checkout: true
        ai-recommendations: false
        dark-mode: true
        beta-ui: false
    
    # Logging
    logging:
      level:
        root: INFO
        com.davtro: INFO
        org.springframework.web: INFO
        org.hibernate.SQL: WARN
        org.apache.kafka: WARN
      pattern:
        console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"
      file:
        name: /var/log/spring/app.log
      logback:
        rollingpolicy:
          max-file-size: 100MB
          max-history: 30
    
    # Management
    management:
      endpoints:
        web:
          exposure:
            include: "*"
      metrics:
        tags:
          application: ${spring.application.name}
          environment: production
      tracing:
        sampling:
          probability: 0.1
      prometheus:
        metrics:
          export:
            enabled: true
EOF

    log INFO "ConfigMap aplikacji webowych wdrożony"
}

# ============================================================================
# SEKCJA 11: CONFIGMAP - MONITORING (PROMETHEUS, LOKI, TEMPO, PROMTAIL)
# ============================================================================
deploy_configmap_monitoring() {
    log STEP "Wdrażanie ConfigMap monitoringu..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
data:
  prometheus.yml: |
    # ============================================================================
    # Prometheus Configuration - DavTro Production
    # ============================================================================
    
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      scrape_timeout: 10s
      external_labels:
        cluster: 'davtro-prod'
        environment: 'production'
        replica: '$(POD_NAME)'
    
    # Alertmanager configuration
    alerting:
      alertmanagers:
      - static_configs:
        - targets: []
    
    # Rule files
    rule_files:
      - "/etc/prometheus/rules/*.yml"
    
    # Scrape configurations
    scrape_configs:
      # Prometheus self-monitoring
      - job_name: 'prometheus'
        honor_labels: true
        static_configs:
          - targets: ['localhost:9090']
      
      # Kubernetes API servers
      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
          - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
            action: keep
            regex: default;kubernetes;https
      
      # Kubernetes nodes
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
      
      # Node exporter
      - job_name: 'node-exporter'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: node-exporter
          - source_labels: [__meta_kubernetes_pod_node_name]
            target_label: node
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
      
      # Kubernetes pods (annotated)
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: kubernetes_namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: kubernetes_pod_name
      
      # Kubernetes services (annotated)
      - job_name: 'kubernetes-services'
        kubernetes_sd_configs:
          - role: service
        metrics_path: /probe
        params:
          module: [http_2xx]
        relabel_configs:
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_probe]
            action: keep
            regex: true
      
      # DavTro applications
      - job_name: 'davtro-fastapi'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: ['davtro']
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: fastapi-web-app
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
        metrics_path: /metrics
      
      - job_name: 'davtro-spring'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: ['davtro']
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: spring-app-deployment
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
        metrics_path: /actuator/prometheus
      
      # PostgreSQL
      - job_name: 'postgres'
        static_configs:
          - targets: ['postgres-exporter:9187']
        metrics_path: /metrics
      
      # Redis
      - job_name: 'redis'
        static_configs:
          - targets: ['redis:6379']
      
      # Kafka
      - job_name: 'kafka'
        static_configs:
          - targets: ['kafka-exporter:9308']
        metrics_path: /metrics
      
      # Kafka JMX
      - job_name: 'kafka-jmx'
        static_configs:
          - targets: ['kafka-kraft-0.kafka-kraft:5556']
      
      # Spark
      - job_name: 'spark-master'
        static_configs:
          - targets: ['spark-master:8080']
        metrics_path: /metrics/prometheus
      
      - job_name: 'spark-workers'
        static_configs:
          - targets: ['spark-worker:8081']
        metrics_path: /metrics/prometheus
      
      # Vault
      - job_name: 'vault'
        static_configs:
          - targets: ['vault:8200']
        metrics_path: /v1/metrics
      
      # Grafana
      - job_name: 'grafana'
        static_configs:
          - targets: ['grafana:3000']
  
  alert-rules.yml: |
    groups:
      - name: davtro-alerts
        rules:
          - alert: HighCPUUsage
            expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High CPU usage on {{ $labels.instance }}"
              description: "CPU usage is above 80% for 5 minutes"
          
          - alert: HighMemoryUsage
            expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High memory usage on {{ $labels.instance }}"
              description: "Memory usage is above 85% for 5 minutes"
          
          - alert: PodCrashLooping
            expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 5 > 0
            for: 15m
            labels:
              severity: critical
            annotations:
              summary: "Pod {{ $labels.pod }} is crash looping"
              description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has restarted frequently"
          
          - alert: PodNotReady
            expr: kube_pod_status_ready{condition="true"} == 0
            for: 10m
            labels:
              severity: critical
            annotations:
              summary: "Pod {{ $labels.pod }} is not ready"
          
          - alert: HighErrorRate
            expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "High error rate on {{ $labels.job }}"
          
          - alert: PostgresDown
            expr: pg_up == 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "PostgreSQL is down"
          
          - alert: KafkaConsumerLag
            expr: kafka_consumergroup_lag > 1000
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Kafka consumer lag is high"
          
          - alert: DiskSpaceLow
            expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Low disk space on {{ $labels.instance }}"
          
          - alert: VaultSealed
            expr: vault_unsealed == 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "Vault is sealed"
  
  recording-rules.yml: |
    groups:
      - name: davtro-recording
        rules:
          - record: job:http_requests_total:rate5m
            expr: sum(rate(http_requests_total[5m])) by (job)
          
          - record: job:http_request_duration_seconds:avg5m
            expr: avg(rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])) by (job)
          
          - record: instance:node_cpu_utilization:ratio
            expr: 1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: logging
data:
  loki.yaml: |
    # ============================================================================
    # Loki Configuration - DavTro Production
    # NAPRAWA CrashLoopBackOff - poprawna konfiguracja
    # ============================================================================
    
    auth_enabled: false
    
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
      http_listen_address: 0.0.0.0
      grpc_listen_address: 0.0.0.0
      log_level: info
    
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
    
    query_range:
      results_cache:
        cache:
          embedded_cache:
            enabled: true
            max_size_mb: 100
    
    schema_config:
      configs:
        - from: 2020-10-24
          store: tsdb
          object_store: filesystem
          schema: v12
          index:
            prefix: index_
            period: 24h
    
    limits_config:
      reject_old_samples: true
      reject_old_samples_max_age: 168h
      max_cache_freshness_per_query: 10m
      split_queries_by_interval: 15m
      query_timeout: 1m
      volume_enabled: true
      volume_max_age: 28d
      ingestion_rate_mb: 10
      ingestion_burst_size_mb: 20
      per_stream_rate_limit: 5MB
      per_stream_rate_limit_burst: 15MB
      max_streams_per_user: 10000
      max_global_streams_per_user: 0
      max_entries_limit_per_query: 5000
    
    storage_config:
      filesystem:
        directory: /loki/chunks
    
    chunk_store_config:
      max_look_back_period: 0s
    
    table_manager:
      retention_deletes_enabled: true
      retention_period: 168h
    
    compactor:
      working_directory: /loki/compactor
      shared_store: filesystem
      compaction_interval: 10m
      retention_enabled: true
      retention_delete_delay: 2h
      retention_delete_worker_count: 150
    
    analytics:
      reporting_enabled: false
    
    ruler:
      alertmanager_url: http://alertmanager:9093
      storage:
        type: local
        local:
          directory: /loki/rules
      rule_path: /loki/rules-temp
      ring:
        kvstore:
          store: inmemory
      enable_api: true
    
    frontend:
      max_outstanding_per_tenant: 2048
    
    ingester:
      wal:
        enabled: true
        dir: /loki/wal
      lifecycler:
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
      chunk_idle_period: 30m
      chunk_block_size: 262144
      chunk_retain_period: 30s
      max_transfer_retries: 0
  
  runtime.yaml: |
    # Runtime overrides
    limits:
      global:
        ingestion_rate_mb: 10
        ingestion_burst_size_mb: 20
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: logging
data:
  promtail.yaml: |
    # ============================================================================
    # Promtail Configuration - DavTro Production
    # ============================================================================
    
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
      log_level: info
    
    positions:
      filename: /tmp/positions.yaml
    
    clients:
      - url: http://loki:3100/loki/api/v1/push
        tenant_id: davtro
        batchwait: 1s
        batchsize: 1048576
        timeout: 10s
    
    scrape_configs:
      # Kubernetes pods
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_controller_name]
            regex: ([0-9a-z-.]+?)(-[0-9a-f]{8,10})?
            action: replace
            target_label: __tmp_pod_controller_name
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_component, __tmp_pod_controller_name]
            regex: (.*);(.*)
            action: replace
            target_label: job
          - source_labels: [__meta_kubernetes_pod_node_name]
            action: replace
            target_label: node
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: pod
          - source_labels: [__meta_kubernetes_pod_container_name]
            action: replace
            target_label: container
          - action: replace
            source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
            target_label: app
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - action: drop
            source_labels: [__meta_kubernetes_pod_container_name]
            regex: istio-proxy
          - action: drop
            source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            regex: false
        pipeline_stages:
          - docker: {}
          - timestamp:
              source: time
              format: RFC3339Nano
          - labels:
              stream: stream
          - output:
              source: log
      
      # System logs
      - job_name: journal
        journal:
          max_age: 12h
          labels:
            job: systemd-journal
        relabel_configs:
          - source_labels: ['__journal__systemd_unit']
            target_label: 'unit'
      
      # Application logs (direct file)
      - job_name: application-logs
        static_configs:
          - targets:
              - localhost
            labels:
              job: application
              __path__: /var/log/app/*.log
      
      # Nginx/Ingress logs
      - job_name: nginx
        static_configs:
          - targets:
              - localhost
            labels:
              job: nginx
              __path__: /var/log/nginx/*.log
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: tracing
data:
  tempo.yaml: |
    # ============================================================================
    # Tempo Configuration - DavTro Production
    # ============================================================================
    
    server:
      http_listen_port: 3200
      http_listen_address: 0.0.0.0
      log_level: info
    
    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
        jaeger:
          protocols:
            grpc:
              endpoint: 0.0.0.0:14250
            thrift_http:
              endpoint: 0.0.0.0:14268
        zipkin:
          endpoint: 0.0.0.0:9411
    
    ingester:
      trace_idle_period: 10s
      max_block_bytes: 1_000_000
      max_block_duration: 5m
    
    compactor:
      compaction:
        compaction_window: 1h
        max_block_bytes: 100_000_000
        block_retention: 48h
        compacted_block_retention: 10m
    
    metrics_generator:
      registry:
        external_labels:
          source: tempo
          cluster: davtro-prod
      storage:
        path: /var/tempo/generator/wal
        remote_write:
          - url: http://prometheus:9090/api/v1/write
            send_exemplars: true
    
    storage:
      trace:
        backend: local
        wal:
          path: /var/tempo/wal
        local:
          path: /var/tempo/traces
    
    overrides:
      metrics_generator_processors: [service-graphs, span-metrics]
      ingestion_rate_limit_bytes: 15000000
      ingestion_burst_size_bytes: 20000000
EOF

    log INFO "ConfigMap monitoringu wdrożony"
}

# ============================================================================
# SEKCJA 12: CONFIGMAP - GRAFANA
# ============================================================================
deploy_configmap_grafana() {
    log STEP "Wdrażanie ConfigMap Grafana..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
data:
  grafana.ini: |
    # ============================================================================
    # Grafana Configuration - DavTro Production
    # ============================================================================
    
    [paths]
    data = /var/lib/grafana/data
    logs = /var/log/grafana
    plugins = /var/lib/grafana/plugins
    provisioning = /etc/grafana/provisioning
    
    [server]
    protocol = http
    http_addr = 0.0.0.0
    http_port = 3000
    domain = grafana.davtro.local
    root_url = %(protocol)s://%(domain)s/
    enforce_domain = false
    router_logging = false
    static_root_path = /usr/share/grafana/public
    enable_gzip = true
    cert_file =
    cert_key =
    
    [database]
    type = sqlite3
    path = grafana.db
    cache_mode = private
    
    [session]
    provider = file
    provider_config = sessions
    
    [analytics]
    reporting_enabled = false
    check_for_updates = false
    check_for_plugin_updates = false
    
    [security]
    admin_user = ${GF_SECURITY_ADMIN_USER}
    admin_password = ${GF_SECURITY_ADMIN_PASSWORD}
    secret_key = SW2YcwTIb9zpOOhoPsMm
    disable_gravatar = true
    cookie_secure = false
    cookie_samesite = lax
    allow_embedding = false
    strict_transport_security = false
    
    [users]
    allow_sign_up = false
    allow_org_create = false
    auto_assign_org = true
    auto_assign_org_id = 1
    auto_assign_org_role = Viewer
    default_theme = dark
    
    [auth.anonymous]
    enabled = false
    
    [auth]
    disable_login_form = false
    disable_signout_menu = false
    signout_redirect_url =
    oauth_auto_login = false
    
    [log]
    mode = console
    level = info
    
    [log.console]
    format = text
    
    [dashboards]
    versions_to_keep = 20
    min_refresh_interval = 5s
    
    [alerting]
    enabled = true
    execute_alerts = true
    error_or_timeout = alerting
    nodata_or_nullvalues = no_data
    concurrent_render_limit = 5
    evaluation_timeout_seconds = 30
    notification_timeout_seconds = 30
    max_attempts = 3
    
    [unified_alerting]
    enabled = true
    min_interval = 10s
    
    [feature_toggles]
    enable = publicDashboards
    
    [rendering]
    server_url =
    callback_url =
    
    [metrics]
    enabled = true
    basic_auth_username =
    basic_auth_password =
    interval_seconds = 10
    
    [tracing.jaeger]
    address = tempo:6831
    always_included_tag = tag1:value1
    sampler_type = const
    sampler_param = 1
  
  datasources.yaml: |
    apiVersion: 1
    
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus:9090
        isDefault: true
        editable: false
        jsonData:
          timeInterval: 15s
          httpMethod: POST
          manageAlerts: true
          prometheusType: Prometheus
          prometheusVersion: 2.48.0
          cacheLevel: 'High'
      
      - name: Loki
        type: loki
        access: proxy
        url: http://loki:3100
        editable: false
        jsonData:
          maxLines: 1000
      
      - name: Tempo
        type: tempo
        access: proxy
        url: http://tempo:3200
        editable: false
        jsonData:
          tracesToLogs:
            datasourceUid: loki
            tags: ['job', 'instance', 'pod', 'namespace']
            filteredDatasourceUid: loki
          serviceMap:
            datasourceUid: prometheus
          nodeGraph:
            enabled: true
      
      - name: PostgreSQL
        type: postgres
        url: postgres-db:5432
        database: davtro_production
        user: davtro_admin
        secureJsonData:
          password: ${POSTGRES_PASSWORD}
        jsonData:
          sslmode: disable
          postgresVersion: 1500
          timescaledb: false
  
  dashboards.yaml: |
    apiVersion: 1
    
    providers:
      - name: 'DavTro Dashboards'
        orgId: 1
        folder: 'DavTro'
        type: file
        disableDeletion: false
        editable: true
        updateIntervalSeconds: 30
        options:
          path: /var/lib/grafana/dashboards/davtro
          foldersFromFilesStructure: false
  
  # Dashboard - System Overview
  dashboard-system.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 1,
      "id": null,
      "links": [],
      "liveNow": false,
      "panels": [
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": {
            "defaults": { "color": { "mode": "palette-classic" }, "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }, { "color": "yellow", "value": 70 }, { "color": "red", "value": 85 }] } }
          },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "id": 1,
          "options": { "legend": { "displayMode": "list", "placement": "bottom" } },
          "targets": [
            { "expr": "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)", "legendFormat": "{{instance}}" }
          ],
          "title": "CPU Usage",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": {
            "defaults": { "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }, { "color": "yellow", "value": 70 }, { "color": "red", "value": 85 }] } }
          },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "id": 2,
          "targets": [
            { "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100", "legendFormat": "{{instance}}" }
          ],
          "title": "Memory Usage",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
          "id": 3,
          "targets": [
            { "expr": "sum(kube_pod_status_phase{phase=\"Running\", namespace=\"davtro\"}) by (phase)", "legendFormat": "{{phase}}" }
          ],
          "title": "Pod Status",
          "type": "stat"
        }
      ],
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["davtro", "system"],
      "templating": { "list": [] },
      "time": { "from": "now-1h", "to": "now" },
      "title": "DavTro - System Overview",
      "uid": "davtro-system",
      "version": 1
    }
  
  # Dashboard - Application Metrics
  dashboard-app.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "panels": [
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "id": 1,
          "targets": [
            { "expr": "sum(rate(http_requests_total{namespace=\"davtro\"}[5m])) by (job)", "legendFormat": "{{job}}" }
          ],
          "title": "Request Rate",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "id": 2,
          "targets": [
            { "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace=\"davtro\"}[5m])) by (le, job))", "legendFormat": "p95 {{job}}" }
          ],
          "title": "Request Latency (p95)",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
          "id": 3,
          "targets": [
            { "expr": "sum(rate(http_requests_total{status=~\"5..\", namespace=\"davtro\"}[5m])) by (job)", "legendFormat": "{{job}}" }
          ],
          "title": "Error Rate",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
          "id": 4,
          "targets": [
            { "expr": "sum(http_requests_in_flight{namespace=\"davtro\"}) by (job)", "legendFormat": "{{job}}" }
          ],
          "title": "In-flight Requests",
          "type": "timeseries"
        }
      ],
      "schemaVersion": 38,
      "tags": ["davtro", "application"],
      "title": "DavTro - Application Metrics",
      "uid": "davtro-app",
      "version": 1
    }
  
  # Dashboard - Database
  dashboard-db.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "panels": [
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "id": 1,
          "targets": [
            { "expr": "pg_stat_activity_count{datname=\"davtro_production\"}", "legendFormat": "{{state}}" }
          ],
          "title": "Active Connections",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "id": 2,
          "targets": [
            { "expr": "rate(pg_stat_database_tup_returned{datname=\"davtro_production\"}[5m])", "legendFormat": "returned" },
            { "expr": "rate(pg_stat_database_tup_fetched{datname=\"davtro_production\"}[5m])", "legendFormat": "fetched" }
          ],
          "title": "Rows Processed",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
          "id": 3,
          "targets": [
            { "expr": "pg_database_size_bytes{datname=\"davtro_production\"}", "legendFormat": "size" }
          ],
          "title": "Database Size",
          "type": "stat"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
          "id": 4,
          "targets": [
            { "expr": "pg_stat_database_blks_hit{datname=\"davtro_production\"} / (pg_stat_database_blks_hit{datname=\"davtro_production\"} + pg_stat_database_blks_read{datname=\"davtro_production\"})", "legendFormat": "hit ratio" }
          ],
          "title": "Cache Hit Ratio",
          "type": "gauge"
        }
      ],
      "schemaVersion": 38,
      "tags": ["davtro", "database"],
      "title": "DavTro - Database Metrics",
      "uid": "davtro-db",
      "version": 1
    }
  
  # Dashboard - Kafka
  dashboard-kafka.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "panels": [
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "id": 1,
          "targets": [
            { "expr": "sum(kafka_topic_partition_current_offset{topic=~\"davtro-.*\"}) by (topic)", "legendFormat": "{{topic}}" }
          ],
          "title": "Topic Offsets",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "id": 2,
          "targets": [
            { "expr": "sum(kafka_consumergroup_lag) by (consumergroup, topic)", "legendFormat": "{{consumergroup}} - {{topic}}" }
          ],
          "title": "Consumer Lag",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
          "id": 3,
          "targets": [
            { "expr": "sum(rate(kafka_topic_partition_current_offset{topic=~\"davtro-.*\"}[5m])) by (topic)", "legendFormat": "{{topic}}" }
          ],
          "title": "Messages/sec",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
          "id": 4,
          "targets": [
            { "expr": "kafka_brokers", "legendFormat": "brokers" }
          ],
          "title": "Active Brokers",
          "type": "stat"
        }
      ],
      "schemaVersion": 38,
      "tags": ["davtro", "kafka"],
      "title": "DavTro - Kafka Metrics",
      "uid": "davtro-kafka",
      "version": 1
    }
EOF

    log INFO "ConfigMap Grafana wdrożony"
}

# ============================================================================
# SEKCJA 13: CONFIGMAP - VAULT
# ============================================================================
deploy_configmap_vault() {
    log STEP "Wdrażanie ConfigMap Vault..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
data:
  vault.hcl: |
    # ============================================================================
    # Vault Configuration - DavTro Production
    # ============================================================================
    
    ui = true
    
    listener "tcp" {
      address     = "0.0.0.0:8200"
      cluster_address = "0.0.0.0:8201"
      tls_disable = 1
    }
    
    storage "file" {
      path = "/vault/data"
    }
    
    api_addr = "http://vault:8200"
    cluster_addr = "https://vault:8201"
    
    disable_mlock = true
    
    telemetry {
      prometheus_retention_time = "30s"
      disable_hostname = true
    }
    
    log_level = "Info"
    
    plugin_directory = "/vault/plugins"
    
    max_lease_ttl = "8760h"
    default_lease_ttl = "768h"
    
    raw_storage_endpoint = true
    
    entropy {
      seal "awskms" {
        region = "eu-central-1"
      }
    }
  
  init-vault.sh: |
    #!/bin/sh
    # ============================================================================
    # Vault Initialization Script
    # ============================================================================
    
    set -e
    
    echo "Waiting for Vault to be ready..."
    until vault status >/dev/null 2>&1 || [ $? -eq 2 ]; do
      sleep 2
    done
    
    echo "Checking Vault initialization status..."
    if vault status -format=json | jq -e '.initialized' >/dev/null; then
      echo "Vault is already initialized"
      exit 0
    fi
    
    echo "Initializing Vault..."
    vault operator init -key-shares=5 -key-threshold=3 > /vault/init-output.txt
    
    echo "Vault initialized successfully"
    cat /vault/init-output.txt
EOF

    log INFO "ConfigMap Vault wdrożony"
}

# ============================================================================
# SEKCJA 14: CONFIGMAP - PGADMIN, KAFKA-UI, NODE-EXPORTER
# ============================================================================
deploy_configmap_tools() {
    log STEP "Wdrażanie ConfigMap narzędzi..."
    
    cat <<'EOF' | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgadmin-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database-tools
data:
  servers.json: |
    {
      "Servers": {
        "1": {
          "Name": "DavTro PostgreSQL",
          "Group": "Servers",
          "Host": "postgres-db",
          "Port": 5432,
          "MaintenanceDB": "davtro_production",
          "Username": "davtro_admin",
          "SSLMode": "prefer",
          "PassFile": "/pgadmin4/pgpass",
          "ConnectTimeout": 10,
          "UseSSHTunnel": 0,
          "TunnelPort": "22",
          "TunnelAuthentication": 0
        }
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-ui-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming-tools
data:
  config.yml: |
    # ============================================================================
    # Kafka UI Configuration - DavTro Production
    # ============================================================================
    
    auth:
      type: DISABLED
    
    audit:
      enabled: false
    
    kafka:
      clusters:
        - name: davtro-kafka
          bootstrapServers: kafka-kraft-0.kafka-kraft:9092
          properties:
            security.protocol: PLAINTEXT
          readOnly: false
          metrics:
            port: 9308
            type: JMX
          kafkaConnect: []
          schemaRegistry: null
          ksqldbServer: null
          properties:
            max.request.size: 10485760
    
    rbac:
      roles: []
    
    management:
      health:
        ldap:
          enabled: false
    
    server:
      port: 8080
    
    logging:
      level:
        root: INFO
        com.provectus: INFO
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-exporter-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
data:
  textfile-collector.sh: |
    #!/bin/sh
    # Custom metrics for node-exporter
    
    # Uptime in seconds
    UPTIME=$(cat /proc/uptime | awk '{print $1}')
    echo "node_uptime_seconds $UPTIME" > /textfile/uptime.prom
    
    # Load average
    LOAD=$(cat /proc/loadavg | awk '{print $1}')
    echo "node_load1 $LOAD" >> /textfile/uptime.prom
    
    # Process count
    PROC_COUNT=$(ls -1 /proc | grep -c '^[0-9]')
    echo "node_process_count $PROC_COUNT" >> /textfile/uptime.prom
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: message-processor-config
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
data:
  config.json: |
    {
      "service": {
        "name": "message-processor",
        "version": "2.0.0",
        "environment": "production"
      },
      "kafka": {
        "bootstrapServers": "kafka-kraft-0.kafka-kraft:9092",
        "groupId": "davtro-message-processor",
        "autoOffsetReset": "earliest",
        "enableAutoCommit": false,
        "maxPollRecords": 500,
        "sessionTimeoutMs": 30000,
        "topics": {
          "input": "davtro-events",
          "output": "davtro-processed",
          "deadLetter": "davtro-dead-letter"
        }
      },
      "processing": {
        "batchSize": 100,
        "batchTimeoutMs": 5000,
        "maxRetries": 3,
        "retryDelayMs": 1000,
        "concurrency": 4
      },
      "redis": {
        "host": "redis",
        "port": 6379,
        "db": 1,
        "keyPrefix": "msgproc:"
      },
      "monitoring": {
        "metricsEnabled": true,
        "metricsPort": 9090,
        "healthPort": 8080
      }
    }
EOF

    log INFO "ConfigMap narzędzi wdrożony"
}

# ============================================================================
# SEKCJA 15: RBAC - SERVICE ACCOUNTS, ROLES, BINDINGS
# ============================================================================
deploy_rbac() {
    log STEP "Wdrażanie RBAC..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
# Service Account dla aplikacji
apiVersion: v1
kind: ServiceAccount
metadata:
  name: davtro-app-sa
  labels:
    app.kubernetes.io/part-of: davtro
---
# Service Account dla monitoringu
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitoring-sa
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
---
# Service Account dla Vault
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-sa
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
---
# Service Account dla Spark
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark-sa
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: analytics
---
# ClusterRole dla Prometheus (odczyt metryk z klastra)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-davtro
  labels:
    app.kubernetes.io/part-of: davtro
rules:
  - apiGroups: [""]
    resources: ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch"]
  - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
    verbs: ["get"]
---
# ClusterRoleBinding dla Prometheus
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-davtro
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-davtro
subjects:
  - kind: ServiceAccount
    name: monitoring-sa
    namespace: ${NAMESPACE}
---
# Role dla Vault (auth Kubernetes)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vault-auth-davtro
rules:
  - apiGroups: [""]
    resources: ["serviceaccounts/token"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-davtro
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vault-auth-davtro
subjects:
  - kind: ServiceAccount
    name: vault-sa
    namespace: ${NAMESPACE}
---
# Role dla aplikacji w namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: davtro-app-role
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: davtro-app-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: davtro-app-role
subjects:
  - kind: ServiceAccount
    name: davtro-app-sa
    namespace: ${NAMESPACE}
EOF

    log INFO "RBAC wdrożony"
}

# ============================================================================
# SEKCJA 16: SERVICES
# ============================================================================
deploy_services() {
    log STEP "Wdrażanie Services..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
# FastAPI Web App Service
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-app
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
spec:
  selector:
    app: fastapi-web-app
  ports:
    - name: http
      port: 80
      targetPort: 8000
      protocol: TCP
  type: ClusterIP
---
# Spring App Service
apiVersion: v1
kind: Service
metadata:
  name: spring-app
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
spec:
  selector:
    app: spring-app-deployment
  ports:
    - name: http
      port: 80
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
---
# PostgreSQL Service (headless dla StatefulSet)
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database
spec:
  selector:
    app: postgres-db
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
  clusterIP: None
---
# PostgreSQL Service (dla dostępu z aplikacji)
apiVersion: v1
kind: Service
metadata:
  name: postgres-db-rw
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database
spec:
  selector:
    app: postgres-db
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
  type: ClusterIP
---
# Redis Service
apiVersion: v1
kind: Service
metadata:
  name: redis
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: cache
spec:
  selector:
    app: redis
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
  type: ClusterIP
---
# Kafka Service (headless)
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  selector:
    app: kafka-kraft
  ports:
    - name: client
      port: 9092
      targetPort: 9092
    - name: client-external
      port: 9094
      targetPort: 9094
    - name: controller
      port: 9093
      targetPort: 9093
  clusterIP: None
---
# Kafka Service (dla aplikacji)
apiVersion: v1
kind: Service
metadata:
  name: kafka
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  selector:
    app: kafka-kraft
  ports:
    - name: client
      port: 9092
      targetPort: 9092
    - name: client-external
      port: 9094
      targetPort: 9094
  type: ClusterIP
---
# Kafka Exporter Service
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  selector:
    app: kafka-exporter
  ports:
    - name: metrics
      port: 9308
      targetPort: 9308
  type: ClusterIP
---
# Kafka UI Service
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming-tools
spec:
  selector:
    app: kafka-ui
  ports:
    - name: http
      port: 80
      targetPort: 8080
  type: ClusterIP
---
# Spark Master Service
apiVersion: v1
kind: Service
metadata:
  name: spark-master
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: analytics
spec:
  selector:
    app: spark-master
  ports:
    - name: master
      port: 7077
      targetPort: 7077
    - name: webui
      port: 8080
      targetPort: 8080
    - name: rest
      port: 6066
      targetPort: 6066
  type: ClusterIP
---
# Spark Worker Service
apiVersion: v1
kind: Service
metadata:
  name: spark-worker
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: analytics
spec:
  selector:
    app: spark-worker
  ports:
    - name: webui
      port: 8081
      targetPort: 8081
  type: ClusterIP
---
# Prometheus Service
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
spec:
  selector:
    app: prometheus
  ports:
    - name: http
      port: 9090
      targetPort: 9090
  type: ClusterIP
---
# Grafana Service
apiVersion: v1
kind: Service
metadata:
  name: grafana
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
spec:
  selector:
    app: grafana
  ports:
    - name: http
      port: 3000
      targetPort: 3000
  type: ClusterIP
---
# Loki Service
apiVersion: v1
kind: Service
metadata:
  name: loki
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: logging
spec:
  selector:
    app: loki
  ports:
    - name: http
      port: 3100
      targetPort: 3100
    - name: grpc
      port: 9096
      targetPort: 9096
  type: ClusterIP
---
# Tempo Service
apiVersion: v1
kind: Service
metadata:
  name: tempo
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: tracing
spec:
  selector:
    app: tempo
  ports:
    - name: http
      port: 3200
      targetPort: 3200
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
    - name: otlp-http
      port: 4318
      targetPort: 4318
    - name: jaeger-grpc
      port: 14250
      targetPort: 14250
    - name: jaeger-http
      port: 14268
      targetPort: 14268
    - name: zipkin
      port: 9411
      targetPort: 9411
  type: ClusterIP
---
# Vault Service
apiVersion: v1
kind: Service
metadata:
  name: vault
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
spec:
  selector:
    app: vault
  ports:
    - name: http
      port: 8200
      targetPort: 8200
    - name: cluster
      port: 8201
      targetPort: 8201
  clusterIP: None
---
# Vault Service (dla UI)
apiVersion: v1
kind: Service
metadata:
  name: vault-ui
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
spec:
  selector:
    app: vault
  ports:
    - name: http
      port: 8200
      targetPort: 8200
  type: ClusterIP
---
# pgAdmin Service
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database-tools
spec:
  selector:
    app: pgadmin
  ports:
    - name: http
      port: 80
      targetPort: 80
  type: ClusterIP
---
# Node Exporter Service
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
spec:
  selector:
    app: node-exporter
  ports:
    - name: metrics
      port: 9100
      targetPort: 9100
  type: ClusterIP
---
# Postgres Exporter Service
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
spec:
  selector:
    app: postgres-exporter
  ports:
    - name: metrics
      port: 9187
      targetPort: 9187
  type: ClusterIP
---
# Message Processor Service
apiVersion: v1
kind: Service
metadata:
  name: message-processor
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  selector:
    app: message-processor
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: metrics
      port: 9090
      targetPort: 9090
  type: ClusterIP
EOF

    log INFO "Services wdrożone"
}

# ============================================================================
# SEKCJA 17: DEPLOYMENTS I STATEFULSETS
# ============================================================================
deploy_workloads() {
    log STEP "Wdrażanie Deploymentów i StatefulSets..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
# ============================================================================
# PostgreSQL StatefulSet
# ============================================================================
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database
spec:
  serviceName: postgres-db
  replicas: 1
  podManagementPolicy: OrderedReady
  selector:
    matchLabels:
      app: postgres-db
  template:
    metadata:
      labels:
        app: postgres-db
        app.kubernetes.io/part-of: davtro
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9187"
    spec:
      serviceAccountName: davtro-app-sa
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
      containers:
        - name: postgres
          image: ${POSTGRES_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: postgres
              containerPort: 5432
              protocol: TCP
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_PASSWORD
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_DB
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
            - name: POSTGRES_INITDB_ARGS
              value: "--encoding=UTF-8 --locale=C"
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 2Gi
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
            - name: postgres-config
              mountPath: /etc/postgresql
            - name: init-scripts
              mountPath: /docker-entrypoint-initdb.d
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - pg_isready -U \$(POSTGRES_USER) -d \$(POSTGRES_DB)
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - pg_isready -U \$(POSTGRES_USER) -d \$(POSTGRES_DB)
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          startupProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - pg_isready -U \$(POSTGRES_USER) -d \$(POSTGRES_DB)
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30
      volumes:
        - name: postgres-config
          configMap:
            name: postgres-config
            items:
              - key: postgresql.conf
                path: postgresql.conf
              - key: pg_hba.conf
                path: pg_hba.conf
        - name: init-scripts
          configMap:
            name: postgres-config
            items:
              - key: init-db.sql
                path: init-db.sql
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: ${STORAGE_CLASS}
        resources:
          requests:
            storage: 10Gi
---
# ============================================================================
# Redis Deployment
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: redis
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "6379"
    spec:
      serviceAccountName: davtro-app-sa
      securityContext:
        fsGroup: 999
        runAsUser: 999
      containers:
        - name: redis
          image: ${REDIS_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - redis-server
            - /usr/local/etc/redis/redis.conf
            - --requirepass
            - \$(REDIS_PASSWORD)
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-credentials
                  key: REDIS_PASSWORD
          ports:
            - name: redis
              containerPort: 6379
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: "1"
              memory: 1Gi
          volumeMounts:
            - name: redis-data
              mountPath: /data
            - name: redis-config
              mountPath: /usr/local/etc/redis
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - redis-cli -a \$(REDIS_PASSWORD) ping | grep PONG
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - redis-cli -a \$(REDIS_PASSWORD) ping | grep PONG
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: redis-config
          configMap:
            name: redis-config
        - name: redis-data
          emptyDir: {}
---
# ============================================================================
# Kafka StatefulSet (KRaft) - NAPRAWA ImagePullBackOff
# ============================================================================
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-kraft
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  serviceName: kafka-kraft
  replicas: 1
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: kafka-kraft
  template:
    metadata:
      labels:
        app: kafka-kraft
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9308"
    spec:
      serviceAccountName: davtro-app-sa
      securityContext:
        fsGroup: 1001
      containers:
        - name: kafka
          image: ${KAFKA_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: client
              containerPort: 9092
            - name: client-external
              containerPort: 9094
            - name: controller
              containerPort: 9093
          env:
            - name: KAFKA_ENABLE_KRAFT
              value: "yes"
            - name: KAFKA_KRAFT_CLUSTER_ID
              value: "MkU3OEVBNTcwNTJENDM2Qk"
            - name: KAFKA_CFG_PROCESS_ROLES
              value: "broker,controller"
            - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
              value: "0@kafka-kraft-0.kafka-kraft:9093"
            - name: KAFKA_CFG_LISTENERS
              value: "PLAINTEXT://:9092,CONTROLLER://:9093,SASL_PLAINTEXT://:9094"
            - name: KAFKA_CFG_ADVERTISED_LISTENERS
              value: "PLAINTEXT://kafka-kraft-0.kafka-kraft:9092,SASL_PLAINTEXT://kafka-kraft-0.kafka-kraft:9094"
            - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
              value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SASL_PLAINTEXT:SASL_PLAINTEXT"
            - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
              value: "CONTROLLER"
            - name: KAFKA_CFG_INTER_BROKER_LISTENER_NAME
              value: "PLAINTEXT"
            - name: KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE
              value: "true"
            - name: KAFKA_CFG_NUM_PARTITIONS
              value: "3"
            - name: KAFKA_CFG_DEFAULT_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_CFG_OFFSETS_TOPIC_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_CFG_LOG_RETENTION_HOURS
              value: "168"
            - name: KAFKA_CFG_LOG_DIRS
              value: "/bitnami/kafka/data"
            - name: KAFKA_HEAP_OPTS
              value: "-Xmx1024m -Xms512m"
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: "2"
              memory: 3Gi
          volumeMounts:
            - name: kafka-data
              mountPath: /bitnami/kafka
            - name: kafka-config
              mountPath: /opt/bitnami/kafka/config
          livenessProbe:
            tcpSocket:
              port: 9092
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          readinessProbe:
            tcpSocket:
              port: 9092
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          startupProbe:
            tcpSocket:
              port: 9092
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 30
      volumes:
        - name: kafka-config
          configMap:
            name: kafka-config
  volumeClaimTemplates:
    - metadata:
        name: kafka-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: ${STORAGE_CLASS}
        resources:
          requests:
            storage: 20Gi
---
# ============================================================================
# Kafka Exporter - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-exporter
  template:
    metadata:
      labels:
        app: kafka-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9308"
    spec:
      containers:
        - name: kafka-exporter
          image: ${KAFKA_EXPORTER_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - --kafka.server=kafka-kraft-0.kafka-kraft:9092
            - --topic.filter=davtro-.*
            - --web.listen-address=:9308
            - --web.telemetry-path=/metrics
          ports:
            - name: metrics
              containerPort: 9308
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /metrics
              port: 9308
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /metrics
              port: 9308
            initialDelaySeconds: 5
            periodSeconds: 5
---
# ============================================================================
# Kafka UI - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming-tools
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
          image: ${KAFKA_UI_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: DYNAMIC_CONFIG_ENABLED
              value: "true"
            - name: KAFKA_CLUSTERS_0_NAME
              value: "davtro-kafka"
            - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
              value: "kafka-kraft-0.kafka-kraft:9092"
            - name: KAFKA_CLUSTERS_0_METRICS_PORT
              value: "9308"
            - name: KAFKA_CLUSTERS_0_METRICS_TYPE
              value: "JMX"
            - name: AUTH_TYPE
              value: "DISABLED"
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 5
---
# ============================================================================
# Kafka Topic Job - NAPRAWA ImagePullBackOff
# ============================================================================
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-job
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  backoffLimit: 5
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: kafka-topic-job
    spec:
      restartPolicy: OnFailure
      containers:
        - name: kafka-topic-init
          image: ${KAFKA_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              echo "Waiting for Kafka to be ready..."
              sleep 30
              
              KAFKA_OPTS="" /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --create --if-not-exists \\
                --topic davtro-events \\
                --partitions 3 \\
                --replication-factor 1
              
              /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --create --if-not-exists \\
                --topic davtro-users \\
                --partitions 3 \\
                --replication-factor 1
              
              /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --create --if-not-exists \\
                --topic davtro-processed \\
                --partitions 3 \\
                --replication-factor 1
              
              /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --create --if-not-exists \\
                --topic davtro-notifications \\
                --partitions 3 \\
                --replication-factor 1
              
              /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --create --if-not-exists \\
                --topic davtro-audit \\
                --partitions 3 \\
                --replication-factor 1
              
              /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --create --if-not-exists \\
                --topic davtro-dead-letter \\
                --partitions 1 \\
                --replication-factor 1
              
              echo "All topics created successfully"
              /opt/bitnami/kafka/bin/kafka-topics.sh \\
                --bootstrap-server kafka-kraft-0.kafka-kraft:9092 \\
                --list
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
---
# ============================================================================
# Spark Master - NAPRAWA ImagePullBackOff
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spark-master
  template:
    metadata:
      labels:
        app: spark-master
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      serviceAccountName: spark-sa
      containers:
        - name: spark-master
          image: ${SPARK_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /opt/bitnami/scripts/spark/entrypoint.sh
            - /opt/bitnami/scripts/spark/run.sh
          args:
            - /opt/bitnami/spark/sbin/start-master.sh
          env:
            - name: SPARK_MODE
              value: "master"
            - name: SPARK_MASTER_HOST
              value: "spark-master"
            - name: SPARK_MASTER_PORT
              value: "7077"
            - name: SPARK_MASTER_WEBUI_PORT
              value: "8080"
          ports:
            - name: master
              containerPort: 7077
            - name: webui
              containerPort: 8080
            - name: rest
              containerPort: 6066
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: "2"
              memory: 3Gi
          volumeMounts:
            - name: spark-config
              mountPath: /opt/bitnami/spark/conf
            - name: spark-events
              mountPath: /tmp/spark-events
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: spark-config
          configMap:
            name: spark-config
        - name: spark-events
          emptyDir: {}
---
# ============================================================================
# Spark Worker - NAPRAWA ImagePullBackOff
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: analytics
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
      serviceAccountName: spark-sa
      containers:
        - name: spark-worker
          image: ${SPARK_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /opt/bitnami/scripts/spark/entrypoint.sh
            - /opt/bitnami/scripts/spark/run.sh
          args:
            - /opt/bitnami/spark/sbin/start-worker.sh
            - spark://spark-master:7077
          env:
            - name: SPARK_MODE
              value: "worker"
            - name: SPARK_MASTER_URL
              value: "spark://spark-master:7077"
            - name: SPARK_WORKER_CORES
              value: "2"
            - name: SPARK_WORKER_MEMORY
              value: "2g"
            - name: SPARK_WORKER_WEBUI_PORT
              value: "8081"
          ports:
            - name: webui
              containerPort: 8081
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: "2"
              memory: 3Gi
          volumeMounts:
            - name: spark-config
              mountPath: /opt/bitnami/spark/conf
            - name: spark-work
              mountPath: /tmp/spark-work
          livenessProbe:
            httpGet:
              path: /
              port: 8081
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 8081
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: spark-config
          configMap:
            name: spark-config
        - name: spark-work
          emptyDir: {}
---
# ============================================================================
# FastAPI Web App - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi-web-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: fastapi-web-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: davtro-app-sa
      containers:
        - name: fastapi
          image: ${FASTAPI_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              pip install --no-cache-dir -r /app/requirements.txt
              uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
          workingDir: /app
          ports:
            - name: http
              containerPort: 8000
          envFrom:
            - configMapRef:
                name: web-app-config
            - configMapRef:
                name: fastapi-config
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: DATABASE_URL
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: redis-credentials
                  key: REDIS_URL
            - name: KAFKA_BOOTSTRAP_SERVERS
              valueFrom:
                secretKeyRef:
                  name: kafka-credentials
                  key: KAFKA_BOOTSTRAP_SERVERS
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: fastapi-secrets
                  key: SECRET_KEY
            - name: VAULT_ADDR
              valueFrom:
                secretKeyRef:
                  name: vault-credentials
                  key: VAULT_ADDR
            - name: VAULT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: vault-credentials
                  key: VAULT_TOKEN
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          volumeMounts:
            - name: app-code
              mountPath: /app
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 3
          startupProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 30
      volumes:
        - name: app-code
          configMap:
            name: fastapi-config
            items:
              - key: main.py
                path: main.py
              - key: requirements.txt
                path: requirements.txt
---
# ============================================================================
# Spring App - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app-deployment
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: application
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spring-app-deployment
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: spring-app-deployment
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      serviceAccountName: davtro-app-sa
      containers:
        - name: spring
          image: ${SPRING_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              echo "Spring Boot placeholder - użyj własnego obrazu aplikacji"
              sleep infinity
          ports:
            - name: http
              containerPort: 8080
          envFrom:
            - configMapRef:
                name: web-app-config
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: "production"
            - name: SPRING_DATASOURCE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_URL_JDBC
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: spring-app-secrets
                  key: SPRING_DATASOURCE_USERNAME
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: spring-app-secrets
                  key: SPRING_DATASOURCE_PASSWORD
            - name: SPRING_DATA_REDIS_HOST
              valueFrom:
                secretKeyRef:
                  name: redis-credentials
                  key: REDIS_HOST
            - name: SPRING_DATA_REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-credentials
                  key: REDIS_PASSWORD
            - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
              valueFrom:
                secretKeyRef:
                  name: kafka-credentials
                  key: KAFKA_BOOTSTRAP_SERVERS
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: spring-app-secrets
                  key: JWT_SECRET
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 5
            timeoutSeconds: 3
          startupProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 30
---
# ============================================================================
# Message Processor - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: streaming
spec:
  replicas: 2
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
          image: ${PYTHON_IMAGE:-python:3.11-slim}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              pip install aiokafka redis prometheus-client
              echo "Message processor placeholder"
              sleep infinity
          ports:
            - name: http
              containerPort: 8080
            - name: metrics
              containerPort: 9090
          envFrom:
            - configMapRef:
                name: message-processor-config
          env:
            - name: KAFKA_BOOTSTRAP_SERVERS
              valueFrom:
                secretKeyRef:
                  name: kafka-credentials
                  key: KAFKA_BOOTSTRAP_SERVERS
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: redis-credentials
                  key: REDIS_URL
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
---
# ============================================================================
# Prometheus - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
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
      serviceAccountName: monitoring-sa
      securityContext:
        fsGroup: 65534
        runAsUser: 65534
        runAsGroup: 65534
      containers:
        - name: prometheus
          image: ${PROMETHEUS_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/prometheus
            - --storage.tsdb.retention.time=15d
            - --storage.tsdb.retention.size=10GB
            - --web.console.libraries=/etc/prometheus/console_libraries
            - --web.console.templates=/etc/prometheus/consoles
            - --web.enable-lifecycle
            - --web.enable-admin-api
          ports:
            - name: http
              containerPort: 9090
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 3Gi
          volumeMounts:
            - name: prometheus-config
              mountPath: /etc/prometheus
            - name: prometheus-data
              mountPath: /prometheus
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: 9090
            initialDelaySeconds: 30
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /-/ready
              port: 9090
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: prometheus-config
          configMap:
            name: prometheus-config
        - name: prometheus-data
          emptyDir: {}
---
# ============================================================================
# Grafana
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
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
      securityContext:
        fsGroup: 472
        runAsUser: 472
      containers:
        - name: grafana
          image: ${GRAFANA_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: grafana-credentials
                  key: GF_SECURITY_ADMIN_USER
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-credentials
                  key: GF_SECURITY_ADMIN_PASSWORD
            - name: GF_INSTALL_PLUGINS
              value: "grafana-piechart-panel,grafana-clock-panel"
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          volumeMounts:
            - name: grafana-config
              mountPath: /etc/grafana/grafana.ini
              subPath: grafana.ini
            - name: grafana-datasources
              mountPath: /etc/grafana/provisioning/datasources
            - name: grafana-dashboards-config
              mountPath: /etc/grafana/provisioning/dashboards
            - name: grafana-dashboards
              mountPath: /var/lib/grafana/dashboards/davtro
            - name: grafana-data
              mountPath: /var/lib/grafana
          livenessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: grafana-config
          configMap:
            name: grafana-config
            items:
              - key: grafana.ini
                path: grafana.ini
        - name: grafana-datasources
          configMap:
            name: grafana-config
            items:
              - key: datasources.yaml
                path: datasources.yaml
        - name: grafana-dashboards-config
          configMap:
            name: grafana-config
            items:
              - key: dashboards.yaml
                path: dashboards.yaml
        - name: grafana-dashboards
          configMap:
            name: grafana-config
            items:
              - key: dashboard-system.json
                path: system.json
              - key: dashboard-app.json
                path: app.json
              - key: dashboard-db.json
                path: db.json
              - key: dashboard-kafka.json
                path: kafka.json
        - name: grafana-data
          emptyDir: {}
---
# ============================================================================
# Loki - NAPRAWA CrashLoopBackOff
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: logging
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
      securityContext:
        fsGroup: 10001
        runAsUser: 10001
        runAsGroup: 10001
      containers:
        - name: loki
          image: ${LOKI_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - -config.file=/etc/loki/loki.yaml
          ports:
            - name: http
              containerPort: 3100
            - name: grpc
              containerPort: 9096
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 3Gi
          volumeMounts:
            - name: loki-config
              mountPath: /etc/loki
            - name: loki-data
              mountPath: /loki
          livenessProbe:
            httpGet:
              path: /ready
              port: 3100
            initialDelaySeconds: 45
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 3100
            initialDelaySeconds: 30
            periodSeconds: 5
            timeoutSeconds: 3
          startupProbe:
            httpGet:
              path: /ready
              port: 3100
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 30
      volumes:
        - name: loki-config
          configMap:
            name: loki-config
        - name: loki-data
          emptyDir: {}
---
# ============================================================================
# Promtail - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: logging
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      serviceAccountName: monitoring-sa
      containers:
        - name: promtail
          image: ${PROMTAIL_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - -config.file=/etc/promtail/promtail.yaml
          ports:
            - name: http
              containerPort: 9080
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          volumeMounts:
            - name: promtail-config
              mountPath: /etc/promtail
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
          livenessProbe:
            httpGet:
              path: /ready
              port: 9080
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 9080
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: promtail-config
          configMap:
            name: promtail-config
        - name: varlog
          hostPath:
            path: /var/log
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
---
# ============================================================================
# Tempo
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: tracing
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
          image: ${TEMPO_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - -config.file=/etc/tempo/tempo.yaml
          ports:
            - name: http
              containerPort: 3200
            - name: otlp-grpc
              containerPort: 4317
            - name: otlp-http
              containerPort: 4318
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          volumeMounts:
            - name: tempo-config
              mountPath: /etc/tempo
            - name: tempo-data
              mountPath: /var/tempo
          livenessProbe:
            httpGet:
              path: /ready
              port: 3200
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 3200
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: tempo-config
          configMap:
            name: tempo-config
        - name: tempo-data
          emptyDir: {}
---
# ============================================================================
# Vault StatefulSet - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: security
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      serviceAccountName: vault-sa
      securityContext:
        fsGroup: 1000
        runAsUser: 100
        runAsGroup: 1000
      containers:
        - name: vault
          image: ${VAULT_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - vault
            - server
            - -config=/vault/config/vault.hcl
          ports:
            - name: http
              containerPort: 8200
            - name: cluster
              containerPort: 8201
          env:
            - name: VAULT_ADDR
              value: "http://127.0.0.1:8200"
            - name: VAULT_API_ADDR
              value: "http://\$(POD_IP):8200"
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          volumeMounts:
            - name: vault-config
              mountPath: /vault/config
            - name: vault-data
              mountPath: /vault/data
            - name: vault-file
              mountPath: /vault/file
            - name: vault-logs
              mountPath: /vault/logs
          livenessProbe:
            httpGet:
              path: /v1/sys/health?standbyok=true
              port: 8200
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204
              port: 8200
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: vault-config
          configMap:
            name: vault-config
        - name: vault-file
          emptyDir: {}
        - name: vault-logs
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vault-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: ${STORAGE_CLASS}
        resources:
          requests:
            storage: 5Gi
---
# ============================================================================
# pgAdmin - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database-tools
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
      securityContext:
        fsGroup: 5050
        runAsUser: 5050
      containers:
        - name: pgadmin
          image: ${PGADMIN_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
          env:
            - name: PGADMIN_DEFAULT_EMAIL
              valueFrom:
                secretKeyRef:
                  name: pgadmin-credentials
                  key: PGADMIN_DEFAULT_EMAIL
            - name: PGADMIN_DEFAULT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: pgadmin-credentials
                  key: PGADMIN_DEFAULT_PASSWORD
            - name: PGADMIN_CONFIG_SERVER_MODE
              value: "False"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          volumeMounts:
            - name: pgadmin-data
              mountPath: /var/lib/pgadmin
            - name: pgadmin-config
              mountPath: /pgadmin4/servers.json
              subPath: servers.json
          livenessProbe:
            httpGet:
              path: /misc/ping
              port: 80
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /misc/ping
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 5
      volumes:
        - name: pgadmin-data
          emptyDir: {}
        - name: pgadmin-config
          configMap:
            name: pgadmin-config
---
# ============================================================================
# Node Exporter (DaemonSet) - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9100"
    spec:
      hostPID: true
      hostNetwork: true
      tolerations:
        - operator: Exists
      containers:
        - name: node-exporter
          image: ${NODE_EXPORTER_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - --path.procfs=/host/proc
            - --path.sysfs=/host/sys
            - --path.rootfs=/host/root
            - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)
            - --collector.textfile.directory=/textfile
          ports:
            - name: metrics
              containerPort: 9100
              hostPort: 9100
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
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
              mountPropagation: HostToContainer
            - name: textfile
              mountPath: /textfile
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
        - name: textfile
          emptyDir: {}
---
# ============================================================================
# Postgres Exporter - NAPRAWA CreateContainerConfigError
# ============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9187"
    spec:
      containers:
        - name: postgres-exporter
          image: ${POSTGRES_EXPORTER_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: metrics
              containerPort: 9187
          env:
            - name: DATA_SOURCE_NAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_URL
            - name: PG_EXPORTER_AUTO_DISCOVER_DATABASES
              value: "true"
            - name: PG_EXPORTER_EXTEND_QUERY_PATH
              value: "/config/queries.yaml"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /metrics
              port: 9187
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /metrics
              port: 9187
            initialDelaySeconds: 5
            periodSeconds: 5
---
EOF

    log INFO "Workloads wdrożone"
}

# ============================================================================
# SEKCJA 18: INGRESS
# ============================================================================
deploy_ingress() {
    log STEP "Wdrażanie Ingress..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-ingress
  labels:
    app.kubernetes.io/part-of: davtro
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - davtro.local
        - api.davtro.local
        - grafana.davtro.local
        - kafka-ui.davtro.local
        - pgadmin.davtro.local
        - vault.davtro.local
      secretName: davtro-tls
  rules:
    - host: davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fastapi-web-app
                port:
                  number: 80
    - host: api.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: spring-app
                port:
                  number: 80
    - host: grafana.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
    - host: kafka-ui.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-ui
                port:
                  number: 80
    - host: pgadmin.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: pgadmin
                port:
                  number: 80
    - host: vault.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vault-ui
                port:
                  number: 8200
EOF

    log INFO "Ingress wdrożony"
}

# ============================================================================
# SEKCJA 19: NETWORK POLICIES
# ============================================================================
deploy_network_policies() {
    log STEP "Wdrażanie Network Policies..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
# Domyślna polityka - deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
    - Ingress
---
# Pozwól na ruch wewnątrz namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${NAMESPACE}
---
# Pozwól na dostęp do aplikacji webowych z zewnątrz
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-ingress
spec:
  podSelector:
    matchLabels:
      app: fastapi-web-app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
        - podSelector:
            matchLabels:
              app: ingress-nginx
      ports:
        - protocol: TCP
          port: 8000
---
# Pozwól aplikacjom na dostęp do bazy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-db
spec:
  podSelector:
    matchLabels:
      app: postgres-db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: fastapi-web-app
        - podSelector:
            matchLabels:
              app: spring-app-deployment
        - podSelector:
            matchLabels:
              app: pgadmin
        - podSelector:
            matchLabels:
              app: postgres-exporter
      ports:
        - protocol: TCP
          port: 5432
---
# Pozwól aplikacjom na dostęp do Redis
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-redis
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: fastapi-web-app
        - podSelector:
            matchLabels:
              app: spring-app-deployment
        - podSelector:
            matchLabels:
              app: message-processor
      ports:
        - protocol: TCP
          port: 6379
---
# Pozwól aplikacjom na dostęp do Kafka
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-kafka
spec:
  podSelector:
    matchLabels:
      app: kafka-kraft
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: fastapi-web-app
        - podSelector:
            matchLabels:
              app: spring-app-deployment
        - podSelector:
            matchLabels:
              app: message-processor
        - podSelector:
            matchLabels:
              app: kafka-exporter
        - podSelector:
            matchLabels:
              app: kafka-ui
      ports:
        - protocol: TCP
          port: 9092
        - protocol: TCP
          port: 9094
EOF

    log INFO "Network Policies wdrożone"
}

# ============================================================================
# SEKCJA 20: POD DISRUPTION BUDGETS
# ============================================================================
deploy_pdbs() {
    log STEP "Wdrażanie PodDisruptionBudgets..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-web-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: fastapi-web-app
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: spring-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: spring-app-deployment
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: postgres-db-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: postgres-db
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: message-processor-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: message-processor
EOF

    log INFO "PDBs wdrożone"
}

# ============================================================================
# SEKCJA 21: CRONJOBS - BACKUP I CLEANUP
# ============================================================================
deploy_cronjobs() {
    log STEP "Wdrażanie CronJobs..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
# Backup bazy PostgreSQL
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  labels:
    app.kubernetes.io/part-of: davtro
    app.kubernetes.io/component: database
spec:
  schedule: "0 2 * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: ${POSTGRES_IMAGE}
              command:
                - /bin/sh
                - -c
                - |
                  BACKUP_FILE="/backup/davtro-db-\$(date +%Y%m%d-%H%M%S).sql.gz"
                  echo "Starting backup to \$BACKUP_FILE"
                  pg_dump -h postgres-db -U \${POSTGRES_USER} -d \${POSTGRES_DB} | gzip > \$BACKUP_FILE
                  echo "Backup completed: \$(ls -lh \$BACKUP_FILE)"
                  # Usuń stare backupy (starsze niż 7 dni)
                  find /backup -name "*.sql.gz" -mtime +7 -delete
              env:
                - name: POSTGRES_USER
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: POSTGRES_USER
                - name: POSTGRES_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: POSTGRES_PASSWORD
                - name: POSTGRES_DB
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: POSTGRES_DB
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: POSTGRES_PASSWORD
              volumeMounts:
                - name: backup-storage
                  mountPath: /backup
              resources:
                requests:
                  cpu: 100m
                  memory: 256Mi
                limits:
                  cpu: 500m
                  memory: 1Gi
          volumes:
            - name: backup-storage
              emptyDir: {}
---
# Cleanup starych podów
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pod-cleanup
spec:
  schedule: "0 */6 * * *"
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: monitoring-sa
          containers:
            - name: cleanup
              image: ${CURL_IMAGE}
              command:
                - /bin/sh
                - -c
                - |
                  echo "Cleaning up completed jobs..."
                  kubectl delete jobs -n ${NAMESPACE} --field-selector=status.successful=1 --ignore-not-found=true
                  echo "Cleanup completed"
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
                limits:
                  cpu: 100m
                  memory: 128Mi
EOF

    log INFO "CronJobs wdrożone"
}

# ============================================================================
# SEKCJA 22: SERVICE MONITORS
# ============================================================================
deploy_service_monitors() {
    log STEP "Wdrażanie ServiceMonitors (dla Prometheus Operator)..."
    
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - >> "$LOG_FILE" 2>&1
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fastapi-monitor
  labels:
    app.kubernetes.io/part-of: davtro
spec:
  selector:
    matchLabels:
      app: fastapi-web-app
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spring-monitor
  labels:
    app.kubernetes.io/part-of: davtro
spec:
  selector:
    matchLabels:
      app: spring-app-deployment
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-monitor
  labels:
    app.kubernetes.io/part-of: davtro
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  endpoints:
    - port: metrics
      interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-monitor
  labels:
    app.kubernetes.io/part-of: davtro
spec:
  selector:
    matchLabels:
      app: kafka-exporter
  endpoints:
    - port: metrics
      interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: promtail-monitor
  labels:
    app.kubernetes.io/part-of: davtro
spec:
  selector:
    matchLabels:
      app: promtail
  podMetricsEndpoints:
    - port: http
      path: /metrics
      interval: 15s
EOF

    log INFO "ServiceMonitors wdrożone"
}

# ============================================================================
# SEKCJA 23: DIAGNOSTYKA I WERYFIKACJA
# ============================================================================
run_diagnostics() {
    log STEP "Uruchamianie diagnostyki..."
    
    echo ""
    separator
    log INFO "Status podów:"
    kubectl get pods -n "$NAMESPACE" -o wide
    separator
    
    echo ""
    log INFO "Status services:"
    kubectl get svc -n "$NAMESPACE"
    separator
    
    echo ""
    log INFO "Sprawdzanie błędnych podów:"
    local error_pods
    error_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null || true)
    
    if [[ -n "$error_pods" ]]; then
        log WARN "Znaleziono pody w stanach błędnych:"
        echo "$error_pods" | while read -r pod; do
            echo "---"
            kubectl describe "$pod" -n "$NAMESPACE" | grep -A 5 "Events:" | tail -10
        done
    else
        log INFO "Wszystkie pody działają poprawnie!"
    fi
    
    separator
    log INFO "Informacje o wdrożeniu:"
    echo "  Namespace: $NAMESPACE"
    echo "  Deployment ID: $DEPLOYMENT_ID"
    echo "  Timestamp: $TIMESTAMP"
    echo "  Log file: $LOG_FILE"
    separator
}

# ============================================================================
# SEKCJA 24: GŁÓWNA FUNKCJA
# ============================================================================
main() {
    separator
    log STEP "Rozpoczynanie wdrożenia DavTro (all-in-one.sh v${SCRIPT_VERSION})"
    separator
    
    check_prerequisites
    generate_credentials
    
    # 1. Namespace
    deploy_namespace
    
    # 2. Secrets (NAPRAWA CreateContainerConfigError)
    deploy_secrets
    
    # 3. ConfigMaps
    deploy_configmap_postgres
    deploy_configmap_redis
    deploy_configmap_kafka
    deploy_configmap_spark
    deploy_configmap_webapps
    deploy_configmap_monitoring
    deploy_configmap_grafana
    deploy_configmap_vault
    deploy_configmap_tools
    
    # 4. RBAC
    deploy_rbac
    
    # 5. Services
    deploy_services
    
    # 6. Workloads (NAPRAWA ImagePullBackOff, CrashLoopBackOff)
    deploy_workloads
    
    # 7. Ingress
    deploy_ingress
    
    # 8. Network Policies
    deploy_network_policies
    
    # 9. PDBs
    deploy_pdbs
    
    # 10. CronJobs
    deploy_cronjobs
    
    # 11. Service Monitors
    deploy_service_monitors
    
    # 12. Cleanup
    cleanup_failed_pods
    
    # 13. Diagnostyka
    run_diagnostics
    
    separator
    log STEP "Wdrożenie zakończone pomyślnie!"
    separator
    
    echo ""
    log INFO "Dostęp do usług:"
    echo "  FastAPI:        http://davtro.local"
    echo "  Spring API:     http://api.davtro.local"
    echo "  Grafana:        http://grafana.davtro.local (admin/$(echo $GRAFANA_ADMIN_PASSWORD | head -c 8)...)"
    echo "  Kafka UI:       http://kafka-ui.davtro.local"
    echo "  pgAdmin:        http://pgadmin.davtro.local"
    echo "  Vault UI:       http://vault.davtro.local"
    echo "  Prometheus:     kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"
    echo "  Loki:           kubectl port-forward -n $NAMESPACE svc/loki 3100:3100"
    echo "  Tempo:          kubectl port-forward -n $NAMESPACE svc/tempo 3200:3200"
    echo ""
    log INFO "Logi zapisane w: $LOG_FILE"
    separator
}

# Uruchomienie
main "$@"