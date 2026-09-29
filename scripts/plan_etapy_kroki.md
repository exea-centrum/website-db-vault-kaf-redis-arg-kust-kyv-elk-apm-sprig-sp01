## A. Porównanie: Twoja lista vs. stan zweryfikowany dziś

| KROK | Co mówi Twoja lista | Co jest **naprawdę** (repo + live cluster) | Zgoda? |
|---|---|---|---|
| **1** Raft + PVC | ✅ | ✅ `Seal Type shamir (1 share)`, `Storage Type raft`, PVC 2Gi | ✅ |
| **1** Audit → Loki | ✅ | ✅ `vault audit list → file/` | ✅ |
| **1** Metryki → Prometheus | „✅/częściowo, telemetry + scrape" | ⚠️ Telemetry **włączone**, ale w `prometheus.yaml` **nie ma joba `vault`** (są: fastapi, postgres/kafka/node-exporter, cert-expiry). `service-monitors.yaml` i `vault-servicemonitor.yaml` **nie są nawet wpisane w `resources`** kustomization (nie tylko „wyłączone”), a **Prometheus Operator nie działa** (jest sam Deployment `prometheus`, CRD tylko) | ⚠️ trafnie „częściowo", ale konkret jest inny |
| **1** KV v2 | ✅ | ✅ `sys/mounts/davtro → options: {version: 2}`, klucze `auth/db/smtp` | ✅ |
| **1** Snapshot CronJob | ✅ | ❌ **`SUSPEND=True`, `lastSuccessfulTime` puste** → nigdy nie zadziałał. W repo `suspend` nie ma (ręczna interwencja). Brak kopii poza PVC | ❌ **błąd** |
| **2** ESO zamiast AVP | ✅ | ✅ 3 SecretStore `Valid`, 3 ExternalSecret `SecretSynced`, dyn creds odświeżane co 30 min | ✅ |
| **3** Dynamic DB creds | ✅ 80% | ✅ w 80% – `database/roles → **tylko** davtro-app-rw`, `sslmode=disable`; fastapi + consumer dynamicznie, **spring/spark statyczne `davtro-secrets`** | ✅ |
| **4** Transit PII | ❌ **0%** („grep transit trafia tylko w komentarz", „PII leży w Postgres w plaintext") | ✅ **ZRÓBIONE i działa**: silnik `transit/`, klucz `davtro-app` (`aes256-gcm96`, auto-rotate 720h), polityka + rola `davtro-transit`, kod `transit_client.py` + `encrypt_pii/decrypt_pii` w `main.py`, **13/13 wierszy zaszyfrowanych**, `/api/health → transit: True`, e2e `decrypt → user1` potwierdzone na żywym API | ❌ **nieaktualne** |
| **5** PKI | „częściowo, brak `pki intermediate`" | ✅ trafne: `pki/roles → davtro-ingress, davtro-internal`, `pki/issuers → **1** (bez intermediate) | ✅ |
| **5** ClusterIssuer + Certificate | ✅ działa | ✅ potwierdzone: 2 ClusterIssuer + 2 Issuer (bootstrap CA dla Vaulta), **9 Certificate READY**, mTLS fastapi/consumer/spring, TLS ingressu i Sparka | ✅ |
| **5** `vault.yaml: tls_disable=true`, „Vault na plain HTTP" | ❌ | ✅ **Vault na TLS :8203** (KROK 9/10), `tls_cert_file`, CA `davtro-vault-ca`, port 8200 nie istnieje. W repo jest tylko `tls_disable_client_certs = true` (świadomie: klienci autoryzują się tokenem) | ❌ **nieaktualne** |
| **5** OIDC / ESO `pki/issue` | ❌ | ✅ nadal nie ma: `vault auth list → kubernetes/, token/` (brak `jwt/`); certy robi cert-manager przez `pki/sign` (nie ESO) – to jest prawidłowy wariant, nie brak | ✅ |
| **6** NetworkPolicy + Kyverno | ✅ | ✅ 8 NP (default-deny + allow-*) i 3 ClusterPolicy | ✅ |
| **6** Test restore, pgadmin, ServiceMonitor | ❌ | ✅ trafne: restore nieprzetestowany (tym bardziej – brak backupów), **pgadmin ma 0 volumes** (potwierdzone), ServiceMonitor czeka na operatora (którego nie ma) | ✅ |
| **(nowe)** KROK 11 Kafka SSL | — | ❌ **nie działa**: `InvalidAlgorithmParameterException: the trustAnchors parameter must be non-empty` → **truststore brokera pusty**, `KAFKA_SSL_CLIENT_AUTH=required` odrzuca certy klientów; FastAPI nie publikuje eventów (`PLAINTEXT :9092 OK, SSL :9094 FAIL`) | 🔴 nowy defekt |

---

## B. Podsumowanie

**✅ Działa i jest wdrożone (nie ruszać):** raft+PVC, audit, KV v2, ESO (3 store / 3 secret), dynamic creds DB (1 rola, rotacja 30 min), **Transit PII (klucz+polityka+rola+kod)**, **Vault na TLS :8203**, cert-manager + Vault PKI (2 ClusterIssuer, 9 certyfikatów, mTLS 3 aplikacji, TLS ingressu), NetworkPolicy (default-deny), Kyverno (3 polityki), fix „Moje Rezerwacje" (wdrożony na wszystkich 3 replikach, potwierdzony e2e).

**❌ Nie działa mimo że „jest" (priorytet P0):**
1. **Kafka mTLS** – pusty truststore → eventy nie idą do Kafki (KROK 11 jest pozorny).
2. **Snapshot Vaulta** – CronJob zawieszony, nigdy nie wykonał się poprawnie → brak możliwości restore.
3. **Brak monitoringu Vaulta** – telemetry leje się do /dev/null (brak joba scrape).

**⚠️ Niedokończone (P1/P2):** role `spring-ro`/`spark-ro`; OIDC dla CI; TLS Postgres (`sslmode=disable`) i Redis (bez TLS); brak intermediate CA; auto-unseal (1 share na PVC); rewrap/HMAC w Transit; pgadmin bez PVC; Egress NetworkPolicy.

**Repo:** `main == origin/main` (HEAD `02d46bd`), drzewo czyste – **nic nie wypchnięte, żadnych zmian w manifestach**.

---

## C. Co warto – kolejność z moją rekomendacją

| # | Zadanie | Zysk | Ryzyko | Moja ocena |
|---|---|---|---|---|
| 1 | **Truststore Kafka** (`keytool -importcert` w initContainer zamiast `openssl pkcs12 -export -nokeys`) | KROK 11 naprawdę działa: eventy, maile, marketing, consumer | niskie (restart brokera, `concurrencyPolicy`) | **rób od razu** |
| 2 | **Włączyć + przetestować snapshot** i wyeksportować poza klaster | możliwość restore | niskie | **rób od razu** |
| 3 | **Job `vault` w `prometheus.yaml` + alerty** (sealed/raft/mounts) | widoczność Vaulta bez Operatora | bardzo niskie | **rób od razu** |
| 4 | **OIDC GitHub Actions → Vault** (`auth jwt`, role per workflow) | największy zysk bezpieczeństwa z Vaulta w tym repo | średnie (konfiguracja workflow) | następny „duży" krok |
| 5 | **Least-privilege**: role K8s per workload + `spring-ro`/`spark-ro` | mniejszy blast radius | średnie | po 4 |
| 6 | **TLS Postgres + Redis** z `vault-issuer-internal` | szyfrowany ruch do baz | średnie (Redis wymaga obrazu z TLS albo stunnel) | po 5 |
| 7 | **Rewrap + HMAC blind index** w Transit | bezpieczna rotacja klucza i szybki lookup e-mail bez decryptowania tabeli | średnie | gdyTransit urośnie |
| 8 | Auto-unseal + HA 3 węzły; `newTag: latest` w overlayu (push = automatyczny rollout) | odporność, spójność GitOps | średnie/wysokie | osobny temat, po stabilizacji |

**Jeśli mam wybrać jedno „następne” zrobić: nr 1 (truststore Kafka)** – bo to jedyna awaria, któca teraz cicho gubi zdarzenia biznesowe, a naprawa jest jednym plikiem i jednym restartem. Potem nr 2 i 3 (po 15 minutach, a ratują przed najgorszym scenariuszem: brak backupu i ślepy Vault). Powiedz „start” i numer – wdrożę, wypchnę i zweryfikuję na klastrze.
