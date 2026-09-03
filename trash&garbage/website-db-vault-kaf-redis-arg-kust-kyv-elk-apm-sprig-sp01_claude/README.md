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
