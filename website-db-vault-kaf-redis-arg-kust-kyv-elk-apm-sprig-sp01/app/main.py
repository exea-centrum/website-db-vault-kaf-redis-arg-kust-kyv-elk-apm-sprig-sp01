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
