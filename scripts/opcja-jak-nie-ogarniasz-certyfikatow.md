# DavTro — certyfikaty, port-forward-without-an-argument i dostęp klientów

Dokument opisuje dwa skrypty i pełny workflow związany z wystawieniem usług DavTro z klastra K8s, wygenerowaniem certyfikatów TLS/mTLS oraz ich dystrybucją i importem na komputerach klientów.

---

## Spis treści

1. [Architektura — dwa skrypty, dwie role](#1-architektura--dwa-skrypty-dwie-role)
2. [Skrypt 1 — `scripts/port-forward-without-an-argument.sh` (maszyna z K8s)](#2-skrypt-1--scriptsport-forward-without-an-argumentsh-maszyna-z-k8s)
3. [Skrypt 2 — `client-port-forward-without-an-argument.sh` (komputer klienta)](#3-skrypt-2--client-port-forward-without-an-argumentsh-komputer-klienta)
4. [Workflow krok po kroku](#4-workflow-krok-po-kroku)
5. [Hasło do `.pfx` — gdzie jest i jak je zmienić](#5-hasło-do-pfx--gdzie-jest-i-jak-je-zmienić)
6. [Co się pojawia w `/tmp/ctr/`](#6-co-się-pojawia-w-tmpctr)
7. [Import certyfikatów do przeglądarki](#7-import-certyfikatów-do-przeglądarki)
8. [Diagnostyka błędów](#8-diagnostyka-błędów)
9. [Uwagi i ograniczenia](#9-uwagi-i-ograniczenia)

---

## 1. Architektura — dwa skrypty, dwie role

| Aspekt | `port-forward-without-an-argument.sh` | `client-port-forward-without-an-argument.sh` |
|--------|-------------------|-------------------|
| Gdzie uruchamiany | maszyna z `kubectl` / `microk8s` | komputer użytkownika (przeglądarka) |
| Wymaga `kubectl` | tak | **nie** |
| Wymaga `openssl` | tak (do generowania `.pfx`) | nie (dostaje gotowy `.pfx`) |
| Modyfikuje system | nie (tylko forwardy + pliki w `/tmp/ctr/`) | **tak** (magazyn CA, NSS, keychain) |
| Uprawnienia | user | `sudo` / admin |
| Rola | wystawia usługi + wypluwa certyfikaty | importuje CA + cert klienta |

**Skrypt z K8s = „wystaw usługi i wypluj certyfikaty".**
**Skrypt klienta = „zaufaj temu CA i zaimportuj swój certyfikat klienta".**

---

## 2. Skrypt 1 — `scripts/port-forward-without-an-argument.sh` (maszyna z K8s)

### 2.1 Co robi bez argumentu

1. Odpala wszystkie forwardy **HTTP** (FastAPI, frontend, spring, spark-ui, grafana, kafka-ui, loki, tempo, prometheus, pgadmin, postgres, redis, vault, spark, kafka, kafka-exp, pg-exp, node-exp).
2. Tworzy katalog `/tmp/ctr/` (jeśli nie istnieje) i **wyciąga z Secretów** wszystkie certyfikaty TLS/mTLS.
3. Generuje z nich pliki `.pfx` i `.p12` z hasłem `slodkadziurkazwypiekami`.

### 2.2 Główne argumenty

```bash
./scripts/port-forward-without-an-argument.sh                  # forwardy HTTP + ekstrakcja certów
./scripts/port-forward-without-an-argument.sh https-fastapi  8443
./scripts/port-forward-without-an-argument.sh https-frontend 8444
./scripts/port-forward-without-an-argument.sh https-spring   8445
./scripts/port-forward-without-an-argument.sh https-vault    8243
./scripts/port-forward-without-an-argument.sh https-all        # wszystko naraz (wait, Ctrl+C kończy)
./scripts/port-forward-without-an-argument.sh extract-tls <secret> [prefix]
./scripts/port-forward-without-an-argument.sh extract-all      # to samo co bez argumentu, tylko ekstrakcja
./scripts/port-forward-without-an-argument.sh serve            # serwuje /tmp/ctr/ na 0.0.0.0:8099
./scripts/port-forward-without-an-argument.sh import-help      # instrukcja importu do przeglądarki
./scripts/port-forward-without-an-argument.sh diag             # porty, logi, secrety, zawartość /tmp/ctr/
```

### 2.3 Konfiguracja (zmienne środowiskowe)

| Zmienna | Domyślnie | Znaczenie |
|---------|-----------|-----------|
| `ADDR` | `0.0.0.0` | adres bindowania forwardów (`127.0.0.1` = tylko lokalnie) |
| `NS` | `davtro02` | namespace w K8s |
| `CTR_DIR` | `/tmp/ctr` | katalog na certyfikaty |
| `PFX_PASS` | `slodkadziurkazwypiekami` | hasło do `.pfx`/`.p12` |

### 2.4 Sekrety wyciągane domyślnie

```bash
TLS_SECRETS=(
  "davtro-tls:davtro-tls"
  "fastapi-mtls:fastapi-mtls"
  "spring-app-mtls:spring-app-mtls"
  "message-processor-mtls:message-processor-mtls"
)
```

Rozszerzasz edytując tablicę w skrypcie.

---

## 3. Skrypt 2 — `client-port-forward-without-an-argument.sh` (komputer klienta)

### 3.1 Co robi

1. Pobiera `davtro-tls-ca.crt` z `http://192.168.1.19:8099/`.
2. (Opcjonalnie, z `--mtls`) pobiera `<nazwa>-mtls.pfx`.
3. Importuje CA do zaufanych magazynów systemu i przeglądarki.
4. Importuje `.pfx` do magazynu certyfikatów klienta.

### 3.2 Użycie

```bash
./client-port-forward-without-an-argument.sh                        # tylko CA (bez mTLS)
./client-port-forward-without-an-argument.sh --mtls fastapi         # CA + cert klienta fastapi-mtls.pfx
./client-port-forward-without-an-argument.sh --uninstall            # usuwa CA i cert klienta
```

### 3.3 Zmienne środowiskowe

| Zmienna | Domyślnie | Znaczenie |
|---------|-----------|-----------|
| `K8S_HOST` | `192.168.1.19` | adres maszyny z K8s |
| `K8S_PORT` | `8099` | port serwera HTTP z certyfikatami |
| `PFX_PASS` | `slodkadziurkazwypiekami` | hasło do `.pfx` |
| `WORKDIR` | `/tmp/davtro-client` | katalog roboczy na pobrane pliki |

### 3.4 Co robi na poszczególnych systemach

| System | CA | `.pfx` klienta |
|--------|----|----------------|
| **Linux** | `update-ca-certificates` | `pk12util` → NSS Chrome |
| **macOS** | `security add-trusted-cert` | `security import` → login keychain |
| **Windows** (Git Bash) | `certutil -addstore ROOT` | `certutil -importpfx MY` |

---

## 4. Workflow krok po kroku

### 4.1 Na maszynie z K8s (`192.168.1.19`)

```bash
# 1. Odpal forwardy HTTP + wyciagnij certy do /tmp/ctr/
./scripts/port-forward-without-an-argument.sh

# 2. Udostepnij certy klientom przez HTTP
cp scripts/client-port-forward-without-an-argument.sh /tmp/ctr/       # zeby klient mogl go pobrac
./scripts/port-forward-without-an-argument.sh serve            # http://192.168.1.19:8099/
```

`serve` zostaw w `tmux` / `screen` — dopóki działa, klienci mogą pobierać pliki.

### 4.2 Na komputerze klienta

```bash
# 1. Pobierz skrypt klienta
curl -O http://192.168.1.19:8099/client-port-forward-without-an-argument.sh
chmod +x client-port-forward-without-an-argument.sh

# 2. Tylko CA (bez mTLS) — dla zwyklej przegladarki
./client-port-forward-without-an-argument.sh

# 3. CA + cert klienta (mTLS) — jesli serwer wymaga certyfikatu klienta
./client-port-forward-without-an-argument.sh --mtls fastapi

# 4. Odinstalowanie
./client-port-forward-without-an-argument.sh --uninstall
```

### 4.3 Weryfikacja

```bash
curl -v https://192.168.1.19:8443/ 2>&1 | head -20
# Oczekiwane: "SSL certificate verify ok"
```

Otwórz w przeglądarce:

- `https://192.168.1.19:8443/` — FastAPI przez Ingress
- `https://192.168.1.19:8444/` — frontend przez Ingress
- `https://192.168.1.19:8445/` — spring przez Ingress

---

## 5. Hasło do `.pfx` — gdzie jest i jak je zmienić

| Miejsce | Wartość |
|---------|---------|
| `port-forward-without-an-argument.sh` (domyślnie) | `slodkadziurkazwypiekami` |
| `client-port-forward-without-an-argument.sh` (domyślnie) | `slodkadziurkazwypiekami` |
| Nadpisanie po stronie K8s | `PFX_PASS="inne" ./scripts/port-forward-without-an-argument.sh` |
| Nadpisanie po stronie klienta | `PFX_PASS="inne" ./client-port-forward-without-an-argument.sh --mtls fastapi` |

**Hasło musi być takie samo po obu stronach** — inaczej import `.pfx` się nie powiedzie.

---

## 6. Co się pojawia w `/tmp/ctr/`

Po uruchomieniu `./scripts/port-forward-without-an-argument.sh` bez argumentu:

```
davtro-tls-ca.crt              ← CA do zaufania przeglądarki (to importuje klient)
davtro-tls.crt
davtro-tls.key
davtro-tls.pfx                 ← hasło: slodkadziurkazwypiekami
davtro-tls.p12

fastapi-mtls-ca.crt
fastapi-mtls.crt
fastapi-mtls.key
fastapi-mtls.pfx               ← hasło: slodkadziurkazwypiekami
fastapi-mtls.p12

spring-app-mtls.pfx
spring-app-mtls.p12

message-processor-mtls.pfx
message-processor-mtls.p12
```

Katalog ma uprawnienia `700`, klucze prywatne `600`.

---

## 7. Import certyfikatów do przeglądarki

### 7.1 Certyfikat CA (żeby przeglądarka ufała serwerowi)

#### Linux — Chromium / Chrome / Edge

Chrome na Linuxie używa **własnej bazy NSS**, a nie systemowego magazynu. Dwie opcje:

**Opcja A (systemowo + Chrome):**
```bash
sudo cp /tmp/ctr/davtro-tls-ca.crt /usr/local/share/ca-certificates/davtro-ca.crt
sudo update-ca-certificates
```
Potem w Chrome:
`chrome://settings/certificates` → **Certyfikaty lokalne** → **Linux** → zaznacz **„Używaj certyfikatów lokalnych zaimportowanych z systemu operacyjnego"**.

**Opcja B (ręcznie do bazy NSS Chrome):**
```bash
sudo apt install libnss3-tools
certutil -d sql:$HOME/.local/share/pki/nssdb -A -t "C,," \
  -n "davtro-internal CA" -i /tmp/ctr/davtro-tls-ca.crt
# starsze Chrome: $HOME/.pki/nssdb
```

#### Firefox

`about:preferences#privacy` → **Certyfikaty** → **Wyświetl certyfikaty** → **Urzędy certyfikacji** → **Importuj** → `/tmp/ctr/davtro-tls-ca.crt` → zaznacz **„Zaufaj temu CA do identyfikacji witryn internetowych"**.

Alternatywnie: `about:config` → `security.enterprise_roots.enabled = true` (Firefox ufa wtedy magazynowi systemowemu).

### 7.2 Certyfikat klienta (mTLS) — tylko `.pfx` / `.p12`

Przeglądarka **nie zaimportuje** `.crt` + `.key` osobno. Musi to być kontener PKCS#12:

```bash
./scripts/port-forward-without-an-argument.sh make-pfx fastapi-mtls /tmp/ctr/fastapi.pfx "slodkadziurkazwypiekami" "fastapi client"
```

Import:

- **Chrome/Edge:** `chrome://settings/certificates` → **Twoje certyfikaty** → **Importuj** → `/tmp/ctr/fastapi-mtls.pfx` → hasło `slodkadziurkazwypiekami`.
- **Firefox:** `about:preferences#privacy` → **Certyfikaty** → **Wyświetl certyfikaty** → **Twoje certyfikaty** → **Importuj** → `/tmp/ctr/fastapi-mtls.pfx`.

---

## 8. Diagnostyka błędów

### 8.1 Typowe błędy przeglądarki

| Błąd | Znaczenie | Rozwiązanie |
|------|-----------|-------------|
| `ERR_SSL_PROTOCOL_ERROR` | złe `http://` vs `https://` albo forward nie działa | sprawdź `/tmp/pf-*.log`, użyj `https://` |
| `ERR_CONNECTION_REFUSED` | żaden port-forward-without-an-argument nie nasłuchuje | `./scripts/port-forward-without-an-argument.sh diag` |
| `ERR_CERT_AUTHORITY_INVALID` | CA niezaimportowane | punkt 7.1 |
| `ERR_CERT_COMMON_NAME_INVALID` | cert na inną nazwę (np. `*.davtro.local`), a wchodzisz po IP | dodaj SAN z IP albo używaj DNS z Ingressa |
| „Witryna prosi o wybór certyfikatu klienta" | mTLS działa | wybierz cert z punktu 7.2 |

### 8.2 Szybka diagnostyka

```bash
./scripts/port-forward-without-an-argument.sh diag
```

Pokazuje:

- nasłuchujące porty,
- procesy `kubectl port-forward-without-an-argument`,
- zawartość `/tmp/ctr/`,
- secrety TLS w `davtro02`.

### 8.3 Test z `curl`

```bash
# mTLS:
curl --cacert /tmp/ctr/fastapi-mtls-ca.crt \
     --cert   /tmp/ctr/fastapi-mtls.crt \
     --key    /tmp/ctr/fastapi-mtls.key \
     https://localhost:8443/api/health

# samo CA:
curl --cacert /tmp/ctr/davtro-tls-ca.crt https://localhost:8443/

# ignorowanie certyfikatu (dev):
curl -k https://localhost:8443/
```

---

## 9. Uwagi i ograniczenia

1. **Skrypt klienta nie potrzebuje `kubectl`** — pobiera gotowe pliki przez HTTP.
2. **`client-port-forward-without-an-argument.sh` musi być dostępny na serwerze HTTP** — wrzuć go do `/tmp/ctr/` przed `serve`.
3. **`serve` binduje na `0.0.0.0:8099`** — jeśli nie chcesz wystawiać na cały LAN, użyj `--bind 127.0.0.1` i tuneluj SSH.
4. **Po restarcie maszyny z K8s** — forwardy i `serve` padają. Warto owinąć w `systemd` albo odpalać w `tmux`.
5. **Certyfikaty w `/tmp/ctr/`** — `/tmp` czyści się przy restarcie. Jeśli chcesz trwałe, ustaw `CTR_DIR=/srv/certs`.
6. **Nie kopiuj `.key` na klientów** — klucz prywatny serwera nie może wyciec. Klient dostaje **tylko** `.pfx` (jeśli mTLS) albo sam `ca.crt`.
7. **Nie importuj `.crt` + `.key` osobno w przeglądarce** — to nie zadziała. Tylko `.pfx` / `.p12`.

---

## Załączniki

- `scripts/port-forward-without-an-argument.sh` — skrypt na maszynie z K8s (forwardy + ekstrakcja certów).
- `client-port-forward-without-an-argument.sh` — skrypt na komputerze klienta (pobranie + import).
- `/tmp/ctr/` — katalog wymiany (na maszynie z K8s), serwowany przez `serve`.

---

*Dokument wygenerowany dla środowiska DavTro — K8s `davtro02`, host `192.168.1.19`, port HTTP dystrybucji certyfikatów `8099`.*
