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
6. Sekrety pochodzą z HashiCorp Vault przez External Secrets Operator (ESO) – `secret-store.yaml` + `external-secrets.yaml`; bootstrap Vaulta (init/unseal/KV/auth/database) robi automatycznie Job `vault-bootstrap` (PostSync). Aplikacje Python dostają dynamiczne credsy DB z `database/creds/davtro-app-rw` (rotacja co 30 min).

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
- ~~sekrety w repo~~ ZROBIONE: Vault (raft na PVC) + ESO generują `davtro-secrets`; Job `vault-bootstrap` automatyzuje init/unseal/KV/auth/database po każdym syncu.
- ~~Vault dev-mode~~ ZROBIONE: storage raft na PVC. Do produkcji HA: Helm chart z auto-unseal (cloud KMS / transit) zamiast klucza unseal na PVC.
- `service-monitors.yaml` wymaga Prometheus Operatora (CRD `ServiceMonitor`) – jest wyłączony w `kustomization.yaml`, odkomentuj po instalacji operatora.
- SMTP nie jest skonfigurowany – bez zmiennych `SMTP_*` e-maile tylko logują się do stdout (`app/email_sender.py`).
- Obrazy produkcyjne CI/CD budują się pod `ghcr.io/<twoja-organizacja>/...` – ustaw `github.repository_owner` zgodnie z Twoim kontem/organizacją.



# Davtro Apartments – platforma wynajmu krotkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
Namespace: `davtro`

## Architektura
1. **Frontend** (SPA) → Nginx
2. **FastAPI** → PostgreSQL + Redis (cache) + Kafka (producent)
3. **message-processor** (consumer) → Kafka → email + PostgreSQL update
4. **Spring Boot** → panel raportowy / admin
5. **Spark** → analityka marketingowa z Kafka
6. **Vault** → sekrety (raft + ESO + auto-bootstrap; dynamiczne credsy DB dla FastAPI/consumer)
7. **Observability** → Prometheus + Grafana + Loki + Tempo

## Lokalne uruchomienie (dev)
```bash
cd backend-fastapi
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## K8s / ArgoCD
```bash
kubectl apply -f argocd/application.yaml -n argocd
```
Push do `main` → GitHub Actions buduje obrazy → Kustomize aktualizuje tagi → ArgoCD sync.

### Dostep ArgoCD do prywatnego repozytorium GitHub

ArgoCD musi miec osobne dane dostepowe do prywatnego repozytorium. Tokenu nie
wpisuj do tego repozytorium ani do `application.yaml`. Utworz secret w
namespace `argocd` z tokenem GitHub (PAT powinien miec co najmniej `Contents:
Read`):

```bash
read -s GITHUB_PAT
export GITHUB_PAT
kubectl create secret generic davtro-github-repo \
	-n argocd \
	--from-literal=type=git \
	--from-literal=url=https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01.git \
	--from-literal=username=exea-centrum \
	--from-literal=password="$GITHUB_PAT" \
	--dry-run=client -o yaml |
	kubectl label -f - argocd.argoproj.io/secret-type=repository --local -o yaml |
	kubectl apply -f -
unset GITHUB_PAT
```

Nastepnie odswiez ArgoCD:

```bash
kubectl annotate application davtro-website -n argocd \
	argocd.argoproj.io/refresh=hard --overwrite
kubectl get application davtro-website -n argocd -w
```

## WAZNE – przed produkcja
- ~~Vault dev-mode~~ ZROBIONE (raft + auto-bootstrap); produkcja HA: Helm chart + auto-unseal
- ~~ArgoCD Vault Plugin (AVP)~~ ZROBIONE inaczej: External Secrets Operator (ESO)
- Skonfiguruj realny SMTP w secretach
- Zainstaluj Prometheus Operator jesli chcesz uzyc ServiceMonitor

# Vault: pełna automatyzacja (full-auto cold start)

Usunięcie projektu + wklejenie `argocd/application.yaml` do ArgoCD wystarcza – bez kroków ręcznych:

1. ArgoCD deployuje stack; Job `vault-bootstrap` (PostSync, idempotentny) inicjalizuje i unsealuje Vault (klucze: `/vault/data/bootstrap-keys` na PVC `vault-data-vault-0`), generuje `DB_PASSWORD` do KV `davtro/db`, włącza audit→stdout (Loki), auth kubernetes (+ `system:auth-delegator`), policy/role `davtro-apps`, database engine + rolę `davtro-app-rw` (retry aż Postgres wstanie) oraz `davtro-snapshot`.
2. ESO tworzy `davtro-secrets` (statyczne KV: db/smtp) → Postgres robi initdb z tym hasłem → ESO tworzy dynamiczne credsy `fastapi-db-creds` / `message-processor-db-creds` z `database/creds/davtro-app-rw` (rotacja co 30 min; aplikacje przełączają pool(e) w locie – `watch_db_creds` / `get_engine()`).
3. CronJob `vault-snapshot` robi nocny snapshot rafta (logowanie po ServiceAccount, retencja 14 dni).

## Jednorazowa migracja klastra sprzed automatyzacji

Jeżeli Vault był inicjalizowany ręcznie (przed wdrożeniem `vault-bootstrap.yaml`), Job wyexituje z prośbą o plik kluczy. Skonsumuj raz wartości z pierwotnego `vault operator init`:

```bash
kubectl -n davtro02 exec vault-0 -- sh -c \
  'printf "%s\n%s\n" "<UNSEAL_KEY>" "<ROOT_TOKEN>" > /vault/data/bootstrap-keys && chmod 600 /vault/data/bootstrap-keys'
kubectl -n davtro02 delete job vault-bootstrap
kubectl -n argocd annotate application davtro-website argocd.argoproj.io/refresh=hard --overwrite
kubectl -n davtro02 logs -f job/vault-bootstrap   # czekaj na "[bootstrap] DONE"
```

## Weryfikacja Vault + ESO

```bash
kubectl -n davtro02 get externalsecret                                            # 3x SYNCED=True
kubectl -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -c '\du'  # userzy v-token-...
kubectl -n davtro02 logs deploy/fastapi-web-app | grep -i "przelaczono\|creds"
```

Roadmapa: **Krok 4** = PKI (cert-manager + Vault issuer dla ingress TLS) + GitHub OIDC dla CI; opcjonalnie Transit (szyfrowanie PII w PostgreSQL) i migracja Springa na Spring Cloud Vault.

---

# Platforma Davtro — co to za strona i po co każdy komponent (wersja bez sekretów)

> Ta sekcja nie zawiera żadnych haseł, tokenów ani certyfikatów. Opisuje wyłącznie przeznaczenie elementów systemu.

## 1. Jaka to strona i do czego służy

**Davtro Apartments** to platforma wynajmu krótkoterminowego (apartamenty / pokoje na doby):

- gość wybiera apartament i termin w kalendarzu na stronie,
- wysyła rezerwację przez API,
- system zapisuje rezerwację, wysyła e-mail z potwierdzeniem i fakturą proforma,
- zgody marketingowe gościa zasilają analitykę marketingową,
- panel administracyjno-raportowy służy obsłudze obiektu.

Wejście od internetu: host `davtro.local` (Ingress `davtro-ingress`):

| Ścieżka | Dokąd prowadzi | Do czego służy |
|---|---|---|
| `/` | `frontend-svc:80` (Nginx) | strona dla gościa: oferta, kalendarz, formularz rezerwacji |
| `/api` | `fastapi-web-app-svc:80` | REST API rezerwacji (tworzenie / odczyt / status) |
| `/grafana` | `grafana:3000` | podgląd metryk, logów i tracingu |
| `/kafka-ui` | `kafka-ui:80` | podgląd topiców i wiadomości Kafka (diagnostyka) |
| `/pgadmin` | `pgadmin:80` | przegląd bazy przez przeglądarkę (administracja) |
| `spark.davtro.local /` | `spark-master-svc:8082` | podgląd jobów Spark (analityka) |

## 2. Mapa komponentów — co do czego uderza i po co istnieje

```text
gość (przeglądarka)
  |
  v
Ingress davtro.local
  |-- / ---------> frontend (Nginx, statyczna strona + kalendarz)
  |-- /api ------> fastapi-web-app (API rezerwacji)
  |                   |-- zapis/odczyt ---> postgres (baza rezerwacji)
  |                   |-- cache/sesje ----> redis (szybka pamięć)
  |                   |-- event rezerwacji -> kafka-kraft (kolejka zdarzeń)
  |-- /grafana ---> grafana (metryki + logi + trace w jednym miejscu)
  |-- /kafka-ui --> kafka-ui (podgląd kolejek)
  |-- /pgadmin ---> pgadmin (podgląd bazy)
```

```text
kafka-kraft (bookings-created, email-invoices, marketing-actions)
  |
  +--> message-processor (konsument: wysyła e-maile, aktualizuje status w DB)
  +--> spring-app (panel raportowy Java na tych samych danych)
  +--> spark-master + spark-worker x2 (analityka marketingowa w tle)

postgres-exporter / kafka-exporter / node-exporter
  |
  v
prometheus (metryki) ---> grafana (wykresy)

promtail (zbiera logi z każdego noda)
  |
  v
loki (magazyn logów) ---> grafana (przeszukiwanie logów)

aplikacje (OpenTelemetry)
  |
  v
tempo (magazyn trace) ---> grafana (podgląd ścieżki requestu)

vault + vault-bootstrap (sejf na sekrety, auto-konfiguracja po starcie)
  |
  v
external-secrets (SecretStore + ExternalSecret + VaultDynamicSecret)
  |
  v
Sekrety Kubernetes (davtro-secrets, fastapi-db-creds, message-processor-db-creds)
  |
  v
postgres / fastapi / message-processor / spring-app / pgadmin / postgres-exporter
```

## 3. Warstwa aplikacji — opis każdego elementu

### frontend (Nginx)
- **Co to:** statyczna strona dla gościa (oferta, zdjęcia, kalendarz, formularz).
- **Po co:** szybkie serwowanie treści bez obciążania API.
- **Z kim gada:** przeglądarka gościa; formularz woła `/api` na backendzie.

### fastapi-web-app — API (Python FastAPI, 3 repliki na produkcji)
- **Co to:** główne API rezerwacji (`POST /api/...`, `GET /api/health` do sond).
- **Po co:** przyjmuje rezerwacje, waliduje terminy, zapisuje do bazy, odkłada event na kolejkę.
- **Z kim gada:** `postgres-clusterip:5432` (zapis rezerwacji), `redis:6379` (cache dostępności / idempotencja), `kafka-kraft:9092` (publikacja eventu). Konfiguracja z `ConfigMap fastapi-config`, sekrety z `davtro-secrets` + dynamiczne credsy z `/etc/db-creds`.
- **Odporność:** `HPA 2-8 (CPU 70%)`, `PDB minAvailable: 1`, sondy `readiness/liveness /api/health`.

### message-processor (Python consumer)
- **Co to:** pracownik w tle, konsument Kafki.
- **Po co:** odbiera event rezerwacji, wysyła e-mail (potwierdzenie + faktura proforma) i przestawia status rezerwacji w bazie; konsumuje też zgody marketingowe. Bez niego rezerwacja zostałaby w statusie "oczekująca".
- **Z kim gada:** `kafka-kraft:9092` (konsumpcja), `postgres-clusterip:5432` (update statusu), SMTP (wysyłka).

### spring-app-deployment (Java Spring Boot `:8081`)
- **Co to:** panel raportowo-administracyjny na tych samych danych co FastAPI.
- **Po co:** zestawienia, raporty, obsługa obiektu w technologii Java.
- **Z kim gada:** `postgres-clusterip`, `kafka-kraft`.

### spark-master + spark-worker x2 (Apache Spark 3.5)
- **Co to:** silnik obliczeń batch (master `:7077`, UI `:8082` + 2 workery).
- **Po co:** analityka marketingowa (`spark-jobs/marketing_analytics.py`), np. agregacje zgód / kampanii. Odciąża bazę transakcyjną od ciężkich zapytań.
- **Z kim gada:** workerzy łączą się do `spark://spark-master-svc:7077`.

## 4. Warstwa danych — po co Postgres, Redis i Kafka

### postgres-db (PostgreSQL 16, StatefulSet 1x + headless Service `postgres-clusterip:5432`)
- **Co to:** jedyne trwałe źródło prawdy (baza `davtro_rentals`).
- **Po co:** rezerwacje, statusy, użytkownicy, zgody marketingowe.
- **Trwałość:** wolumen `pgdata 5Gi` (szablon PVC w StatefulSecie).
- **Dostęp:** tylko wewnątrz klastra; graficznie przez `pgadmin`, metryki przez `postgres-exporter`.

### redis (Redis 7, Deployment 1x, `redis:6379`)
- **Co to:** pamięć podręczna klucz-wartość (in-memory).
- **Po co:** cache dostępności terminów, sesje, bufor eventów, odciążenie Postgresa od powtarzalnych odczytów. Dane ulotne — po restarcie odtwarzane z bazy.
- **Z kim gada:** wyłącznie `fastapi-web-app` (zmienne `REDIS_HOST/REDIS_PORT` z ConfigMap).

### kafka-kraft (Apache Kafka 3.7, KRaft bez Zookepera, StatefulSet 1x)
- **Co to:** rozproszony dziennik zdarzeń (kolejka): broker `:9092` + kontroler `:9093`, wolumen `kafka-data 5Gi`.
- **Po co:** rozprzęga API od wysyłki maili i analityki. API odpowiada gościowi od razu, a ciężka praca (mail, faktura, agregacje) dzieje się asynchronicznie. Topici (po 3 partycje): `bookings-created` (nowe rezerwacje), `email-invoices` (maile/faktury), `marketing-actions` (zgody/akcje marketingowe).
- **Kto tworzy topici:** `Job kafka-topic-job` (ArgoCD `PostSync` hook, samousuwalny po 300 s).
- **Kto produkuje / konsumuje:** producent `fastapi-web-app`; konsumenci `message-processor`, `spring-app`, joby Spark.
- **Podgląd:** `kafka-ui`.

## 5. Bezpieczeństwo i sekrety — po co Vault i External Secrets (bez wartości)

### vault (HashiCorp Vault 1.17, StatefulSet 1x, `:8200/:8201`, storage Raft na PVC)
- **Co to:** sejf na sekrety z szyfrowaniem danych w spoczynku.
- **Po co:** żadne hasło nie leży w Git. Aplikacje dostają je dopiero w klastrze.
- **Tryb:** Raft na wolumenie `vault-data 2Gi`, UI włączone, telemetria dla Prometheusa.

### vault-bootstrap (Deployment z pętlą self-heal co 60 s)
- **Co to:** automatyczny konfigurator sejfu po starcie od zera (cold start).
- **Po co:** odtwarza cały łańcuch bez klikania: init/unseal, audit do stdout, wpisy KV, auth Kubernetes, polityki i role, silnik bazy danych + wyrównanie hasła z żywym Postgresem. Kończy logiem `DONE - Vault skonfigurowany`.

### vault-snapshot (CronJob `0 3 * * *` + PVC `vault-backup 2Gi`)
- **Co to:** nocna kopia Rafta (`snapshot-STAMP.snap`, retencja 14 dni).
- **Po co:** odtworzenie sejfu po awarii (`raft snapshot restore`).
- **Uwierzytelnianie:** tokenem krótkoterminowym z logowania JWT ServiceAccount (rola snapshotowa), bez stałych sekretów w YAML.

### SecretStore `vault-backend` / `vault-dynamic` + ExternalSecret + VaultDynamicSecret
- **Co to:** most `Vault -> Kubernetes Secrets` (operator ESO w osobnym namespace `external-secrets`).
- **Po co:** zamienia wpisy sejfu na natywne Sekrety K8s, które Deploymenty montują jako env/pliki:
  - `davtro-secrets` (statyczne: login/hasło DB + SMTP),
  - `fastapi-db-creds` / `message-processor-db-creds` (dynamiczne, rotowane konta DB z silnika `database/creds/...`).
- **Rotacja:** statyczne co 1 h, dynamiczne co 30 min; aplikacje Python przeładowują pule połączeń w locie.

## 6. Obserwowalność — po co Prometheus, Grafana, Loki, Promtail i Tempo

### prometheus (`prometheus:9090`)
- **Co to:** baza metryk liczbowych (scrape co 15 s).
- **Po co:** odpowiada na pytania "ile requestów?", "jaki czas odpowiedzi?", "czy baza/Kafka żyją?".
- **Skąd zbiera:** `fastapi-web-app-svc:80`, `postgres-exporter:9187`, `kafka-exporter:9308`, `node-exporter:9100`.

### postgres-exporter / kafka-exporter / node-exporter
- **Co to:** tłumacze stanu na metryki dla Prometheusa.
- **Po co:** osobno widać kondycję bazy, kolejek i samego węzła (CPU/RAM/dysk/sieć).

### grafana (`grafana:3000`, gotowy dashboard `Davtro Platform Overview`)
- **Co to:** jedno okno na metryki + logi + trace (źródła: Prometheus, Loki, Tempo).
- **Po co:** diagnoza "co się stało?" bez grzebania po podach. Wystawiona pod `/grafana`.

### loki (`loki:3100`) + promtail (DaemonSet na każdym nodzie)
- **Co to:** magazyn logów (Loki) + zbieracz logów (Promtail czyta `/var/log/containers/*.log` i wysyła do Loki).
- **Po co:** przeszukiwanie logów wszystkich podów (API, konsument, Vault audit ze stdout) z jednego miejsca w Grafanie.

### tempo (`tempo:3200`)
- **Co to:** magazyn trace rozproszonych (OpenTelemetry, protokoły OTLP http+grpc).
- **Po co:** pokazuje ścieżkę jednego requestu przez system (frontend -> API -> DB/Kafka -> konsument), więc widać, który krok spowalnia rezerwację.

### kafka-ui (`:8080`, ścieżka `/kafka-ui`) i pgadmin (`:80`, ścieżka `/pgadmin`)
- **Po co:** szybki podgląd "czy eventy płyną?" (Kafka) i "co leży w bazie?" (Postgres) bez wchodzenia na pody.

## 7. Wejście, skalowanie, odporność i polityki

- **Ingress:** `davtro-ingress` (klasa `public`, host `davtro.local`) + `spark-ingress` (`spark.davtro.local`). Bez zainstalowanego kontrolera Ingress obiekty istnieją, ale nie dostają adresu — stan oczekiwany w tym środowisku (adnotacja `ignore-healthcheck`).
- **Skalowanie:** `HPA fastapi-web-app-hpa` (2-8 replik przy CPU 70%), na produkcji bazowo 3 repliki API, 2 repliki frontendu i 2 workery Spark.
- **Dostępność:** `PDB fastapi-web-app-pdb` (min. 1 dostępny przy pracach na węzłach).
- **Sieć:** `NetworkPolicy default-deny-ingress` (domyślnie zamknij) + jawne otwarcia: ruch wewnątrz namespacu, ESO (`external-secrets`) do Vaulta (`:8200/:8201`), wejście do API i frontendu.
- **Ład:** `ClusterPolicy davtro-baseline-policy` (Kyverno, `Enforce`): obrazy z zaufanych rejestrów, wymagane `requests/limits`, zakaz kontenerów uprzywilejowanych. `ServiceMonitor`y są przygotowane, ale nieaktywne do czasu instalacji Prometheus Operatora.

## 8. GitOps w jednym zdaniu

`push do main -> CI buduje 5 obrazów GHCR (api, consumer, frontend, spark, spring) i podbija tagi w Kustomize -> ArgoCD (Aplikacja davtro-website, auto-sync prune+selfHeal, CreateNamespace) buduje overlay production i odtwarza cały powyższy graf w namespace davtro02`.

```text
                    +---------------- GitHub HEAD ------------------+
                    | manifests/overlays/production -> ../../base   |
                    +---------------+--------------------------------+
                                    | pull + kustomize build
                          +---------v-----------+
                          | ArgoCD davtro-website (ns argocd) |
                          +---------+-----------+
                                    | apply -> ns davtro02
        +---------------------------+-----------------------------+
        |                           |                             |
+-------v-------+        +----------v----------+       +----------v----------+
|   VAULT LAYER |        |     DATA LAYER      |       |     APP LAYER       |
| vault-0 :8200 |<-------+ postgres-db :5432   |<------+ fastapi-web-app :8080|
| bootstrap     |  dynamic| redis :6379         |  SQL  | message-processor  |
| snapshot 03:00|  creds  | kafka-kraft :9092   |  KV   | spring-app :8081   |
+-------+-------+        +----------+----------+       | frontend nginx :8080 |
        ^                           ^                  | spark master/worker |
        | K8s auth                    |                  +----------+----------+
        | jwt davtro-sa               |                             | Kafka topics
+-------v---------------------------v-----------------------------v----------+
| SECRETS LAYER: SecretStore vault-backend/vault-dynamic + ExternalSecret     |
| davtro-secrets + VaultDynamicSecret db-creds-davtro-app-rw ->               |
| fastapi-db-creds / message-processor-db-creds                               |
+--------------------------------+--------------------------------------------+
                                 |
        +------------------------v-------------------------------------------+
        | OBSERVABILITY: prometheus:9090 <- postgres/kafka/node-exporter      |
        | grafana:3000 (Prometheus+Loki+Tempo) | loki:3100 <- promtail (DS)   |
        | tempo:3200 | kafka-ui:8080 | pgadmin:80                             |
        +------------------------------------------------+-------------------+
                                         |
                          +--------------v---------------+
                          | EDGE: Ingress davtro.local   |
                          | /api->fastapi /->frontend    |
                          | /grafana /kafka-ui /pgadmin  |
                          | spark.davtro.local->spark-ui |
                          +------------+-----------------+
                                       |
                    +--------+---------+---------+--------+
                    | HPA fastapi 2-8 CPU70% | PDB minAvailable:1 |
                    | NetworkPolicy deny+allow | Kyverno Enforce |
                    +--------------------------------------------+
```

## 9. Szczegółowy opis architektury i przepływu

### 9.1 Diagram przepływu (Full Stack)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GITHUB (main branch)                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ CI/CD Pipeline (.github/workflows/ci-cd.yaml)                                   │   │
│  │  1. Build 5 obrazów Docker (api, consumer, frontend, spring, spark) -> GHCR     │   │
│  │  2. kustomize edit set image -> tagi w manifests/base/kustomization.yaml        │   │
│  │  3. git commit + git push                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
                                          │
                                          │ webhook / auto-sync (3min)
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ARGOCD (namespace: argocd)                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ Application: davtro-website                                                      │   │
│  │  source: manifests/overlays/production -> ../../base                            │   │
│  │  destination: https://kubernetes.default.svc, namespace: davtro02               │   │
│  │  syncPolicy: automated (prune: true, selfHeal: true)                           │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
                                          │
                                          │ kustomize build + apply
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              MICROK8S CLUSTER (namespace: davtro02)                     │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              EDGE LAYER (Ingress + TLS)                         │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ Ingress Controller (nginx, microk8s enable ingress)                     │  │   │
│  │  │  TLS termination: cert-manager + Vault PKI                             │  │   │
│  │  │  Hosts: davtro.local, spark.davtro.local                                │  │   │
│  │  │  Secrets: davtro-tls, spark-tls (auto-rotowane przez cert-manager)     │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │         │                    │                    │                    │          │
│  │    /api -> fastapi      / -> frontend      /grafana -> grafana   /spark -> spark │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              APPLICATION LAYER                                  │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ fastapi-web-app  │  │ message-processor│  │ spring-app       │              │   │
│  │  │ (Python/FastAPI) │  │ (Kafka consumer) │  │ (Java/Spring)    │              │   │
│  │  │ :8080, replicas:3│  │ :8080, replicas:1│  │ :8081, replicas:1│              │   │
│  │  │ HPA: 2-8, CPU70% │  │                  │  │                  │              │   │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘              │   │
│  │           │ Kafka produce        │ Kafka consume        │                        │   │
│  │           ▼                      ▼                      ▼                        │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ frontend (nginx) │  │ spark-master     │  │ spark-worker (x2)│              │   │
│  │  │ :8080, replicas:2│  │ :8082, :4040     │  │ :8083             │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.2 Data Layer

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              DATA LAYER                                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ postgres-db      │  │ redis            │  │ kafka-kraft      │              │   │
│  │  │ (StatefulSet)    │  │ (Deployment)     │  │ (StatefulSet)    │              │   │
│  │  │ :5432            │  │ :6379            │  │ :9092            │              │   │
│  │  │ PVC: 5Gi         │  │ cache layer      │  │ topics:          │              │   │
│  │                                               └──────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.3 Secrets Layer (Vault + ESO)

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SECRETS LAYER (Vault + ESO)                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ vault-0 (StatefulSet, raft storage na PVC 2Gi)                           │  │   │
│  │  │  :8200 (API)                                                             │  │   │
│  │  │  Engines:                                                                │  │   │
│  │  │   - kv-v2: davtro/db, davtro/smtp (sekrety aplikacji)                   │  │   │
│  │  │   - database: postgres-clusterip (dynamiczne credsy)                    │  │   │
│  │  │   - pki: davtro-internal CA (certyfikaty TLS)                            │  │   │
│  │  │  Auth: kubernetes (SA davtro-sa), token (cert-manager)                   │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │           ▲                                       ▲                              │   │
│  │           │ K8s auth (jwt)                        │ token auth                   │   │
│  │           │                                       │                              │   │
│  │  ┌────────┴───────────────────────────────────────┴─────────────────────────┐  │   │
│  │  │ vault-bootstrap (Deployment, self-heal co 60s)                           │  │   │
│  │  │  1. vault operator init (1 key share) -> bootstrap-keys na PVC           │  │   │
│  │  │  2. vault operator unseal (auto-unseal z pliku)                         │  │   │
│  │  │  3. kv-v2: davtro/db, davtro/smtp (generuje DB_PASSWORD jeśli brak)     │  │   │
│  │  │  4. audit: stdout -> promtail -> Loki -> Grafana                         │  │   │
│  │  │  5. auth/kubernetes/config + role davtro-apps, davtro-snapshot           │  │   │
│  │  │  6. database engine + role davtro-app-rw (TTL 1h/24h)                    │  │   │
│  │  │  7. PKI: root CA + roles davtro-ingress, davtro-internal                 │  │   │
│  │  │  8. Policy pki-issuer + role cert-manager (token auth)                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ External Secrets Operator (namespace: external-secrets)                  │  │   │
│  │  │  SecretStore vault-backend: kv-v2, K8s auth, role davtro-apps           │  │   │
│  │  │  SecretStore vault-dynamic: database engine (bez path prefix)           │  │   │
│  │  │                                                                          │  │   │
│  │  │  ExternalSecret davtro-secrets -> Secret davtro-secrets (refresh: 1h)    │  │   │
│  │  │   DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                        │  │   │
│  │  │                                                                          │  │   │
│  │  │  VaultDynamicSecret db-creds-davtro-app-rw                              │  │   │
│  │  │   -> ExternalSecret fastapi-db-creds (refresh: 30m)                      │  │   │
│  │  │   -> ExternalSecret message-processor-db-creds (refresh: 30m)            │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ cert-manager (namespace: cert-manager)                                   │  │   │
│  │  │  ClusterIssuer vault-issuer:                                             │  │   │
│  │  │   server: http://vault.davtro02.svc.cluster.local:8200                   │  │   │
│  │  │   path: pki/sign/davtro-ingress                                          │  │   │
│  │  │   auth: tokenSecretRef cert-manager-vault-token                          │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate davtro-tls:                                                 │  │   │
│  │  │   Secret: davtro-tls, CN=davtro.local, duration: 90d, renew: 15d        │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate spark-tls:                                                  │  │   │
│  │  │   Secret: spark-tls, CN=spark.davtro.local, duration: 90d, renew: 15d   │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```
### 9.3 Secrets Layer (Vault + ESO)

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SECRETS LAYER (Vault + ESO)                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ vault-0 (StatefulSet, raft storage na PVC 2Gi)                           │  │   │
│  │  │  :8200 (API)                                                             │  │   │
│  │  │  Engines:                                                                │  │   │
│  │  │   - kv-v2: davtro/db, davtro/smtp (sekrety aplikacji)                   │  │   │
│  │  │   - database: postgres-clusterip (dynamiczne credsy)                    │  │   │
│  │  │   - pki: davtro-internal CA (certyfikaty TLS)                            │  │   │
│  │  │  Auth: kubernetes (SA davtro-sa), token (cert-manager)                   │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │           ▲                                       ▲                              │   │
│  │           │ K8s auth (jwt)                        │ token auth                   │   │
│  │           │                                       │                              │   │
│  │  ┌────────┴───────────────────────────────────────┴─────────────────────────┐  │   │
│  │  │ vault-bootstrap (Deployment, self-heal co 60s)                           │  │   │
│  │  │  1. vault operator init (1 key share) -> bootstrap-keys na PVC           │  │   │
│  │  │  2. vault operator unseal (auto-unseal z pliku)                         │  │   │
│  │  │  3. kv-v2: davtro/db, davtro/smtp (generuje DB_PASSWORD jeśli brak)     │  │   │
│  │  │  4. audit: stdout -> promtail -> Loki -> Grafana                         │  │   │
│  │  │  5. auth/kubernetes/config + role davtro-apps, davtro-snapshot           │  │   │
│  │  │  6. database engine + role davtro-app-rw (TTL 1h/24h)                    │  │   │
│  │  │  7. PKI: root CA + roles davtro-ingress, davtro-internal                 │  │   │
│  │  │  8. Policy pki-issuer + role cert-manager (token auth)                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ External Secrets Operator (namespace: external-secrets)                  │  │   │
│  │  │  SecretStore vault-backend: kv-v2, K8s auth, role davtro-apps           │  │   │
│  │  │  SecretStore vault-dynamic: database engine (bez path prefix)           │  │   │
│  │  │                                                                          │  │   │
│  │  │  ExternalSecret davtro-secrets -> Secret davtro-secrets (refresh: 1h)    │  │   │
│  │  │   DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                        │  │   │
│  │  │                                                                          │  │   │
│  │  │  VaultDynamicSecret db-creds-davtro-app-rw                              │  │   │
│  │  │   -> ExternalSecret fastapi-db-creds (refresh: 30m)                      │  │   │
│  │  │   -> ExternalSecret message-processor-db-creds (refresh: 30m)            │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ cert-manager (namespace: cert-manager)                                   │  │   │
│  │  │  ClusterIssuer vault-issuer:                                             │  │   │
│  │  │   server: http://vault.davtro02.svc.cluster.local:8200                   │  │   │
│  │  │   path: pki/sign/davtro-ingress                                          │  │   │
│  │  │   auth: tokenSecretRef cert-manager-vault-token                          │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate davtro-tls:                                                 │  │   │
│  │  │   Secret: davtro-tls, CN=davtro.local, duration: 90d, renew: 15d        │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate spark-tls:                                                  │  │   │
│  │  │   Secret: spark-tls, CN=spark.davtro.local, duration: 90d, renew: 15d   │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.4 Observability Layer + Network Policies + Backup

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              OBSERVABILITY LAYER                                 │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ prometheus       │  │ grafana          │  │ loki             │              │   │
│  │  │ :9090            │  │ :3000            │  │ :3100            │              │   │
│  │  │ metrics scrape   │  │ dashboards       │  │ log aggregation  │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ tempo            │  │ promtail         │  │ kafka-ui         │              │   │
│  │  │ :3200            │  │ (DaemonSet)      │  │ :8080            │              │   │
│  │  │ trace storage    │  │ log collection   │  │ Kafka management │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  │  ┌──────────────────┐  ┌──────────────────┐                                    │   │
│  │  │ pgadmin          │  │ exporters        │                                    │   │
│  │  │ :80              │  │ postgres, kafka, │                                    │   │
│  │  │ DB management    │  │ node             │                                    │   │
│  │  └──────────────────┘  └──────────────────┘                                    │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              NETWORK POLICIES                                    │   │
│  │  default-deny-ingress (zamyka wszystko)                                          │   │
│  │  allow-intra-namespace (ruch wewnątrz davtro02)                                  │   │
│  │  allow-eso-to-vault (external-secrets -> vault:8200)                             │   │
│  │  allow-certmanager-to-vault (cert-manager -> vault:8200)                         │   │
│  │  allow-ingress-controller-to-web (ingress -> fastapi/frontend:8080)              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              BACKUP LAYER                                        │   │
│  │  vault-snapshot (CronJob, 03:00 daily) -> PVC vault-backup (retencja 14 dni)     │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 9.5 Odpowiedzialność komponentów

| Komponent | Plik(y) | Odpowiedzialność |
|-----------|---------|------------------|
| **ArgoCD** | `argocd/application.yaml` | GitOps: synchronizuje stan klastra z repozytorium. Auto-sync co 3 minuty, self-heal (naprawia ręczne zmiany), prune (usuwa zasoby nie w Git). |
| **GitHub Actions** | `.github/workflows/ci-cd.yaml` | CI: buduje 5 obrazów Docker (api, consumer, frontend, spring, spark) i push do GHCR. Aktualizuje tagi w `manifests/base/kustomization.yaml`. |
| **Kustomize** | `manifests/base/kustomization.yaml` | Deklaracja wszystkich zasobów K8s. Overlay production nadpisuje namespace, replica count, image tags. |
| **Vault** | `vault.yaml`, `vault-bootstrap.yaml` | Centralne zarządzanie sekretami: KV v2 (sekrety aplikacji), database engine (dynamiczne credsy), PKI (certyfikaty TLS), autoryzacja (K8s + token). |
| **vault-bootstrap** | `vault-bootstrap.yaml` | Automatyczna inicjalizacja Vault: init, unseal, konfiguracja KV/auth/database/PKI. Self-heal co 60s. |
| **External Secrets Operator** | `secret-store.yaml`, `external-secrets.yaml`, `external-secrets-db-dynamic.yaml` | Most między Vault a Kubernetes: synchronizuje sekrety z Vault do K8s Secrets. |
| **cert-manager** | `pki-issuer.yaml`, `certificates.yaml` | Zarządzanie certyfikatami TLS: zamawia z Vault PKI, automatycznie odnawia przed wygaśnięciem. |
| **Ingress Controller** | `ingress.yaml`, `network-policies.yaml` | Reverse proxy: terminacja TLS, routing do usług (fastapi, frontend, grafana, spark). |
| **Kyverno** | `kyverno-policy.yaml` | Polityki bezpieczeństwa: wymagane requests/limits, zakaz kontenerów uprzywilejowanych, zaufane rejestry. |

### 9.6 Przepływ sekretów (Vault -> Aplikacja)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ KV v2 Engine (mount: davtro)                                        │   │
│  │  davtro/db: { DB_USER: davtro, DB_PASSWORD: *** }                  │   │
│  │  davtro/smtp: { SMTP_USER: ***, SMTP_PASSWORD: *** }               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ExternalSecret davtro-secrets (refresh: 1h)                         │   │
│  │  -> Secret davtro-secrets (namespace: davtro02)                     │   │
│  │     DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ envFrom: secretRef                          │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Aplikacje: fastapi, message-processor, spring-app                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Database Engine (mount: database)                                   │   │
│  │  Role: davtro-app-rw                                                │   │
│  │    creation: CREATE ROLE ... LOGIN PASSWORD ... VALID UNTIL ...     │   │
│  │    revocation: DROP ROLE ...                                        │   │
│  │    default_ttl: 1h, max_ttl: 24h                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ VaultDynamicSecret db-creds-davtro-app-rw                           │   │
│  │  -> POST /v1/database/creds/davtro-app-rw                          │   │
│  │  -> generuje: { username: v-token-davtro-app-rw-xxx, password: *** }│   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ ExternalSecret (refresh: 30m)              │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: fastapi-db-creds, message-processor-db-creds               │   │
│  │  zawartość: { username: ..., password: ... }                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ volumeMount: /etc/db-creds (read-only)     │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Aplikacje:                                                          │   │
│  │  fastapi: DB_USER_FILE=/etc/db-creds/username                       │   │
│  │           DB_PASSWORD_FILE=/etc/db-creds/password                   │   │
│  │           (main.py watch_db_creds: przeladowuje pool przy zmianie)  │   │
│  │  message-processor: DB_USER_FILE, DB_PASSWORD_FILE                  │   │
│  │                      (db.py: przeladowuje SQLAlchemy)               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.7 Przepływ certyfikatów (Vault PKI -> Ingress)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT PKI (namespace: davtro02)                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ PKI Engine (mount: pki)                                             │   │
│  │  Root CA: davtro-internal (self-signed, homelab)                    │   │
│  │   CN=davtro-internal CA, TTL=87600h (10 lat)                        │   │
│  │                                                                     │   │
│  │  Roles:                                                             │   │
│  │   davtro-ingress:                                                   │   │
│  │     allowed_domains: davtro.local, spark.davtro.local               │   │
│  │     allow_subdomains: true, max_ttl: 2160h (90d)                    │   │
│  │   davtro-internal:                                                  │   │
│  │     allowed_domains: svc.cluster.local, cluster.local               │   │
│  │     allow_any_name: true, enforce_hostnames: false                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ token auth (cert-manager-vault-token)       │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ClusterIssuer vault-issuer (cert-manager)                           │   │
│  │  server: http://vault.davtro02.svc.cluster.local:8200               │   │
│  │  path: pki/sign/davtro-ingress                                      │   │
│  │  auth: tokenSecretRef cert-manager-vault-token                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Certificate resources                        │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Certificate davtro-tls                                              │   │
│  │  Secret: davtro-tls, CN=davtro.local                                │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  │                                                                     │   │
│  │ Certificate spark-tls                                               │   │
│  │  Secret: spark-tls, CN=spark.davtro.local                           │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ cert-manager generuje Secret z tls.crt/tls.key
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: davtro-tls, spark-tls (type: kubernetes.io/tls)            │   │
│  │  zawartość: { tls.crt: <cert PEM>, tls.key: <key PEM> }             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Ingress spec.tls.secretName                  │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Ingress Controller (nginx)                                          │   │
│  │  TLS termination na poziomie Ingress                                │   │
│  │  Hosts: davtro.local, spark.davtro.local                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.8 Co jest potrzebne poza projektem (wymagania zewnętrzne)

| Komponent | Instalacja | Status w projekcie |
|-----------|------------|-------------------|
| **MicroK8s** | `snap install microk8s --classic` | Wymagany jako runtime |
| **Ingress Controller** | `microk8s enable ingress` | CRD + Deployment w namespace `ingress` |
| **cert-manager** | `helm install jetstack/cert-manager --set crds.enabled=true` | CRD ClusterIssuer/Certificate wymagane przed syncem |
| **External Secrets Operator** | `helm install external-secrets external-secrets/external-secrets -n external-secrets` | CRD ExternalSecret/SecretStore wymagane przed syncem |
| **Kyverno** | `helm install kyverno kyverno/kyverno -n kyverno` | CRD ClusterPolicy wymagane przed syncem |
| **GitHub Container Registry** | Public package visibility | Obrazy Docker: `ghcr.io/<org>/...` |
| **DNS** | Wpisy A/CNAME dla `davtro.local`, `spark.davtro.local` | Wymagane dla dostępu z zewnątrz |


### 9.9 Czy działa full automatic deployment?

**TAK** — po jednorazowej instalacji komponentów zewnętrznych, cały pipeline działa automatycznie:

```
1. Developer push do main branch
2. GitHub Actions buduje 5 obrazów Docker -> GHCR
3. GitHub Actions aktualizuje tagi w kustomization.yaml -> git push
4. ArgoCD wykrywa zmiany (co 3 min) -> kustomize build -> apply
5. Pody są rolling update z nowymi obrazami
6. cert-manager monitoruje Certificate resources -> odnawia TLS przed wygaśnięciem
7. ESO synchronizuje sekrety z Vault co 1h (static) / 30min (dynamic)
8. vault-bootstrap self-heal co 60s (naprawia stan Vault po restarcie)
9. vault-snapshot CronJob codziennie o 03:00 -> backup raft na PVC
```


### 9.10 Czy można wstawić zewnętrzne certyfikaty?

**TAK** — 3 opcje:

**Opcja A: Import do Vault PKI (zalecane)**
```bash
# Wygeneruj CSR przez cert-manager, podpisz zewnętrznym CA, importuj do Vault
vault write pki/intermediate/set-signed certificate=@intermediate.cert.pem
# Vault PKI przejmuje zarządzanie rotacją
```

**Opcja B: Ręczny Secret (bez cert-manager)**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: davtro-tls
  namespace: davtro02
type: kubernetes.io/tls
data:
  tls.crt: <base64 encoded cert>
  tls.key: <base64 encoded key>
```
Następnie zmień `ingress.yaml` aby używał tego Secrets. **Uwaga**: brak auto-rotacji — trzeba ręcznie aktualizować.

**Opcja C: cert-manager + Let's Encrypt (dla publicznych domen)**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@davtro.local
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: public
```


### 9.11 Rotacja certyfikatów, tokenów i kluczy

| Zasób | Mechanizm rotacji | Lokalizacja | Częstotliwość |
|-------|-------------------|-------------|---------------|
| **Certyfikaty TLS** (davtro-tls, spark-tls) | cert-manager odnawia automatycznie `renewBefore: 360h (15d)` przed expiry | Secret: `davtro-tls`, `spark-tls` (ns davtro02) | Co 90 dni (auto) |
| **Vault PKI Root CA** | Brak auto-rotacji (10 lat TTL). Rotacja ręczna: nowy CA + re-sign wszystkich certów | Vault PKI engine | Ręcznie (rocznie) |
| **Dynamiczne credsy DB** | Vault database engine generuje nowe przy każdym request. Stare TTL 1h -> automatycznie wygasa | Secret: `fastapi-db-creds`, `message-processor-db-creds` (ns davtro02) | Co 30 min (ESO refresh) |
| **KV sekrety** (davtro/db, davtro/smtp) | ESO synchronizuje z Vault. Ręczna zmiana w Vault -> ESO podłapie | Secret: `davtro-secrets` (ns davtro02) | Co 1h (ESO refresh) |
| **cert-manager-vault-token** | Ręczna: `vault token create` -> update Secret | Secret: `cert-manager-vault-token` (ns cert-manager) | Ręcznie (rocznie) |
| **Vault unseal key** | Na PVC `/vault/data/bootstrap-keys` (tryb 1-of-1, homelab). Produkcja: auto-unseal (cloud KMS) | PVC: vault-data-vault-0 | Ręcznie (po każdym restarcie) |
| **Vault snapshot** | CronJob codziennie 03:00, retencja 14 dni | PVC: vault-backup | Codziennie |
| **Docker obrazy** | GitHub Actions po każdym push do main | GHCR | Każdy commit |

### 9.12 Gdzie są przechowywane sekrety i certyfikaty

```
PRZECHOWYWANIE SEKRETÓW

  VAULT (namespace: davtro02)
   /vault/data/ (PVC 2Gi)
    - bootstrap-keys (unseal key + root token, chmod 600)
    - raft/ (stan Vault: KV, auth, policies)

  KUBERNETES SECRETS (namespace: davtro02)
   davtro-secrets: DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD
   fastapi-db-creds: username, password (dynamiczne)
   message-processor-db-creds: username, password (dynamiczne)
   davtro-tls: tls.crt, tls.key (auto-rotowane)
   spark-tls: tls.crt, tls.key (auto-rotowane)

  KUBERNETES SECRETS (namespace: cert-manager)
   cert-manager-vault-token: token (Vault auth dla cert-manager)

  PVC (namespace: davtro02)
   vault-backup: snapshot-*.snap (codziennie, retencja 14 dni)
```


### 9.13 Potwierdzenie działania (stan aktualny)

```
CERTYFIKATY:
  davtro-tls: Ready=True, CN=davtro.local, Issuer=vault-issuer, Expiry=2026-12-11
  spark-tls:  Ready=True, CN=spark.davtro.local, Issuer=vault-issuer, Expiry=2026-12-11

CLUSTERISSUER:
  vault-issuer: Ready=True (token auth)

ARGODCD:
  davtro-website: SYNC=Synced, HEALTH=Healthy

PODY (23 Running, 0 Errors):
  fastapi-web-app (3 replicas), frontend (2), message-processor, spring-app
  postgres-db, redis, kafka-kraft, kafka-ui
  vault-0, vault-bootstrap
  spark-master, spark-worker (2)
  prometheus, grafana, loki, tempo, promtail
  postgres-exporter, kafka-exporter, node-exporter
  pgadmin
```
