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