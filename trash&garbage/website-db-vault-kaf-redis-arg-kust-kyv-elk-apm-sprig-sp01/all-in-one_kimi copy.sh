#!/bin/bash
set -e

PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
NAMESPACE="davtro"
REPO="https://github.com/exea-centrum/${PROJECT_NAME}.git"

echo "=== DavTro Rentals - All-in-One Setup (Completed) ==="
mkdir -p ${PROJECT_NAME}/{frontend,backend-fastapi/app,java-app/src/main/{java/com/davtro/rental/{model,repository,consumer,service},resources},spark-jobs,manifests/{base,overlays/{production,staging},argocd},terraform,.github/workflows,scripts,docs,kyverno-policies,argocd}

# ============================================
# FRONTEND (SPA z kalendarzem, rezerwacjami, adminem)
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
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
psycopg2-binary==2.9.9
redis==5.0.8
confluent-kafka==2.5.3
pydantic[email]==2.9.2
python-multipart==0.0.9
jinja2==3.1.4
prometheus-fastapi-instrumentator==7.0.0
hvac==2.3.0
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

cat > ${PROJECT_NAME}/Dockerfile.consumer << 'EOF'
FROM python:3.12-slim
WORKDIR /srv
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY backend-fastapi/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY backend-fastapi/app ./app
CMD ["python", "-m", "app.consumer"]
EOF

mkdir -p ${PROJECT_NAME}/backend-fastapi/app
cat > ${PROJECT_NAME}/backend-fastapi/app/__init__.py << 'EOF'
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/db.py << 'EOF'
import os
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, Text, func
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@postgres-clusterip:5432/davtro",
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()


class Property(Base):
    __tablename__ = "properties"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    location = Column(String)
    price = Column(Numeric(10, 2), nullable=False)
    guests = Column(Integer, default=2)
    description = Column(Text)
    amenities = Column(String, default="[]")


class Booking(Base):
    __tablename__ = "bookings"
    id = Column(Integer, primary_key=True)
    property_id = Column(Integer, nullable=False)
    check_in = Column(Date, nullable=False)
    check_out = Column(Date, nullable=False)
    guest_name = Column(String, nullable=False)
    guest_email = Column(String, nullable=False)
    phone = Column(String)
    nights = Column(Integer)
    total_price = Column(Numeric(10, 2))
    marketing_consent = Column(Boolean, default=False)
    status = Column(String, default="pending")
    invoice_sent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())


def init_db():
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
    if session.query(Property).count() == 0:
        session.add_all([
            Property(name="Apartament Premium - Warszawa", location="warsaw", price=450, guests=4, description="Luksusowy apartament w centrum", amenities='["WiFi","Klimatyzacja","Balkon","Parking"]'),
            Property(name="Studio Modern - Kraków", location="krakow", price=320, guests=2, description="Stylowe studio obok Rynku", amenities='["WiFi","Smart TV","Kuchnia"]'),
            Property(name="Villa nad Morzem - Gdańsk", location="gdansk", price=680, guests=6, description="Willa 200m od plaży", amenities='["WiFi","Ogródek","Grill","Parking"]'),
            Property(name="Loft Industrial - Wrocław", location="wroclaw", price=280, guests=3, description="Industrialny loft", amenities='["WiFi","Projektor","Klimatyzacja"]'),
            Property(name="Penthouse View - Warszawa", location="warsaw", price=850, guests=4, description="Ekskluzywny penthouse", amenities='["WiFi","Basen","Siłownia","Concierge"]'),
            Property(name="Apartament Royal - Kraków", location="krakow", price=390, guests=4, description="Elegancki apartament w Kazimierzu", amenities='["WiFi","Klimatyzacja","Balkon"]'),
        ])
        session.commit()
    session.close()
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/email_sender.py << 'EOF'
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
        f"Twoja rezerwacja ({event['check_in']} - {event['check_out']}) została potwierdzona.\n"
        f"W załączeniu (proforma) prosimy o dokonanie płatności przed przyjazdem.\n\n"
        f"Pozdrawiamy,\nDavtro Apartments"
    )
    _send(to_email, subject, body)


def send_marketing_email(to_email: str, guest_name: str):
    subject = "Sprawdź nasze najnowsze oferty!"
    body = f"Cześć {guest_name}, mamy dla Ciebie nowe promocje na pobyty krótkoterminowe."
    _send(to_email, subject, body)
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/kafka_producer.py << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/consumer.py << 'EOF'
import json
import os
import time
import redis
from confluent_kafka import Consumer
from app.db import SessionLocal, Booking
from app.email_sender import send_confirmation_email, send_marketing_email

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def handle_booking_event(event: dict):
    dedup_key = f"processed:{event['event_id']}"
    if redis_client.get(dedup_key):
        return
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
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/main.py << 'PYEOF'
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import Optional
import redis
import os
import uuid
from datetime import datetime

from app.db import init_db, SessionLocal, Property, Booking
from app.kafka_producer import publish_event

app = FastAPI(title="DavTro Rentals API", version="2.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


@app.on_event("startup")
def on_startup():
    init_db()


class BookingIn(BaseModel):
    property_id: int
    check_in: str
    check_out: str
    guest_name: str
    guest_email: EmailStr
    phone: Optional[str] = None
    marketing_consent: bool = False


@app.get("/api/health")
def health():
    return {"status": "healthy", "redis": redis_client.ping(), "database": "ok"}


@app.get("/api/properties")
def get_properties():
    cache_key = "properties:all"
    cached = redis_client.get(cache_key)
    if cached:
        import json
        return json.loads(cached)
    session = SessionLocal()
    try:
        rows = session.query(Property).all()
        result = [{"id": r.id, "name": r.name, "location": r.location, "price": float(r.price), "guests": r.guests, "description": r.description, "amenities": r.amenities} for r in rows]
        redis_client.setex(cache_key, 300, __import__('json').dumps(result))
        return result
    finally:
        session.close()


@app.post("/api/bookings")
def create_booking(booking: BookingIn):
    if booking.check_in >= booking.check_out:
        raise HTTPException(status_code=400, detail="Data wyjazdu musi być późniejsza niż przyjazdu")
    session = SessionLocal()
    try:
        nights = (datetime.strptime(booking.check_out, "%Y-%m-%d") - datetime.strptime(booking.check_in, "%Y-%m-%d")).days
        prop = session.query(Property).get(booking.property_id)
        total = float(prop.price) * nights if prop else 0
        b = Booking(
            property_id=booking.property_id,
            check_in=datetime.strptime(booking.check_in, "%Y-%m-%d").date(),
            check_out=datetime.strptime(booking.check_out, "%Y-%m-%d").date(),
            guest_name=booking.guest_name,
            guest_email=booking.guest_email,
            phone=booking.phone,
            nights=nights,
            total_price=total,
            marketing_consent=booking.marketing_consent,
            status="pending",
        )
        session.add(b)
        session.commit()
        session.refresh(b)
        booking_id = b.id
    finally:
        session.close()

    event = {
        "event_id": str(uuid.uuid4()),
        "booking_id": booking_id,
        "guest_email": booking.guest_email,
        "guest_name": booking.guest_name,
        "property_id": booking.property_id,
        "check_in": booking.check_in,
        "check_out": booking.check_out,
        "total_price": total,
        "type": "booking_confirmation",
    }
    redis_client.setex(f"booking:{event['event_id']}", 3600, __import__('json').dumps(event))
    publish_event("booking-events", event)
    if booking.marketing_consent:
        publish_event("marketing-events", {
            "event_id": str(uuid.uuid4()),
            "guest_email": booking.guest_email,
            "guest_name": booking.guest_name,
            "type": "newsletter_opt_in",
        })
    return {"booking_id": booking_id, "status": "pending", "message": "Rezerwacja zapisana, e-mail w drodze"}


@app.get("/api/bookings")
def get_bookings():
    session = SessionLocal()
    try:
        rows = session.query(Booking).order_by(Booking.created_at.desc()).all()
        return [{"id": r.id, "property_id": r.property_id, "guest_name": r.guest_name, "guest_email": r.guest_email, "check_in": str(r.check_in), "check_out": str(r.check_out), "nights": r.nights, "total_price": float(r.total_price), "status": r.status} for r in rows]
    finally:
        session.close()
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
FROM eclipse-temurin:17-jdk-alpine AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN apk add --no-cache maven && mvn -B clean package -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/rental-processor-1.0.0.jar app.jar
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
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;
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
public interface BookingRepository extends JpaRepository<Booking, Integer> {}
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
    @KafkaListener(topics = "booking-events", groupId = "spring-app-group")
    public void consumeBooking(String message) {
        try {
            JsonNode json = objectMapper.readTree(message);
            log.info("Received booking: {}", json.get("booking_id").asText());
            Booking booking = new Booking();
            booking.setPropertyId(json.get("property_id").asInt());
            booking.setGuestName(json.get("guest_name").asText());
            booking.setEmail(json.get("guest_email").asText());
            booking.setCheckIn(LocalDate.parse(json.get("check_in").asText()));
            booking.setCheckOut(LocalDate.parse(json.get("check_out").asText()));
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
            emailService.sendProformaInvoice(json.get("guest_email").asText(), json.get("guest_name").asText(), json.get("booking_id").asText(), new BigDecimal(json.get("total_price").asText()));
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
spring.datasource.url=jdbc:postgresql://${DB_HOST:postgres-clusterip}:5432/davtro
spring.datasource.username=${DB_USER:postgres}
spring.datasource.password=${DB_PASSWORD:postgres}
spring.jpa.hibernate.ddl-auto=update
spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP:kafka-kraft:9092}
spring.kafka.consumer.group-id=spring-app-group
spring.kafka.consumer.auto-offset-reset=earliest
spring.mail.host=${SMTP_HOST:localhost}
spring.mail.port=${SMTP_PORT:587}
EOF

# ============================================
# SPARK JOBS (Python)
# ============================================
cat > ${PROJECT_NAME}/spark-jobs/marketing_analytics.py << 'EOF'
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, window, count
from pyspark.sql.types import StructType, StringType

KAFKA_BOOTSTRAP = "kafka-kraft:9092"

schema = StructType().add("event_id", StringType()).add("guest_email", StringType()).add("guest_name", StringType()).add("type", StringType())

if __name__ == "__main__":
    spark = SparkSession.builder.appName("marketing-analytics").getOrCreate()
    df = spark.readStream.format("kafka").option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP).option("subscribe", "marketing-events").load()
    parsed = df.select(from_json(col("value").cast("string"), schema).alias("data")).select("data.*")
    agg = parsed.groupBy(window(parsed.event_id, "1 hour")).agg(count("*").alias("events_count"))
    query = agg.writeStream.outputMode("update").format("console").start()
    query.awaitTermination()
EOF

cat > ${PROJECT_NAME}/spark-jobs/Dockerfile << 'EOF'
FROM bitnami/spark:3.5
WORKDIR /jobs
COPY marketing_analytics.py .
EOF

# ============================================
# KUBERNETES MANIFESTS
# ============================================
mkdir -p ${PROJECT_NAME}/manifests/base
mkdir -p ${PROJECT_NAME}/manifests/overlays/production
mkdir -p ${PROJECT_NAME}/manifests/overlays/staging
mkdir -p ${PROJECT_NAME}/manifests/argocd

cat > ${PROJECT_NAME}/manifests/base/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
  labels:
    app.kubernetes.io/part-of: davtro-platform
EOF

cat > ${PROJECT_NAME}/manifests/base/serviceaccount.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/configmap.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/secret.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/deployment.yaml << 'EOF'
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
            httpGet: { path: /api/health, port: 8080 }
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: { path: /api/health, port: 8080 }
            initialDelaySeconds: 15
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
EOF

cat > ${PROJECT_NAME}/manifests/base/service.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/hpa.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/pdb.yaml << 'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-web-app-pdb
  namespace: davtro
spec:
  minAvailable: 1
  selector:
    matchLabels: { app: fastapi-web-app }
EOF

cat > ${PROJECT_NAME}/manifests/base/postgres.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/redis.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/vault.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/kafka.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/message-processor.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/spring-app.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/spark.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/prometheus.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/exporters.yaml << 'EOF'
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
EOF

cat > ${PROJECT_NAME}/manifests/base/grafana.yaml << 'EOF'
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
      volumes:
        - name: datasource
          configMap: { name: grafana-datasource }
---
apiVersion: v1
kind