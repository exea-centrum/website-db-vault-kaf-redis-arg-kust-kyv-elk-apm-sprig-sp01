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
