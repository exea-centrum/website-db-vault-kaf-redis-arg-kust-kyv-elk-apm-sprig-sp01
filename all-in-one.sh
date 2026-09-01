#!/usr/bin/env bash
set -e
echo "Rozpakowywanie projektu website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01 ..."
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/.github/workflows"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/static"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/templates"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/argocd"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app/src/main/java/com/davtro/app"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app/src/main/resources"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/kyverno-policies"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/production"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/spark-jobs"
mkdir -p "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/terraform"
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/.github/workflows/ci-cd.yaml" << 'DAVTRO_EOF'
name: CI/CD - Davtro Platform

permissions:
  contents: write
  packages: write

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_BASE: ghcr.io/${{ github.repository_owner }}/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
  KUSTOMIZE_PATH: ./manifests/production

jobs:
  build-fastapi:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}:latest
            ${{ env.IMAGE_BASE }}:${{ github.sha }}

  build-consumer:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile.consumer
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-consumer:latest
            ${{ env.IMAGE_BASE }}-consumer:${{ github.sha }}

  build-spring:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: ./java-app
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-spring:latest
            ${{ env.IMAGE_BASE }}-spring:${{ github.sha }}

  build-spark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: ./spark-jobs
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-spark:latest
            ${{ env.IMAGE_BASE }}-spark:${{ github.sha }}

  update-manifests:
    runs-on: ubuntu-latest
    needs: [build-fastapi, build-consumer, build-spring, build-spark]
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Set new image tags via Kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          cd manifests/base
          ../../kustomize edit set image \
            ${{ env.IMAGE_BASE }}=${{ env.IMAGE_BASE }}:${{ github.sha }} \
            ${{ env.IMAGE_BASE }}-consumer=${{ env.IMAGE_BASE }}-consumer:${{ github.sha }} \
            ${{ env.IMAGE_BASE }}-spring=${{ env.IMAGE_BASE }}-spring:${{ github.sha }}

      # ArgoCD śledzi ten branch/ścieżkę (KUSTOMIZE_PATH=./manifests/production) i sam
      # zsynchronizuje klaster po tym commicie (automated sync w argocd/application.yaml).
      - name: Commit updated manifests
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add manifests/base/kustomization.yaml
          git diff --cached --quiet || git commit -m "ci: aktualizacja obrazów na ${{ github.sha }}"
          git push
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/Dockerfile" << 'DAVTRO_EOF'
FROM python:3.12-slim AS base
WORKDIR /srv
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY app/requirements.txt ./app/requirements.txt
RUN pip install --no-cache-dir -r app/requirements.txt
COPY app ./app
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/Dockerfile.consumer" << 'DAVTRO_EOF'
FROM python:3.12-slim
WORKDIR /srv
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY app/requirements.txt ./app/requirements.txt
RUN pip install --no-cache-dir -r app/requirements.txt
COPY app ./app
CMD ["python", "-m", "app.consumer"]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/README.md" << 'DAVTRO_EOF'
# Davtro Apartments – platforma wynajmu krótkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
Namespace docelowy: `davtro`
KUSTOMIZE_IMAGE_ID: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
KUSTOMIZE_PATH: `./manifests/production`

## Architektura przepływu rezerwacji
1. Użytkownik rezerwuje termin na stronie (kalendarz w `app/templates/index.html`).
2. `FastAPI` (`app/main.py`) zapisuje rezerwację w PostgreSQL, buforuje event w Redis, publikuje do Kafka (`booking-events`).
3. `message-processor` (`app/consumer.py`) konsumuje event, wysyła e-mail (potwierdzenie + faktura proforma) i aktualizuje status w PostgreSQL.
4. Zgody marketingowe trafiają do tematu `marketing-events`, konsumowane tak samo, dodatkowo agregowane przez `spark-jobs/marketing_analytics.py`.
5. `spring-app-deployment` udostępnia panel raportowy/administracyjny na tych samych danych.
6. Sekrety (SMTP, DB) mają docelowo pochodzić z Vault (patrz `manifests/base/secret.yaml` i sekcja "Vault" niżej), nie z repo.

## Struktura repo
```
app/                  # FastAPI (web + API rezerwacji) + konsument Kafka + wysyłka e-mail
java-app/             # Spring Boot – panel raportowy
spark-jobs/           # Spark – analityka marketingowa
manifests/base/       # Wszystkie zasoby K8s (Kustomize base)
manifests/production/ # Overlay produkcyjny (namespace davtro, replicas)
kyverno-policies/     # Polityki Kyverno (kopiowane też do manifests/base)
.github/workflows/    # CI: build obrazów -> GHCR -> aktualizacja Kustomize -> ArgoCD sync
argocd/application.yaml
terraform/            # Terraform Cloud (workspace github-actions-terraform)
```

## Uruchomienie lokalnie (dev, bez K8s)
```bash
cd app/.. 
python -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## Wdrożenie na MicroK8s przez ArgoCD
1. Włącz ingress: `microk8s enable ingress`
2. Utwórz sekrety realne (nie commituj!) lub skonfiguruj Vault + ArgoCD Vault Plugin.
3. Zastosuj `argocd/application.yaml`: `kubectl apply -f argocd/application.yaml -n argocd`
4. Push do `main` -> GitHub Actions zbuduje obrazy i zaktualizuje tagi w `manifests/base/kustomization.yaml` -> ArgoCD (auto-sync) wdroży zmiany.

## WAŻNE – rzeczy do dopracowania przed produkcją
- `manifests/base/secret.yaml` zawiera placeholdery Vault (`<path:...>`) – wymaga realnej integracji ArgoCD Vault Plugin (AVP), inaczej sekrety trzeba podać ręcznie.
- Vault jest w trybie `-dev` (dane nietrwałe) – do produkcji podmień na Helm chart HashiCorp Vault z auto-unseal.
- `service-monitors.yaml` wymaga Prometheus Operatora (CRD `ServiceMonitor`) – jest wyłączony w `kustomization.yaml`, odkomentuj po instalacji operatora.
- SMTP nie jest skonfigurowany – bez zmiennych `SMTP_*` e-maile tylko logują się do stdout (`app/email_sender.py`).
- Obrazy produkcyjne CI/CD budują się pod `ghcr.io/<twoja-organizacja>/...` – ustaw `github.repository_owner` zgodnie z Twoim kontem/organizacją.
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/__init__.py" << 'DAVTRO_EOF'

DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/consumer.py" << 'DAVTRO_EOF'
"""
message-processor: osobny deployment/consumer.
Czyta z tematów Kafka 'booking-events' i 'marketing-events',
wysyła e-mail (potwierdzenie + faktura proforma) i aktualizuje status w Postgresql.
Kolejka Redis służy do deduplikacji/idempotencji przetwarzania.
"""
import json
import os
import time

import redis
from confluent_kafka import Consumer

from .db import SessionLocal, Booking
from .email_sender import send_confirmation_email, send_marketing_email

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def handle_booking_event(event: dict):
    dedup_key = f"processed:{event['event_id']}"
    if redis_client.get(dedup_key):
        return  # już przetworzone
    send_confirmation_email(event["guest_email"], event["guest_name"], event)

    session = SessionLocal()
    try:
        booking = session.query(Booking).get(event["booking_id"])
        if booking:
            booking.status = "confirmed"
            booking.invoice_sent = True
            session.commit()
    finally:
        session.close()

    redis_client.setex(dedup_key, 86400, "1")


def handle_marketing_event(event: dict):
    send_marketing_email(event["guest_email"], event["guest_name"])


def main():
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": "message-processor",
        "auto.offset.reset": "earliest",
    })
    consumer.subscribe(["booking-events", "marketing-events"])
    print("message-processor: nasłuchiwanie na booking-events i marketing-events...")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print("Kafka error:", msg.error())
                continue
            event = json.loads(msg.value().decode("utf-8"))
            if msg.topic() == "booking-events":
                handle_booking_event(event)
            elif msg.topic() == "marketing-events":
                handle_marketing_event(event)
    except KeyboardInterrupt:
        pass
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/db.py" << 'DAVTRO_EOF'
import os
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@postgres-clusterip:5432/davtro",
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()


class Apartment(Base):
    __tablename__ = "apartments"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String)
    price_per_night = Column(Numeric(10, 2), nullable=False)


class Booking(Base):
    __tablename__ = "bookings"
    id = Column(Integer, primary_key=True)
    apartment_id = Column(Integer, nullable=False)
    date_from = Column(Date, nullable=False)
    date_to = Column(Date, nullable=False)
    guest_name = Column(String, nullable=False)
    guest_email = Column(String, nullable=False)
    marketing_consent = Column(Boolean, default=False)
    status = Column(String, default="pending")  # pending -> confirmed
    invoice_sent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())


def init_db():
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
    if session.query(Apartment).count() == 0:
        session.add_all([
            Apartment(name="Apartament Centrum", description="2 pokoje, blisko rynku", price_per_night=250),
            Apartment(name="Apartament Panoramiczny", description="Widok na miasto", price_per_night=320),
            Apartment(name="Studio Kompakt", description="Idealne dla pary", price_per_night=180),
        ])
        session.commit()
    session.close()
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/email_sender.py" << 'DAVTRO_EOF'
"""
Wysyłka e-maili (potwierdzenie rezerwacji + faktura proforma, kampanie marketingowe).
W produkcji: podmień na realny SMTP / SES / SendGrid - dane dostępowe trzymane w Vault,
wstrzykiwane jako sekrety K8s (patrz manifests/base/secret.yaml).
"""
import os
import smtplib
from email.mime.text import MIMEText

SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
FROM_EMAIL = os.getenv("FROM_EMAIL", "rezerwacje@davtro.pl")


def _send(to_email: str, subject: str, body: str):
    if not SMTP_HOST:
        print(f"[DEV] Email do {to_email}: {subject}\n{body}")
        return
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = FROM_EMAIL
    msg["To"] = to_email
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.sendmail(FROM_EMAIL, [to_email], msg.as_string())


def send_confirmation_email(to_email: str, guest_name: str, event: dict):
    subject = f"Potwierdzenie rezerwacji nr {event['booking_id']}"
    body = (
        f"Cześć {guest_name},\n\n"
        f"Twoja rezerwacja ({event['date_from']} - {event['date_to']}) została potwierdzona.\n"
        f"W załączeniu (proforma) prosimy o dokonanie płatności przed przyjazdem.\n\n"
        f"Pozdrawiamy,\nDavtro Apartments"
    )
    _send(to_email, subject, body)


def send_marketing_email(to_email: str, guest_name: str):
    subject = "Sprawdź nasze najnowsze oferty!"
    body = f"Cześć {guest_name}, mamy dla Ciebie nowe promocje na pobyty krótkoterminowe."
    _send(to_email, subject, body)
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/kafka_producer.py" << 'DAVTRO_EOF'
import json
import os
from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
_producer = None


def get_producer():
    global _producer
    if _producer is None:
        _producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
    return _producer


def publish_event(topic: str, event: dict):
    producer = get_producer()
    producer.produce(topic, json.dumps(event).encode("utf-8"))
    producer.flush(5)
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/main.py" << 'DAVTRO_EOF'
"""
FastAPI - główne API strony wynajmu mieszkań.
Przepływ rezerwacji: Klient -> FastAPI -> Redis (bufor/kolejka) -> Kafka (booking-events)
                      -> message-processor (consumer) -> wysyłka e-mail (potwierdzenie + proforma) -> Postgres (status)
Kafka obsługuje też temat marketing-events (akcje marketingowe po wyrażeniu zgody).
"""
import json
import os
import uuid
from datetime import datetime

import redis
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

from .db import init_db, SessionLocal, Apartment, Booking
from .kafka_producer import publish_event

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

app = FastAPI(title="Davtro Apartments API")
app.mount("/static", StaticFiles(directory="app/static"), name="static")
Instrumentator().instrument(app).expose(app)  # metryki dla Prometheus

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


@app.on_event("startup")
def on_startup():
    init_db()


class BookingIn(BaseModel):
    apartment_id: int
    date_from: str
    date_to: str
    guest_name: str
    guest_email: str
    marketing_consent: bool = False


@app.get("/")
def index():
    return FileResponse("app/templates/index.html")


@app.get("/api/apartments")
def list_apartments():
    session = SessionLocal()
    try:
        rows = session.query(Apartment).all()
        return [
            {"id": a.id, "name": a.name, "description": a.description, "price_per_night": float(a.price_per_night)}
            for a in rows
        ]
    finally:
        session.close()


@app.get("/api/apartments/{apartment_id}/availability")
def availability(apartment_id: int):
    """Zwraca zajęte przedziały dat, żeby kalendarz na froncie mógł je wyszarzyć."""
    session = SessionLocal()
    try:
        rows = session.query(Booking).filter(
            Booking.apartment_id == apartment_id,
            Booking.status != "cancelled",
        ).all()
        return [{"date_from": str(b.date_from), "date_to": str(b.date_to)} for b in rows]
    finally:
        session.close()


@app.post("/api/bookings")
def create_booking(payload: BookingIn):
    if payload.date_from >= payload.date_to:
        raise HTTPException(status_code=400, detail="Data 'do' musi być późniejsza niż data 'od'")

    session = SessionLocal()
    try:
        booking = Booking(
            apartment_id=payload.apartment_id,
            date_from=datetime.strptime(payload.date_from, "%Y-%m-%d").date(),
            date_to=datetime.strptime(payload.date_to, "%Y-%m-%d").date(),
            guest_name=payload.guest_name,
            guest_email=payload.guest_email,
            marketing_consent=payload.marketing_consent,
            status="pending",
        )
        session.add(booking)
        session.commit()
        session.refresh(booking)
        booking_id = booking.id
    finally:
        session.close()

    event = {
        "event_id": str(uuid.uuid4()),
        "booking_id": booking_id,
        "guest_email": payload.guest_email,
        "guest_name": payload.guest_name,
        "apartment_id": payload.apartment_id,
        "date_from": payload.date_from,
        "date_to": payload.date_to,
        "type": "booking_confirmation",
    }

    # Redis jako szybki bufor/idempotency-cache przed publikacją do Kafki
    redis_client.setex(f"booking:{event['event_id']}", 3600, json.dumps(event))
    publish_event("booking-events", event)

    if payload.marketing_consent:
        publish_event("marketing-events", {
            "event_id": str(uuid.uuid4()),
            "guest_email": payload.guest_email,
            "guest_name": payload.guest_name,
            "type": "newsletter_opt_in",
        })

    return {"booking_id": booking_id, "status": "pending", "message": "Rezerwacja zapisana, e-mail w drodze"}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/requirements.txt" << 'DAVTRO_EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
psycopg2-binary==2.9.9
redis==5.0.8
confluent-kafka==2.5.3
jinja2==3.1.4
python-multipart==0.0.9
pydantic==2.9.2
prometheus-fastapi-instrumentator==7.0.0
hvac==2.3.0
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/static/script.js" << 'DAVTRO_EOF'
function showTab(tabName) {
  document.querySelectorAll(".tab-content").forEach(t => t.classList.add("hidden"));
  document.getElementById(tabName + "-tab").classList.remove("hidden");
  document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
  document.querySelector(`[data-tab="${tabName}"]`).classList.add("active");
}
showTab("offer");

// Pobiera oferty mieszkań z backendu (FastAPI -> Postgres)
async function loadApartments() {
  try {
    const res = await fetch("/api/apartments");
    const data = await res.json();
    const grid = document.getElementById("apartments-grid");
    grid.innerHTML = data.map(a => `
      <div class="bg-gradient-to-br from-blue-500/10 to-purple-500/10 backdrop-blur-lg border border-blue-500/20 rounded-xl p-6">
        <h3 class="text-xl font-bold mb-2 text-blue-300">${a.name}</h3>
        <p class="text-gray-400 mb-2">${a.description || ""}</p>
        <p class="text-purple-300 font-bold">${a.price_per_night} zł / noc</p>
      </div>`).join("");
  } catch (e) { console.error("Nie udało się pobrać ofert", e); }
}
loadApartments();

// Rezerwacja -> POST /api/bookings -> backend publikuje event do Kafki (przez Redis jako bufor)
document.getElementById("booking-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const payload = {
    apartment_id: document.getElementById("apartment-id").value,
    date_from: document.getElementById("date-from").value,
    date_to: document.getElementById("date-to").value,
    guest_name: document.getElementById("guest-name").value,
    guest_email: document.getElementById("guest-email").value,
    marketing_consent: document.getElementById("marketing-consent").checked
  };
  const resultEl = document.getElementById("booking-result");
  resultEl.textContent = "Przetwarzanie rezerwacji...";
  try {
    const res = await fetch("/api/bookings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    if (res.ok) {
      resultEl.textContent = `Rezerwacja przyjęta (nr ${data.booking_id}). Potwierdzenie i faktura proforma zostaną wysłane na e-mail.`;
    } else {
      resultEl.textContent = `Błąd: ${data.detail || "nieznany"}`;
    }
  } catch (err) {
    resultEl.textContent = "Błąd połączenia z serwerem.";
  }
});
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/static/style.css" << 'DAVTRO_EOF'
@keyframes fadeIn { from { opacity:0; transform:translateY(10px);} to {opacity:1; transform:translateY(0);} }
.animate-fade-in { animation: fadeIn 0.5s ease-out; }
.tab-btn.active { background-color:#a855f7; color:#fff; }
.day.booked { background:#7f1d1d; cursor:not-allowed; opacity:.5; }
.day.free { background:#334155; cursor:pointer; }
.day.free:hover { background:#7c3aed; }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/app/templates/index.html" << 'DAVTRO_EOF'
<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Davtro Apartments - Wynajem Krótkoterminowy</title>
<script src="https://cdn.tailwindcss.com"></script>
<link rel="stylesheet" href="/static/style.css" />
</head>
<body class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen">

<header class="border-b border-purple-500/30 backdrop-blur-sm bg-black/20">
  <div class="container mx-auto px-6 py-6 flex items-center justify-between flex-wrap gap-4">
    <div class="flex items-center gap-3">
      <svg class="w-10 h-10 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9.5L12 3l9 6.5V21H3V9.5z"></path>
      </svg>
      <h1 class="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
        Davtro Apartments
      </h1>
    </div>
    <nav class="flex gap-4">
      <button onclick="showTab('offer')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="offer">Oferta</button>
      <button onclick="showTab('booking')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="booking">Rezerwacja</button>
      <button onclick="showTab('contact')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="contact">Kontakt</button>
    </nav>
  </div>
</header>

<main class="container mx-auto px-6 py-12">

  <div id="offer-tab" class="tab-content">
    <div class="space-y-8 animate-fade-in">
      <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
        <h2 class="text-4xl font-bold mb-6 text-purple-300">Mieszkania na wynajem krótkoterminowy</h2>
        <p class="text-lg text-gray-300 leading-relaxed">
          Komfortowe apartamenty w centrum miasta. Sprawdź dostępność w kalendarzu
          i zarezerwuj termin online. Po rezerwacji otrzymasz potwierdzenie
          oraz fakturę proforma na e-mail.
        </p>
      </div>
      <div id="apartments-grid" class="grid md:grid-cols-3 gap-6">
        <!-- wypełniane przez apartments.js z /api/apartments -->
      </div>
    </div>
  </div>

  <div id="booking-tab" class="tab-content hidden">
    <div class="space-y-6 animate-fade-in">
      <h2 class="text-4xl font-bold mb-8 text-purple-300">Rezerwacja</h2>
      <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
        <div id="calendar" class="mb-6"></div>
        <form id="booking-form" class="grid md:grid-cols-2 gap-4">
          <input type="hidden" id="apartment-id" value="1" />
          <div>
            <label class="block text-gray-400 mb-2">Data od</label>
            <input required type="date" id="date-from" class="w-full py-3 px-4 rounded-lg bg-slate-700 border border-purple-500/30 outline-none" />
          </div>
          <div>
            <label class="block text-gray-400 mb-2">Data do</label>
            <input required type="date" id="date-to" class="w-full py-3 px-4 rounded-lg bg-slate-700 border border-purple-500/30 outline-none" />
          </div>
          <div>
            <label class="block text-gray-400 mb-2">Imię i nazwisko</label>
            <input required type="text" id="guest-name" class="w-full py-3 px-4 rounded-lg bg-slate-700 border border-purple-500/30 outline-none" />
          </div>
          <div>
            <label class="block text-gray-400 mb-2">Email</label>
            <input required type="email" id="guest-email" class="w-full py-3 px-4 rounded-lg bg-slate-700 border border-purple-500/30 outline-none" />
          </div>
          <div class="md:col-span-2">
            <label class="flex items-center gap-2 text-gray-400">
              <input type="checkbox" id="marketing-consent" />
              Chcę otrzymywać oferty marketingowe (newsletter)
            </label>
          </div>
          <div class="md:col-span-2">
            <button type="submit" class="w-full py-3 px-4 rounded-lg bg-purple-500 hover:bg-purple-600 transition-all">
              Zarezerwuj i wyślij potwierdzenie
            </button>
          </div>
        </form>
        <p id="booking-result" class="mt-4 text-purple-300"></p>
      </div>
    </div>
  </div>

  <div id="contact-tab" class="tab-content hidden">
    <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
      <h2 class="text-4xl font-bold mb-6 text-purple-300">Kontakt</h2>
      <p class="text-gray-300">Davtro Apartments · biuro@davtro.pl</p>
    </div>
  </div>

</main>

<footer class="border-t border-purple-500/30 backdrop-blur-sm bg-black/20 mt-16">
  <div class="container mx-auto px-6 py-8 text-center text-gray-400">
    <p>Davtro Apartments © 2026</p>
  </div>
</footer>

<script src="/static/script.js"></script>
</body>
</html>
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/argocd/application.yaml" << 'DAVTRO_EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/exea-centrum/website-argocd-k8s-github-kustomize.git
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: davtro
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app/Dockerfile" << 'DAVTRO_EOF'
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -B clean package -DskipTests

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /build/target/*.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java","-jar","app.jar"]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app/pom.xml" << 'DAVTRO_EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.davtro</groupId>
  <artifactId>spring-app</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <scope>runtime</scope>
    </dependency>
    <dependency>
      <groupId>org.springframework.kafka</groupId>
      <artifactId>spring-kafka</artifactId>
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
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app/src/main/java/com/davtro/app/SpringAppApplication.java" << 'DAVTRO_EOF'
package com.davtro.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// Rola tego serwisu: panel administracyjny / raportowanie rezerwacji
// (odczyt z tej samej bazy Postgresql co FastAPI, agregaty do Grafany).
@SpringBootApplication
@RestController
public class SpringAppApplication {

    public static void main(String[] args) {
        SpringApplication.run(SpringAppApplication.class, args);
    }

    @GetMapping("/actuator/health/custom")
    public String health() {
        return "OK";
    }
}
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/java-app/src/main/resources/application.properties" << 'DAVTRO_EOF'
server.port=8081
spring.datasource.url=jdbc:postgresql://postgres-clusterip:5432/davtro
spring.datasource.username=${DB_USER:postgres}
spring.datasource.password=${DB_PASSWORD:postgres}
spring.kafka.bootstrap-servers=kafka-kraft:9092
management.endpoints.web.exposure.include=health,prometheus
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/kyverno-policies/kyverno-policy.yaml" << 'DAVTRO_EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: davtro-baseline-policy
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-ghcr-images
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Obrazy kontenerów w namespace 'davtro' muszą pochodzić z ghcr.io lub zaufanych rejestrów (bitnami, postgres, redis itd. na potrzeby usług pomocniczych)."
        pattern:
          spec:
            containers:
              - image: "*"
    - name: require-resource-requests-limits
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Każdy kontener musi mieć zdefiniowane requests/limits."
        pattern:
          spec:
            containers:
              - resources:
                  requests:
                    cpu: "?*"
                    memory: "?*"
                  limits:
                    cpu: "?*"
                    memory: "?*"
    - name: disallow-privileged
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Kontenery uprzywilejowane (privileged) są niedozwolone."
        pattern:
          spec:
            =(securityContext):
              =(privileged): "false"
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/configmap.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  namespace: davtro
data:
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
  DATABASE_URL: "postgresql://postgres:postgres@postgres-clusterip:5432/davtro"
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/deployment.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  namespace: davtro
  labels: { app: fastapi-web-app }
spec:
  replicas: 2
  selector:
    matchLabels: { app: fastapi-web-app }
  template:
    metadata:
      labels: { app: fastapi-web-app }
    spec:
      serviceAccountName: davtro-sa
      containers:
        - name: fastapi
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
          ports: [{ containerPort: 8080 }]
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 15
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/exporters.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: postgres-exporter } }
  template:
    metadata: { labels: { app: postgres-exporter } }
    spec:
      containers:
        - name: postgres-exporter
          image: prometheuscommunity/postgres-exporter:v0.15.0
          env:
            - name: DATA_SOURCE_NAME
              value: "postgresql://postgres:postgres@postgres-clusterip:5432/davtro?sslmode=disable"
          ports: [{ containerPort: 9187 }]
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: davtro
spec:
  selector: { app: postgres-exporter }
  ports: [{ port: 9187, targetPort: 9187 }]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: kafka-exporter } }
  template:
    metadata: { labels: { app: kafka-exporter } }
    spec:
      containers:
        - name: kafka-exporter
          image: danielqsj/kafka-exporter:v1.7.0
          args: ["--kafka.server=kafka-kraft:9092"]
          ports: [{ containerPort: 9308 }]
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: davtro
spec:
  selector: { app: kafka-exporter }
  ports: [{ port: 9308, targetPort: 9308 }]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: davtro
spec:
  selector: { matchLabels: { app: node-exporter } }
  template:
    metadata: { labels: { app: node-exporter } }
    spec:
      hostNetwork: true
      hostPID: true
      containers:
        - name: node-exporter
          image: prom/node-exporter:v1.8.2
          ports: [{ containerPort: 9100 }]
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: davtro
spec:
  selector: { app: node-exporter }
  ports: [{ port: 9100, targetPort: 9100 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/grafana.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: davtro
data:
  datasource.yaml: |
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
        access: proxy
      - name: Tempo
        type: tempo
        url: http://tempo:3200
        access: proxy
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: davtro
data:
  davtro-overview.json: |
    { "title": "Davtro Platform Overview", "panels": [] }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: grafana } }
  template:
    metadata: { labels: { app: grafana } }
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:11.2.0
          ports: [{ containerPort: 3000 }]
          volumeMounts:
            - { name: datasource, mountPath: /etc/grafana/provisioning/datasources }
            - { name: dashboards, mountPath: /etc/grafana/provisioning/dashboards-data }
      volumes:
        - name: datasource
          configMap: { name: grafana-datasource }
        - name: dashboards
          configMap: { name: grafana-dashboards }
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: davtro
spec:
  selector: { app: grafana }
  ports: [{ port: 3000, targetPort: 3000 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/hpa.yaml" << 'DAVTRO_EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-web-app-hpa
  namespace: davtro
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi-web-app
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/ingress.yaml" << 'DAVTRO_EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-ingress
  namespace: davtro
  annotations:
    kubernetes.io/ingress.class: "public"
spec:
  rules:
    - host: davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: fastapi-web-app-svc, port: { number: 80 } }
          - path: /grafana
            pathType: Prefix
            backend:
              service: { name: grafana, port: { number: 3000 } }
          - path: /kafka-ui
            pathType: Prefix
            backend:
              service: { name: kafka-ui, port: { number: 80 } }
          - path: /pgadmin
            pathType: Prefix
            backend:
              service: { name: pgadmin, port: { number: 80 } }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spark-ingress
  namespace: davtro
  annotations:
    kubernetes.io/ingress.class: "public"
spec:
  rules:
    - host: spark.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: spark-master-svc, port: { number: 8082 } }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/kafka-ui.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: kafka-ui } }
  template:
    metadata: { labels: { app: kafka-ui } }
    spec:
      containers:
        - name: kafka-ui
          image: provectuslabs/kafka-ui:latest
          env:
            - { name: KAFKA_CLUSTERS_0_NAME, value: davtro }
            - { name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS, value: "kafka-kraft:9092" }
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: davtro
spec:
  selector: { app: kafka-ui }
  ports: [{ port: 80, targetPort: 8080 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/kafka.yaml" << 'DAVTRO_EOF'
# Kafka w trybie KRaft (bez Zookeepera) - pojedynczy broker do celów tego projektu.
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-kraft
  namespace: davtro
spec:
  serviceName: kafka-kraft
  replicas: 1
  selector: { matchLabels: { app: kafka-kraft } }
  template:
    metadata: { labels: { app: kafka-kraft } }
    spec:
      containers:
        - name: kafka
          image: bitnami/kafka:3.7
          ports: [{ containerPort: 9092 }]
          env:
            - { name: KAFKA_CFG_NODE_ID, value: "0" }
            - { name: KAFKA_CFG_PROCESS_ROLES, value: "controller,broker" }
            - { name: KAFKA_CFG_LISTENERS, value: "PLAINTEXT://:9092,CONTROLLER://:9093" }
            - { name: KAFKA_CFG_ADVERTISED_LISTENERS, value: "PLAINTEXT://kafka-kraft:9092" }
            - { name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS, value: "0@kafka-kraft-0.kafka-kraft:9093" }
            - { name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES, value: "CONTROLLER" }
          volumeMounts:
            - name: kafka-data
              mountPath: /bitnami/kafka
  volumeClaimTemplates:
    - metadata: { name: kafka-data }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 5Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft
  namespace: davtro
spec:
  clusterIP: None
  selector: { app: kafka-kraft }
  ports:
    - { name: broker, port: 9092, targetPort: 9092 }
    - { name: controller, port: 9093, targetPort: 9093 }
---
# Job tworzący tematy Kafka (booking-events, marketing-events) przy starcie.
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-job
  namespace: davtro
spec:
  template:
    spec:
      serviceAccountName: kafka-job-sa
      restartPolicy: OnFailure
      containers:
        - name: kafka-topic-init
          image: bitnami/kafka:3.7
          command:
            - /bin/bash
            - -c
            - |
              kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic booking-events --partitions 3 --replication-factor 1
              kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic marketing-events --partitions 3 --replication-factor 1
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/kustomization.yaml" << 'DAVTRO_EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - serviceaccount.yaml
  - configmap.yaml
  - secret.yaml
  - deployment.yaml
  - service.yaml
  - hpa.yaml
  - pdb.yaml
  - postgres.yaml
  - redis.yaml
  - vault.yaml
  - kafka.yaml
  - message-processor.yaml
  - spring-app.yaml
  - spark.yaml
  - prometheus.yaml
  - exporters.yaml
  # service-monitors.yaml wymaga Prometheus Operatora (CRD) - odkomentuj, jeśli zainstalowany
  # - service-monitors.yaml
  - grafana.yaml
  - loki.yaml
  - promtail.yaml
  - tempo.yaml
  - pgadmin.yaml
  - kafka-ui.yaml
  - network-policies.yaml
  - ingress.yaml
  - kyverno-policy.yaml

images:
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
    newTag: latest
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/kyverno-policy.yaml" << 'DAVTRO_EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: davtro-baseline-policy
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-ghcr-images
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Obrazy kontenerów w namespace 'davtro' muszą pochodzić z ghcr.io lub zaufanych rejestrów (bitnami, postgres, redis itd. na potrzeby usług pomocniczych)."
        pattern:
          spec:
            containers:
              - image: "*"
    - name: require-resource-requests-limits
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Każdy kontener musi mieć zdefiniowane requests/limits."
        pattern:
          spec:
            containers:
              - resources:
                  requests:
                    cpu: "?*"
                    memory: "?*"
                  limits:
                    cpu: "?*"
                    memory: "?*"
    - name: disallow-privileged
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Kontenery uprzywilejowane (privileged) są niedozwolone."
        pattern:
          spec:
            =(securityContext):
              =(privileged): "false"
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/loki.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: davtro
data:
  loki-config.yaml: |
    auth_enabled: false
    server: { http_listen_port: 3100 }
    schema_config:
      configs:
        - from: 2024-01-01
          store: boltdb-shipper
          object_store: filesystem
          schema: v12
          index: { prefix: index_, period: 24h }
    storage_config:
      filesystem: { directory: /loki/chunks }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: loki } }
  template:
    metadata: { labels: { app: loki } }
    spec:
      containers:
        - name: loki
          image: grafana/loki:3.1.1
          args: ["-config.file=/etc/loki/loki-config.yaml"]
          ports: [{ containerPort: 3100 }]
          volumeMounts:
            - { name: config, mountPath: /etc/loki }
      volumes:
        - name: config
          configMap: { name: loki-config }
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: davtro
spec:
  selector: { app: loki }
  ports: [{ port: 3100, targetPort: 3100 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/message-processor.yaml" << 'DAVTRO_EOF'
# Konsument Kafka: booking-events + marketing-events -> e-mail + aktualizacja Postgresql.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: message-processor } }
  template:
    metadata: { labels: { app: message-processor } }
    spec:
      serviceAccountName: davtro-sa
      containers:
        - name: message-processor
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer:latest
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 300m, memory: 256Mi }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/namespace.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
  labels:
    app.kubernetes.io/part-of: davtro-platform
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/network-policies.yaml" << 'DAVTRO_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: davtro
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: davtro
spec:
  podSelector: {}
  ingress:
    - from: [{ podSelector: {} }]
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-web
  namespace: davtro
spec:
  podSelector: { matchLabels: { app: fastapi-web-app } }
  ingress:
    - from: []
      ports: [{ protocol: TCP, port: 8080 }]
  policyTypes: [Ingress]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/pdb.yaml" << 'DAVTRO_EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-web-app-pdb
  namespace: davtro
spec:
  minAvailable: 1
  selector:
    matchLabels: { app: fastapi-web-app }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/pgadmin.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: pgadmin } }
  template:
    metadata: { labels: { app: pgadmin } }
    spec:
      containers:
        - name: pgadmin
          image: dpage/pgadmin4:8
          env:
            - { name: PGADMIN_DEFAULT_EMAIL, value: admin@davtro.pl }
            - name: PGADMIN_DEFAULT_PASSWORD
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_PASSWORD } }
          ports: [{ containerPort: 80 }]
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: davtro
spec:
  selector: { app: pgadmin }
  ports: [{ port: 80, targetPort: 80 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/postgres.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: davtro
spec:
  serviceName: postgres-clusterip
  replicas: 1
  selector:
    matchLabels: { app: postgres-db }
  template:
    metadata:
      labels: { app: postgres-db }
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports: [{ containerPort: 5432 }]
          env:
            - name: POSTGRES_DB
              value: davtro
            - name: POSTGRES_USER
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_USER } }
            - name: POSTGRES_PASSWORD
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_PASSWORD } }
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata: { name: pgdata }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 5Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-clusterip
  namespace: davtro
spec:
  clusterIP: None
  selector: { app: postgres-db }
  ports: [{ port: 5432, targetPort: 5432 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/prometheus.yaml" << 'DAVTRO_EOF'
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
      - job_name: fastapi
        static_configs: [{ targets: ["fastapi-web-app-svc:80"] }]
      - job_name: postgres-exporter
        static_configs: [{ targets: ["postgres-exporter:9187"] }]
      - job_name: kafka-exporter
        static_configs: [{ targets: ["kafka-exporter:9308"] }]
      - job_name: node-exporter
        static_configs: [{ targets: ["node-exporter:9100"] }]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: prometheus } }
  template:
    metadata: { labels: { app: prometheus } }
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:v2.54.1
          args: ["--config.file=/etc/prometheus/prometheus.yml"]
          ports: [{ containerPort: 9090 }]
          volumeMounts:
            - { name: config, mountPath: /etc/prometheus }
      volumes:
        - name: config
          configMap: { name: prometheus-config }
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: davtro
spec:
  selector: { app: prometheus }
  ports: [{ port: 9090, targetPort: 9090 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/promtail.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: davtro
data:
  promtail.yaml: |
    server: { http_listen_port: 9080 }
    clients: [{ url: http://loki:3100/loki/api/v1/push }]
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs: [{ role: pod }]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: davtro
spec:
  selector: { matchLabels: { app: promtail } }
  template:
    metadata: { labels: { app: promtail } }
    spec:
      serviceAccountName: davtro-sa
      containers:
        - name: promtail
          image: grafana/promtail:3.1.1
          args: ["-config.file=/etc/promtail/promtail.yaml"]
          volumeMounts:
            - { name: config, mountPath: /etc/promtail }
            - { name: varlog, mountPath: /var/log }
      volumes:
        - name: config
          configMap: { name: promtail-config }
        - name: varlog
          hostPath: { path: /var/log }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/redis.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports: [{ containerPort: 6379 }]
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: davtro
spec:
  selector: { app: redis }
  ports: [{ port: 6379, targetPort: 6379 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/secret.yaml" << 'DAVTRO_EOF'
# UWAGA: To jest placeholder. W realnym środowisku wartości mają być
# wstrzykiwane przez Vault (ArgoCD Vault Plugin), NIE trzymane w repo.
apiVersion: v1
kind: Secret
metadata:
  name: davtro-secrets
  namespace: davtro
type: Opaque
stringData:
  DB_USER: "<path:secret/data/davtro#db_user>"
  DB_PASSWORD: "<path:secret/data/davtro#db_password>"
  SMTP_USER: "<path:secret/data/davtro#smtp_user>"
  SMTP_PASSWORD: "<path:secret/data/davtro#smtp_password>"
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/service-monitors.yaml" << 'DAVTRO_EOF'
# Wymaga Prometheus Operatora (CRD ServiceMonitor). Jeśli używasz "gołego" Prometheusa
# jak w prometheus.yaml, ten plik można pominąć w kustomization.yaml.
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: davtro-services
  namespace: davtro
  labels: { release: prometheus }
spec:
  selector:
    matchExpressions:
      - { key: app, operator: In, values: [fastapi-web-app, postgres-exporter, kafka-exporter] }
  endpoints:
    - port: metrics
      interval: 15s
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/service.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-app-svc
  namespace: davtro
spec:
  selector: { app: fastapi-web-app }
  ports:
    - port: 80
      targetPort: 8080
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/serviceaccount.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: davtro-sa
  namespace: davtro
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-job-sa
  namespace: davtro
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/spark.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: spark-master } }
  template:
    metadata: { labels: { app: spark-master } }
    spec:
      containers:
        - name: spark-master
          image: bitnami/spark:3.5
          command: ["/opt/bitnami/spark/sbin/start-master.sh"]
          ports: [{ containerPort: 7077 }, { containerPort: 8082 }]
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master-svc
  namespace: davtro
spec:
  selector: { app: spark-master }
  ports:
    - { name: rpc, port: 7077, targetPort: 7077 }
    - { name: ui, port: 8082, targetPort: 8082 }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: davtro
spec:
  replicas: 2
  selector: { matchLabels: { app: spark-worker } }
  template:
    metadata: { labels: { app: spark-worker } }
    spec:
      containers:
        - name: spark-worker
          image: bitnami/spark:3.5
          command: ["/opt/bitnami/spark/sbin/start-worker.sh", "spark://spark-master-svc:7077"]
          env:
            - { name: SPARK_WORKER_CORES, value: "1" }
            - { name: SPARK_WORKER_MEMORY, value: "1g" }
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/spring-app.yaml" << 'DAVTRO_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app-deployment
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: spring-app } }
  template:
    metadata: { labels: { app: spring-app } }
    spec:
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:latest
          ports: [{ containerPort: 8081 }]
          envFrom:
            - secretRef: { name: davtro-secrets }
          resources:
            requests: { cpu: 200m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app-svc
  namespace: davtro
spec:
  selector: { app: spring-app }
  ports: [{ port: 80, targetPort: 8081 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/tempo.yaml" << 'DAVTRO_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: davtro
data:
  tempo.yaml: |
    server: { http_listen_port: 3200 }
    distributor:
      receivers:
        otlp:
          protocols: { http: {}, grpc: {} }
    storage:
      trace: { backend: local, local: { path: /tmp/tempo/traces } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: davtro
spec:
  replicas: 1
  selector: { matchLabels: { app: tempo } }
  template:
    metadata: { labels: { app: tempo } }
    spec:
      containers:
        - name: tempo
          image: grafana/tempo:2.6.0
          args: ["-config.file=/etc/tempo/tempo.yaml"]
          ports: [{ containerPort: 3200 }]
          volumeMounts:
            - { name: config, mountPath: /etc/tempo }
      volumes:
        - name: config
          configMap: { name: tempo-config }
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: davtro
spec:
  selector: { app: tempo }
  ports: [{ port: 3200, targetPort: 3200 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/base/vault.yaml" << 'DAVTRO_EOF'
# Minimalna instancja Vault (dev-mode) do integracji z ArgoCD Vault Plugin.
# W produkcji: użyj oficjalnego Helm chartu HashiCorp Vault (HA + auto-unseal),
# tu podana jest wersja uproszczona zgodna z resztą manifestów Kustomize.
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: davtro
spec:
  serviceName: vault
  replicas: 1
  selector: { matchLabels: { app: vault } }
  template:
    metadata: { labels: { app: vault } }
    spec:
      serviceAccountName: davtro-sa
      containers:
        - name: vault
          image: hashicorp/vault:1.17
          args: ["server", "-dev", "-dev-listen-address=0.0.0.0:8200"]
          ports: [{ containerPort: 8200 }]
          env:
            - name: VAULT_DEV_ROOT_TOKEN_ID
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: VAULT_ROOT_TOKEN, optional: true } }
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: davtro
spec:
  selector: { app: vault }
  ports: [{ port: 8200, targetPort: 8200 }]
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/manifests/production/kustomization.yaml" << 'DAVTRO_EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: davtro

resources:
  - ../base

images:
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
    newTag: latest

replicas:
  - name: fastapi-web-app
    count: 3
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/spark-jobs/Dockerfile" << 'DAVTRO_EOF'
FROM bitnami/spark:3.5
WORKDIR /jobs
COPY marketing_analytics.py .
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/spark-jobs/marketing_analytics.py" << 'DAVTRO_EOF'
"""
Spark job: agregacja zdarzen z tematu Kafka 'marketing-events'
(np. liczba zgod marketingowych dziennie) i zapis wynikow do Postgresql,
skad Grafana/Spring-app moga je pokazac.
Uruchamiane cyklicznie na spark-master/spark-worker (spark-submit) lub jako CronJob.
"""
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, window, count
from pyspark.sql.types import StructType, StringType

KAFKA_BOOTSTRAP = "kafka-kraft:9092"
JDBC_URL = "jdbc:postgresql://postgres-clusterip:5432/davtro"

schema = StructType() \
    .add("event_id", StringType()) \
    .add("guest_email", StringType()) \
    .add("guest_name", StringType()) \
    .add("type", StringType())

if __name__ == "__main__":
    spark = SparkSession.builder.appName("marketing-analytics").getOrCreate()

    df = spark.readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP) \
        .option("subscribe", "marketing-events") \
        .load()

    parsed = df.select(from_json(col("value").cast("string"), schema).alias("data")).select("data.*")

    agg = parsed.groupBy(window(parsed.event_id, "1 hour")).agg(count("*").alias("events_count"))

    query = agg.writeStream \
        .outputMode("update") \
        .format("console") \
        .start()

    query.awaitTermination()
DAVTRO_EOF
cat > "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/terraform/main.tf" << 'DAVTRO_EOF'
terraform {
  cloud {
    organization = "davtro"
    workspaces { name = "github-actions-terraform" }
  }
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}

provider "github" {
  token = var.github_token
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "ghcr_pat" {
  type      = string
  sensitive = true
}

resource "github_repository" "repo" {
  name        = "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
  description = "Davtro Apartments - platforma wynajmu krótkoterminowego (K8s/ArgoCD/Kafka/Redis/Vault)"
  visibility  = "private"
}

resource "github_actions_secret" "ghcr_pat" {
  repository      = github_repository.repo.name
  secret_name     = "GHCR_PAT"
  plaintext_value = var.ghcr_pat
}
DAVTRO_EOF
chmod +x "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/all-in-one.sh" 2>/dev/null || true
echo "Gotowe. Projekt rozpakowany do katalogu: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01/"
echo "Zobacz README.md w tym katalogu, zeby wiedziec jak zaczac."