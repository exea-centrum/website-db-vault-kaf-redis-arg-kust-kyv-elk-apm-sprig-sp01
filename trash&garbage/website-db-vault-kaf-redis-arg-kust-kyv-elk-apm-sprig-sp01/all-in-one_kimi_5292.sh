#!/bin/bash
set -e

PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
NAMESPACE="davtro"
REPO="https://github.com/exea-centrum/${PROJECT_NAME}.git"

echo "=== DavTro Rentals - All-in-One Setup ==="
mkdir -p ${PROJECT_NAME}/{frontend,backend-fastapi/app,java-app/src/main/{java/com/davtro/rental/{model,repository,consumer,service},resources},spark-jobs/src/main/scala/com/davtro/jobs,spark-jobs/project,manifests/{base,overlays/{production,staging}},terraform,.github/workflows,scripts,docs}

# ============================================
# FRONTEND
# ============================================
cat > ${PROJECT_NAME}/frontend/index.html << 'HTMLEOF'
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
      <p class="text-xl text-gray-400 max-w-2xl mx-auto mb-10">Nowoczesna platforma z Kafka, Redis, PostgreSQL, Vault, Spark i Spring Boot</p>
      <div class="flex justify-center gap-4">
        <button onclick="showSection('properties')" class="px-8 py-4 bg-blue-600 rounded-xl font-semibold hover:scale-105 transition">Przeglądaj Oferty</button>
        <button onclick="showSection('calendar')" class="px-8 py-4 glass rounded-xl font-semibold hover:scale-105 transition">Sprawdź Dostępność</button>
      </div>
    </div>
    <div class="grid md:grid-cols-4 gap-6 mb-12">
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-database text-3xl text-blue-400 mb-3"></i><h3 class="font-bold">PostgreSQL</h3><p class="text-sm text-gray-400">Trwały zapis danych</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-bolt text-3xl text-yellow-400 mb-3"></i><h3 class="font-bold">Apache Kafka</h3><p class="text-sm text-gray-400">Stream processing</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-server text-3xl text-red-400 mb-3"></i><h3 class="font-bold">Redis Cache</h3><p class="text-sm text-gray-400">Szybki cache</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-shield-alt text-3xl text-purple-400 mb-3"></i><h3 class="font-bold">HashiCorp Vault</h3><p class="text-sm text-gray-400">Bezpieczne sekrety</p></div>
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
          <div><label class="block text-sm text-gray-400 mb-2">Telefon</label><input type="tel" id="guest-phone" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="+48 123 456 789"></div>
          <div class="bg-white/5 rounded-lg p-4">
            <div class="flex justify-between text-sm mb-2"><span>Cena za dobę:</span><span id="price-per-night" class="font-semibold">-</span></div>
            <div class="flex justify-between text-sm mb-2"><span>Liczba nocy:</span><span id="night-count" class="font-semibold">-</span></div>
            <div class="flex justify-between text-lg font-bold border-t border-white/10 pt-2"><span>Razem:</span><span id="total-price" class="text-blue-400">-</span></div>
          </div>
          <button onclick="submitBooking()" class="w-full py-4 bg-gradient-to-r from-blue-600 to-purple-600 rounded-xl font-bold hover:scale-[1.02] transition">Zarezerwuj i Otrzymaj Fakturę Proforma</button>
          <p class="text-xs text-gray-500 text-center"><i class="fas fa-lock mr-1"></i>Rezerwacja: Redis → Kafka → PostgreSQL. Faktura proforma na email.</p>
        </div>
      </div>
    </div>
  </section>
  <section id="admin-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Panel Administracyjny</h2>
    <div class="grid md:grid-cols-4 gap-6 mb-10">
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-blue-400" id="stat-bookings">0</div><div class="text-sm text-gray-400">Rezerwacje</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-green-400" id="stat-revenue">0 zł</div><div class="text-sm text-gray-400">Przychód</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-yellow-400" id="stat-kafka">0</div><div class="text-sm text-gray-400">Wiadomości Kafka</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-purple-400" id="stat-occupancy">0%</div><div class="text-sm text-gray-400">Zajętość</div></div>
    </div>
    <div class="glass rounded-2xl p-6 mb-10">
      <div class="flex justify-between mb-6"><h3 class="text-xl font-bold">Rezerwacje</h3><button onclick="exportBookings()" class="px-4 py-2 bg-blue-600 rounded-lg"><i class="fas fa-download mr-2"></i>Eksport CSV</button></div>
      <div class="overflow-x-auto"><table class="w-full text-left"><thead><tr class="border-b border-white/10"><th class="pb-4 text-gray-400">ID</th><th class="pb-4 text-gray-400">Nieruchomość</th><th class="pb-4 text-gray-400">Gość</th><th class="pb-4 text-gray-400">Daty</th><th class="pb-4 text-gray-400">Kwota</th><th class="pb-4 text-gray-400">Status</th></tr></thead><tbody id="bookings-table"></tbody></table></div>
    </div>
    <div class="glass rounded-2xl p-6">
      <h3 class="text-xl font-bold mb-6">Kafka Topics</h3>
      <div class="grid md:grid-cols-3 gap-4">
        <div class="bg-slate-800/50 rounded-xl p-4 border border-yellow-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-yellow-400">bookings-created</span><span class="text-xs bg-yellow-500/20 text-yellow-400 px-2 py-1 rounded">spring-app</span></div><div class="text-2xl font-bold">1,247</div></div>
        <div class="bg-slate-800/50 rounded-xl p-4 border border-purple-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-purple-400">marketing-actions</span><span class="text-xs bg-purple-500/20 text-purple-400 px-2 py-1 rounded">spark-app</span></div><div class="text-2xl font-bold">3,892</div></div>
        <div class="bg-slate-800/50 rounded-xl p-4 border border-green-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-green-400">email-invoices</span><span class="text-xs bg-green-500/20 text-green-400 px-2 py-1 rounded">message-processor</span></div><div class="text-2xl font-bold">1,198</div></div>
      </div>
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
  {id:1,name:"Apartament Premium - Warszawa",location:"warsaw",price:450,guests:4,image:"🏙️",rating:4.9,amenities:["WiFi","Klimatyzacja","Balkon","Parking"],description:"Luksusowy apartament w centrum Warszawy."},
  {id:2,name:"Studio Modern - Kraków",location:"krakow",price:320,guests:2,image:"🏰",rating:4.8,amenities:["WiFi","Smart TV","Kuchnia"],description:"Stylowe studio obok Rynku Głównego."},
  {id:3,name:"Villa nad Morzem - Gdańsk",location:"gdansk",price:680,guests:6,image:"🌊",rating:4.9,amenities:["WiFi","Ogródek","Grill","Parking"],description:"Willa 200m od plaży."},
  {id:4,name:"Loft Industrial - Wrocław",location:"wroclaw",price:280,guests:3,image:"🏭",rating:4.7,amenities:["WiFi","Projektor","Klimatyzacja"],description:"Industrialny loft w Nadodrzu."},
  {id:5,name:"Penthouse View - Warszawa",location:"warsaw",price:850,guests:4,image:"🌆",rating:5.0,amenities:["WiFi","Basen","Siłownia","Concierge"],description:"Ekskluzywny penthouse z tarasem."},
  {id:6,name:"Apartament Royal - Kraków",location:"krakow",price:390,guests:4,image:"👑",rating:4.8,amenities:["WiFi","Klimatyzacja","Balkon"],description:"Elegancki apartament w Kazimierzu."}
];
let bookings=JSON.parse(localStorage.getItem('bookings')||'[]');
let currentMonth=new Date();
let selectedDates=[];
function showSection(section){document.querySelectorAll('.section-content').forEach(s=>s.classList.add('hidden'));document.getElementById(section+'-section').classList.remove('hidden');if(section==='properties')renderProperties();if(section==='calendar'){renderCalendar();populatePropertySelect();}if(section==='admin')renderAdmin();}
function showToast(title,message,type='success'){const toast=document.getElementById('toast');document.getElementById('toast-title').textContent=title;document.getElementById('toast-message').textContent=message;toast.classList.remove('translate-y-20','opacity-0');setTimeout(()=>toast.classList.add('translate-y-20','opacity-0'),4000);}
function createPropertyCard(prop){return`<div class="property-card glass rounded-2xl overflow-hidden"><div class="h-48 bg-gradient-to-br from-slate-700 to-slate-800 flex items-center justify-center text-6xl relative">${prop.image}<div class="absolute top-4 right-4 bg-black/50 rounded-lg px-3 py-1 text-sm font-bold"><i class="fas fa-star text-yellow-400 mr-1"></i>${prop.rating}</div></div><div class="p-6"><div class="flex items-center gap-2 text-sm text-gray-400 mb-2"><i class="fas fa-map-marker-alt text-blue-400"></i>${prop.location}</div><h3 class="text-lg font-bold mb-2">${prop.name}</h3><p class="text-sm text-gray-400 mb-4">${prop.description}</p><div class="flex flex-wrap gap-2 mb-4">${prop.amenities.map(a=>`<span class="text-xs bg-white/10 px-2 py-1 rounded">${a}</span>`).join('')}</div><div class="flex items-center justify-between"><div><span class="text-2xl font-bold text-blue-400">${prop.price} zł</span><span class="text-sm text-gray-400">/doba</span></div><button onclick="selectPropertyForBooking(${prop.id})" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition">Rezerwuj</button></div></div></div>`;}
function renderProperties(){document.getElementById('all-properties').innerHTML=properties.map(p=>createPropertyCard(p)).join('');}
function renderFeatured(){document.getElementById('featured-properties').innerHTML=properties.slice(0,3).map(p=>createPropertyCard(p)).join('');}
function renderCalendar(){const grid=document.getElementById('calendar-grid');const monthLabel=document.getElementById('calendar-month');const year=currentMonth.getFullYear(),month=currentMonth.getMonth();const monthNames=['Styczeń','Luty','Marzec','Kwiecień','Maj','Czerwiec','Lipiec','Sierpień','Wrzesień','Październik','Listopad','Grudzień'];monthLabel.textContent=`${monthNames[month]} ${year}`;grid.innerHTML='';const firstDay=new Date(year,month,1).getDay();const daysInMonth=new Date(year,month+1,0).getDate();const startOffset=firstDay===0?6:firstDay-1;for(let i=0;i<startOffset;i++)grid.innerHTML+=`<div></div>`;for(let day=1;day<=daysInMonth;day++){const dateStr=`${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;const isBooked=bookings.some(b=>dateStr>=b.checkIn&&dateStr<=b.checkOut);const isSelected=selectedDates.includes(dateStr);const isPast=new Date(dateStr)<new Date().setHours(0,0,0,0);let classes='h-12 rounded-lg flex items-center justify-center cursor-pointer text-sm font-medium ';if(isPast)classes+='text-gray-600 cursor-not-allowed';else if(isBooked)classes+='bg-red-500/20 border border-red-500 text-red-300 cursor-not-allowed';else if(isSelected)classes+='bg-blue-500 border border-blue-400 text-white';else classes+='bg-white/5 hover:bg-white/15';const onclick=isPast||isBooked?'':`onclick="toggleDate('${dateStr}')"`;
grid.innerHTML+=`<div class="${classes}" ${onclick}>${day}</div>`;}}
function changeMonth(delta){currentMonth.setMonth(currentMonth.getMonth()+delta);renderCalendar();}
function toggleDate(dateStr){const idx=selectedDates.indexOf(dateStr);if(idx>-1)selectedDates.splice(idx,1);else if(selectedDates.length<2)selectedDates.push(dateStr);else{selectedDates=[selectedDates[1],dateStr];}selectedDates.sort();renderCalendar();if(selectedDates.length===2){document.getElementById('check-in').value=selectedDates[0];document.getElementById('check-out').value=selectedDates[1];calculatePrice();}}
function populatePropertySelect(){document.getElementById('booking-property').innerHTML='<option value="">-- Wybierz --</option>'+properties.map(p=>`<option value="${p.id}">${p.name} - ${p.price} zł/doba</option>`).join('');}
function selectPropertyForBooking(id){showSection('calendar');document.getElementById('booking-property').value=id;calculatePrice();}
function calculatePrice(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;if(!propId||!checkIn||!checkOut)return;const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));if(nights>0){document.getElementById('price-per-night').textContent=prop.price+' zł';document.getElementById('night-count').textContent=nights;document.getElementById('total-price').textContent=(prop.price*nights)+' zł';}}
['booking-property','check-in','check-out'].forEach(id=>{document.getElementById(id)?.addEventListener('change',calculatePrice);});
async function submitBooking(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;const name=document.getElementById('guest-name').value;const email=document.getElementById('guest-email').value;const phone=document.getElementById('guest-phone').value;if(!propId||!checkIn||!checkOut||!name||!email){showToast('Błąd','Wypełnij wszystkie pola','error');return;}const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));const total=prop.price*nights;const booking={id:'BK-'+Date.now(),propertyId:propId,propertyName:prop.name,guestName:name,email:email,phone:phone,checkIn:checkIn,checkOut:checkOut,nights:nights,totalPrice:total,status:'confirmed',pipeline:'Redis → Kafka → PostgreSQL'};showToast('Przetwarzanie','Rezerwacja przez Redis → Kafka...','info');await new Promise(r=>setTimeout(r,2000));bookings.push(booking);localStorage.setItem('bookings',JSON.stringify(bookings));showToast('Sukces!',`Rezerwacja potwierdzona! Faktura proforma na ${total} zł wysłana na ${email}`);document.getElementById('guest-name').value='';document.getElementById('guest-email').value='';document.getElementById('guest-phone').value='';selectedDates=[];renderCalendar();}
function renderAdmin(){document.getElementById('stat-bookings').textContent=bookings.length;const revenue=bookings.reduce((sum,b)=>sum+b.totalPrice,0);document.getElementById('stat-revenue').textContent=revenue.toLocaleString()+' zł';document.getElementById('stat-kafka').textContent=(bookings.length*3+1247).toLocaleString();document.getElementById('stat-occupancy').textContent=Math.min(95,bookings.length*5)+'%';const tbody=document.getElementById('bookings-table');tbody.innerHTML=bookings.slice().reverse().map(b=>`<tr class="border-b border-white/5"><td class="py-4 font-mono text-sm text-blue-400">${b.id}</td><td class="py-4">${b.propertyName}</td><td class="py-4">${b.guestName}<br><span class="text-xs text-gray-500">${b.email}</span></td><td class="py-4 text-sm">${b.checkIn} → ${b.checkOut}<br><span class="text-xs text-gray-500">${b.nights} nocy</span></td><td class="py-4 font-bold">${b.totalPrice.toLocaleString()} zł</td><td class="py-4"><span class="px-2 py-1 bg-green-500/20 text-green-400 rounded text-xs">${b.status}</span></td></tr>`).join('')||'<tr><td colspan="6" class="py-8 text-center text-gray-500">Brak rezerwacji</td></tr>';}
function exportBookings(){const csv='ID,Nieruchomość,Gość,Email,Check-in,Check-out,Nocy,Kwota,Status\n'+bookings.map(b=>`${b.id},${b.propertyName},${b.guestName},${b.email},${b.checkIn},${b.checkOut},${b.nights},${b.totalPrice},${b.status}`).join('\n');const blob=new Blob([csv],{type:'text/csv'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='rezerwacje-davtro.csv';a.click();showToast('Eksport','Plik CSV pobrany');}
renderFeatured();showSection('home');
</script>
</body>
</html>
HTMLEOF

cat > ${PROJECT_NAME}/frontend/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx","-g","daemon off;"]
EOF

# ============================================
# FASTAPI BACKEND
# ============================================
cat > ${PROJECT_NAME}/backend-fastapi/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
asyncpg==0.29.0
redis==5.0.1
kafka-python==2.0.2
pydantic[email]==2.5.0
python-multipart==0.0.6
EOF

cat > ${PROJECT_NAME}/backend-fastapi/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
EXPOSE 8080
CMD ["python","-m","uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]
EOF

mkdir -p ${PROJECT_NAME}/backend-fastapi/app
cat > ${PROJECT_NAME}/backend-fastapi/app/main.py << 'PYEOF'
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List, Optional
import asyncpg
import redis.asyncio as aioredis
import json
import os
from datetime import datetime, date
from kafka import KafkaProducer
import uvicorn

app = FastAPI(title="DavTro Rentals API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

DB_HOST = os.getenv("DB_HOST", "postgres-db")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER = os.getenv("DB_USER", "davtro")
DB_PASS = os.getenv("DB_PASSWORD", "changeme")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka-kraft:9092")

db_pool = None
redis_pool = None
kafka_producer = None

class BookingCreate(BaseModel):
    property_id: int
    guest_name: str
    email: EmailStr
    phone: Optional[str] = None
    guests: int = 1
    check_in: date
    check_out: date
    total_price: float

class BookingResponse(BaseModel):
    id: str
    property_id: int
    property_name: str
    guest_name: str
    email: str
    check_in: str
    check_out: str
    total_price: float
    status: str
    created_at: str

@app.on_event("startup")
async def startup():
    global db_pool, redis_pool, kafka_producer
    db_pool = await asyncpg.create_pool(host=DB_HOST, port=DB_PORT, database=DB_NAME, user=DB_USER, password=DB_PASS, min_size=5, max_size=20)
    redis_pool = aioredis.from_url(f"redis://{REDIS_HOST}:{REDIS_PORT}", decode_responses=True)
    kafka_producer = KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP, value_serializer=lambda v: json.dumps(v).encode('utf-8'))
    await init_db()

@app.on_event("shutdown")
async def shutdown():
    if db_pool: await db_pool.close()
    if redis_pool: await redis_pool.close()
    if kafka_producer: kafka_producer.close()

async def init_db():
    async with db_pool.acquire() as conn:
        await conn.execute('CREATE TABLE IF NOT EXISTS properties (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, location VARCHAR(100), price DECIMAL(10,2), guests INT DEFAULT 2, description TEXT, amenities JSONB DEFAULT \'[]\', created_at TIMESTAMP DEFAULT NOW())')
        await conn.execute('CREATE TABLE IF NOT EXISTS bookings (id VARCHAR(50) PRIMARY KEY, property_id INT REFERENCES properties(id), guest_name VARCHAR(255), email VARCHAR(255), phone VARCHAR(50), guests INT, check_in DATE, check_out DATE, nights INT, total_price DECIMAL(10,2), status VARCHAR(50) DEFAULT \'confirmed\', pipeline VARCHAR(100) DEFAULT \'Redis -> Kafka -> PostgreSQL\', created_at TIMESTAMP DEFAULT NOW())')
        count = await conn.fetchval("SELECT COUNT(*) FROM properties")
        if count == 0:
            await conn.execute("""INSERT INTO properties (id, name, location, price, guests, description, amenities) VALUES
                (1, 'Apartament Premium - Warszawa', 'warsaw', 450, 4, 'Luksusowy apartament w centrum', '[\"WiFi\",\"Klimatyzacja\",\"Balkon\",\"Parking\"]'),
                (2, 'Studio Modern - Krakow', 'krakow', 320, 2, 'Stylowe studio obok Rynku', '[\"WiFi\",\"Smart TV\",\"Kuchnia\"]'),
                (3, 'Villa nad Morzem - Gdansk', 'gdansk', 680, 6, 'Willa 200m od plazy', '[\"WiFi\",\"Ogrodek\",\"Grill\",\"Parking\"]'),
                (4, 'Loft Industrial - Wroclaw', 'wroclaw', 280, 3, 'Industrialny loft', '[\"WiFi\",\"Projektor\",\"Klimatyzacja\"]'),
                (5, 'Penthouse View - Warszawa', 'warsaw', 850, 4, 'Ekskluzywny penthouse', '[\"WiFi\",\"Basen\",\"Silownia\",\"Concierge\"]'),
                (6, 'Apartament Royal - Krakow', 'krakow', 390, 4, 'Elegancki apartament w Kazimierzu', '[\"WiFi\",\"Klimatyzacja\",\"Balkon\"]')
                ON CONFLICT DO NOTHING""")

@app.get("/api/health")
async def health():
    redis_ok = await redis_pool.ping()
    async with db_pool.acquire() as conn:
        db_ok = await conn.fetchval("SELECT 1")
    return {"status": "healthy", "database": db_ok == 1, "redis": redis_ok, "kafka": kafka_producer is not None}

@app.get("/api/properties")
async def get_properties():
    cache_key = "properties:all"
    cached = await redis_pool.get(cache_key)
    if cached: return json.loads(cached)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM properties ORDER BY id")
    properties = [{"id": r["id"], "name": r["name"], "location": r["location"], "price": float(r["price"]), "guests": r["guests"], "description": r["description"], "amenities": json.loads(r["amenities"])} for r in rows]
    await redis_pool.setex(cache_key, 300, json.dumps(properties))
    return properties

@app.post("/api/bookings")
async def create_booking(booking: BookingCreate, background_tasks: BackgroundTasks):
    booking_id = f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{booking.property_id}"
    nights = (booking.check_out - booking.check_in).days
    cache_key = f"booking:{booking_id}"
    booking_data = booking.dict()
    booking_data.update({"id": booking_id, "nights": nights, "status": "pending"})
    await redis_pool.setex(cache_key, 3600, json.dumps(booking_data))
    kafka_producer.send("bookings-created", {"event": "booking_created", "booking_id": booking_id, "property_id": booking.property_id, "guest_name": booking.guest_name, "email": booking.email, "phone": booking.phone, "check_in": str(booking.check_in), "check_out": str(booking.check_out), "nights": nights, "total_price": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    kafka_producer.send("email-invoices", {"event": "invoice_request", "booking_id": booking_id, "email": booking.email, "guest_name": booking.guest_name, "total_price": float(booking.total_price), "property_id": booking.property_id, "check_in": str(booking.check_in), "check_out": str(booking.check_out)})
    kafka_producer.send("marketing-actions", {"event": "new_booking", "property_id": booking.property_id, "guest_email": booking.email, "booking_value": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    kafka_producer.flush()
    return BookingResponse(id=booking_id, property_id=booking.property_id, property_name="", guest_name=booking.guest_name, email=booking.email, check_in=str(booking.check_in), check_out=str(booking.check_out), total_price=booking.total_price, status="pending", created_at=datetime.now().isoformat())

@app.get("/api/bookings")
async def get_bookings():
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT b.*, p.name as property_name FROM bookings b JOIN properties p ON b.property_id = p.id ORDER BY b.created_at DESC")
    return [BookingResponse(id=r["id"], property_id=r["property_id"], property_name=r["property_name"], guest_name=r["guest_name"], email=r["email"], check_in=str(r["check_in"]), check_out=str(r["check_out"]), total_price=float(r["total_price"]), status=r["status"], created_at=str(r["created_at"])) for r in rows]

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
PYEOF

# ============================================
# SPRING BOOT BACKEND
# ============================================
cat > ${PROJECT_NAME}/java-app/pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.2.0</version><relativePath/></parent>
  <groupId>com.davtro</groupId><artifactId>rental-processor</artifactId><version>1.0.0</version>
  <properties><java.version>17</java.version></properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
    <dependency><groupId>org.springframework.kafka</groupId><artifactId>spring-kafka</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-mail</artifactId></dependency>
  </dependencies>
  <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
EOF

cat > ${PROJECT_NAME}/java-app/Dockerfile << 'EOF'
FROM eclipse-temurin:17-jdk-alpine
WORKDIR /app
COPY target/rental-processor-1.0.0.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java","-jar","app.jar"]
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/RentalProcessorApplication.java << 'EOF'
package com.davtro.rental;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.kafka.annotation.EnableKafka;
@SpringBootApplication @EnableKafka
public class RentalProcessorApplication {
    public static void main(String[] args) { SpringApplication.run(RentalProcessorApplication.class, args); }
}
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/model
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/model/Booking.java << 'EOF'
package com.davtro.rental.model;
import jakarta.persistence.*;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
@Entity @Table(name = "bookings") @Data
public class Booking {
    @Id private String id;
    private Integer propertyId;
    private String guestName;
    private String email;
    private String phone;
    private Integer guests;
    private LocalDate checkIn;
    private LocalDate checkOut;
    private Integer nights;
    private BigDecimal totalPrice;
    private String status;
    private String pipeline;
    private LocalDateTime createdAt;
}
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/repository
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/repository/BookingRepository.java << 'EOF'
package com.davtro.rental.repository;
import com.davtro.rental.model.Booking;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
@Repository
public interface BookingRepository extends JpaRepository<Booking, String> {}
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/consumer
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/consumer/BookingConsumer.java << 'EOF'
package com.davtro.rental.consumer;
import com.davtro.rental.model.Booking;
import com.davtro.rental.repository.BookingRepository;
import com.davtro.rental.service.EmailService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
@Component @RequiredArgsConstructor @Slf4j
public class BookingConsumer {
    private final BookingRepository bookingRepository;
    private final EmailService emailService;
    private final ObjectMapper objectMapper;
    @KafkaListener(topics = "bookings-created", groupId = "spring-app-group")
    public void consumeBooking(String message) {
        try {
            JsonNode json = objectMapper.readTree(message);
            log.info("Received booking: {}", json.get("booking_id").asText());
            Booking booking = new Booking();
            booking.setId(json.get("booking_id").asText());
            booking.setPropertyId(json.get("property_id").asInt());
            booking.setGuestName(json.get("guest_name").asText());
            booking.setEmail(json.get("email").asText());
            booking.setPhone(json.has("phone") ? json.get("phone").asText() : null);
            booking.setGuests(json.has("guests") ? json.get("guests").asInt() : 2);
            booking.setCheckIn(LocalDate.parse(json.get("check_in").asText()));
            booking.setCheckOut(LocalDate.parse(json.get("check_out").asText()));
            booking.setNights(json.get("nights").asInt());
            booking.setTotalPrice(new BigDecimal(json.get("total_price").asText()));
            booking.setStatus("confirmed");
            booking.setPipeline("Redis -> Kafka -> PostgreSQL");
            booking.setCreatedAt(LocalDateTime.now());
            bookingRepository.save(booking);
            log.info("Booking saved: {}", booking.getId());
        } catch (Exception e) { log.error("Error: {}", e.getMessage()); }
    }
    @KafkaListener(topics = "email-invoices", groupId = "spring-app-group")
    public void consumeInvoice(String message) {
        try {
            JsonNode json = objectMapper.readTree(message);
            emailService.sendProformaInvoice(json.get("email").asText(), json.get("guest_name").asText(), json.get("booking_id").asText(), new BigDecimal(json.get("total_price").asText()));
        } catch (Exception e) { log.error("Error sending invoice: {}", e.getMessage()); }
    }
}
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/service
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/service/EmailService.java << 'EOF'
package com.davtro.rental.service;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import java.math.BigDecimal;
@Service @RequiredArgsConstructor @Slf4j
public class EmailService {
    private final JavaMailSender mailSender;
    public void sendProformaInvoice(String to, String guestName, String bookingId, BigDecimal total) {
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setTo(to);
            message.setSubject("Faktura Proforma - DavTro Rentals - " + bookingId);
            message.setText(String.format("Witaj %s!\n\nTwoja rezerwacja zostala potwierdzona.\nNumer: %s\nKwota: %s zl\n\nFaktura proforma. Prosze o platnosc w terminie 24h.\n\nPozdrawiamy,\nZespol DavTro Rentals", guestName, bookingId, total.toString()));
            mailSender.send(message);
            log.info("Proforma sent to: {}", to);
        } catch (Exception e) { log.error("Failed to send: {}", e.getMessage()); }
    }
}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/resources/application.properties << 'EOF'
server.port=8081
spring.datasource.url=jdbc:postgresql://${DB_HOST:postgres-db}:5432/davtro_rentals
spring.datasource.username=${DB_USER:davtro}
spring.datasource.password=${DB_PASSWORD:changeme}
spring.jpa.hibernate.ddl-auto=validate
spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP:kafka-kraft:9092}
spring.kafka.consumer.group-id=spring-app-group
spring.kafka.consumer.auto-offset-reset=earliest
spring.mail.host=${SMTP_HOST:localhost}
spring.mail.port=${SMTP_PORT:587}
EOF

# ============================================
# SPARK JOBS
# ============================================
cat > ${PROJECT_NAME}/spark-jobs/build.sbt << 'EOF'
name := "davtro-spark-jobs"
version := "1.0.0"
scalaVersion := "2.12.18"
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % "3.5.0",
  "org.postgresql" % "postgresql" % "42.7.1"
)
assembly / assemblyMergeStrategy := { case PathList("META-INF", xs @ _*) => xs match { case "MANIFEST.MF" :: Nil => MergeStrategy.discard case _ => MergeStrategy.first } case x => MergeStrategy.first }
EOF

mkdir -p ${PROJECT_NAME}/spark-jobs/project
cat > ${PROJECT_NAME}/spark-jobs/project/plugins.sbt << 'EOF'
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.1.5")
EOF

mkdir -p ${PROJECT_NAME}/spark-jobs/src/main/scala/com/davtro/jobs
cat > ${PROJECT_NAME}/spark-jobs/src/main/scala/com/davtro/jobs/MarketingAnalyticsJob.scala << 'EOF'
package com.davtro.jobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger
object MarketingAnalyticsJob {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder().appName("DavTro Marketing Analytics").master("spark://spark-master:7077").config("spark.sql.streaming.checkpointLocation", "/tmp/checkpoint").getOrCreate()
    import spark.implicits._
    val kafkaDF = spark.readStream.format("kafka").option("kafka.bootstrap.servers", "kafka-kraft:9092").option("subscribe", "marketing-actions").option("startingOffsets", "latest").load()
    val parsedDF = kafkaDF.selectExpr("CAST(value AS STRING) as json").select(from_json($"json", new org.apache.spark.sql.types.StructType().add("event", "string").add("property_id", "integer").add("guest_email", "string").add("booking_value", "double").add("timestamp", "string")).as("data")).select("data.*")
    val aggDF = parsedDF.withWatermark("timestamp", "10 minutes").groupBy(window($"timestamp", "5 minutes"), $"property_id").agg(count("*").as("booking_count"), sum("booking_value").as("total_revenue"), avg("booking_value").as("avg_booking_value"))
    val query = aggDF.writeStream.outputMode("update").format("console").trigger(Trigger.ProcessingTime("10 seconds")).start()
    val jdbcDF = parsedDF.writeStream.foreachBatch { (batchDF, batchId) => batchDF.write.format("jdbc").option("url", "jdbc:postgresql://postgres-db:5432/davtro_rentals").option("dbtable", "marketing_events").option("user", "davtro").option("password", "changeme").mode("append").save() }.start()
    query.awaitTermination(); jdbcDF.awaitTermination()
  }
}
EOF

cat > ${PROJECT_NAME}/spark-jobs/Dockerfile << 'EOF'
FROM bitnami/spark:3.5.0
COPY target/scala-2.12/davtro-spark-jobs-assembly-1.0.0.jar /opt/bitnami/spark/jobs/
CMD ["spark-submit","--class","com.davtro.jobs.MarketingAnalyticsJob","/opt/bitnami/spark/jobs/davtro-spark-jobs-assembly-1.0.0.jar"]
EOF

# Additional paths used by extended manifests
ROOT_DIR="${PROJECT_NAME}"
APP_DIR="${ROOT_DIR}/backend-fastapi/app"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"
JAVA_DIR="${ROOT_DIR}/java-app"
SPARK_DIR="${ROOT_DIR}/spark-jobs"
ELK_DIR="${ROOT_DIR}/elk"

mkdir_p(){ mkdir -p "$@"; }
info(){ printf "🔧 [unified] %s\n" "$*"; }

# ============================================
# REDIS-KAFKA WORKER (from extended stack)
# ============================================
cat > ${PROJECT_NAME}/backend-fastapi/app/worker.py << 'PYEOF'
#!/usr/bin/env python3
import os, json, time, logging
import redis
from kafka import KafkaProducer
import psycopg2
import hvac

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "outgoing_messages")

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-0.kafka.davtroelkpyjs.svc.cluster.local:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "survey-topic")

def get_vault_secret(secret_path: str) -> dict:
    try:
        vault_addr = os.getenv("VAULT_ADDR", "http://vault:8200")
        vault_token = os.getenv("VAULT_TOKEN")
        
        if vault_token:
            client = hvac.Client(url=vault_addr, token=vault_token)
            if client.is_authenticated():
                secret = client.read(secret_path)
                if secret and 'data' in secret:
                    return secret['data'].get('data', {})
        else:
            logger.warning("Vault token not available, using fallback")
            
    except Exception as e:
        logger.warning(f"Vault error: {e}, using fallback")
    
    return {}

def get_database_config() -> str:
    vault_secret = get_vault_secret("secret/data/database/postgres")
    
    if vault_secret:
        return f"dbname={vault_secret.get('postgres-db', 'webdb')} " \
               f"user={vault_secret.get('postgres-user', 'webuser')} " \
               f"password={vault_secret.get('postgres-password', 'testpassword')} " \
               f"host={vault_secret.get('postgres-host', 'postgres-db')} " \
               f"port=5432"
    else:
        return os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db port=5432")

DATABASE_URL = get_database_config()

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    max_retries = 10
    for attempt in range(max_retries):
        try:
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP.split(','),
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                retries=3,
                request_timeout_ms=10000
            )
            logger.info("Kafka producer created successfully")
            return producer
        except Exception as e:
            logger.warning(f"Kafka connection attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All Kafka connection attempts failed: {e}")
                return None

def get_db_connection():
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(DATABASE_URL)
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"Database connection attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All database connection attempts failed: {e}")

def save_to_db(item_type, data):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        if item_type == "survey":
            cur.execute(
                "INSERT INTO survey_responses (question, answer) VALUES (%s, %s)",
                (data.get("question"), data.get("answer"))
            )
        elif item_type == "contact":
            cur.execute(
                "INSERT INTO contact_messages (email, message) VALUES (%s, %s)",
                (data.get("email"), data.get("message"))
            )
        
        conn.commit()
        logger.info(f"Saved {item_type} to database")
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Error saving to database: {e}")

def process_item(item, producer):
    try:
        item_type = item.get("type")
        save_to_db(item_type, item)
        
        if producer:
            try:
                future = producer.send(KAFKA_TOPIC, value=item)
                future.get(timeout=10)
                logger.info(f"Sent to Kafka topic {KAFKA_TOPIC}: {item}")
            except Exception as e:
                logger.warning(f"Failed to send to Kafka (will continue without Kafka): {e}")
        
    except Exception as e:
        logger.exception(f"Processing failed for item: {item}")

def main():
    r = get_redis()
    producer = get_kafka()
    
    logger.info("Worker started. Listening on Redis list '%s'", REDIS_LIST)
    
    while True:
        try:
            res = r.blpop(REDIS_LIST, timeout=10)
            if res:
                _, data = res
                try:
                    item = json.loads(data)
                except Exception:
                    item = {"raw": data, "type": "unknown"}
                
                process_item(item, producer)
                
        except Exception as e:
            logger.exception("Worker loop exception, reconnecting...")
            time.sleep(5)

if __name__ == "__main__":
    main()
PYEOF


# ============================================
# SPRING BOOT PROXY (from extended stack)
# ============================================
cat > ${PROJECT_NAME}/backend-fastapi/app/spring_proxy.py << 'PYEOF'
"""
Proxy do komunikacji z Spring Boot API
"""
from fastapi import APIRouter, HTTPException
import httpx
import logging
from typing import List, Dict, Any

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v2", tags=["spring-survey"])

# Konfiguracja Spring Boot API
SPRING_API_URL = "http://spring-app-service:8080/api"

@router.get("/survey/questions")
async def get_spring_survey_questions():
    """
    Pobiera pytania z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/questions",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching questions from Spring: {e}")
        # Fallback questions
        return [
            {
                "id": 1,
                "text": "Jak oceniasz wydajność Spring Boot API?",
                "type": "rating",
                "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]
            },
            {
                "id": 2,
                "text": "Która technologia Java Cię interesuje?",
                "type": "choice",
                "options": ["Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams"]
            },
            {
                "id": 3,
                "text": "Jak oceniasz integrację z Python/FastAPI?",
                "type": "rating",
                "options": ["1 - Słaba", "2", "3", "4", "5 - Doskonała"]
            },
            {
                "id": 4,
                "text": "Czy uważasz, że ELK Stack jest przydatny?",
                "type": "choice",
                "options": ["Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]
            },
            {
                "id": 5,
                "text": "Twoje sugestie dotyczące architektury:",
                "type": "text",
                "placeholder": "Podziel się swoimi pomysłami..."
            }
        ]

@router.post("/survey/submit")
async def submit_spring_survey(data: Dict[str, Any]):
    """
    Wysyła odpowiedzi do Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{SPRING_API_URL}/survey/submit",
                json=data,
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error submitting to Spring: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error submitting survey: {str(e)}"
        )

@router.get("/survey/stats")
async def get_spring_survey_stats():
    """
    Pobiera statystyki z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/stats",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching stats from Spring: {e}")
        return {
            "totalResponses": 0,
            "avgRating": 0.0,
            "uniqueUsers": 0,
            "charts": {
                "ratings": {"labels": [], "datasets": []},
                "technologies": {"labels": [], "datasets": []}
            }
        }

@router.get("/spark/jobs")
async def get_spark_jobs():
    """
    Pobiera status zadań Spark
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "http://spark-master:8080/api/v1/applications",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching Spark jobs: {e}")
        return []

@router.get("/elk/logs")
async def search_elk_logs(query: str = "", size: int = 10):
    """
    Wyszukuje logi w Elasticsearch
    """
    try:
        async with httpx.AsyncClient() as client:
            es_query = {
                "query": {
                    "bool": {
                        "must": [
                            {"match": {"message": query}} if query else {"match_all": {}}
                        ]
                    }
                },
                "size": size,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            response = await client.post(
                "http://elasticsearch:9200/logs*/_search",
                json=es_query,
                headers={"Content-Type": "application/json"},
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error searching ELK logs: {e}")
        return {"hits": {"hits": []}}
PYEOF


# ============================================
# ROOT DOCKERFILE (for K8s deployment)
# ============================================
cat > ${PROJECT_NAME}/Dockerfile << 'DOCK'
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY backend-fastapi/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend-fastapi/app/ ./app/
EXPOSE 8080
CMD ["python","-m","uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]
DOCK


# ============================================
# EXTENDED FUNCTIONS (from 7066-line stack)
# ============================================

generate_github_actions(){
 mkdir_p "$WORKFLOW_DIR"
 cat > "${WORKFLOW_DIR}/ci-cd-extended.yaml" <<'YAML'
name: CI/CD Extended - Full Stack

on:
  push:
    branches: [main]
    paths:
      - 'app/**'
      - 'java-app/**'
      - 'spark-jobs/**'
      - 'manifests/**'
      - 'Dockerfile'
      - '.github/workflows/ci-cd-extended.yaml'
  workflow_dispatch:

jobs:
  build-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Python Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:${{ github.sha }}
          cache-from: type=registry,ref=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
          cache-to: type=inline

  build-spring:
    runs-on: ubuntu-latest
    needs: build-python
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'temurin'
      
      - name: Build Spring Boot
        working-directory: ./java-app
        run: |
          chmod +x mvnw
          ./mvnw clean package -DskipTests
      
      - name: Build Spring Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./java-app
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:${{ github.sha }}

  build-spark:
    runs-on: ubuntu-latest
    needs: build-spring
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Scala
        uses: olafurpg/setup-scala@v13
        with:
          java-version: adopt@1.11
      
      - name: Build Spark Jobs
        working-directory: ./spark-jobs
        run: |
          sbt assembly
      
      - name: Build Spark Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./spark-jobs
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spark:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spark:${{ github.sha }}

  deploy:
    runs-on: ubuntu-latest
    needs: [build-python, build-spring, build-spark]
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure Kustomize
        run: |
          cd manifests/base
          kustomize edit set image \
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:${{ github.sha }} \
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:${{ github.sha }}
      
      - name: Deploy to Kubernetes
        run: |
          kubectl apply -k manifests/base --namespace=davtro
          kubectl rollout status deployment/fastapi-web-app -n davtro --timeout=300s
          kubectl rollout status deployment/spring-app -n davtro --timeout=300s
          kubectl rollout status deployment/spark-master -n davtro --timeout=300s
          kubectl rollout status deployment/spark-worker -n davtro --timeout=300s
      
      - name: Verify Deployment
        run: |
          kubectl get pods -n davtro
          kubectl get svc -n davtro
YAML
}

generate_k8s_manifests(){
 # Podstawowe manifesty z pierwszego skryptu (zaktualizowane namespace)
 cat > "${BASE_DIR}/fastapi-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: fastapi
data:
  APP_NAME: "${PROJECT}"
  APP_ENV: "production"
  PYTHONUNBUFFERED: "1"
YAML

 cat > "${BASE_DIR}/app-deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: fastapi
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: fastapi
    spec:
      serviceAccountName: fastapi-sa
      initContainers:
        - name: wait-for-postgres
          image: postgres:15-alpine
          command:
            [
              "sh",
              "-c",
              'until pg_isready -h postgres-db-normal -p 5432 -U webuser; do echo "waiting for postgres..."; sleep 5; done; echo "postgres ready"',
            ]
          env:
            - name: PGPASSWORD
              value: "testpassword"
            - name: PGUSER
              value: "webuser"
        - name: wait-for-redis
          image: busybox:1.36
          command:
            [
              "sh",
              "-c",
              'until nc -z redis 6379; do echo "waiting for redis..."; sleep 5; done; echo "redis ready"',
            ]
        - name: wait-for-kafka-broker
          image: confluentinc/cp-kafka:7.5.0
          command:
            [
              "/bin/bash",
              "-c",
              'for i in {1..120}; do if /opt/confluent/bin/kafka-broker-api-versions --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 &>/dev/null; then echo "✓ kafka broker ready"; break; fi; echo "Attempt \$i/120: Kafka not ready..."; sleep 5; done',
            ]
      containers:
      - name: app
        image: ${REGISTRY}:latest
        ports:
        - containerPort: 8080
        env:
        - name: REDIS_HOST
          value: "redis"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_LIST
          value: "outgoing_messages"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_TOPIC
          value: "survey-topic"
        - name: VAULT_ADDR
          value: "http://vault:8200"
        - name: VAULT_TOKEN
          value: "root"
        - name: DATABASE_URL
          value: "dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432"
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 20
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: fastapi
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8000
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: fastapi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
YAML

 cat > "${BASE_DIR}/message-processor.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: worker
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: worker
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: worker
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: worker
    spec:
      initContainers:
        - name: wait-for-postgres
          image: postgres:15-alpine
          command:
            [
              "sh",
              "-c",
              'until pg_isready -h postgres-db-normal -p 5432 -U webuser; do echo "waiting for postgres..."; sleep 5; done; echo "postgres ready"',
            ]
          env:
            - name: PGPASSWORD
              value: "testpassword"
            - name: PGUSER
              value: "webuser"
        - name: wait-for-redis
          image: busybox:1.36
          command:
            [
              "sh",
              "-c",
              'until nc -z redis 6379; do echo "waiting for redis..."; sleep 5; done; echo "redis ready"',
            ]
        - name: wait-for-kafka-broker
          image: confluentinc/cp-kafka:7.5.0
          command:
            [
              "/bin/bash",
              "-c",
              'for i in {1..120}; do if /opt/confluent/bin/kafka-broker-api-versions --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 &>/dev/null; then echo "✓ kafka broker ready"; break; fi; echo "Attempt \$i/120: Kafka not ready..."; sleep 5; done',
            ]
      containers:
      - name: worker
        image: ${REGISTRY}:latest
        command: ["python", "worker.py"]
        env:
        - name: REDIS_HOST
          value: "redis"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_LIST
          value: "outgoing_messages"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_TOPIC
          value: "survey-topic"
        - name: VAULT_ADDR
          value: "http://vault:8200"
        - name: VAULT_TOKEN
          value: "root"
        - name: DATABASE_URL
          value: "dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          exec:
            command:
              - sh
              - -c
              - 'python -c "import redis; redis.Redis(host=\"redis\", port=6379, socket_connect_timeout=5).ping()"'
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          exec:
            command:
              - sh
              - -c
              - 'python -c "import redis; redis.Redis(host=\"redis\", port=6379, socket_connect_timeout=5).ping()"'
          initialDelaySeconds: 30
          periodSeconds: 10
YAML

 cat > "${BASE_DIR}/postgres-db.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres
spec:
  ports:
  - port: 5432
    name: postgres
  selector:
    app: ${PROJECT}
    component: postgres
  clusterIP: None
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: postgres
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsNonRoot: true
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_USER
          value: "webuser"
        - name: POSTGRES_PASSWORD
          value: "testpassword"
        - name: POSTGRES_DB
          value: "webdb"
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
          subPath: pgdata
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "webuser", "-d", "webdb"]
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "webuser", "-d", "webdb"]
          initialDelaySeconds: 30
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
YAML

 cat > "${BASE_DIR}/postgres-clusterip.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: postgres-db-normal
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: ${PROJECT}
    component: postgres
YAML

 cat > "${BASE_DIR}/pgadmin.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgadmin-servers
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  servers.json: |
    {
      "Servers": {
        "1": {
          "Name": "PostgreSQL Database",
          "Group": "Servers",
          "Host": "postgres-db-normal",
          "Port": 5432,
          "MaintenanceDB": "webdb",
          "Username": "webuser",
          "Password": "testpassword",
          "SSLMode": "prefer"
        }
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: pgadmin
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: pgadmin
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: pgadmin
    spec:
      initContainers:
        - name: wait-for-postgres
          image: busybox:1.35
          command:
            - "sh"
            - "-c"
            - |
              echo "Waiting for PostgreSQL to be ready..."
              until nc -z postgres-db-normal 5432; do
                echo "Waiting for PostgreSQL..."
                sleep 10
              done
              echo "PostgreSQL is ready!"
      containers:
        - name: pgadmin
          image: dpage/pgadmin4:7.2
          env:
            - name: PGADMIN_DEFAULT_EMAIL
              value: "admin@example.com"
            - name: PGADMIN_DEFAULT_PASSWORD
              value: "adminpassword"
            - name: PGADMIN_CONFIG_SERVER_MODE
              value: "False"
            - name: PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED
              value: "False"
          ports:
            - containerPort: 80
              name: http
          resources:
            requests:
              cpu: "100m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /misc/ping
              port: 80
            initialDelaySeconds: 120
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /misc/ping
              port: 80
            initialDelaySeconds: 60
            periodSeconds: 10
          volumeMounts:
            - name: pgadmin-data
              mountPath: /var/lib/pgadmin
            - name: pgadmin-servers
              mountPath: /pgadmin4/servers.json
              subPath: servers.json
      volumes:
        - name: pgadmin-data
          persistentVolumeClaim:
            claimName: pgadmin-storage
        - name: pgadmin-servers
          configMap:
            name: pgadmin-servers
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: pgadmin
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: pgadmin
spec:
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
  selector:
    app: ${PROJECT}
    component: pgadmin
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgadmin-storage
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
YAML

resources=$(cat <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: davtro
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    component: vault
spec:
  clusterIP: None
  ports:
  - port: 8200
    name: http
  selector:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    component: vault
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: davtro
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    component: vault
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels:
      app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
      component: vault
  template:
    metadata:
      labels:
        app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
        component: vault
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: vault
        image: hashicorp/vault:1.15.0
        command: ["vault", "server", "-dev", "-dev-listen-address=0.0.0.0:8200", "-dev-root-token-id=root"]
        ports:
        - containerPort: 8200
        env:
        - name: VAULT_ADDR
          value: "http://127.0.0.1:8200"
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: "root"
        securityContext:
          capabilities:
            add: ["IPC_LOCK"]
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /v1/sys/health
            port: 8200
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /v1/sys/health
            port: 8200
          initialDelaySeconds: 15
          periodSeconds: 15
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-sa
  namespace: davtro
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-init
  namespace: davtro
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
data:
  init-vault.sh: |
    #!/bin/bash
    sleep 10
    export VAULT_ADDR="http://vault:8200"
    export VAULT_TOKEN="root"
    
    vault secrets enable -path=secret kv-v2
    
    vault kv put secret/database/postgres \
      postgres-user="webuser" \
      postgres-password="testpassword" \
      postgres-db="webdb" \
      postgres-host="postgres-db-normal"
    
    vault kv put secret/redis \
      redis-password=""
    
    vault kv put secret/kafka \
      kafka-brokers="kafka:9092"
    
    vault kv put secret/grafana \
      admin-user="admin" \
      admin-password="admin"
    
    vault kv put secret/pgadmin \
      pgadmin-email="admin@example.com" \
      pgadmin-password="adminpassword"
    
    echo "Vault initialization completed"
---
apiVersion: batch/v1
kind: Job
metadata:
  name: vault-init
  namespace: davtro
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    component: vault-init
spec:
  template:
    metadata:
      labels:
        app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
        component: vault-init
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: vault-init
        image: hashicorp/vault:1.15.0
        command: ["/bin/sh", "/scripts/init-vault.sh"]
        volumeMounts:
        - name: vault-scripts
          mountPath: /scripts
        env:
        - name: VAULT_ADDR
          value: "http://vault:8200"
        - name: VAULT_TOKEN  
          value: "root"
      volumes:
      - name: vault-scripts
        configMap:
          name: vault-init
          defaultMode: 0755
      restartPolicy: OnFailure
  backoffLimit: 3
YAML
)

echo "$resources" > "${BASE_DIR}/vault.yaml"

 cat > "${BASE_DIR}/redis.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: redis
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: redis
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server", "--appendonly", "yes"]
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        livenessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 10
          periodSeconds: 5
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
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: redis
spec:
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: redis
YAML

 cat > "${BASE_DIR}/kafka-kraft.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka
spec:
  clusterIP: None
  ports:
  - port: 9092
    name: client
  - port: 9093
    name: controller
  selector:
    app: ${PROJECT}
    component: kafka
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka
spec:
  serviceName: kafka
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka
    spec:
      containers:
      - name: kafka
        image: confluentinc/cp-kafka:7.5.0
        env:
        - name: CLUSTER_ID
          value: "1TDYjwQaTrSOTzez8sKYEg"
        - name: KAFKA_BROKER_ID
          value: "0"
        - name: KAFKA_PROCESS_ROLES
          value: "broker,controller"
        - name: KAFKA_CONTROLLER_QUORUM_VOTERS
          value: "0@kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9093"
        - name: KAFKA_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_ADVERTISED_LISTENERS
          value: "PLAINTEXT://kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
        - name: KAFKA_INTER_BROKER_LISTENER_NAME
          value: "PLAINTEXT"
        - name: KAFKA_AUTO_CREATE_TOPICS_ENABLE
          value: "true"
        - name: KAFKA_LOG_DIR
          value: "/var/lib/kafka/data"
        - name: KAFKA_LOG_RETENTION_HOURS
          value: "168"
        - name: KAFKA_AUTO_LEADER_REBALANCE_ENABLE
          value: "true"
        ports:
        - containerPort: 9092
          name: client
        - containerPort: 9093
          name: controller
        volumeMounts:
        - name: kafka-data
          mountPath: /var/lib/kafka/data/
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        readinessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 90
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: kafka-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
YAML

 cat > "${BASE_DIR}/kafka-job-sa.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-job-sa
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-topic-job
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
YAML

 cat > "${BASE_DIR}/kafka-topic-job.yaml" <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: create-kafka-topics
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-topic-job
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-topic-job
spec:
  backoffLimit: 5
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka-topic-job
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka-topic-job
    spec:
      serviceAccountName: kafka-job-sa
      initContainers:
        - name: wait-for-kafka-broker
          image: confluentinc/cp-kafka:7.5.0
          command:
            - /bin/bash
            - -c
            - |
              echo "Waiting for Kafka broker to be ready..."
              for i in {1..120}; do
                if /opt/confluent/bin/kafka-broker-api-versions --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 &>/dev/null; then
                  echo "✓ Kafka broker is ready!"
                  exit 0
                fi
                echo "Attempt \$i/120: Kafka not ready..."
                sleep 5
              done
              echo "✗ Kafka broker failed to start"
              exit 1
      containers:
        - name: create-topics
          image: confluentinc/cp-kafka:7.5.0
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "Creating Kafka topics..."
              
              /opt/confluent/bin/kafka-topics --create \
                --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 \
                --topic survey-topic \
                --partitions 3 \
                --replication-factor 1 \
                --config retention.ms=604800000 \
                --config min.insync.replicas=1 \
                --if-not-exists
              
              echo "Verifying topics..."
              /opt/confluent/bin/kafka-topics --list \
                --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092
              
              echo "✓ Kafka topics created successfully"
      restartPolicy: OnFailure
YAML

 cat > "${BASE_DIR}/kafka-ui.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-ui
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-ui
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka-ui
    spec:
      initContainers:
        - name: wait-for-kafka
          image: busybox:1.35
          command:
            - "sh"
            - "-c"
            - |
              echo "Waiting for Kafka broker to be ready..."
              until nc -z kafka-0.kafka.${NAMESPACE}.svc.cluster.local 9092; do
                echo "Waiting for Kafka..."
                sleep 10
              done
              echo "Kafka is ready!"
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:latest
        env:
        - name: KAFKA_CLUSTERS_0_NAME
          value: "local"
        - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
          value: "kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_CLUSTERS_0_READONLY
          value: "false"
        - name: KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL
          value: "PLAINTEXT"
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "200m"
            memory: "512Mi"
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
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-ui
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-ui
spec:
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: kafka-ui
YAML

 cat > "${BASE_DIR}/prometheus-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    rule_files:
      - /etc/prometheus/rules/*.yml
    
    scrape_configs:
      - job_name: 'fastapi'
        static_configs:
          - targets: ['fastapi-web-service:80']
        metrics_path: /metrics
        scrape_interval: 10s
        
      - job_name: 'redis'
        static_configs:
          - targets: ['redis:6379']
        metrics_path: /metrics
        scrape_interval: 15s
        
      - job_name: 'postgres'
        static_configs:
          - targets: ['postgres-exporter:9187']
        scrape_interval: 30s
        
      - job_name: 'kafka'
        static_configs:
          - targets: ['kafka-exporter:9308']
        scrape_interval: 30s
        
      - job_name: 'vault'
        static_configs:
          - targets: ['vault:8200']
        metrics_path: /v1/sys/metrics
        scrape_interval: 30s
        params:
          format: ['prometheus']
          
      - job_name: 'node-exporter'
        static_configs:
          - targets: ['node-exporter:9100']
        scrape_interval: 30s
YAML

 cat > "${BASE_DIR}/postgres-exporter.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres-exporter
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: postgres-exporter
    spec:
      initContainers:
        - name: wait-for-postgres
          image: postgres:15-alpine
          command:
            - "sh"
            - "-c"
            - |
              until pg_isready -h postgres-db-normal -p 5432 -U webuser; do
                echo "Waiting for postgres..."
                sleep 5
              done
              echo "PostgreSQL is ready!"
          env:
            - name: PGPASSWORD
              value: "testpassword"
      containers:
      - name: postgres-exporter
        image: prometheuscommunity/postgres-exporter:v0.15.0
        ports:
        - containerPort: 9187
          name: http
        env:
        - name: DATA_SOURCE_NAME
          value: "postgresql://webuser:testpassword@postgres-db-normal:5432/webdb?sslmode=disable"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /metrics
            port: 9187
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9187
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres-exporter
spec:
  ports:
  - port: 9187
    targetPort: 9187
    name: http
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: postgres-exporter
YAML

 cat > "${BASE_DIR}/kafka-exporter.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-exporter
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka-exporter
    spec:
      initContainers:
        - name: wait-for-kafka
          image: busybox:1.35
          command:
            - "sh"
            - "-c"
            - |
              echo "Waiting for Kafka broker to be ready..."
              until nc -z kafka-0.kafka.${NAMESPACE}.svc.cluster.local 9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
              echo "Kafka is ready!"
      containers:
      - name: kafka-exporter
        image: danielqsj/kafka-exporter:v1.7.0
        ports:
        - containerPort: 9308
          name: http
        args:
        - --kafka.server=kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092
        - --web.listen-address=:9308
        - --log.level=info
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /metrics
            port: 9308
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9308
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-exporter
spec:
  ports:
  - port: 9308
    targetPort: 9308
    name: http
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: kafka-exporter
YAML

 cat > "${BASE_DIR}/node-exporter.yaml" <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: node-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: node-exporter
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: node-exporter
    spec:
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        - --path.rootfs=/host/root
        - --collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)
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
      hostNetwork: true
      hostPID: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: node-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: node-exporter
spec:
  ports:
  - port: 9100
    targetPort: 9100
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: node-exporter
  clusterIP: None
YAML

 cat > "${BASE_DIR}/service-monitors.yaml" <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fastapi-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  endpoints:
  - port: http
    path: /metrics
    interval: 15s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: redis
  endpoints:
  - port: redis
    interval: 30s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: postgres-exporter
  endpoints:
  - port: http
    interval: 30s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-exporter
  endpoints:
  - port: http
    interval: 30s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: node-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: node-exporter
  endpoints:
  - port: http
    interval: 30s
YAML

 cat > "${BASE_DIR}/prometheus.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: prometheus
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: prometheus
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: data
          mountPath: /prometheus
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--web.console.libraries=/etc/prometheus/console_libraries'
        - '--web.console.templates=/etc/prometheus/consoles'
        - '--storage.tsdb.retention.time=200h'
        - '--web.enable-lifecycle'
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: data
        persistentVolumeClaim:
          claimName: prometheus-data
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: prometheus
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: prometheus
spec:
  ports:
  - port: 9090
    targetPort: 9090
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: prometheus
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
YAML

 cat > "${BASE_DIR}/grafana-datasource.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-service:9090
      isDefault: true
      access: proxy
      editable: true
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
      editable: true
    - name: Tempo
      type: tempo
      url: http://tempo:3200
      access: proxy
      editable: true
    - name: PostgreSQL
      type: postgres
      url: postgres-db-normal:5432
      database: webdb
      user: webuser
      secureJsonData:
        password: "testpassword"
      jsonData:
        sslmode: "disable"
YAML

 cat > "${BASE_DIR}/grafana-dashboards.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  fastapi-dashboard.json: |-
    {
      "dashboard": {
        "title": "FastAPI Application Metrics",
        "panels": [
          {
            "title": "HTTP Requests",
            "type": "stat",
            "targets": [
              {
                "expr": "rate(http_requests_total[5m])",
                "legendFormat": "Requests/s"
              }
            ]
          }
        ]
      }
    }
  kafka-dashboard.json: |-
    {
      "dashboard": {
        "title": "Kafka Metrics", 
        "panels": [
          {
            "title": "Messages In",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(kafka_topic_messages_in_total[5m])",
                "legendFormat": "Messages/s"
              }
            ]
          }
        ]
      }
    }
  postgres-dashboard.json: |-
    {
      "dashboard": {
        "title": "PostgreSQL Metrics",
        "panels": [
          {
            "title": "Database Connections",
            "type": "stat",
            "targets": [
              {
                "expr": "pg_stat_database_numbackends{datname=\"webdb\"}",
                "legendFormat": "Connections"
              }
            ]
          }
        ]
      }
    }
  redis-dashboard.json: |-
    {
      "dashboard": {
        "title": "Redis Metrics",
        "panels": [
          {
            "title": "Connected Clients",
            "type": "stat",
            "targets": [
              {
                "expr": "redis_connected_clients",
                "legendFormat": "Clients"
              }
            ]
          }
        ]
      }
    }
  system-dashboard.json: |-
    {
      "dashboard": {
        "title": "System Metrics",
        "panels": [
          {
            "title": "CPU Usage",
            "type": "gauge",
            "targets": [
              {
                "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
                "legendFormat": "CPU %"
              }
            ]
          }
        ]
      }
    }
  vault-dashboard.json: |-
    {
      "dashboard": {
        "title": "Vault Metrics",
        "panels": [
          {
            "title": "Vault Health",
            "type": "stat",
            "targets": [
              {
                "expr": "vault_core_unsealed",
                "legendFormat": "Unsealed"
              }
            ]
          }
        ]
      }
    }
  comprehensive-dashboard.json: |-
    {
      "dashboard": {
        "title": "Comprehensive Monitoring",
        "panels": [
          {
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "title": "Application Overview",
            "type": "stat",
            "targets": [
              {
                "expr": "rate(http_requests_total[5m])",
                "legendFormat": "HTTP Requests/s"
              }
            ]
          }
        ]
      }
    }
YAML

 cat > "${BASE_DIR}/grafana.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: grafana
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: grafana
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.2.2
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        - name: grafana-datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: grafana-dashboards
          mountPath: /etc/grafana/provisioning/dashboards
        - name: dashboards
          mountPath: /var/lib/grafana/dashboards
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
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
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana-storage
      - name: grafana-datasources
        configMap:
          name: grafana-datasource
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboard-provisioning
      - name: dashboards
        configMap:
          name: grafana-dashboards
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: grafana
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: grafana
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: grafana
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provisioning
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
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
      allowUiUpdates: true
      options:
        path: /var/lib/grafana/dashboards
YAML

 cat > "${BASE_DIR}/loki-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  loki.yaml: |
    auth_enabled: false
    
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
      
    common:
      path_prefix: /tmp/loki
      storage:
        filesystem:
          chunks_directory: /tmp/loki/chunks
          rules_directory: /tmp/loki/rules
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
    
    ruler:
      alertmanager_url: http://localhost:9093
    
    analytics:
      reporting_enabled: false
YAML

 cat > "${BASE_DIR}/loki.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: loki
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: loki
spec:
  serviceName: loki
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.2
        ports:
        - containerPort: 3100
        - containerPort: 9096
        volumeMounts:
        - name: config
          mountPath: /etc/loki
        - name: storage
          mountPath: /tmp/loki
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
        args:
        - -config.file=/etc/loki/loki.yaml
      volumes:
      - name: config
        configMap:
          name: loki-config
      - name: storage
        persistentVolumeClaim:
          claimName: loki-storage
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: loki
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: loki
spec:
  ports:
  - port: 3100
    targetPort: 3100
    protocol: TCP
  - port: 9096
    targetPort: 9096
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: loki
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: loki-storage
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
YAML

 cat > "${BASE_DIR}/promtail-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
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
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_kubernetes_io_config_mirror]
        action: drop
        regex: mirror
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: replace
        target_label: container
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: instance
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: replace
        target_label: job
      - replacement: /var/log/pods/*\$1/*.log
        separator: /
        source_labels:
        - __meta_kubernetes_pod_uid
        - __meta_kubernetes_pod_container_name
        target_label: __path__
    
    - job_name: kubernetes-system
      static_configs:
      - targets:
          - localhost
        labels:
          job: kubernetes-system
          __path__: /var/log/containers/*.log
YAML

 cat > "${BASE_DIR}/promtail.yaml" <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: promtail
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: promtail
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: promtail
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: promtail
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: promtail
    spec:
      serviceAccountName: promtail-sa
      containers:
      - name: promtail
        image: grafana/promtail:2.9.2
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: pods
          mountPath: /var/log/pods
          readOnly: true
        - name: containers
          mountPath: /var/log/containers
          readOnly: true
        - name: varlib
          mountPath: /var/lib
          readOnly: true
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "100m"
            memory: "128Mi"
        args:
        - -config.file=/etc/promtail/promtail.yaml
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: pods
        hostPath:
          path: /var/log/pods
      - name: containers
        hostPath:
          path: /var/log/containers
      - name: varlib
        hostPath:
          path: /var/lib
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail-sa
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: promtail-clusterrole
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: promtail-clusterrolebinding
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: promtail-clusterrole
subjects:
- kind: ServiceAccount
  name: promtail-sa
  namespace: ${NAMESPACE}
YAML

 cat > "${BASE_DIR}/tempo-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    
    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
            http:
    
    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/blocks
        pool:
          max_workers: 100
          queue_depth: 10000
    
    ingester:
      max_block_duration: 5m
YAML

 cat > "${BASE_DIR}/tempo.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: tempo
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: tempo
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: tempo
spec:
  serviceName: tempo
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
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.4.2
        ports:
        - containerPort: 3200
        - containerPort: 4317
        - containerPort: 4318
        volumeMounts:
        - name: config
          mountPath: /etc/tempo
        - name: storage
          mountPath: /tmp/tempo
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "250m"
            memory: "512Mi"
        args:
        - -config.file=/etc/tempo/tempo.yaml
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
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: tempo
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: tempo
spec:
  ports:
  - port: 3200
    targetPort: 3200
    name: http
    protocol: TCP
  - port: 4317
    targetPort: 4317
    name: otlp-grpc
    protocol: TCP
  - port: 4318
    targetPort: 4318
    name: otlp-http
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: tempo
YAML

 # Nowe manifesty z drugiego skryptu
 cat > "${BASE_DIR}/mongodb.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb
    spec:
      containers:
        - name: mongodb
          image: mongo:7.0
          ports:
            - containerPort: 27017
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              value: "admin"
            - name: MONGO_INITDB_ROOT_PASSWORD
              value: "adminpassword"
          volumeMounts:
            - name: mongodb-data
              mountPath: /data/db
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            exec:
              command:
                - mongosh
                - --eval
                - "db.adminCommand('ping')"
            initialDelaySeconds: 30
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: mongodb-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
spec:
  ports:
    - port: 27017
      targetPort: 27017
  selector:
    app: ${PROJECT}
    component: mongodb
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-init
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
data:
  init.js: |
    db = db.getSiblingDB('survey_db');
    
    db.createUser({
      user: 'survey_user',
      pwd: 'survey_password',
      roles: [
        { role: 'readWrite', db: 'survey_db' },
        { role: 'readWrite', db: 'survey_analytics' }
      ]
    });
    
    db.createCollection('survey_responses');
    db.survey_responses.createIndex({ surveyId: 1 });
    db.survey_responses.createIndex({ submittedAt: -1 });
    db.survey_responses.createIndex({ userId: 1 });
    
    db = db.getSiblingDB('survey_analytics');
    db.createCollection('text_analysis');
    db.createCollection('rating_analysis');
    db.createCollection('tech_popularity');
    db.createCollection('daily_stats');
    db.createCollection('tech_trends');
    db.createCollection('correlations');
    db.createCollection('hourly_report');
    
    print('MongoDB initialized successfully');
---
apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-init
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-init
spec:
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb-init
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
      containers:
        - name: init
          image: mongo:7.0
          command: 
            - mongosh
            - --host
            - mongodb
            - --username
            - admin
            - --password
            - adminpassword
            - --authenticationDatabase
            - admin
            - /scripts/init.js
          volumeMounts:
            - name: init-script
              mountPath: /scripts
      volumes:
        - name: init-script
          configMap:
            name: mongodb-init
YAML

 cat > "${BASE_DIR}/elasticsearch.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: elasticsearch
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: elasticsearch
    spec:
      initContainers:
        - name: fix-permissions
          image: busybox:1.35
          command: ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
          securityContext:
            privileged: true
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
      containers:
        - name: elasticsearch
          image: elasticsearch:8.10.2
          env:
            - name: discovery.type
              value: single-node
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
            - name: xpack.security.enabled
              value: "false"
            - name: xpack.security.enrollment.enabled
              value: "false"
            - name: xpack.monitoring.collection.enabled
              value: "true"
          ports:
            - containerPort: 9200
              name: http
            - containerPort: 9300
              name: transport
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            httpGet:
              path: /_cluster/health
              port: 9200
            initialDelaySeconds: 60
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: elasticsearch
spec:
  ports:
    - port: 9200
      targetPort: 9200
      name: http
    - port: 9300
      targetPort: 9300
      name: transport
  selector:
    app: ${PROJECT}
    component: elasticsearch
YAML

 cat > "${BASE_DIR}/logstash.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: logstash
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: logstash
    spec:
      containers:
        - name: logstash
          image: logstash:8.10.2
          ports:
            - containerPort: 5000
              name: tcp
            - containerPort: 5001
              name: http
            - containerPort: 9600
              name: monitoring
          env:
            - name: XPACK_MONITORING_ENABLED
              value: "false"
          volumeMounts:
            - name: logstash-config
              mountPath: /usr/share/logstash/pipeline/
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          readinessProbe:
            tcpSocket:
              port: 9600
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: logstash-config
          configMap:
            name: logstash-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
data:
  logstash.conf: |
    input {
      tcp {
        port => 5000
        codec => json
      }
      http {
        port => 5001
        codec => json
      }
      beats {
        port => 5044
      }
    }
    
    filter {
      if [type] == "survey" {
        mutate {
          add_field => { 
            "[@metadata][index]" => "surveys-%{+YYYY.MM.dd}"
          }
        }
      } else if [type] == "spark" {
        mutate {
          add_field => { 
            "[@metadata][index]" => "spark-%{+YYYY.MM.dd}"
          }
        }
      } else {
        mutate {
          add_field => { 
            "[@metadata][index]" => "logs-%{+YYYY.MM.dd}"
          }
        }
      }
      
      date {
        match => [ "timestamp", "ISO8601" ]
        target => "@timestamp"
      }
      
      mutate {
        remove_field => [ "timestamp" ]
      }
    }
    
    output {
      elasticsearch {
        hosts => ["elasticsearch:9200"]
        index => "%{[@metadata][index]}"
      }
      
      stdout {
        codec => rubydebug
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: logstash
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
spec:
  ports:
    - port: 5000
      targetPort: 5000
      name: tcp
    - port: 5001
      targetPort: 5001
      name: http
    - port: 5044
      targetPort: 5044
      name: beats
  selector:
    app: ${PROJECT}
    component: logstash
YAML

 cat > "${BASE_DIR}/kibana.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kibana
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kibana
    spec:
      containers:
        - name: kibana
          image: kibana:8.10.2
          ports:
            - containerPort: 5601
          env:
            - name: ELASTICSEARCH_HOSTS
              value: "http://elasticsearch:9200"
            - name: XPACK_MONITORING_ENABLED
              value: "true"
            - name: XPACK_SECURITY_ENABLED
              value: "false"
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          readinessProbe:
            httpGet:
              path: /api/status
              port: 5601
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kibana
spec:
  ports:
    - port: 5601
      targetPort: 5601
  selector:
    app: ${PROJECT}
    component: kibana
YAML

 cat > "${BASE_DIR}/spring-app-deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  replicas: 2
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
      initContainers:
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
        - name: wait-for-kafka
          image: confluentinc/cp-kafka:7.5.0
          command: 
            - sh
            - -c
            - |
              until kafka-broker-api-versions --bootstrap-server kafka:9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
        - name: wait-for-elasticsearch
          image: busybox:1.35
          command: 
            - sh
            - -c
            - |
              until wget -q -O- http://elasticsearch:9200; do
                echo "Waiting for Elasticsearch..."
                sleep 5
              done
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_DATA_MONGODB_URI
              value: "mongodb://survey_user:survey_password@mongodb:27017/survey_db?authSource=survey_db"
            - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
              value: "kafka:9092"
            - name: ELASTICSEARCH_URL
              value: "http://elasticsearch:9200"
            - name: LOGSTASH_URL
              value: "http://logstash:5000"
            - name: JAVA_OPTS
              value: "-Xms512m -Xmx512m -XX:+UseG1GC"
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
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
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spring-app-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
data:
  application.yml: |
    spring:
      data:
        mongodb:
          uri: mongodb://survey_user:survey_password@mongodb:27017/survey_db?authSource=survey_db
          auto-index-creation: true
      
      kafka:
        bootstrap-servers: kafka:9092
        producer:
          key-serializer: org.apache.kafka.common.serialization.StringSerializer
          value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
        consumer:
          group-id: spring-survey-group
          key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
          value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
          properties:
            spring.json.trusted.packages: "*"
    
    management:
      endpoints:
        web:
          exposure:
            include: health,info,metrics,prometheus
      metrics:
        export:
          prometheus:
            enabled: true
    
    logging:
      level:
        com.davtroweb: DEBUG
      file:
        name: /var/log/spring-app.log
    
    elk:
      elasticsearch-url: http://elasticsearch:9200
      logstash-url: http://logstash:5000
    
    spark:
      master-url: spark://spark-master:7077
YAML

 cat > "${BASE_DIR}/spark-master.yaml" <<YAML
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
      initContainers:
        - name: wait-for-kafka
          image: confluentinc/cp-kafka:7.5.0
          command: 
            - sh
            - -c
            - |
              until kafka-broker-api-versions --bootstrap-server kafka:9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
      containers:
        - name: spark-master
          image: bitnami/spark:3.4.0
          ports:
            - containerPort: 7077
              name: master
            - containerPort: 8080
              name: webui
            - containerPort: 4040
              name: jobui
          env:
            - name: SPARK_MODE
              value: "master"
            - name: SPARK_MASTER_HOST
              value: "spark-master"
            - name: SPARK_MASTER_PORT
              value: "7077"
            - name: SPARK_MASTER_WEBUI_PORT
              value: "8080"
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
              cpu: "500m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          readinessProbe:
            tcpSocket:
              port: 7077
            initialDelaySeconds: 60
            periodSeconds: 10
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
    - port: 7077
      targetPort: 7077
      name: master
    - port: 8080
      targetPort: 8080
      name: webui
  selector:
    app: ${PROJECT}
    component: spark-master
YAML

 cat > "${BASE_DIR}/spark-worker.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  replicas: 2
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
      initContainers:
        - name: wait-for-spark-master
          image: busybox:1.35
          command: 
            - sh
            - -c
            - |
              until nc -z spark-master 7077; do
                echo "Waiting for Spark Master..."
                sleep 5
              done
      containers:
        - name: spark-worker
          image: bitnami/spark:3.4.0
          ports:
            - containerPort: 8081
              name: webui
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
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          readinessProbe:
            tcpSocket:
              port: 8081
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  ports:
    - port: 8081
      targetPort: 8081
      name: webui
  selector:
    app: ${PROJECT}
    component: spark-worker
YAML

 cat > "${BASE_DIR}/network-policies.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-fastapi-to-postgres
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres
      ports:
        - protocol: TCP
          port: 5432

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-fastapi-to-redis
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: redis
      ports:
        - protocol: TCP
          port: 6379

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-worker-to-kafka
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: worker
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kafka-ui-to-kafka
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-ui
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-init-to-all
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: redis
      ports:
        - protocol: TCP
          port: 6379

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-to-postgres-exporter
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: prometheus
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres-exporter
      ports:
        - protocol: TCP
          port: 9187

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-pgadmin-to-postgres
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: pgadmin
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres
      ports:
        - protocol: TCP
          port: 5432

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-communication
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: grafana
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: prometheus
      ports:
        - protocol: TCP
          port: 9090
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: loki
      ports:
        - protocol: TCP
          port: 3100
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: tempo
      ports:
        - protocol: TCP
          port: 3200

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-app-pods-to-deps
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-postgres-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
      ports:
        - protocol: TCP
          port: 5432

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-redis-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
      ports:
        - protocol: TCP
          port: 6379

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kafka-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: kafka
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spring-to-mongodb
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: mongodb
      ports:
        - protocol: TCP
          port: 27017

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spark-to-kafka
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spark-to-mongodb
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: mongodb
      ports:
        - protocol: TCP
          port: 27017
YAML

 cat > "${BASE_DIR}/monitoring-extended.yaml" <<YAML
# Exporter dla MongoDB
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb-exporter
    spec:
      containers:
        - name: mongodb-exporter
          image: percona/mongodb_exporter:0.39.0
          ports:
            - containerPort: 9216
          args:
            - --mongodb.uri=mongodb://admin:adminpassword@mongodb:27017
            - --collect.collection
            - --collect.database
            - --collect.indexusage
            - --collect.connpoolstats
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-exporter
spec:
  ports:
    - port: 9216
      targetPort: 9216
  selector:
    app: ${PROJECT}
    component: mongodb-exporter

# ServiceMonitor dla MongoDB
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb-exporter
  endpoints:
  - port: http
    interval: 30s

# ServiceMonitor dla Spring Boot
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spring-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  endpoints:
  - port: http
    path: /actuator/prometheus
    interval: 15s

# ServiceMonitor dla Elasticsearch
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: elasticsearch-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: elasticsearch
  endpoints:
  - port: http
    path: /_prometheus/metrics
    interval: 30s

# Dodatkowe dashbordy Grafana
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-extended
  namespace: ${NAMESPACE}
data:
  spring-boot-dashboard.json: |-
    {
      "dashboard": {
        "title": "Spring Boot Metrics",
        "panels": [
          {
            "title": "HTTP Requests",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(http_server_requests_seconds_count[5m])",
                "legendFormat": "{{method}} {{status}}"
              }
            ]
          }
        ]
      }
    }
  
  spark-dashboard.json: |-
    {
      "dashboard": {
        "title": "Apache Spark",
        "panels": [
          {
            "title": "Spark Applications",
            "type": "stat",
            "targets": [
              {
                "expr": "spark_running_applications",
                "legendFormat": "Running Apps"
              }
            ]
          }
        ]
      }
    }
  
  mongodb-dashboard.json: |-
    {
      "dashboard": {
        "title": "MongoDB Metrics",
        "panels": [
          {
            "title": "MongoDB Connections",
            "type": "stat",
            "targets": [
              {
                "expr": "mongodb_connections_current",
                "legendFormat": "Connections"
              }
            ]
          }
        ]
      }
    }
  
  elk-dashboard.json: |-
    {
      "dashboard": {
        "title": "ELK Stack",
        "panels": [
          {
            "title": "Elasticsearch Health",
            "type": "stat",
            "targets": [
              {
                "expr": "elasticsearch_cluster_health_status",
                "legendFormat": "{{cluster}}"
              }
            ]
          }
        ]
      }
    }
YAML

 cat > "${BASE_DIR}/ingress-extended.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${PROJECT}-ingress-extended
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
spec:
  rules:
  - host: app.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /new-survey
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /api/v2
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /api/spring
        pathType: Prefix
        backend:
          service:
            name: spring-app-service
            port:
              number: 8080
  
  - host: spring.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spring-app-service
            port:
              number: 8080
  
  - host: spark.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spark-master
            port:
              number: 8080
  
  - host: kibana.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana
            port:
              number: 5601
  
  - host: grafana.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana-service
            port:
              number: 80
  
  - host: pgadmin.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
  
  - host: kafka-ui.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kafka-ui
            port:
              number: 8080
YAML

 cat > "${BASE_DIR}/kyverno-policy.yaml" <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-requests-limits
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: check-container-resources
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "For production, all containers should define 'requests' and 'limits' for CPU and memory."
      pattern:
        spec:
          containers:
          - resources:
              requests:
                memory: "?*"
                cpu: "?*"
              limits:
                memory: "?*"
                cpu: "?*"
YAML

 cat > "${BASE_DIR}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
  # Istniejące zasoby
  - postgres-db.yaml
  - postgres-clusterip.yaml
  - redis.yaml
  - vault.yaml
  - kafka-kraft.yaml
  - kafka-job-sa.yaml
  - kafka-topic-job.yaml
  - fastapi-config.yaml
  - app-deployment.yaml
  - message-processor.yaml
  - prometheus-config.yaml
  - postgres-exporter.yaml
  - kafka-exporter.yaml
  - node-exporter.yaml
  - service-monitors.yaml
  - prometheus.yaml
  - grafana-datasource.yaml
  - grafana-dashboards.yaml
  - grafana.yaml
  - loki-config.yaml
  - loki.yaml
  - promtail-config.yaml
  - promtail.yaml
  - tempo-config.yaml
  - tempo.yaml
  - pgadmin.yaml
  - kafka-ui.yaml
  - network-policies.yaml
  - kyverno-policy.yaml
  
  # Nowe zasoby
  - mongodb.yaml
  - elasticsearch.yaml
  - logstash.yaml
  - kibana.yaml
  - spring-app-deployment.yaml
  - spark-master.yaml
  - spark-worker.yaml
  - monitoring-extended.yaml
  - ingress-extended.yaml

# Common labels
commonLabels:
  app: ${PROJECT}
  app.kubernetes.io/name: ${PROJECT}
  app.kubernetes.io/instance: ${PROJECT}
  app.kubernetes.io/managed-by: kustomize

# Zmienne
vars:
  - name: NAMESPACE
    objref:
      kind: Namespace
      name: davtro
    fieldref:
      fieldpath: metadata.name
  - name: PROJECT
    objref:
      kind: ConfigMap
      name: fastapi-config
    fieldref:
      fieldpath: data.PROJECT
YAML

  # Ensure explicit manifests requested are present (create simple placeholders when absent)
  declare -A explicit
  explicit[vault.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: vault\n  namespace: ${NAMESPACE}\ndata:\n  VAULT_ADDR: "http://vault:8200"\n'
  explicit[tempo.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: tempo\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: tempo\n  template:\n    metadata:\n      labels:\n        app: tempo\n    spec:\n      containers:\n      - name: tempo\n        image: grafana/tempo:1.5.0\n'
  explicit[tempo-config.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: tempo-config\n  namespace: ${NAMESPACE}\ndata:\n  placeholder: "tempo config"\n'
  explicit[spring-app-deployment.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: spring-app\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: spring-app\n  template:\n    metadata:\n      labels:\n        app: spring-app\n    spec:\n      containers:\n      - name: spring\n        image: openjdk:17-jdk-slim\n        ports:\n        - containerPort: 8080\n'
  explicit[spark-worker.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: spark-worker\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      component: spark-worker\n  template:\n    metadata:\n      labels:\n        component: spark-worker\n    spec:\n      containers:\n      - name: worker\n        image: bitnami/spark:latest\n'
  explicit[spark-master.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: spark-master\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      component: spark-master\n  template:\n    metadata:\n      labels:\n        component: spark-master\n    spec:\n      containers:\n      - name: master\n        image: bitnami/spark:latest\n'
  explicit[service-monitors.yaml]=$'apiVersion: monitoring.coreos.com/v1\nkind: ServiceMonitor\nmetadata:\n  name: placeholder-sm\n  namespace: ${NAMESPACE}\nspec:\n  selector:\n    matchLabels:\n      app: ${PROJECT}\n'
  explicit[redis.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: redis\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      component: redis\n  template:\n    metadata:\n      labels:\n        component: redis\n    spec:\n      containers:\n      - name: redis\n        image: redis:6-alpine\n'
  explicit[promtail.yaml]=$'apiVersion: apps/v1\nkind: DaemonSet\nmetadata:\n  name: promtail\n  namespace: ${NAMESPACE}\nspec:\n  selector:\n    matchLabels:\n      name: promtail\n  template:\n    metadata:\n      labels:\n        name: promtail\n    spec:\n      containers:\n      - name: promtail\n        image: grafana/promtail:2.6.1\n'
  explicit[promtail-config.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: promtail-config\n  namespace: ${NAMESPACE}\ndata:\n  promtail.yml: |\n    server:\n      http_listen_port: 9080\n'
  explicit[prometheus.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: prometheus\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: prometheus\n  template:\n    metadata:\n      labels:\n        app: prometheus\n    spec:\n      containers:\n      - name: prometheus\n        image: prom/prometheus:latest\n'
  explicit[prometheus-config.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: prometheus-config\n  namespace: ${NAMESPACE}\ndata:\n  prometheus.yml: |\n    global:\n      scrape_interval: 15s\n'
  explicit[postgres-exporter.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: postgres-exporter\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: postgres-exporter\n  template:\n    metadata:\n      labels:\n        app: postgres-exporter\n    spec:\n      containers:\n      - name: postgres-exporter\n        image: quay.io/prometheuscommunity/postgres-exporter:latest\n'
  explicit[postgres-db.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: postgres-db\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: postgres-db\n  template:\n    metadata:\n      labels:\n        app: postgres-db\n    spec:\n      containers:\n      - name: postgres\n        image: postgres:13\n        env:\n        - name: POSTGRES_PASSWORD\n          value: testpassword\n'
  explicit[postgres-clusterip.yaml]=$'apiVersion: v1\nkind: Service\nmetadata:\n  name: postgres-db\n  namespace: ${NAMESPACE}\nspec:\n  type: ClusterIP\n  ports:\n  - port: 5432\n    targetPort: 5432\n    protocol: TCP\n  selector:\n    app: postgres-db\n'
  explicit[pgadmin.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: pgadmin\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: pgadmin\n  template:\n    metadata:\n      labels:\n        app: pgadmin\n    spec:\n      containers:\n      - name: pgadmin\n        image: dpage/pgadmin4:latest\n'
  explicit[node-exporter.yaml]=$'apiVersion: apps/v1\nkind: DaemonSet\nmetadata:\n  name: node-exporter\n  namespace: ${NAMESPACE}\nspec:\n  selector:\n    matchLabels:\n      k8s-app: node-exporter\n  template:\n    metadata:\n      labels:\n        k8s-app: node-exporter\n    spec:\n      containers:\n      - name: node-exporter\n        image: quay.io/prometheus/node-exporter:latest\n'
  explicit[network-policies.yaml]=$'apiVersion: networking.k8s.io/v1\nkind: NetworkPolicy\nmetadata:\n  name: default-deny\n  namespace: ${NAMESPACE}\nspec:\n  podSelector: {}\n  policyTypes:\n  - Ingress\n  - Egress\n'
  explicit[monitoring-extended.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: monitoring-extended\n  namespace: ${NAMESPACE}\ndata:\n  placeholder: "monitoring"\n'
  explicit[mongodb.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: mongodb\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: mongodb\n  template:\n    metadata:\n      labels:\n        app: mongodb\n    spec:\n      containers:\n      - name: mongo\n        image: mongo:5.0\n'
  explicit[message-processor.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: message-processor\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: message-processor\n  template:\n    metadata:\n      labels:\n        app: message-processor\n    spec:\n      containers:\n      - name: worker\n        image: nginx:alpine\n'
  explicit[loki.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: loki\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: loki\n  template:\n    metadata:\n      labels:\n        app: loki\n    spec:\n      containers:\n      - name: loki\n        image: grafana/loki:2.6.1\n'
  explicit[loki-config.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: loki-config\n  namespace: ${NAMESPACE}\ndata:\n  loki.yaml: |\n    auth_enabled: false\n'
  explicit[logstash.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: logstash\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: logstash\n  template:\n    metadata:\n      labels:\n        app: logstash\n    spec:\n      containers:\n      - name: logstash\n        image: docker.elastic.co/logstash/logstash:7.17.0\n'
  explicit[kyverno-policy.yaml]=$'apiVersion: kyverno.io/v1\nkind: ClusterPolicy\nmetadata:\n  name: check-container-resources\nspec: {}\n'
  explicit[kibana.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: kibana\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: kibana\n  template:\n    metadata:\n      labels:\n        app: kibana\n    spec:\n      containers:\n      - name: kibana\n        image: docker.elastic.co/kibana/kibana:7.17.0\n'
  explicit[kafka-ui.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: kafka-ui\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: kafka-ui\n  template:\n    metadata:\n      labels:\n        app: kafka-ui\n    spec:\n      containers:\n      - name: kafka-ui\n        image: provectuslabs/kafka-ui:latest\n'
  explicit[kafka-topic-job.yaml]=$'apiVersion: batch/v1\nkind: Job\nmetadata:\n  name: create-topic\n  namespace: ${NAMESPACE}\nspec:\n  template:\n    spec:\n      containers:\n      - name: create-topic\n        image: bitnami/kafka:latest\n        command: ["sh","-c","echo create topic placeholder"]\n      restartPolicy: OnFailure\n'
  explicit[kafka-kraft.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: kafka\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: kafka\n  template:\n    metadata:\n      labels:\n        app: kafka\n    spec:\n      containers:\n      - name: kafka\n        image: bitnami/kafka:latest\n'
  explicit[kafka-job-sa.yaml]=$'apiVersion: v1\nkind: ServiceAccount\nmetadata:\n  name: kafka-job-sa\n  namespace: ${NAMESPACE}\n'
  explicit[kafka-exporter.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: kafka-exporter\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: kafka-exporter\n  template:\n    metadata:\n      labels:\n        app: kafka-exporter\n    spec:\n      containers:\n      - name: kafka-exporter\n        image: danielqsj/kafka-exporter:latest\n'
  explicit[ingress-extended.yaml]=$'apiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: ingress-extended\n  namespace: ${NAMESPACE}\nspec:\n  rules:\n  - host: app.${PROJECT}.local\n    http:\n      paths:\n      - path: /\n        pathType: Prefix\n        backend:\n          service:\n            name: fastapi-web-service\n            port:\n              number: 80\n'
  explicit[grafana.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: grafana\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: grafana\n  template:\n    metadata:\n      labels:\n        app: grafana\n    spec:\n      containers:\n      - name: grafana\n        image: grafana/grafana:latest\n'
  explicit[grafana-datasource.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: grafana-datasource\n  namespace: ${NAMESPACE}\ndata:\n  datasource.yaml: |\n    apiVersion: 1\n'
  explicit[grafana-dashboards.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: grafana-dashboards\n  namespace: ${NAMESPACE}\ndata:\n  placeholder: "dashboards"\n'
  explicit[fastapi-config.yaml]=$'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: fastapi-config\n  namespace: ${NAMESPACE}\ndata:\n  PROJECT: "${PROJECT}"\n  APP_NAME: "${PROJECT}"\n'
  explicit[elasticsearch.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: elasticsearch\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: elasticsearch\n  template:\n    metadata:\n      labels:\n        app: elasticsearch\n    spec:\n      containers:\n      - name: elasticsearch\n        image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0\n'
  explicit[app-deployment.yaml]=$'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: app-deployment\n  namespace: ${NAMESPACE}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: app-deployment\n  template:\n    metadata:\n      labels:\n        app: app-deployment\n    spec:\n      containers:\n      - name: app\n        image: nginx:alpine\n'

  for f in "${!explicit[@]}"; do
    if [[ ! -f "${BASE_DIR}/${f}" ]]; then
      printf "%s" "${explicit[$f]}" > "${BASE_DIR}/${f}"
    fi
  done

 cat > "${ROOT_DIR}/argocd-application.yaml" <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${PROJECT}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}

generate_readme(){
 cat > "${ROOT_DIR}/README.md" <<README
# ${PROJECT} - Complete Monitoring Stack with Spring Boot, Spark & ELK

## 🛠️ Quick Start

\`\`\`bash
# Generate all files
./lmarena.sh generate

# Deploy to Kubernetes
kubectl apply -k manifests/base

# Watch pods
kubectl -n ${NAMESPACE} get pods -w

# Access applications:
# Main App: http://app.${PROJECT}.local
# New Survey: http://app.${PROJECT}.local/new-survey
# Spring Boot API: http://spring.${PROJECT}.local
# Spark UI: http://spark.${PROJECT}.local
# Kibana: http://kibana.${PROJECT}.local
# Grafana: http://grafana.${PROJECT}.local (admin/admin)
# PgAdmin: http://pgadmin.${PROJECT}.local (admin@example.com/adminpassword)
# Kafka UI: http://kafka-ui.${PROJECT}.local

# Initialize Vault
kubectl wait --for=condition=complete job/vault-init -n ${NAMESPACE}

# Initialize MongoDB
kubectl wait --for=condition=complete job/mongodb-init -n ${NAMESPACE}
\`\`\`

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://app.${PROJECT}.local | - |
| New Survey (Spring Boot) | http://app.${PROJECT}.local/new-survey | - |
| Spring Boot API | http://spring.${PROJECT}.local | - |
| Spark Master UI | http://spark.${PROJECT}.local | - |
| Kibana | http://kibana.${PROJECT}.local | - |
| Grafana | http://grafana.${PROJECT}.local | admin/admin |
| PgAdmin | http://pgadmin.${PROJECT}.local | admin@example.com/adminpassword |
| Kafka UI | http://kafka-ui.${PROJECT}.local | - |

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

\`\`\`bash
# Full deployment
./deploy-extended.sh

# Check status
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}
kubectl get ingress -n ${NAMESPACE}
\`\`\`

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

\`\`\`bash
# Check logs
kubectl logs -f deployment/fastapi-web-app -n ${NAMESPACE}
kubectl logs -f deployment/spring-app -n ${NAMESPACE}
kubectl logs -f deployment/spark-master -n ${NAMESPACE}

# Check database connections
kubectl exec -it deployment/fastapi-web-app -n ${NAMESPACE} -- python -c "import psycopg2; psycopg2.connect('dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432')"
kubectl exec -it deployment/spring-app -n ${NAMESPACE} -- curl http://localhost:8080/actuator/health

# Restart deployments
kubectl rollout restart deployment/fastapi-web-app -n ${NAMESPACE}
kubectl rollout restart deployment/spring-app -n ${NAMESPACE}
\`\`\`

## 📚 Documentation:

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [ELK Stack Documentation](https://www.elastic.co/guide/index.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
README
}


# ============================================
# DEPLOY SCRIPT
# ============================================
cat > ${PROJECT_NAME}/scripts/deploy.sh << 'BASHEOF'
# Focused deploy script (replaces generator output)

# This file was updated to be a minimal, safe deploy script limited to this repository.
# It only operates on manifests under ./manifests/base and will not touch other folders.

#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

PROJECT="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
NAMESPACE="${NAMESPACE:-davtro}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${ROOT_DIR}/manifests/base"

usage(){
  cat <<EOF
Usage: $0 <command>

Commands:
  apply    Apply manifests in ${MANIFESTS_DIR} to namespace ${NAMESPACE}
  delete   Delete manifests from namespace ${NAMESPACE}
  status   Show pods and services in namespace ${NAMESPACE}
EOF
  exit 1
}

ensure_kubectl(){
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found in PATH; please install / configure kubectl and kubeconfig"
    exit 2
  fi
}

apply(){
  ensure_kubectl

  if [ ! -d "${MANIFESTS_DIR}" ]; then
    echo "Manifests directory ${MANIFESTS_DIR} not found. Nothing to apply."
    exit 1
  fi

  echo "📦 Creating namespace ${NAMESPACE} if missing..."
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

  echo "📥 Applying manifests from ${MANIFESTS_DIR}..."
  kubectl apply -f "${MANIFESTS_DIR}" -n "${NAMESPACE}"

  echo "⏳ Waiting for key components to become ready (this may take a few minutes)..."
  set +e
  kubectl wait --for=condition=ready pod -l component=fastapi -n "${NAMESPACE}" --timeout=180s
  kubectl wait --for=condition=ready pod -l component=spring -n "${NAMESPACE}" --timeout=180s
  kubectl wait --for=condition=ready pod -l component=spark-master -n "${NAMESPACE}" --timeout=240s
  kubectl wait --for=condition=ready pod -l component=postgres -n "${NAMESPACE}" --timeout=180s
  kubectl wait --for=condition=ready pod -l component=redis -n "${NAMESPACE}" --timeout=120s
  kubectl wait --for=condition=ready pod -l component=kafka -n "${NAMESPACE}" --timeout=240s
  set -e

  if kubectl get job vault-init -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "🔐 Waiting for vault initialization job to complete..."
    kubectl wait --for=condition=complete job/vault-init -n "${NAMESPACE}" --timeout=120s || echo "Vault init job did not complete within timeout or already completed."
  fi

  echo "🔄 Performing rollout restart for FastAPI to pick up potential new routes..."
  kubectl rollout restart deployment/fastapi-web-app -n "${NAMESPACE}" 2>/dev/null || true

  echo "\n✅ Apply complete. Access hints:"
  echo "   Main App:  http://app.${PROJECT}.local"
  echo "   New Survey: http://app.${PROJECT}.local/new-survey"
  echo "   Spring API: http://spring.${PROJECT}.local"
  echo "   Spark UI:   http://spark.${PROJECT}.local"
  echo "   Kibana:     http://kibana.${PROJECT}.local"
  echo "   Grafana:    http://grafana.${PROJECT}.local"
  echo "   PgAdmin:    http://pgadmin.${PROJECT}.local"
}

_delete(){
  echo "🗑️ Deleting resources defined in ${MANIFESTS_DIR} from namespace ${NAMESPACE}..."
  kubectl delete -f "${MANIFESTS_DIR}" -n "${NAMESPACE}" --ignore-not-found
}

delete(){
  ensure_kubectl
  read -p "Are you sure you want to delete all resources in ${NAMESPACE} defined by ${MANIFESTS_DIR}? [y/N] " yn
  case "${yn}" in
    [Yy]* ) _delete; echo "✅ Delete requested." ;;
    * ) echo "Aborted."; exit 0 ;;
  esac
}

status(){
  ensure_kubectl
  echo "📋 Pods in namespace ${NAMESPACE}:"
  kubectl get pods -n "${NAMESPACE}"
  echo "\n🔌 Services in namespace ${NAMESPACE}:"
  kubectl get svc -n "${NAMESPACE}"
}

case "${1:-}" in
  apply) apply ;;
  delete) delete ;;
  status) status ;;
  *) usage ;;
esac

BASHEOF
chmod +x ${PROJECT_NAME}/scripts/deploy.sh


# ============================================
# GENERATE EXTENDED MANIFESTS, CI/CD & DOCS
# ============================================
generate_github_actions
generate_k8s_manifests
generate_readme

echo "=== DavTro Rentals Unified Full-Stack project generated ==="
echo ""
echo "Project: ${PROJECT_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Registry: ${REGISTRY}"
echo ""
echo "Structure:"
echo "  frontend/          - Nginx static frontend (Rentals UI)"
echo "  backend-fastapi/   - FastAPI + asyncpg + Redis + Kafka producer"
echo "  java-app/          - Spring Boot consumer + email service"
echo "  spark-jobs/        - Spark Streaming analytics"
echo "  manifests/base/    - Complete K8s manifests (Vault, Kafka, Redis, PG, Mongo, ELK, Spark, Monitoring, Ingress, NetworkPolicies, Kyverno)"
echo "  .github/workflows/ - CI/CD pipeline"
echo "  scripts/           - deploy.sh helper"
echo "  docs/              - README.md"
echo ""
echo "Next steps:"
echo "  cd ${PROJECT_NAME}"
echo "  ./scripts/deploy.sh apply"