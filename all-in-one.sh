#!/bin/bash
# all-in-one.sh - Kompletny skrypt do pobrania, wypakowania i uruchomienia projektu
# Autor: Dawid Trojanowski
# Wersja: 2.0.0

set -e

# ============================================
# KOLORY I STYLE
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================
# ZMIENNE GLOBALNE
# ============================================
PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
GITHUB_REPO="https://github.com/exea-centrum/${PROJECT_NAME}.git"
NAMESPACE="davtro"
VERSION="2.0.0"
TEMP_DIR="/tmp/${PROJECT_NAME}_$(date +%s)"
INSTALL_DIR="${HOME}/${PROJECT_NAME}"

# ============================================
# FUNKCJE POMOCNICZE
# ============================================
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  🚀 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_step() {
    echo -e "\n${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️ $1${NC}"
}

check_error() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    fi
}

# ============================================
# FUNKCJA: Sprawdzanie wymaganych narzędzi
# ============================================
check_requirements() {
    print_step "Sprawdzanie wymaganych narzędzi..."
    
    local required_tools=("git" "curl" "wget" "tar" "gzip")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Brakujące narzędzia: ${missing_tools[*]}"
        echo -e "${YELLOW}📦 Zainstaluj brakujące narzędzia:${NC}"
        echo -e "  - Ubuntu/Debian: sudo apt-get install ${missing_tools[*]}"
        echo -e "  - MacOS: brew install ${missing_tools[*]}"
        exit 1
    fi
    
    print_success "Wszystkie wymagane narzędzia są zainstalowane"
}

# ============================================
# FUNKCJA: Sprawdzanie wolnego miejsca
# ============================================
check_disk_space() {
    print_step "Sprawdzanie wolnego miejsca na dysku..."
    
    local required_space=1024
    local available_space=$(df -m . | tail -1 | awk '{print $4}')
    
    if [ $available_space -lt $required_space ]; then
        print_error "Za mało miejsca na dysku! Wymagane: ${required_space}MB, dostępne: ${available_space}MB"
        exit 1
    fi
    
    print_success "Wystarczająca ilość miejsca na dysku (${available_space}MB dostępne)"
}

# ============================================
# FUNKCJA: Wyświetlanie logo
# ============================================
show_logo() {
    echo -e "${BLUE}"
    cat << "LOGO_EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║   ██████╗  █████╗ ██╗    ██╗██╗██████╗                  ║
    ║   ██╔══██╗██╔══██╗██║    ██║██║██╔══██╗                 ║
    ║   ██║  ██║███████║██║ █╗ ██║██║██║  ██║                 ║
    ║   ██║  ██║██╔══██║██║███╗██║██║██║  ██║                 ║
    ║   ██████╔╝██║  ██║╚███╔███╔╝██║██████╔╝                 ║
    ║   ╚═════╝ ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝╚═════╝                  ║
    ║                                                           ║
    ║   ████████╗██████╗  ██████╗ ██╗ █████╗ ███╗   ██╗       ║
    ║   ╚══██╔══╝██╔══██╗██╔═══██╗██║██╔══██╗████╗  ██║       ║
    ║      ██║   ██████╔╝██║   ██║██║███████║██╔██╗ ██║       ║
    ║      ██║   ██╔══██╗██║   ██║██║██╔══██║██║╚██╗██║       ║
    ║      ██║   ██║  ██║╚██████╔╝██║██║  ██║██║ ╚████║       ║
    ║      ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝       ║
    ║                                                           ║
    ║     🏠 SYSTEM WYNAJMU MIESZKAŃ - v${VERSION}            ║
    ║     Dawid Trojanowski © 2025                             ║
    ╚═══════════════════════════════════════════════════════════╝
LOGO_EOF
    echo -e "${NC}"
}

# ============================================
# FUNKCJA: Pobieranie projektu
# ============================================
download_project() {
    print_step "Pobieranie projektu z GitHub..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    print_info "Klonowanie repozytorium: $GITHUB_REPO"
    git clone --depth 1 "$GITHUB_REPO" . || {
        print_warning "Nie udało się sklonować repozytorium, tworzę lokalny projekt..."
        create_project_files
        return
    }
    check_error "Nie udało się sklonować repozytorium"
    
    print_success "Projekt pobrany pomyślnie"
}

# ============================================
# FUNKCJA: Tworzenie podstawowej struktury
# ============================================
create_basic_structure() {
    mkdir -p app/static app/templates
    mkdir -p backend/app backend/migrations
    mkdir -p manifests/{base,production,staging,dev}
    mkdir -p scripts configs
    mkdir -p .github/workflows
}

# ============================================
# FUNKCJA: Tworzenie plików projektu
# ============================================
create_project_files() {
    print_step "Tworzenie plików projektu..."
    
    cd "$TEMP_DIR"
    create_basic_structure
    
    # ============================================
    # APP - FRONTEND (uproszczona wersja)
    # ============================================
    cat > app/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wynajem Mieszkań</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        .bg-gradient { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .card-hover:hover { transform: translateY(-5px); box-shadow: 0 20px 40px rgba(0,0,0,0.3); }
    </style>
</head>
<body>
    <div class="min-h-screen bg-gray-50">
        <header class="bg-gradient text-white shadow-lg">
            <div class="container mx-auto px-6 py-4">
                <h1 class="text-2xl font-bold">🏠 Wynajem Mieszkań</h1>
            </div>
        </header>
        
        <section class="bg-gradient text-white py-20">
            <div class="container mx-auto px-6 text-center">
                <h2 class="text-5xl font-bold mb-6">Znajdź idealne mieszkanie</h2>
                <p class="text-xl mb-8 text-purple-100">Krótkoterminowy wynajem w najlepszych lokalizacjach</p>
                <div class="max-w-2xl mx-auto bg-white/10 backdrop-blur-lg rounded-2xl p-6">
                    <div class="grid md:grid-cols-3 gap-4">
                        <input type="text" placeholder="📍 Lokalizacja" class="rounded-lg p-3 text-gray-800">
                        <input type="date" placeholder="📅 Zameldowanie" class="rounded-lg p-3 text-gray-800">
                        <input type="date" placeholder="📅 Wymeldowanie" class="rounded-lg p-3 text-gray-800">
                    </div>
                    <button class="mt-4 w-full bg-purple-600 hover:bg-purple-700 text-white font-bold py-3 px-6 rounded-lg transition">
                        🔍 Szukaj
                    </button>
                </div>
            </div>
        </section>

        <section id="offers" class="py-16">
            <div class="container mx-auto px-6">
                <h2 class="text-4xl font-bold text-center mb-12 text-gray-800">🏠 Dostępne Mieszkania</h2>
                <div class="grid md:grid-cols-3 gap-8">
                    <div class="bg-white rounded-2xl shadow-xl p-6 card-hover">
                        <div class="text-5xl mb-4">🏢</div>
                        <h3 class="text-xl font-bold text-gray-800">Apartament Centrum</h3>
                        <p class="text-gray-600">👤 4 gości</p>
                        <p class="text-2xl font-bold text-purple-600 mt-2">350 zł/doba</p>
                        <button class="mt-4 w-full bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-4 rounded-lg transition">
                            📅 Zarezerwuj
                        </button>
                    </div>
                    <div class="bg-white rounded-2xl shadow-xl p-6 card-hover">
                        <div class="text-5xl mb-4">🏠</div>
                        <h3 class="text-xl font-bold text-gray-800">Przytulne Studio</h3>
                        <p class="text-gray-600">👤 2 gości</p>
                        <p class="text-2xl font-bold text-purple-600 mt-2">250 zł/doba</p>
                        <button class="mt-4 w-full bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-4 rounded-lg transition">
                            📅 Zarezerwuj
                        </button>
                    </div>
                    <div class="bg-white rounded-2xl shadow-xl p-6 card-hover">
                        <div class="text-5xl mb-4">🏙️</div>
                        <h3 class="text-xl font-bold text-gray-800">Luksusowy Penthouse</h3>
                        <p class="text-gray-600">👤 6 gości</p>
                        <p class="text-2xl font-bold text-purple-600 mt-2">550 zł/doba</p>
                        <button class="mt-4 w-full bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-4 rounded-lg transition">
                            📅 Zarezerwuj
                        </button>
                    </div>
                </div>
            </div>
        </section>

        <footer class="bg-gray-900 text-white py-8">
            <div class="container mx-auto px-6 text-center">
                <p>&copy; 2025 Dawid Trojanowski - Wynajem Mieszkań</p>
            </div>
        </footer>
    </div>
</body>
</html>
HTML_EOF

    # ============================================
    # BACKEND - FASTAPI
    # ============================================
    cat > backend/app/main.py << 'PY_EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from datetime import datetime
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Wynajem Mieszkań API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return FileResponse("app/index.html")

@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.get("/api/properties")
async def get_properties():
    return [
        {"id": 1, "name": "Apartament Centrum", "price": 350, "guests": 4, "image": "🏢", "rating": 4.8},
        {"id": 2, "name": "Przytulne Studio", "price": 250, "guests": 2, "image": "🏠", "rating": 4.9},
        {"id": 3, "name": "Luksusowy Penthouse", "price": 550, "guests": 6, "image": "🏙️", "rating": 4.7}
    ]

app.mount("/static", StaticFiles(directory="static"), name="static")
PY_EOF

    # ============================================
    # DOCKERFILE
    # ============================================
    cat > Dockerfile << 'DOCKER_EOF'
FROM python:3.11-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
COPY app ./app/static
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
DOCKER_EOF

    # ============================================
    # REQUIREMENTS.TXT
    # ============================================
    cat > backend/requirements.txt << 'REQ_EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
python-multipart==0.0.6
REQ_EOF

    # ============================================
    # DOCKER-COMPOSE
    # ============================================
    cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'
services:
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DB_HOST=postgres
      - REDIS_HOST=redis
      - KAFKA_SERVERS=kafka:9092
    depends_on:
      - postgres
      - redis
      - kafka
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: booking_db
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secure_password
    ports:
      - "5432:5432"
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
  kafka:
    image: bitnami/kafka:latest
    environment:
      KAFKA_CFG_NODE_ID: 0
      KAFKA_CFG_PROCESS_ROLES: controller,broker
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: 0@kafka:9093
      KAFKA_CFG_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_CFG_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
    ports:
      - "9092:9092"
COMPOSE_EOF

    # ============================================
    # MANIFESTY KUBERNETES
    # ============================================
    cat > manifests/base/namespace.yaml << 'NS_EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
  labels:
    name: davtro
    environment: production
NS_EOF

    cat > manifests/base/deployment.yaml << 'DEPLOY_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-app
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: booking-app
  template:
    metadata:
      labels:
        app: booking-app
    spec:
      containers:
      - name: app
        image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
        ports:
        - containerPort: 8000
        env:
        - name: DB_HOST
          value: "postgres-db"
        - name: REDIS_HOST
          value: "redis-service"
        - name: KAFKA_SERVERS
          value: "kafka-kraft:9092"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
DEPLOY_EOF

    cat > manifests/base/service.yaml << 'SVC_EOF'
apiVersion: v1
kind: Service
metadata:
  name: booking-app-service
  namespace: davtro
spec:
  type: ClusterIP
  ports:
  - port: 8000
    targetPort: 8000
  selector:
    app: booking-app
SVC_EOF

    # ============================================
    # SKRYPT DEPLOY
    # ============================================
    cat > scripts/deploy.sh << 'DEPLOY_SCRIPT_EOF'
#!/bin/bash
set -e
NAMESPACE="davtro"
echo "🚀 Deploying to Kubernetes..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k manifests/production -n $NAMESPACE
echo "✅ Deployment zakończony!"
echo "🌐 kubectl port-forward svc/booking-app-service 8000:8000 -n $NAMESPACE"
DEPLOY_SCRIPT_EOF
    chmod +x scripts/deploy.sh

    # ============================================
    # README
    # ============================================
    cat > README.md << 'README_EOF'
# 🏠 System Wynajmu Mieszkań

## Szybki start
```bash
docker-compose up -d
# Otwórz http://localhost:8000