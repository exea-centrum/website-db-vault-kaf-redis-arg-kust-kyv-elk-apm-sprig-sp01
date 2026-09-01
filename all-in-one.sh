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

print_progress() {
    echo -e "${MAGENTA}⏳ $1${NC}"
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
        echo -e "  - Windows: użyj WSL lub Git Bash"
        exit 1
    fi
    
    print_success "Wszystkie wymagane narzędzia są zainstalowane"
}

# ============================================
# FUNKCJA: Sprawdzanie wolnego miejsca
# ============================================
check_disk_space() {
    print_step "Sprawdzanie wolnego miejsca na dysku..."
    
    local required_space=1024 # 1GB w MB
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
    cat << "EOF"
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
EOF
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
    git clone --depth 1 "$GITHUB_REPO" .
    check_error "Nie udało się sklonować repozytorium"
    
    print_success "Projekt pobrany pomyślnie"
}

# ============================================
# FUNKCJA: Tworzenie plików projektu (jeśli nie ma repo)
# ============================================
create_project_files() {
    print_step "Tworzenie plików projektu..."
    
    cd "$TEMP_DIR"
    
    # Tworzenie struktury katalogów
    mkdir -p app/static app/templates
    mkdir -p backend/app backend/migrations
    mkdir -p manifests/{base,production,staging,dev}
    mkdir -p scripts configs
    mkdir -p spark-jobs/src/main/scala
    mkdir -p terraform/environments/{dev,staging,prod}
    mkdir -p .github/workflows
    mkdir -p monitoring/{prometheus,grafana,loki,tempo}
    mkdir -p security/{vault,kyverno}
    
    # ============================================
    # APP - FRONTEND
    # ============================================
    cat > app/index.html << 'EOF'
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wynajem Mieszkań - Dawid Trojanowski</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/flatpickr/dist/flatpickr.min.css">
    <script src="https://cdn.jsdelivr.net/npm/flatpickr"></script>
    <style>
        .bg-gradient {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .card-hover:hover {
            transform: translateY(-5px);
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
        }
        .fade-in {
            animation: fadeIn 0.8s ease-in;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .property-card {
            transition: all 0.3s ease;
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .property-card:hover {
            transform: translateY(-10px);
            box-shadow: 0 20px 40px rgba(0,0,0,0.2);
        }
        .flatpickr-calendar {
            font-family: 'Arial', sans-serif;
        }
        .booking-success {
            background: linear-gradient(135deg, #10b981, #059669);
        }
        .booking-error {
            background: linear-gradient(135deg, #ef4444, #dc2626);
        }
    </style>
</head>
<body>
    <div id="app" class="min-h-screen bg-gray-50">
        <!-- Header -->
        <header class="bg-gradient text-white shadow-lg sticky top-0 z-50">
            <div class="container mx-auto px-6 py-4">
                <div class="flex items-center justify-between flex-wrap">
                    <div class="flex items-center space-x-4">
                        <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"></path>
                        </svg>
                        <h1 class="text-2xl font-bold">Wynajem Mieszkań</h1>
                    </div>
                    <nav class="flex space-x-6">
                        <a href="#offers" class="hover:text-purple-200 transition">Oferty</a>
                        <a href="#booking" class="hover:text-purple-200 transition">Rezerwacja</a>
                        <a href="#contact" class="hover:text-purple-200 transition">Kontakt</a>
                    </nav>
                </div>
            </div>
        </header>

        <!-- Hero Section -->
        <section class="bg-gradient text-white py-20">
            <div class="container mx-auto px-6 text-center">
                <h2 class="text-5xl font-bold mb-6 fade-in">Znajdź idealne mieszkanie</h2>
                <p class="text-xl mb-8 text-purple-100">Krótkoterminowy wynajem w najlepszych lokalizacjach</p>
                <div class="max-w-2xl mx-auto bg-white/10 backdrop-blur-lg rounded-2xl p-6">
                    <div class="grid md:grid-cols-3 gap-4">
                        <input type="text" id="search-location" placeholder="📍 Lokalizacja" class="rounded-lg p-3 text-gray-800">
                        <input type="text" id="search-checkin" placeholder="📅 Zameldowanie" class="rounded-lg p-3 text-gray-800" readonly>
                        <input type="text" id="search-checkout" placeholder="📅 Wymeldowanie" class="rounded-lg p-3 text-gray-800" readonly>
                    </div>
                    <button onclick="searchProperties()" class="mt-4 w-full bg-purple-600 hover:bg-purple-700 text-white font-bold py-3 px-6 rounded-lg transition transform hover:scale-105">
                        🔍 Szukaj mieszkań
                    </button>
                </div>
            </div>
        </section>

        <!-- Oferty -->
        <section id="offers" class="py-16">
            <div class="container mx-auto px-6">
                <h2 class="text-4xl font-bold text-center mb-12 text-gray-800">🏠 Dostępne Mieszkania</h2>
                <div id="properties-grid" class="grid md:grid-cols-3 gap-8">
                    <!-- Karty będą generowane dynamicznie -->
                </div>
            </div>
        </section>

        <!-- Rezerwacja -->
        <section id="booking" class="py-16 bg-gray-100">
            <div class="container mx-auto px-6">
                <h2 class="text-4xl font-bold text-center mb-12 text-gray-800">📅 Zarezerwuj teraz</h2>
                <div class="max-w-4xl mx-auto bg-white rounded-2xl shadow-xl p-8">
                    <form id="booking-form" class="space-y-6">
                        <div class="grid md:grid-cols-2 gap-6">
                            <div>
                                <label class="block text-gray-700 font-semibold mb-2">Imię i nazwisko *</label>
                                <input type="text" id="full-name" required class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-purple-400">
                            </div>
                            <div>
                                <label class="block text-gray-700 font-semibold mb-2">Email *</label>
                                <input type="email" id="email" required class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-purple-400">
                            </div>
                        </div>
                        <div class="grid md:grid-cols-2 gap-6">
                            <div>
                                <label class="block text-gray-700 font-semibold mb-2">📅 Data zameldowania *</label>
                                <input type="text" id="check-in-date" required class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-purple-400" readonly>
                            </div>
                            <div>
                                <label class="block text-gray-700 font-semibold mb-2">📅 Data wymeldowania *</label>
                                <input type="text" id="check-out-date" required class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-purple-400" readonly>
                            </div>
                        </div>
                        <div>
                            <label class="block text-gray-700 font-semibold mb-2">Liczba gości *</label>
                            <input type="number" id="guests" min="1" max="10" required class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-purple-400">
                        </div>
                        <div>
                            <label class="block text-gray-700 font-semibold mb-2">Uwagi</label>
                            <textarea id="notes" rows="3" class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-purple-400"></textarea>
                        </div>
                        <button type="submit" class="w-full bg-gradient-to-r from-purple-600 to-purple-700 hover:from-purple-700 hover:to-purple-800 text-white font-bold py-3 px-6 rounded-lg transition transform hover:scale-105">
                            ✅ Zarezerwuj i otrzymaj potwierdzenie
                        </button>
                    </form>
                    <div id="booking-response" class="mt-4 hidden"></div>
                </div>
            </div>
        </section>

        <!-- Kontakt -->
        <section id="contact" class="py-16">
            <div class="container mx-auto px-6">
                <h2 class="text-4xl font-bold text-center mb-12 text-gray-800">📞 Kontakt</h2>
                <div class="max-w-4xl mx-auto grid md:grid-cols-2 gap-8">
                    <div class="bg-white rounded-2xl shadow-xl p-8 card-hover">
                        <h3 class="text-xl font-bold mb-4 text-gray-800">📧 Napisz do nas</h3>
                        <p class="text-gray-600 mb-4">Odpowiemy w ciągu 24h</p>
                        <a href="mailto:kontakt@wynajem.pl" class="text-purple-600 hover:text-purple-700 font-semibold">kontakt@wynajem.pl</a>
                    </div>
                    <div class="bg-white rounded-2xl shadow-xl p-8 card-hover">
                        <h3 class="text-xl font-bold mb-4 text-gray-800">📱 Zadzwoń</h3>
                        <p class="text-gray-600 mb-4">Pomagamy 7 dni w tygodniu</p>
                        <a href="tel:+48123456789" class="text-purple-600 hover:text-purple-700 font-semibold">+48 123 456 789</a>
                    </div>
                </div>
            </div>
        </section>

        <!-- Footer -->
        <footer class="bg-gray-900 text-white py-8">
            <div class="container mx-auto px-6 text-center">
                <p>&copy; 2025 Dawid Trojanowski - Wynajem Mieszkań</p>
                <p class="text-gray-400 mt-2">Technologie: React, FastAPI, Kafka, Redis, PostgreSQL</p>
            </div>
        </footer>
    </div>

    <script>
        // ============================================
        // KONFIGURACJA
        // ============================================
        const API_URL = window.location.origin + '/api';
        
        // ============================================
        // DANE PRZYKŁADOWYCH MIESZKAŃ
        // ============================================
        const properties = [
            { id: 1, name: "Apartament Centrum", price: 350, guests: 4, image: "🏢", rating: 4.8, location: "Warszawa" },
            { id: 2, name: "Przytulne Studio", price: 250, guests: 2, image: "🏠", rating: 4.9, location: "Kraków" },
            { id: 3, name: "Luksusowy Penthouse", price: 550, guests: 6, image: "🏙️", rating: 4.7, location: "Gdańsk" },
            { id: 4, name: "Apartament nad Wisłą", price: 400, guests: 4, image: "🌊", rating: 4.6, location: "Warszawa" },
            { id: 5, name: "Kamienica w Rynku", price: 300, guests: 3, image: "🏛️", rating: 4.8, location: "Kraków" },
            { id: 6, name: "Mieszkanie z Widokiem", price: 450, guests: 5, image: "🏔️", rating: 4.9, location: "Zakopane" }
        ];

        // ============================================
        // FUNKCJE POMOCNICZE
        // ============================================
        function formatPrice(price) {
            return price.toLocaleString('pl-PL') + ' zł';
        }

        function getStars(rating) {
            const full = Math.floor(rating);
            const half = rating % 1 >= 0.5 ? 1 : 0;
            let stars = '';
            for (let i = 0; i < full; i++) stars += '⭐';
            if (half) stars += '⭐';
            return stars;
        }

        function calculateNights(checkIn, checkOut) {
            const start = new Date(checkIn);
            const end = new Date(checkOut);
            return Math.ceil((end - start) / (1000 * 60 * 60 * 24));
        }

        // ============================================
        // WYŚWIETLANIE OFERT
        // ============================================
        function displayProperties(filteredProperties = null) {
            const grid = document.getElementById('properties-grid');
            const data = filteredProperties || properties;
            
            if (data.length === 0) {
                grid.innerHTML = `
                    <div class="col-span-3 text-center py-12">
                        <p class="text-2xl text-gray-400">😕 Brak dostępnych mieszkań</p>
                        <p class="text-gray-500">Spróbuj zmienić kryteria wyszukiwania</p>
                    </div>
                `;
                return;
            }
            
            grid.innerHTML = data.map(prop => `
                <div class="property-card card-hover">
                    <div class="p-6">
                        <div class="text-5xl mb-4">${prop.image}</div>
                        <h3 class="text-xl font-bold text-gray-800">${prop.name}</h3>
                        <p class="text-gray-600">📍 ${prop.location}</p>
                        <p class="text-gray-600">👤 ${prop.guests} gości</p>
                        <p class="text-2xl font-bold text-purple-600 mt-2">${formatPrice(prop.price)}/doba</p>
                        <div class="flex items-center mt-2">
                            <span class="text-yellow-400">${getStars(prop.rating)}</span>
                            <span class="ml-1 text-gray-600">${prop.rating}</span>
                        </div>
                        <button onclick="bookProperty(${prop.id})" class="mt-4 w-full bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-4 rounded-lg transition transform hover:scale-105">
                            📅 Zarezerwuj
                        </button>
                    </div>
                </div>
            `).join('');
        }

        // ============================================
        // WYSZUKIWANIE
        // ============================================
        function searchProperties() {
            const location = document.getElementById('search-location').value.toLowerCase().trim();
            const checkIn = document.getElementById('search-checkin').value;
            const checkOut = document.getElementById('search-checkout').value;
            
            let filtered = properties;
            
            if (location) {
                filtered = filtered.filter(p => 
                    p.location.toLowerCase().includes(location)
                );
            }
            
            displayProperties(filtered);
            
            if (filtered.length === 0) {
                showToast('Brak mieszkań w tej lokalizacji', 'warning');
            } else {
                showToast(`Znaleziono ${filtered.length} mieszkań`, 'success');
            }
        }

        // ============================================
        // REZERWACJA
        // ============================================
        function bookProperty(id) {
            const prop = properties.find(p => p.id === id);
            if (prop) {
                document.getElementById('booking').scrollIntoView({ behavior: 'smooth' });
                showToast(`Wybrano: ${prop.name} (${formatPrice(prop.price)}/doba)`, 'info');
            }
        }

        // ============================================
        // OBSŁUGA FORMULARZA REZERWACJI
        // ============================================
        document.getElementById('booking-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const submitBtn = this.querySelector('button[type="submit"]');
            const originalText = submitBtn.innerHTML;
            submitBtn.innerHTML = '⏳ Wysyłanie...';
            submitBtn.disabled = true;
            
            const formData = {
                name: document.getElementById('full-name').value.trim(),
                email: document.getElementById('email').value.trim(),
                checkIn: document.getElementById('check-in-date').value,
                checkOut: document.getElementById('check-out-date').value,
                guests: parseInt(document.getElementById('guests').value),
                notes: document.getElementById('notes').value.trim()
            };

            // Walidacja
            if (!formData.name || !formData.email || !formData.checkIn || !formData.checkOut || !formData.guests) {
                showBookingResponse('error', '❌ Wszystkie pola oznaczone * są wymagane!');
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
                return;
            }

            // Walidacja dat
            const checkInDate = new Date(formData.checkIn);
            const checkOutDate = new Date(formData.checkOut);
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            
            if (checkInDate < today) {
                showBookingResponse('error', '❌ Data zameldowania nie może być w przeszłości!');
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
                return;
            }
            
            if (checkOutDate <= checkInDate) {
                showBookingResponse('error', '❌ Data wymeldowania musi być po dacie zameldowania!');
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
                return;
            }

            const responseDiv = document.getElementById('booking-response');
            responseDiv.className = 'mt-4 hidden';
            
            try {
                const response = await fetch(`${API_URL}/bookings`, {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    body: JSON.stringify(formData)
                });

                const result = await response.json();
                
                if (response.ok) {
                    const nights = calculateNights(formData.checkIn, formData.checkOut);
                    const totalPrice = nights * 350;
                    
                    showBookingResponse('success', `
                        ✅ <strong>Rezerwacja potwierdzona!</strong><br><br>
                        📋 Numer rezerwacji: <strong>${result.bookingId || 'B-' + Date.now()}</strong><br>
                        📧 Na adres <strong>${formData.email}</strong> wysłaliśmy potwierdzenie i fakturę proforma.<br>
                        📅 Liczba dni: ${nights}<br>
                        💰 Całkowity koszt: <strong>${formatPrice(totalPrice)}</strong><br><br>
                        <span class="text-sm text-gray-600">📌 W razie pytań: +48 123 456 789</span>
                    `);
                    this.reset();
                    
                    // Reset dat
                    document.getElementById('check-in-date').value = '';
                    document.getElementById('check-out-date').value = '';
                    
                    showToast('✅ Rezerwacja zakończona sukcesem!', 'success');
                } else {
                    throw new Error(result.detail || result.message || 'Błąd rezerwacji');
                }
            } catch (error) {
                console.error('Booking error:', error);
                showBookingResponse('error', `
                    ❌ <strong>Błąd rezerwacji:</strong> ${error.message}<br>
                    ⚠️ Sprawdź dane i spróbuj ponownie.<br>
                    <span class="text-sm text-gray-600">📌 Jeśli problem będzie się powtarzał, skontaktuj się z nami.</span>
                `);
                showToast('❌ Błąd rezerwacji', 'error');
            } finally {
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
            }
        });

        // ============================================
        // FUNKCJE DO WYŚWIETLANIA ODPOWIEDZI
        // ============================================
        function showBookingResponse(type, message) {
            const div = document.getElementById('booking-response');
            div.className = `mt-4 p-4 rounded-lg ${type === 'success' ? 'bg-green-100 text-green-700 border border-green-300' : 'bg-red-100 text-red-700 border border-red-300'}`;
            div.innerHTML = message;
            div.classList.remove('hidden');
            
            if (type === 'success') {
                div.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        }

        // ============================================
        // TOASTY
        // ============================================
        function showToast(message, type = 'info') {
            const colors = {
                success: 'bg-green-500',
                error: 'bg-red-500',
                warning: 'bg-yellow-500',
                info: 'bg-blue-500'
            };
            
            const toast = document.createElement('div');
            toast.className = `fixed bottom-4 right-4 ${colors[type]} text-white px-6 py-3 rounded-lg shadow-lg z-50 transform transition-all duration-500 opacity-0 translate-y-10`;
            toast.textContent = message;
            document.body.appendChild(toast);
            
            setTimeout(() => {
                toast.classList.remove('opacity-0', 'translate-y-10');
                toast.classList.add('opacity-100', 'translate-y-0');
            }, 100);
            
            setTimeout(() => {
                toast.classList.remove('opacity-100', 'translate-y-0');
                toast.classList.add('opacity-0', 'translate-y-10');
                setTimeout(() => toast.remove(), 500);
            }, 4000);
        }

        // ============================================
        // INICJALIZACJA
        // ============================================
        document.addEventListener('DOMContentLoaded', () => {
            // Wyświetl oferty
            displayProperties();
            
            // Inicjalizacja Flatpickr dla wyszukiwania
            flatpickr("#search-checkin", {
                minDate: "today",
                dateFormat: "Y-m-d",
                placeholder: "📅 Zameldowanie"
            });
            
            flatpickr("#search-checkout", {
                minDate: "today",
                dateFormat: "Y-m-d",
                placeholder: "📅 Wymeldowanie"
            });
            
            // Inicjalizacja Flatpickr dla rezerwacji
            const checkInPicker = flatpickr("#check-in-date", {
                minDate: "today",
                dateFormat: "Y-m-d",
                placeholder: "Wybierz datę",
                onChange: function(selectedDates, dateStr) {
                    const checkOutPicker = document.getElementById('check-out-date')._flatpickr;
                    if (checkOutPicker) {
                        checkOutPicker.set('minDate', dateStr);
                    }
                }
            });
            
            flatpickr("#check-out-date", {
                minDate: "today",
                dateFormat: "Y-m-d",
                placeholder: "Wybierz datę"
            });
            
            // Obsługa Enter w wyszukiwaniu
            document.getElementById('search-location').addEventListener('keypress', function(e) {
                if (e.key === 'Enter') searchProperties();
            });
            
            // Auto-demo - pokaż toast powitalny
            setTimeout(() => {
                showToast('🏠 Witamy w systemie rezerwacji!', 'info');
            }, 1000);
        });
    </script>
</body>
</html>
EOF

    # ============================================
    # BACKEND - FASTAPI
    # ============================================
    cat > backend/app/main.py << 'EOF'
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel, EmailStr, validator
from datetime import datetime, date, timedelta
from typing import Optional, List
import asyncpg
import redis
import json
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import os
import logging
import uuid
import asyncio
from contextlib import asynccontextmanager

# Konfiguracja logowania
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ============================================
# MODELE
# ============================================
class BookingRequest(BaseModel):
    name: str
    email: EmailStr
    checkIn: date
    checkOut: date
    guests: int
    notes: Optional[str] = None
    
    @validator('checkOut')
    def validate_dates(cls, v, values):
        if 'checkIn' in values and v <= values['checkIn']:
            raise ValueError('Data wymeldowania musi być po dacie zameldowania')
        return v

class BookingResponse(BaseModel):
    bookingId: str
    status: str
    message: str
    totalPrice: Optional[float] = None
    nights: Optional[int] = None

class PropertyResponse(BaseModel):
    id: int
    name: str
    price: float
    guests: int
    image: str
    rating: float
    location: str

# ============================================
# KONFIGURACJA
# ============================================
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "postgres-db"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "database": os.getenv("DB_NAME", "booking_db"),
    "user": os.getenv("DB_USER", "admin"),
    "password": os.getenv("DB_PASSWORD", "secure_password")
}

REDIS_CONFIG = {
    "host": os.getenv("REDIS_HOST", "redis-service"),
    "port": int(os.getenv("REDIS_PORT", "6379")),
    "password": os.getenv("REDIS_PASSWORD", "")
}

KAFKA_CONFIG = {
    "bootstrap_servers": os.getenv("KAFKA_SERVERS", "kafka-kraft:9092"),
    "topic": os.getenv("KAFKA_TOPIC", "booking-events")
}

# ============================================
# APLIKACJA FASTAPI
# ============================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("🚀 Starting application...")
    await init_database()
    yield
    # Shutdown
    logger.info("👋 Shutting down application...")

app = FastAPI(
    title="Wynajem Mieszkań API",
    version="1.0.0",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# FUNKCJE POMOCNICZE
# ============================================
async def init_database():
    """Inicjalizacja bazy danych"""
    try:
        conn = await asyncpg.connect(
            host=DB_CONFIG["host"],
            port=DB_CONFIG["port"],
            database=DB_CONFIG["database"],
            user=DB_CONFIG["user"],
            password=DB_CONFIG["password"]
        )
        
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS bookings (
                id VARCHAR(50) PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                email VARCHAR(100) NOT NULL,
                check_in DATE NOT NULL,
                check_out DATE NOT NULL,
                guests INTEGER NOT NULL,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                status VARCHAR(20) DEFAULT 'confirmed'
            )
        """)
        
        await conn.close()
        logger.info("✅ Database initialized successfully")
    except Exception as e:
        logger.error(f"❌ Database init error: {e}")
        # Kontynuujemy - baza może być jeszcze niedostępna

async def get_db_connection():
    """Pobranie połączenia z bazą"""
    return await asyncpg.connect(
        host=DB_CONFIG["host"],
        port=DB_CONFIG["port"],
        database=DB_CONFIG["database"],
        user=DB_CONFIG["user"],
        password=DB_CONFIG["password"]
    )

def generate_booking_id():
    """Generowanie unikalnego ID rezerwacji"""
    return f"B-{datetime.now().strftime('%Y%m%d%H%M%S')}-{str(uuid.uuid4())[:4].upper()}"

def generate_email_body(booking: BookingRequest, booking_id: str, total_price: float, nights: int):
    """Generowanie treści email z fakturą proforma"""
    return f"""
    <html>
    <head>
        <style>
            body {{ font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; }}
            .header {{ 
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white; 
                padding: 30px 20px; 
                text-align: center;
                border-radius: 10px 10px 0 0;
            }}
            .content {{ padding: 30px 20px; background: #f9f9f9; border-radius: 0 0 10px 10px; }}
            .detail {{ margin: 10px 0; padding: 10px; background: white; border-radius: 5px; }}
            .price {{ font-size: 24px; color: #667eea; font-weight: bold; }}
            .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
        </style>
    </head>
    <body>
        <div class="header">
            <h1>✅ Potwierdzenie Rezerwacji</h1>
            <p>Numer: <strong>{booking_id}</strong></p>
        </div>
        <div class="content">
            <h2>📋 Dane rezerwacji</h2>
            <div class="detail">
                <p><strong>Imię i nazwisko:</strong> {booking.name}</p>
                <p><strong>Email:</strong> {booking.email}</p>
                <p><strong>Data zameldowania:</strong> {booking.checkIn}</p>
                <p><strong>Data wymeldowania:</strong> {booking.checkOut}</p>
                <p><strong>Liczba gości:</strong> {booking.guests}</p>
                <p><strong>Uwagi:</strong> {booking.notes or 'Brak'}</p>
                <p><strong>Liczba dni:</strong> {nights}</p>
            </div>
            
            <hr style="border: 1px solid #ddd; margin: 20px 0;">
            
            <h2>📄 Faktura Proforma</h2>
            <div class="detail">
                <p><strong>Cena za dobę:</strong> 350 zł</p>
                <p><strong>Liczba dni:</strong> {nights}</p>
                <p class="price">Razem: {total_price:.2f} zł</p>
            </div>
            
            <div style="margin-top: 20px; padding: 15px; background: #e8f5e9; border-radius: 5px;">
                <p style="margin: 0;">📞 W razie pytań: +48 123 456 789</p>
                <p style="margin: 0;">📧 kontakt@wynajem.pl</p>
            </div>
        </div>
        <div class="footer">
            <p>&copy; 2025 Wynajem Mieszkań - Dawid Trojanowski</p>
        </div>
    </body>
    </html>
    """

# ============================================
# ENDPOINTY
# ============================================
@app.get("/")
async def root():
    """Strona główna"""
    return FileResponse("app/index.html")

@app.get("/api/health")
async def health_check():
    """Health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0"
    }

@app.post("/api/bookings", response_model=BookingResponse)
async def create_booking(booking: BookingRequest, background_tasks: BackgroundTasks):
    """Endpoint do tworzenia rezerwacji"""
    
    try:
        # Generowanie ID
        booking_id = generate_booking_id()
        nights = (booking.checkOut - booking.checkIn).days
        total_price = nights * 350.0
        
        # Zapis do PostgreSQL
        conn = await get_db_connection()
        try:
            await conn.execute("""
                INSERT INTO bookings (id, name, email, check_in, check_out, guests, notes, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """, booking_id, booking.name, booking.email, booking.checkIn, 
                booking.checkOut, booking.guests, booking.notes, datetime.now())
        finally:
            await conn.close()
        
        logger.info(f"✅ Booking {booking_id} saved to PostgreSQL")
        
        # Wysłanie do Kafka (w tle)
        background_tasks.add_task(publish_to_kafka, booking, booking_id)
        
        # Email przez Redis (w tle)
        background_tasks.add_task(send_email, booking, booking_id, total_price, nights)
        
        # Akcje marketingowe (w tle)
        background_tasks.add_task(process_marketing, booking, booking_id)
        
        return BookingResponse(
            bookingId=booking_id,
            status="confirmed",
            message="Rezerwacja została potwierdzona. Email z potwierdzeniem został wysłany.",
            totalPrice=total_price,
            nights=nights
        )
        
    except asyncpg.exceptions.UniqueViolationError:
        raise HTTPException(status_code=409, detail="Rezerwacja o tym ID już istnieje")
    except Exception as e:
        logger.error(f"❌ Booking error: {e}")
        raise HTTPException(status_code=500, detail=f"Błąd rezerwacji: {str(e)}")

@app.get("/api/properties", response_model=List[PropertyResponse])
async def get_properties():
    """Pobieranie ofert z bazy"""
    # Tymczasowo zwracamy statyczne dane
    return [
        {"id": 1, "name": "Apartament Centrum", "price": 350, "guests": 4, "image": "🏢", "rating": 4.8, "location": "Warszawa"},
        {"id": 2, "name": "Przytulne Studio", "price": 250, "guests": 2, "image": "🏠", "rating": 4.9, "location": "Kraków"},
        {"id": 3, "name": "Luksusowy Penthouse", "price": 550, "guests": 6, "image": "🏙️", "rating": 4.7, "location": "Gdańsk"},
        {"id": 4, "name": "Apartament nad Wisłą", "price": 400, "guests": 4, "image": "🌊", "rating": 4.6, "location": "Warszawa"},
        {"id": 5, "name": "Kamienica w Rynku", "price": 300, "guests": 3, "image": "🏛️", "rating": 4.8, "location": "Kraków"},
        {"id": 6, "name": "Mieszkanie z Widokiem", "price": 450, "guests": 5, "image": "🏔️", "rating": 4.9, "location": "Zakopane"}
    ]

@app.get("/api/bookings/{booking_id}")
async def get_booking(booking_id: str):
    """Pobieranie szczegółów rezerwacji"""
    try:
        conn = await get_db_connection()
        try:
            result = await conn.fetchrow(
                "SELECT * FROM bookings WHERE id = $1", booking_id
            )
        finally:
            await conn.close()
        
        if not result:
            raise HTTPException(status_code=404, detail="Rezerwacja nie znaleziona")
        
        return {
            "id": result["id"],
            "name": result["name"],
            "email": result["email"],
            "checkIn": result["check_in"].isoformat(),
            "checkOut": result["check_out"].isoformat(),
            "guests": result["guests"],
            "notes": result["notes"],
            "createdAt": result["created_at"].isoformat(),
            "status": result["status"]
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Get booking error: {e}")
        raise HTTPException(status_code=500, detail="Błąd pobierania rezerwacji")

# ============================================
# FUNKCJE ASYNCHRONICZNE (w tle)
# ============================================
async def publish_to_kafka(booking: BookingRequest, booking_id: str):
    """Wysłanie do Kafka"""
    try:
        from aiokafka import AIOKafkaProducer
        
        producer = AIOKafkaProducer(
            bootstrap_servers=KAFKA_CONFIG["bootstrap_servers"],
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        
        await producer.start()
        
        message = {
            "booking_id": booking_id,
            "event_type": "booking_created",
            "data": booking.dict(),
            "timestamp": datetime.now().isoformat()
        }
        
        await producer.send(KAFKA_CONFIG["topic"], message)
        await producer.stop()
        
        logger.info(f"📤 Booking {booking_id} published to Kafka")
        return True
    except Exception as e:
        logger.error(f"❌ Kafka error: {e}")
        return False

async def send_email(booking: BookingRequest, booking_id: str, total_price: float, nights: int):
    """Wysyłka email przez Redis"""
    try:
        r = redis.Redis(
            host=REDIS_CONFIG["host"],
            port=REDIS_CONFIG["port"],
            password=REDIS_CONFIG["password"] if REDIS_CONFIG["password"] else None,
            decode_responses=True
        )
        
        email_body = generate_email_body(booking, booking_id, total_price, nights)
        
        email_data = {
            "to": booking.email,
            "subject": f"✅ Potwierdzenie rezerwacji #{booking_id}",
            "body": email_body,
            "type": "booking_confirmation"
        }
        
        r.rpush("email_queue", json.dumps(email_data))
        logger.info(f"📧 Email for booking {booking_id} queued in Redis")
        return True
    except Exception as e:
        logger.error(f"❌ Redis/Email error: {e}")
        return False

async def process_marketing(booking: BookingRequest, booking_id: str):
    """Przetwarzanie akcji marketingowych"""
    try:
        r = redis.Redis(
            host=REDIS_CONFIG["host"],
            port=REDIS_CONFIG["port"],
            password=REDIS_CONFIG["password"] if REDIS_CONFIG["password"] else None,
            decode_responses=True
        )
        
        marketing_data = {
            "booking_id": booking_id,
            "email": booking.email,
            "name": booking.name,
            "action": "new_customer",
            "timestamp": datetime.now().isoformat(),
            "segment": "new_booking"
        }
        
        # Zapis do Redis dla szybkiego dostępu
        r.setex(
            f"marketing:{booking_id}",
            3600,  # 1 godzina
            json.dumps(marketing_data)
        )
        
        # Dodanie do kolejki marketingowej
        r.rpush("marketing_queue", json.dumps(marketing_data))
        
        logger.info(f"📊 Marketing event for {booking_id} processed")
        return True
    except Exception as e:
        logger.error(f"❌ Marketing error: {e}")
        return False

# ============================================
# SERWOWANIE STATYCZNYCH PLIKÓW
# ============================================
app.mount("/static", StaticFiles(directory="static"), name="static")
EOF

    # ============================================
    # DOCKERFILE
    # ============================================
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Instalacja zależności systemowych
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Kopiowanie requirements
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Kopiowanie aplikacji
COPY backend/app ./app
COPY app ./app/static

# Uruchomienie
ENV PYTHONPATH=/app
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

    # ============================================
    # REQUIREMENTS.TXT
    # ============================================
    cat > backend/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
asyncpg==0.29.0
redis==5.0.1
aiokafka==0.8.0
pydantic==2.5.0
python-multipart==0.0.6
email-validator==2.1.0
prometheus-client==0.19.0
python-json-logger==2.0.7
httpx==0.25.1
EOF

    # ============================================
    # DOCKER-COMPOSE
    # ============================================
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: booking-postgres
    environment:
      POSTGRES_DB: booking_db
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secure_password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - booking-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: booking-redis
    ports:
      - "6379:6379"
    networks:
      - booking-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  kafka:
    image: bitnami/kafka:latest
    container_name: booking-kafka
    environment:
      KAFKA_CFG_NODE_ID: 0
      KAFKA_CFG_PROCESS_ROLES: controller,broker
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: 0@kafka:9093
      KAFKA_CFG_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_CFG_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_CFG_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CFG_INTER_BROKER_LISTENER_NAME: PLAINTEXT
    ports:
      - "9092:9092"
      - "9093:9093"
    networks:
      - booking-network
    healthcheck:
      test: ["CMD", "kafka-topics.sh", "--bootstrap-server", "localhost:9092", "--list"]
      interval: 30s
      timeout: 10s
      retries: 3

  app:
    build: .
    container_name: booking-app
    environment:
      DB_HOST: postgres
      DB_PORT: 5432
      DB_NAME: booking_db
      DB_USER: admin
      DB_PASSWORD: secure_password
      REDIS_HOST: redis
      REDIS_PORT: 6379
      KAFKA_SERVERS: kafka:9092
      KAFKA_TOPIC: booking-events
    ports:
      - "8000:8000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      kafka:
        condition: service_healthy
    networks:
      - booking-network
    volumes:
      - ./app:/app/app
    restart: unless-stopped

networks:
  booking-network:
    driver: bridge

volumes:
  postgres_data:
EOF

    # ============================================
    # MANIFESTY KUBERNETES
    # ============================================
    cat > manifests/base/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
  labels:
    name: davtro
    environment: production
    managed-by: argocd
EOF

    cat > manifests/base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-app
  namespace: davtro
  labels:
    app: booking-app
    component: frontend
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: booking-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: booking-app
        component: frontend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      serviceAccountName: app-sa
      containers:
      - name: app
        image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
          name: http
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /api/health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /api/health
            port: 8000
          initialDelaySeconds: 15
          periodSeconds: 15
      imagePullSecrets:
      - name: ghcr-secret
EOF

    # ============================================
    # SKRYPT DEPLOY
    # ============================================
    cat > scripts/deploy.sh << 'EOF'
#!/bin/bash
set -e

NAMESPACE="davtro"
echo "🚀 Deploying to Kubernetes..."

# Tworzenie namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy aplikacji
kubectl apply -k manifests/production -n $NAMESPACE

# Czekanie na gotowość
echo "⏳ Czekanie na uruchomienie podów..."
kubectl wait --for=condition=ready pod -l app=booking-app -n $NAMESPACE --timeout=300s

echo "✅ Deployment zakończony pomyślnie!"
echo "🌐 Aplikacja dostępna pod: http://localhost:8000"
echo "📊 Uruchom port-forward: kubectl port-forward svc/booking-app-service 8000:8000 -n $NAMESPACE"
EOF
    chmod +x scripts/deploy.sh

    # ============================================
    # README
    # ============================================
    cat > README.md << 'EOF'
# 🏠 System Wynajmu Mieszkań

Kompleksowy system do zarządzania wynajmem krótkoterminowym.

## 🚀 Szybki start

```bash
# Lokalny rozwój
docker-compose up -d

# Deploy na Kubernetes
./scripts/deploy.sh
