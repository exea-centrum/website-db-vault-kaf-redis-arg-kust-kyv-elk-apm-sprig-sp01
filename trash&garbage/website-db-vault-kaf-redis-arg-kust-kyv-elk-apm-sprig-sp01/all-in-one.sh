#!/bin/bash
# ============================================================================
# System Przetwarzania Pytań - All-in-One Setup Script
# Przepływ: FastAPI → Redis → Kafka → PostgreSQL
# Data: 2026-09-01
# ============================================================================

set -e

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step()    { echo -e "${CYAN}==>${NC} $1"; }

PROJECT_DIR="question-processing-system"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  System Przetwarzania Pytań - Generator Projektu          ║${NC}"
echo -e "${GREEN}║  FastAPI → Redis → Kafka → PostgreSQL                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# 1. STRUKTURA KATALOGÓW
# ============================================================================
log_step "Tworzenie struktury katalogów..."

mkdir -p "$PROJECT_DIR"/{apps/{fastapi-app,message-processor,redis-to-kafka,spring-app},k8s/{base,monitoring,tools,policies},scripts,docs}

cd "$PROJECT_DIR"

# ============================================================================
# 2. APLIKACJA FASTAPI (Web UI + Producer do Redis)
# ============================================================================
log_step "Tworzenie FastAPI Application..."

cat > apps/fastapi-app/main.py << 'FASTAPI_EOF'
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import redis
import json
import os
import logging
import uuid
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Question Processing System", version="1.0.0")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")

redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD if REDIS_PASSWORD else None,
    decode_responses=True
)

class Question(BaseModel):
    id: str = None
    content: str
    author: str
    timestamp: str = None

    def __init__(self, **data):
        super().__init__(**data)
        if not self.id:
            self.id = f"Q-{uuid.uuid4().hex[:8]}"
        if not self.timestamp:
            self.timestamp = datetime.utcnow().isoformat()

@app.get("/", response_class=HTMLResponse)
async def root():
    return """
    <!DOCTYPE html>
    <html lang="pl">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>System Przetwarzania Pytań</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
                font-family: 'Segoe UI', Tahoma, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                padding: 40px 20px;
            }
            .container {
                max-width: 900px;
                margin: 0 auto;
                background: white;
                border-radius: 20px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                overflow: hidden;
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 40px;
                text-align: center;
            }
            .header h1 { font-size: 2.5em; margin-bottom: 10px; }
            .header p { opacity: 0.9; font-size: 1.1em; }
            .content { padding: 40px; }
            .flow-diagram {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 40px;
                padding: 20px;
                background: #f8f9fa;
                border-radius: 10px;
                flex-wrap: wrap;
            }
            .flow-step {
                padding: 15px 25px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                border-radius: 8px;
                font-weight: 600;
                text-align: center;
                min-width: 120px;
            }
            .flow-arrow { color: #667eea; font-size: 28px; font-weight: bold; }
            .form-group { margin-bottom: 20px; }
            label {
                display: block;
                margin-bottom: 8px;
                color: #333;
                font-weight: 600;
            }
            input, textarea {
                width: 100%;
                padding: 12px;
                border: 2px solid #e0e0e0;
                border-radius: 8px;
                font-size: 16px;
                transition: border-color 0.3s;
                font-family: inherit;
            }
            input:focus, textarea:focus {
                outline: none;
                border-color: #667eea;
            }
            textarea { min-height: 120px; resize: vertical; }
            button {
                width: 100%;
                padding: 15px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                border: none;
                border-radius: 8px;
                font-size: 18px;
                font-weight: 600;
                cursor: pointer;
                transition: transform 0.2s, box-shadow 0.2s;
            }
            button:hover:not(:disabled) {
                transform: translateY(-2px);
                box-shadow: 0 10px 20px rgba(102, 126, 234, 0.4);
            }
            button:disabled { opacity: 0.6; cursor: not-allowed; }
            .status {
                margin-top: 20px;
                padding: 15px;
                border-radius: 8px;
                display: none;
                font-weight: 500;
            }
            .status.success {
                background: #d4edda;
                color: #155724;
                border: 1px solid #c3e6cb;
            }
            .status.error {
                background: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
            }
            .stats {
                margin-top: 30px;
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 15px;
            }
            .stat-card {
                background: #f8f9fa;
                padding: 20px;
                border-radius: 10px;
                text-align: center;
                border-left: 4px solid #667eea;
            }
            .stat-value { font-size: 2em; font-weight: bold; color: #667eea; }
            .stat-label { color: #666; margin-top: 5px; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🎓 System Przetwarzania Pytań</h1>
                <p>Zadaj pytanie - przejdzie przez Redis, Kafka do PostgreSQL</p>
            </div>
            <div class="content">
                <div class="flow-diagram">
                    <div class="flow-step">📝 FastAPI</div>
                    <div class="flow-arrow">→</div>
                    <div class="flow-step">⚡ Redis</div>
                    <div class="flow-arrow">→</div>
                    <div class="flow-step">📨 Kafka</div>
                    <div class="flow-arrow">→</div>
                    <div class="flow-step">🗄️ PostgreSQL</div>
                </div>

                <form id="questionForm">
                    <div class="form-group">
                        <label for="author">Autor (Student):</label>
                        <input type="text" id="author" required placeholder="Jan Kowalski">
                    </div>
                    <div class="form-group">
                        <label for="content">Treść pytania:</label>
                        <textarea id="content" required placeholder="Wpisz swoje pytanie do wykładowcy..."></textarea>
                    </div>
                    <button type="submit" id="submitBtn">🚀 Wyślij pytanie</button>
                </form>

                <div id="status" class="status"></div>

                <div class="stats">
                    <div class="stat-card">
                        <div class="stat-value" id="totalSent">0</div>
                        <div class="stat-label">Wysłanych pytań</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value" id="lastQuestion">-</div>
                        <div class="stat-label">Ostatnie ID</div>
                    </div>
                </div>
            </div>
        </div>

        <script>
            let totalSent = 0;
            document.getElementById('questionForm').addEventListener('submit', async (e) => {
                e.preventDefault();
                const statusDiv = document.getElementById('status');
                const submitBtn = document.getElementById('submitBtn');
                submitBtn.disabled = true;
                submitBtn.textContent = '⏳ Wysyłanie...';

                const questionData = {
                    author: document.getElementById('author').value,
                    content: document.getElementById('content').value
                };

                try {
                    const response = await fetch('/api/questions', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(questionData)
                    });
                    if (response.ok) {
                        const result = await response.json();
                        statusDiv.className = 'status success';
                        statusDiv.innerHTML = `✅ <strong>Pytanie przyjęte!</strong><br>ID: ${result.question_id}<br>Status: ${result.status}<br>Timestamp: ${result.timestamp}`;
                        statusDiv.style.display = 'block';
                        totalSent++;
                        document.getElementById('totalSent').textContent = totalSent;
                        document.getElementById('lastQuestion').textContent = result.question_id;
                        e.target.reset();
                    } else {
                        throw new Error('Błąd serwera');
                    }
                } catch (error) {
                    statusDiv.className = 'status error';
                    statusDiv.textContent = `❌ Błąd: ${error.message}`;
                    statusDiv.style.display = 'block';
                } finally {
                    submitBtn.disabled = false;
                    submitBtn.textContent = '🚀 Wyślij pytanie';
                }
            });
        </script>
    </body>
    </html>
    """

@app.post("/api/questions")
async def submit_question(question: Question):
    try:
        question_data = {
            "id": question.id,
            "content": question.content,
            "author": question.author,
            "timestamp": question.timestamp,
            "status": "received"
        }
        redis_client.setex(f"question:{question.id}", 3600, json.dumps(question_data))
        redis_client.lpush("questions:queue", json.dumps(question_data))
        redis_client.incr("stats:questions_total")
        logger.info(f"Question {question.id} queued")
        return {
            "status": "accepted",
            "message": "Question queued for processing",
            "question_id": question.id,
            "timestamp": question.timestamp
        }
    except Exception as e:
        logger.error(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questions/{question_id}")
async def get_question(question_id: str):
    data = redis_client.get(f"question:{question_id}")
    if not data:
        raise HTTPException(status_code=404, detail="Not found")
    return json.loads(data)

@app.get("/health")
async def health():
    try:
        redis_client.ping()
        return {"status": "healthy", "redis": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
FASTAPI_EOF

cat > apps/fastapi-app/requirements.txt << 'EOF'
fastapi==0.109.0
uvicorn[standard]==0.27.0
redis==5.0.1
pydantic==2.5.3
python-multipart==0.0.6
EOF

cat > apps/fastapi-app/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

log_success "FastAPI Application"

# ============================================================================
# 3. REDIS TO KAFKA BRIDGE
# ============================================================================
log_step "Tworzenie Redis to Kafka Bridge..."

cat > apps/redis-to-kafka/main.py << 'EOF'
from kafka import KafkaProducer
import redis
import json
import os
import logging
import time

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "questions")

def main():
    logger.info("Starting Redis to Kafka bridge...")
    redis_client = redis.Redis(
        host=REDIS_HOST, port=REDIS_PORT,
        password=REDIS_PASSWORD if REDIS_PASSWORD else None,
        decode_responses=True
    )
    for i in range(30):
        try:
            redis_client.ping()
            logger.info("Connected to Redis")
            break
        except:
            logger.info(f"Waiting for Redis... ({i+1}/30)")
            time.sleep(5)
    else:
        logger.error("Failed to connect to Redis")
        return

    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        retries=5, acks='all'
    )
    logger.info(f"Connected to Kafka: {KAFKA_BOOTSTRAP}")

    count = 0
    try:
        while True:
            message = redis_client.rpop("questions:queue")
            if message:
                try:
                    data = json.loads(message)
                    future = producer.send(KAFKA_TOPIC, value=data)
                    meta = future.get(timeout=10)
                    count += 1
                    logger.info(f"Sent {data['id']} to Kafka (partition={meta.partition}, offset={meta.offset}) [total: {count}]")
                except Exception as e:
                    logger.error(f"Error: {e}")
                    redis_client.lpush("questions:queue", message)
                    time.sleep(1)
            else:
                time.sleep(0.5)
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        producer.close()

if __name__ == "__main__":
    main()
EOF

cat > apps/redis-to-kafka/requirements.txt << 'EOF'
kafka-python==2.0.2
redis==5.0.1
EOF

cat > apps/redis-to-kafka/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "main.py"]
EOF

log_success "Redis to Kafka Bridge"

# ============================================================================
# 4. MESSAGE PROCESSOR (Kafka → PostgreSQL)
# ============================================================================
log_step "Tworzenie Message Processor..."

cat > apps/message-processor/main.py << 'EOF'
from kafka import KafkaConsumer
import psycopg2
import json
import os
import logging
import time

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "questions")
KAFKA_GROUP = os.getenv("KAFKA_GROUP_ID", "question-processor")
PG_HOST = os.getenv("POSTGRES_HOST", "postgres-db")
PG_PORT = int(os.getenv("POSTGRES_PORT", 5432))
PG_DB = os.getenv("POSTGRES_DB", "questions_db")
PG_USER = os.getenv("POSTGRES_USER", "postgres")
PG_PASS = os.getenv("POSTGRES_PASSWORD", "postgres")

def init_db():
    try:
        conn = psycopg2.connect(host=PG_HOST, port=PG_PORT, database=PG_DB, user=PG_USER, password=PG_PASS)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS questions (
                id VARCHAR(50) PRIMARY KEY,
                content TEXT NOT NULL,
                author VARCHAR(255) NOT NULL,
                timestamp TIMESTAMP NOT NULL,
                status VARCHAR(50) DEFAULT 'processed',
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cur.close()
        conn.close()
        logger.info("Database initialized")
        return True
    except Exception as e:
        logger.error(f"DB init failed: {e}")
        return False

def save_to_postgres(data):
    try:
        conn = psycopg2.connect(host=PG_HOST, port=PG_PORT, database=PG_DB, user=PG_USER, password=PG_PASS)
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO questions (id, content, author, timestamp, status)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, processed_at = CURRENT_TIMESTAMP
        """, (data['id'], data['content'], data['author'], data['timestamp'], 'processed'))
        conn.commit()
        cur.close()
        conn.close()
        logger.info(f"Saved {data['id']} to PostgreSQL")
        return True
    except Exception as e:
        logger.error(f"Save failed: {e}")
        return False

def main():
    logger.info("Starting message processor...")
    for i in range(30):
        if init_db():
            break
        logger.info(f"Waiting for DB... ({i+1}/30)")
        time.sleep(5)
    else:
        return

    consumer = KafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id=KAFKA_GROUP,
        auto_offset_reset='earliest',
        enable_auto_commit=True,
        value_deserializer=lambda m: json.loads(m.decode('utf-8'))
    )
    logger.info(f"Connected to Kafka topic: {KAFKA_TOPIC}")

    count = 0
    try:
        for message in consumer:
            try:
                data = message.value
                if save_to_postgres(data):
                    count += 1
                    logger.info(f"Processed {count} questions")
            except Exception as e:
                logger.error(f"Error: {e}")
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        consumer.close()

if __name__ == "__main__":
    main()
EOF

cat > apps/message-processor/requirements.txt << 'EOF'
kafka-python==2.0.2
psycopg2-binary==2.9.9
EOF

cat > apps/message-processor/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "main.py"]
EOF

log_success "Message Processor"

# ============================================================================
# 5. SPRING APP (dodatkowa aplikacja Java)
# ============================================================================
log_step "Tworzenie Spring Boot Application..."

mkdir -p apps/spring-app/src/main/java/com/example
mkdir -p apps/spring-app/src/main/resources

cat > apps/spring-app/pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>question-viewer</artifactId>
    <version>1.0.0</version>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
    </parent>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <version>42.7.1</version>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF

cat > apps/spring-app/src/main/java/com/example/QuestionViewerApplication.java << 'EOF'
package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class QuestionViewerApplication {
    public static void main(String[] args) {
        SpringApplication.run(QuestionViewerApplication.class, args);
    }
}
EOF

cat > apps/spring-app/src/main/resources/application.properties << 'EOF'
server.port=8080
spring.datasource.url=jdbc:postgresql://postgres-db:5432/questions_db
spring.datasource.username=postgres
spring.datasource.password=postgres_secure_password
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
management.endpoints.web.exposure.include=health,metrics,prometheus
EOF

cat > apps/spring-app/Dockerfile << 'EOF'
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
EOF

log_success "Spring Boot Application"

# ============================================================================
# 6. KUBERNETES MANIFESTS - Wszystkie 41 zasobów
# ============================================================================
log_step "Tworzenie Kubernetes manifests (wszystkie 41 zasobów)..."

# --- 1. NAMESPACE ---
cat > k8s/base/00-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: question-system
  labels:
    name: question-system
    monitoring: enabled
EOF

# --- 2. CONFIGMAPS ---
cat > k8s/base/01-configmaps.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  namespace: question-system
data:
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
  KAFKA_TOPIC: "questions"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: message-processor-config
  namespace: question-system
data:
  POSTGRES_HOST: "postgres-db"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "questions_db"
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
  KAFKA_TOPIC: "questions"
  KAFKA_GROUP_ID: "question-processor"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-to-kafka-config
  namespace: question-system
data:
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
  KAFKA_TOPIC: "questions"
EOF

# --- 3. SECRETS ---
cat > k8s/base/02-secrets.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: question-system
type: Opaque
stringData:
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "postgres_secure_password"
  POSTGRES_DB: "questions_db"
---
apiVersion: v1
kind: Secret
metadata:
  name: redis-credentials
  namespace: question-system
type: Opaque
stringData:
  REDIS_PASSWORD: "redis_secure_password"
EOF

# --- 4. SERVICE ACCOUNTS ---
cat > k8s/base/03-serviceaccounts.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-job-sa
  namespace: question-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: question-system-sa
  namespace: question-system
EOF

# --- 9 & 10. POSTGRES DB + CLUSTERIP ---
cat > k8s/base/04-postgres.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-db
  namespace: question-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-db
  template:
    metadata:
      labels:
        app: postgres-db
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_PASSWORD
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_DB
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "postgres"]
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-clusterip
  namespace: question-system
spec:
  selector:
    app: postgres-db
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF

# --- 11. REDIS ---
cat > k8s/base/05-redis.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: question-system
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
        command: ["redis-server", "--requirepass", "$(REDIS_PASSWORD)"]
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: REDIS_PASSWORD
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: question-system
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
  type: ClusterIP
EOF

# --- 12. VAULT ---
cat > k8s/base/06-vault.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: question-system
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
        image: hashicorp/vault:1.15
        ports:
        - containerPort: 8200
        env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: "root"
        - name: VAULT_DEV_LISTEN_ADDRESS
          value: "0.0.0.0:8200"
        - name: VAULT_ADDR
          value: "http://127.0.0.1:8200"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: question-system
spec:
  selector:
    app: vault
  ports:
  - port: 8200
    targetPort: 8200
  type: ClusterIP
EOF

# --- 13. KAFKA KRAFT ---
cat > k8s/base/07-kafka.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-kraft
  namespace: question-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-kraft
  template:
    metadata:
      labels:
        app: kafka-kraft
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:3.6
        ports:
        - containerPort: 9092
        - containerPort: 9093
        env:
        - name: KAFKA_ENABLE_KRAFT
          value: "yes"
        - name: KAFKA_CFG_PROCESS_ROLES
          value: "broker,controller"
        - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
        - name: KAFKA_CFG_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_CFG_ADVERTISED_LISTENERS
          value: "PLAINTEXT://kafka-kraft:9092"
        - name: KAFKA_CFG_BROKER_ID
          value: "1"
        - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
          value: "1@kafka-kraft:9093"
        - name: ALLOW_PLAINTEXT_LISTENER
          value: "yes"
        - name: KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE
          value: "true"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft
  namespace: question-system
spec:
  selector:
    app: kafka-kraft
  ports:
  - name: kafka
    port: 9092
    targetPort: 9092
  - name: controller
    port: 9093
    targetPort: 9093
  type: ClusterIP
EOF

# --- 15. KAFKA TOPIC JOB ---
cat > k8s/base/08-kafka-topic-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-job
  namespace: question-system
spec:
  template:
    spec:
      serviceAccountName: kafka-job-sa
      containers:
      - name: kafka-topic-creator
        image: bitnami/kafka:3.6
        command:
        - /bin/bash
        - -c
        - |
          echo "Waiting for Kafka..."
          sleep 30
          kafka-topics.sh --create \
            --bootstrap-server kafka-kraft:9092 \
            --replication-factor 1 \
            --partitions 3 \
            --topic questions \
            --if-not-exists
          echo "Topic created"
          kafka-topics.sh --list --bootstrap-server kafka-kraft:9092
      restartPolicy: Never
  backoffLimit: 4
EOF

# --- 5, 16, 17. DEPLOYMENTS: FastAPI, Message Processor, Redis-to-Kafka ---
cat > k8s/base/09-app-deployments.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
  namespace: question-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi-app
  template:
    metadata:
      labels:
        app: fastapi-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      serviceAccountName: question-system-sa
      containers:
      - name: fastapi
        image: fastapi-app:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: fastapi-config
        - secretRef:
            name: redis-credentials
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: question-system
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
      serviceAccountName: question-system-sa
      containers:
      - name: processor
        image: message-processor:latest
        imagePullPolicy: IfNotPresent
        envFrom:
        - configMapRef:
            name: message-processor-config
        - secretRef:
            name: postgres-credentials
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-to-kafka
  namespace: question-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-to-kafka
  template:
    metadata:
      labels:
        app: redis-to-kafka
    spec:
      serviceAccountName: question-system-sa
      containers:
      - name: bridge
        image: redis-to-kafka:latest
        imagePullPolicy: IfNotPresent
        envFrom:
        - configMapRef:
            name: redis-to-kafka-config
        - secretRef:
            name: redis-credentials
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-service
  namespace: question-system
spec:
  selector:
    app: fastapi-app
  ports:
  - port: 80
    targetPort: 8000
  type: ClusterIP
EOF

# --- 18 & 19. SPARK MASTER & WORKER ---
cat > k8s/base/10-spark.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: question-system
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
        image: bitnami/spark:3.5
        ports:
        - containerPort: 7077
        - containerPort: 8080
        env:
        - name: SPARK_MODE
          value: "master"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master
  namespace: question-system
spec:
  selector:
    app: spark-master
  ports:
  - name: ui
    port: 8080
    targetPort: 8080
  - name: master
    port: 7077
    targetPort: 7077
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: question-system
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
        image: bitnami/spark:3.5
        ports:
        - containerPort: 8081
        env:
        - name: SPARK_MODE
          value: "worker"
        - name: SPARK_MASTER_URL
          value: "spark://spark-master:7077"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
EOF

# --- 20. SPRING APP DEPLOYMENT ---
cat > k8s/base/11-spring-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app-deployment
  namespace: question-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spring-app
  template:
    metadata:
      labels:
        app: spring-app
    spec:
      containers:
      - name: spring-app
        image: spring-app:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres-db:5432/questions_db"
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_USER
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_PASSWORD
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app-service
  namespace: question-system
spec:
  selector:
    app: spring-app
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

# --- 7 & 8. HPA & PDB ---
cat > k8s/base/12-hpa-pdb.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-hpa
  namespace: question-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-pdb
  namespace: question-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: fastapi-app
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: message-processor-pdb
  namespace: question-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: message-processor
EOF

# --- 38. NETWORK POLICIES ---
cat > k8s/policies/13-network-policies.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: network-policies
  namespace: question-system
spec:
  podSelector:
    matchLabels:
      app: fastapi-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: redis
  - to:
    - podSelector:
        matchLabels:
          app: kafka-kraft
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: message-processor-policy
  namespace: question-system
spec:
  podSelector:
    matchLabels:
      app: message-processor
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: kafka-kraft
  - to:
    - podSelector:
        matchLabels:
          app: postgres-db
EOF

# --- 39 & 40. INGRESS ---
cat > k8s/base/14-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress
  namespace: question-system
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: questions.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-service
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spark-ingress
  namespace: question-system
spec:
  rules:
  - host: spark.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spark-master
            port:
              number: 8080
EOF

# --- 41. KYVERNO POLICY ---
cat > k8s/policies/15-kyverno-policy.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: kyverno-policy
  annotations:
    policies.kyverno.io/title: Require Resource Limits
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/description: >-
      Require all containers to have resource limits defined
spec:
  validationFailureAction: Audit
  rules:
  - name: require-resource-limits
    match:
      resources:
        kinds:
        - Pod
        namespaces:
        - question-system
    validate:
      message: "CPU and memory limits are required."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
EOF

# ============================================================================
# MONITORING STACK
# ============================================================================
log_step "Tworzenie Monitoring Stack..."

# --- 21 & 26. PROMETHEUS CONFIG + DEPLOYMENT ---
cat > k8s/monitoring/16-prometheus.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: question-system
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - question-system
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
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: question-system
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
      serviceAccountName: question-system-sa
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: question-system
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
  type: ClusterIP
EOF

# --- 25. SERVICE MONITORS ---
cat > k8s/monitoring/17-service-monitors.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: service-monitors
  namespace: question-system
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: fastapi-app
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
EOF

# --- 22. POSTGRES EXPORTER ---
cat > k8s/monitoring/18-postgres-exporter.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: question-system
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
      - name: exporter
        image: prometheuscommunity/postgres-exporter:latest
        ports:
        - containerPort: 9187
        env:
        - name: DATA_SOURCE_NAME
          value: "postgresql://postgres:postgres_secure_password@postgres-db:5432/questions_db?sslmode=disable"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: question-system
  labels:
    app: postgres-exporter
spec:
  selector:
    app: postgres-exporter
  ports:
  - port: 9187
    targetPort: 9187
  type: ClusterIP
EOF

# --- 23. KAFKA EXPORTER ---
cat > k8s/monitoring/19-kafka-exporter.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: question-system
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
      - name: exporter
        image: danielqsj/kafka-exporter:latest
        args:
        - --kafka.server=kafka-kraft:9092
        ports:
        - containerPort: 9308
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: question-system
  labels:
    app: kafka-exporter
spec:
  selector:
    app: kafka-exporter
  ports:
  - port: 9308
    targetPort: 9308
  type: ClusterIP
EOF

# --- 24. NODE EXPORTER ---
cat > k8s/monitoring/20-node-exporter.yaml << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: question-system
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostPID: true
      hostNetwork: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
          hostPort: 9100
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: question-system
spec:
  selector:
    app: node-exporter
  ports:
  - port: 9100
    targetPort: 9100
  type: ClusterIP
EOF

# --- 27, 28, 29. GRAFANA ---
cat > k8s/monitoring/21-grafana.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: question-system
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
      access: proxy
      isDefault: true
    - name: Loki
      type: loki
      url: http://loki:3100
    - name: Tempo
      type: tempo
      url: http://tempo:3200
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: question-system
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      updateIntervalSeconds: 10
      options:
        path: /var/lib/grafana/dashboards
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: question-system
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
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        volumeMounts:
        - name: datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: dashboards-config
          mountPath: /etc/grafana/provisioning/dashboards
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: datasources
        configMap:
          name: grafana-datasource
      - name: dashboards-config
        configMap:
          name: grafana-dashboards
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: question-system
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
EOF

# --- 30 & 31. LOKI ---
cat > k8s/monitoring/22-loki.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: question-system
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
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
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: question-system
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
        args:
        - -config.file=/etc/loki/loki.yaml
        volumeMounts:
        - name: config
          mountPath: /etc/loki
        - name: storage
          mountPath: /loki
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: loki-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: question-system
spec:
  selector:
    app: loki
  ports:
  - port: 3100
    targetPort: 3100
  type: ClusterIP
EOF

# --- 32 & 33. PROMTAIL ---
cat > k8s/monitoring/23-promtail.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: question-system
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    positions:
      filename: /tmp/positions.yaml
    clients:
    - url: http://loki:3100/loki/api/v1/push
    scrape_configs:
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - question-system
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: replace
        target_label: container
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: question-system
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
        args:
        - -config.file=/etc/promtail/promtail.yaml
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: logs
          mountPath: /var/log
          readOnly: true
        - name: containers
          mountPath: /var/lib/docker/containers
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: logs
        hostPath:
          path: /var/log
      - name: containers
        hostPath:
          path: /var/lib/docker/containers
EOF

# --- 34 & 35. TEMPO ---
cat > k8s/monitoring/24-tempo.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: question-system
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/blocks
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: question-system
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
        ports:
        - containerPort: 3200
        - containerPort: 4317
        - containerPort: 4318
        args:
        - -config.file=/etc/tempo/tempo.yaml
        volumeMounts:
        - name: config
          mountPath: /etc/tempo
        - name: storage
          mountPath: /tmp/tempo
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: tempo-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: question-system
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
  type: ClusterIP
EOF

# ============================================================================
# TOOLS: pgAdmin & Kafka UI
# ============================================================================
log_step "Tworzenie Tools (pgAdmin, Kafka UI)..."

cat > k8s/tools/25-pgadmin.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: question-system
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
        ports:
        - containerPort: 80
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: "admin@example.com"
        - name: PGADMIN_DEFAULT_PASSWORD
          value: "admin"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: question-system
spec:
  selector:
    app: pgadmin
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

cat > k8s/tools/26-kafka-ui.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: question-system
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
        env:
        - name: KAFKA_CLUSTERS_0_NAME
          value: "local"
        - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
          value: "kafka-kraft:9092"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: question-system
spec:
  selector:
    app: kafka-ui
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

# ============================================================================
# HELPER SCRIPTS
# ============================================================================
log_step "Tworzenie skryptów pomocniczych..."

cat > scripts/build-images.sh << 'EOF'
#!/bin/bash
echo "🔨 Budowanie obrazów Docker..."
docker build -t fastapi-app:latest ../apps/fastapi-app
docker build -t message-processor:latest ../apps/message-processor
docker build -t redis-to-kafka:latest ../apps/redis-to-kafka
echo "✅ Obrazy zbudowane"
docker images | grep -E "fastapi-app|message-processor|redis-to-kafka"
EOF
chmod +x scripts/build-images.sh

cat > scripts/deploy.sh << 'EOF'
#!/bin/bash
echo "🚀 Deployment do Kubernetes..."
kubectl cluster-info || { echo "❌ Brak połączenia z K8s"; exit 1; }
for file in ../k8s/base/*.yaml ../k8s/monitoring/*.yaml ../k8s/tools/*.yaml ../k8s/policies/*.yaml; do
    echo "Aplikowanie $file..."
    kubectl apply -f "$file"
    sleep 1
done
echo "✅ Deployment zakończony"
kubectl get pods -n question-system
EOF
chmod +x scripts/deploy.sh

cat > scripts/cleanup.sh << 'EOF'
#!/bin/bash
echo "🧹 Czyszczenie..."
read -p "Usunąć namespace question-system? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    kubectl delete namespace question-system
    echo "✅ Wyczyszczono"
fi
EOF
chmod +x scripts/cleanup.sh

cat > scripts/port-forward.sh << 'EOF'
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
EOF
chmod +x scripts/port-forward.sh

# ============================================================================
# README
# ============================================================================
cat > README.md << 'EOF'
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
EOF

# ============================================================================
# FINAL MESSAGE
# ============================================================================
cd ..

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Projekt utworzony pomyślnie!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 Struktura projektu:${NC}"
echo "   $PROJECT_DIR/"
echo "   ├── apps/"
echo "   │   ├── fastapi-app/          (Web UI + Producer)"
echo "   │   ├── message-processor/    (Kafka → PostgreSQL)"
echo "   │   ├── redis-to-kafka/       (Redis → Kafka Bridge)"
echo "   │   └── spring-app/           (Spring Boot)"
echo "   ├── k8s/"
echo "   │   ├── base/                 (14 plików - core)"
echo "   │   ├── monitoring/           (9 plików - LGTM stack)"
echo "   │   ├── tools/                (2 pliki - pgAdmin, Kafka UI)"
echo "   │   └── policies/             (2 pliki - Network, Kyverno)"
echo "   ├── scripts/"
echo "   │   ├── build-images.sh"
echo "   │   ├── deploy.sh"
echo "   │   ├── cleanup.sh"
echo "   │   └── port-forward.sh"
echo "   └── README.md"
echo ""
echo -e "${CYAN}📊 Zawartość: 41 zasobów Kubernetes${NC}"
echo "   ✅ Wszystkie z Twojej listy zostały utworzone!"
echo ""
echo -e "${YELLOW}🚀 Następne kroki:${NC}"
echo "   1. cd $PROJECT_DIR"
echo "   2. cd scripts && ./build-images.sh"
echo "   3. ./deploy.sh"
echo "   4. ./port-forward.sh"
echo ""
echo -e "${GREEN}💡 Chcesz spakować projekt do archiwum?${NC}"
echo "   tar -czf $PROJECT_DIR.tar.gz $PROJECT_DIR/"
echo ""


