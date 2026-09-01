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
