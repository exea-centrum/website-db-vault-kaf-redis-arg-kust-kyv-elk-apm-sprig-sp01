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



@@@@@@@@@@@@@@@@@@@@@2
Zweryfikowałem stan repo i żywego klastra. Mam już wystarczający obraz — przedstawiam wynik.

## A. Co faktycznie jest zrobione (potwierdzone dziś)

**Działa i potwierdzone na żywo:**

| Obszar | Stan | Dowód |
|---|---|---|
| Vault sealed=false, active | ✅ | `/v1/sys/health` → `"sealed":false, "version":"1.17.6"`, restartCount=1, start 29.09 16:44 |
| Vault na TLS :8203 + telemetry | ✅ config, ⚠️ scrape | `vault-config` ma `prometheus_retention="12h"` + `unauthenticated_metrics_access=true` |
| **Kafka mTLS (KROK 11)** | ✅ **NAPRAWIONE** | `kafka-kraft-0`: oba initContainery `Completed`, broker ready; **`openssl s_client` z fastapi na `kafka-kraft:9094` → `CONNECTION ESTABLISHED`, TLSv1.3, TLS_AES_256_GCM_SHA384` z certem klienta `/etc/mtls/tls.crt`** → truststore fix z `keytool -importcert` działa, `CLIENT_AUTH=required` przepuszcza klientów |
| **Snapshot Vaulta (KROK 12)** | ✅ **DZIAŁA** | CronJob `suspend=false`; job `vault-snapshot-29845500` → `Complete`, `succeeded=1` (30.09 05:09). Poprzedni `29844060` = `Failed` (przed poprawką) |
| Job `vault` w Prometheus | ⚠️ **jest w configu, ale target `down`** | `prometheus.yaml` ma job `vault` + `vault-alerts.yml` + mount `vault-tls`; ConfigMap w klastrze to zawiera; ale target: `vault \| down \| server returned HTTP status 403 Forbidden` |
| fastapi metrics | ⚠️ `down` | `fastapi \| down \| 404 Not Found` (job celuje w `:80/metrics`, a fastapi nie eksponuje `/metrics` — inny, drobny problem) |
| pozostałe joby | ✅ | cert-expiry, kafka-exporter, node-exporter, postgres-exporter = `up` |
| Certyfikaty / ESO / Transit / NetworkPolicy / Kyverno | ✅ | bez zmian od poprzedniego audytu, drzewo repo nie ruszone w tych plikach |

## B. Twój raport vs. rzeczywistość — korekty

1. **„Repo: nic nie wypchnięte, drzewo czyste" — nieaktualne.** Jest commit **`a0b1861` „KROK 12: Vault metrics scrape + snapshot fix"**, lokalnie, **`main` jest 1 commit WSTECZ względem `origin/main`** (HEAD wyprzedza remote). Drzewo czyste, ale push nie poszedł.
2. **P0 #1 (truststore Kafka) — już naprawione i potwierdzone e2e** (TLS handshake przechodzi z mTLS). To nie jest już defekt.
3. **P0 #2 (snapshot zawieszony) — już naprawione**: `suspend: false` w repo, pierwszy udany snapshot 30.09 05:09.
4. **P0 #3 (brak monitoringu Vaulta) — połowa zrobona**: manifesty (job, alerty, CA mount) są, ale **target `vault` jest `down` z 403**. To jest teraz jedyny realny P0.
5. **fastapi scrape 404** — nowy, drobny defekt: albo `/metrics` nie istnieje w aplikacji, albo ścieżka/metoda jest zła.

### Dlaczego `vault` = 403 (diagnoza)
`vault-0` startował **29.09 16:44**, a commit z konfiguracją `unauthenticated_metrics_access = true` powstał **29.09 19:07**. Vault **nie przeładowuje stanzas `telemetry {}` bez restartu kontenera** — ConfigMap jest aktualny, ale proces Vaulta działa na starej konfiguracji, więc `/v1/sys/metrics` wymaga tokenu → 403 dla Prometheusa.

## C. Proponowany następny krok

**KROK 12 dokończenie: restart `vault-0`, żeby telemetry faktycznie weszło, plus weryfikacja targetu + test restore ze snapshotu.**

Konkretnie:
1. `kubectl -n davtro02 rollout restart deploy…/sts vault` (StatefulSet `vault`) → Vault wczytuje nowy `telemetry{}`; `vault-bootstrap` podniesie/odsejluje w razie potrzeby.
2. Sprawdzić `up{job="vault"}==1` i że `vault_status_sealed==0` (alerty `vault-health` przestają być ciszą).
3. **Test restore** z `/backup/snapshot-29845500…snap` na jednorazowym podzie/Jobie w namespace testowym — to jedyny sposób, żeby przekonać się, że backoff naprawdę działa (dziś mamy „snapshot się wykonał”, ale „przywrócenie działa” jest nadal niesprawdzone).
4. Push commitu `a0b1861` na `origin/main` (ArgoCD sync).

**Po tym** kolejność dalej: OIDC dla GitHub Actions (największy zysk), potem least-privilege role `spring-ro`/`spark-ro`, TLS Postgres/Redis.

Chcesz, żebym od razu wykonał restart Vaulta + weryfikację targetu (kroki 1–2, niskie ryzyko, kilka minut), czy najpierw wolisz pełny test restore (krok 3, wolniejszy)?


# ########
Zweryfikowałem wszystkie warstwy. Odpowiedź na Twoje pytanie o szyfrowanie + plan 5→8:

## Mapa szyfrowania — co jest, a czego nie ma

| Warstwa | Szyfrowanie | Stan |
|---|---|---|
| **Zewnątrz (ingress)** | HTTPS 443 → `davtro.local`, `spark.davtro.local` (cert z Vault PKI) | ✅ działa, ale **terminacja na ingressie** |
| **Ingress → aplikacje** | **HTTP :8080 plaintext** | ❌ **brak** — NetworkPolicy przepuszcza ingress→`8080` |
| **Aplikacja → aplikacja** | **brak** — fastapi/consumer/spring nie mają portu HTTPS, tylko `:8080`; certy mTLS istnieją, ale są używane **wyłącznie do Kafki** | ❌ **brak** (mTLS jest w praktyce tylko dla Kafki) |
| **Aplikacja → Kafka** | **mTLS :9094**, `CLIENT_AUTH=required` | ✅ potwierdzone (TLS 1.3, handshake OK) |
| Kafka obok tego | **PLAINTEXT :9092** też istnieje i jest advertise'owany; inter-broker = PLAINTEXT | ⚠️ obejście mTLS w klastrze |
| **Aplikacja → Vault** | **TLS :8203**, ale `tls_disable_client_certs = true` (komentarz w repo: „klienci autoryzują się tokenem") | ✅ szyfrowane, ⚠️ **bez mTLS** |
| **Aplikacja → Postgres** | **`?sslmode=disable`** w Vault database engine, brak `ssl_cert_file` w postgres.yaml | ❌ **plaintext, w tym hasło dyncred** |
| **Aplikacja → Redis** | `redis:7-alpine`, **brak `requirepass`**, brak TLS | 🔴 **najsłabsze ogniwo: zero uwierzytelniania + plaintext** |
| **Dane w Postgres** | Transit PII (`aes256-gcm96`, 13/13 wierszy) | ✅ działa |

**Wniosek:** szyfrowanie jest **zewnętrzne (ingress), na Kafce i na danych w spoczynku (Transit)**. **Wewnątrz klastru praktycznie nic poza Kafką nie jest szyfrowane** — Postgres, Redis i ruch app↔app idą czystym tekstem, a Redis w ogóle nie ma hasła.

## Rekomendacja: zacząć od 5, ale z jednym wtrąceniem P0

Twoja kolejność jest dobra, ale **„Redis bez hasła" nie jest P2 — to P0**, bo każdy pod w namespace (a `allow-intra-namespace` dopuszcza wszystko) czyta i nadpisuje cache sesji, bez żadnego sekretu. Dlatego:

### KROK 5 (least-privilege) — z dwoma dodatkami
1. **`redis` → `requirepass` z hasłem z Vault KV** (przez ESO, `creationPolicy: Owner`, `refreshInterval: 30m`) + `REDIS_PASSWORD_FILE` w appkach. *Kilkanaście minut, zerowy downtime po restarcie, ogromny zysk.*
2. Osobne SA per workload: `fastapi-sa`, `processor-sa`, `spring-sa`, `spark-sa` (zamiast wszystkie na `davtro-sa`), i **nowe role Vault z węższymi politykami**:
   - `davtro-transit-fastapi` (transit encrypt/decrypt, bez `database/creds`)
   - `davtro-transit-processor` (jwtnie, bo to konsument)
   - `davtro-db-spring` / `davtro-db-spark` → **`database/creds/davtro-spring-ro` i `davtro-db-spark-ro`** (role Postgres z `GRANT SELECT` tylko) + nowe ExternalSecrets, żeby **spring/spark przestały używać statycznego `davtro-secrets`**.
   - Efekt: wyciek w spring/spark nie daje ani prawa zapisu, ani współdzielonego hasła z fastapi.

### Potem 6 → 7 → 8
- **6 TLS Postgres + Redis**: Postgres — nowy `Certificate` przez `vault-issuer-internal` (`postgres.davtro02.svc`), `ssl=on` + `ssl_cert_file`/`ssl_key_file` w postgres.yaml, `sslmode=verify-full` + `sslrootcert` w `connection_url` (Vault database engine) i w `davtro-secrets` dla statycznych klientów. Redis — TLS wymaga zmiany obrazu/komend, więc **Redis = `redis:7-alpine` + stunnel** albo przejście na obraz z TLS-em.
- **7 Rewrap + HMAC blind index**: klucz `davtro-app` już ma `auto_rotate_period=720h` i alert `vault_transit_last_rotation_time` — brakuje procedury `rewrap` po rotacji i `hmac` dla lookupu e-mailu.
- **8 Auto-unseal + HA 3 + `newTag: latest`**: osobny temat, dopiero po stabilizacji 5–7.

**Moja odpowiedź na „jaki następny krok": KROK 5, zaczynając od hasła Redisa, potem role Vault per workload + `spring-ro`/`spark-ro`.**

Powiedz „start" — wdrożę to etapami: (1) Redis `requirepass` + weryfikacja, (2) SA per workload i role Vault, (3) `spring-ro`/`spark-ro` i odłączenie ich od statycznego `davtro-secrets`. Zatrzymuję się na każdym etapie do weryfikacji na klastrze, i pamiętaj o niewypchniętym commicie `a0b1861` (KROK 12) — wypchnę go w osobnym kroku, żeby nie mieszać zmian.



$$$$$$$$$$$$$$$$$$$
Zweryfikowałem repo **i** żywy klaster. Poniżej stan faktyczny, a potem konkretna odpowiedź na Twoje pytanie: **co usunąć / z czego zrezygnować, a co zostawić, jeśli przechodzisz na Istio**.

---

# 1. Stan zweryfikowany (dziś, na żywo)

| Element | Twoja lista | Rzeczywistość (klaster `parrot`) |
|---|---|---|
| Ingress | „nginx” | ❌ **to nie nginx, to Traefik.** `kubectl get ingressclass` → `nginx`, `public (default)`, `traefik` — **wszystkie trzy** mają `CONTROLLER: traefik.io/ingress-controller`. Pod `ingress/traefik-vm7pq` (Helm release `traefik`, 19 dni). |
| Addon `ingress` | enabled | ✅, ale pod nim siedzi **Traefik** (nowy addon MicroK8s jest Gateway-API-owy: `Gateway ingress/traefik-gateway`, PROGRAMMED=True). |
| Addon `traefik` | disabled | ✅ zbędny — `ingress` go zastępuje. Nic do usuwania. |
| Istio | „istio enabled” | ⚠️ **Istio wisi, ale jest nieużywane**: `istiod` + `istio-ingressgateway` + `istio-egressgateway` działają **127 dni**, a namespace `davtro02` **nie ma** labela `istio-injection` → wszystkie pody mają tylko swój kontener (sprawdziłem: `fastapi-web-app-... sidecars=fastapi`, `frontend-... sidecars=nginx` itd.). |
| Ingressy aplikacji | działają | ⚠️ `davtro-ingress` / `spark-ingress` mają **`status.loadBalancer: {}` = pusty ADDRESS**. Powód: Traefik ma `--providers.kubernetesingress.ingressendpoint.publishedservice=ingress/traefik`, a **Service `traefik` jest `LoadBalancer` z `EXTERNAL-IP: <pending>` (brak MetalLB)** → nie ma adresu do opublikowania. Ruch realnie idzie przez NodePort **31086 (80)** / **30968 (443)**. |
| `scripts/port-forward.sh` | — | 🔴 **błąd**: skrypt robi `port-forward svc/davtro-ingress`. W `davtro02` **nie ma takiego Service** (są tylko `fastapi-web-app-svc`, `frontend-svc`, …). Wpis `https-fastapi/https-frontend/https-spring` **nie zadziała**. Powinno być `-n ingress svc/traefik`, a po migracji `-n istio-system svc/istio-ingressgateway`. |
| Git | (z planu: „commit niewypchnięty”) | ⚠️ **nieaktualne**: `origin/main` = `b0a0476` (CI: tag obrazów), lokalny HEAD = `83bb8e9` → **jesteś 1 commit ZA `origin/main`** (`git status`: `main...origin/main [wstecz 1]`). Nie ma nic do wypchnięcia, trzeba `git pull`. |
| Reszta | — | ✅ bez zmian: Vault TLS :8203, 3 ClusterIssuer READY, 9–10 Certificate READY, 8 NetworkPolicy, Kyverno (3 polityki), ESO, Transit. |
| Kyverno | — | 🔴 **cichy defekt**: wszystkie 3 reguły mają `namespaces: [davtro]`, a workloady są w **`davtro02`** → polityki **faktycznie nie działają**. |

---

# 2. Jeśli przechodzisz na Istio — co USUNĄĆ, co ZOSTAWIĆ

Ważne: **nic nie musisz instalować** — Istio już stoi. „Przejście” = podpięcie `davtro02` do mesha + przeniesienie wejścia z Traefika na `istio-ingressgateway`.

## 2.1. Możesz usunąć / z czego zrezygnować (po weryfikacji Istio!)

| # | Co usunąć | Dlaczego | Uwaga |
|---|---|---|---|
| 1 | `manifests/base/ingress.yaml` (2× `Ingress`) + wpis w `kustomization.yaml` | Zastępuje to **`Gateway` + `VirtualService`** (te same 2 ho­sty: `davtro.local`, `spark.davtro.local` i te same 5 ścieżek: `/api`, `/`, `/grafana`, `/kafka-ui`, `/pgadmin`) | rób to **po** postawieniu Gatewaya (Traefik = droga powrotu) |
| 2 | Adnotacja `argocd.argoproj.io/ignore-healthcheck: "true"` z obu Ingressów | Istnieje tylko dlatego, że Ingress „czeka bez adresu”. `Gateway` ma normalny status od istiod | — |
| 3 | NP `allow-ingress-controller-to-web` i `allow-ingress-controller-to-frontend` | Wskazują `namespaceSelector: kubernetes.io/metadata.name: ingress`. Po migracji kontrolerem jest `istio-system` → te reguły **przestają cokolwiek wpuszczać** | zamień na `istio-system` (albo zostaw jako uzupełnienie NP) |
| 4 | NP `allow-ingress-to-web` i `allow-ingress-to-frontend` (`from: []`) | To **dziura**: `from: []` = „wpuszczam każdego na `:8080`”, więc `default-deny` jest w praktyce zniesiony. Powinno zniknąć **niezależnie od Istio** | zastępuje je `AuthorizationPolicy` |
| 5 | Addon MicroK8s `ingress` → `microk8s disable ingress` | Usuwa Traefika, `IngressClass public/nginx/traefik`, ns `ingress` i `traefik-gateway` | **dopiero po** potwierdzeniu, że Istio Gateway serwuje `davtro.local` |
| 6 | (warunkowo) `manifests/base/mtls-certificates.yaml` → `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` | Istio daje mTLS automatycznie (tożsamości SPIFFE z istiod), więc certy klienta do **ruchu app↔app nie są potrzebne** | ⚠️ **ALE**: te same sekrety są mountowane jako `/etc/mtls` i **używane do mTLS do Kafki** (`KAFKA_TLS_CERT_FILE=/etc/mtls/tls.crt`). **Na teraz: ZOSTAW.** Usuniesz, dopiero gdy Kafka przestanie wymagać certów klienta |
| 7 | `pki-issuer.yaml` → rola `davtro-internal` | Używana tylko przez te mTLS-y app↔app. Po 6 staje się martwa | rola `davtro-ingress` **musi zostać** |

## 2.2. Musisz ZOSTAWIĆ (Istio tego nie zastępuje)

- **cert-manager + Vault PKI** (`pki-issuer.yaml`, `certificates.yaml`, `vault-server-tls.yaml`) — `Gateway` Istio **też** konsumuje k8s Secret TLS (`davtro-tls`, `spark-tls`, `credentialName`). Bez tego nie ma HTTPS.
- **`kafka-server-tls` + mTLS Kafki** (`/etc/mtls`) — Kafka to L4, Istio nie robi protocol-aware mTLS dla Kafki. Certy zostają.
- **Cały Vault** (raft, TLS :8203, Transit PII, database engine, KV v2, snapshot), **ESO**, **dynamiczne creds DB**.
- **Postgres, Redis, ELK/Loki/Tempo/Grafana/Prometheus/Alertmanager, ArgoCD, Kustomize, HPA/PDB, HPA, Kyverno** (te ostatnie warto „naprawić” — zły namespace).
- **`default-deny-ingress`** + `allow-intra-namespace` — NP działa w L3/L4 i **uzupełnia** `AuthorizationPolicy` (Istio nie zastępuje NetworkPolicy). Zostają.
- **`frontend/nginx.conf`** — to nie ingress, tylko serwer aplikacji (SPA + proxy `/api`). Zostaje.
- **`scripts/port-forward.sh`** — zostaje, ale wymaga poprawki (patrz §1).
- **`istio-egressgateway`** — zostaje i możesz go **wykorzystać** do TLS-origination do Postgres/Redis (Twój roadmap #6) zamiast pisać TLS ręcznie.

## 2.3. Co trzeba dodać (nowe pliki + kustomization)

1. `manifests/base/namespace.yaml` → label `istio-injection: enabled` (jeśli chcesz sidecary).
2. `manifests/base/istio-gateway.yaml` → `Gateway networking.istio.io/v1` (`selector: istio: ingressgateway`, servery 80/443, `tls.credentialName: davtro-tls` dla `davtro.local` i `spark-tls` dla `spark.davtro.local`).
3. `manifests/base/istio-virtualservices.yaml` → `VirtualService` z 5 ścieżkami (przepisanie 1:1 z `ingress.yaml`).
4. `manifests/base/istio-peer-authentication.yaml` → **najpierw `PERMISSIVE`**, dopiero po rolloutcie `STRICT`.
5. `manifests/base/istio-authorization-policy.yaml` → zastępuje dziurawe NP z §2.1/4.
6. Wszystkie 5 plików dopisać do `resources` w `manifests/base/kustomization.yaml`.

## 2.4. Pułapki specyficzne dla tego repo (kolejność ma znaczenie)

- **STRICT mTLS + brak sidecarów = całkowita awaria.** Zacznij od `PERMISSIVE`.
- Po labelu `istio-injection` **wszystkie pody muszą się zrestartować** (istio-proxy + ~100 mC/…) — ArgoCD tego nie zrobi sam „w locie”.
- **Kyverno ma bug** (`namespaces: [davtro]`), więc sidecary **nie zostaną zablokowane** przez `require-requests-limits`/`require-ghcr-images` — a powinny (istio-proxy to `docker.io/istio/proxyv2`, bez requests/limits). To osobny, realny defekt do naprawy.
- **`istio-ingressgateway` jest `LoadBalancer` z `<pending>`** (jak Traefik) → i tak wejście tylko przez NodePort (`80→31426`, `443→31411`) lub port-forward. Chcesz prawdziwy VIP → MetalLB.
- **Prometheus/metryki**: job `fastapi` celuje w `:80/metrics` (i zwraca 404), a przy `STRICT` scrape przez sidecara się psuje → zostań na `PERMISSIVE`, dopóki nie poprawisz metryk.
- **Stateful infra** (`vault`, `kafka-kraft`, `postgres-db`, `redis`): rozważ `sidecar.istio.io/inject: "false"` — Vault/Kafka mają własny TLS/raft i sidecar tylko komplikuje lifecycle.

---

# 3. Co jest zrobione + mój proponowany następny krok

**Zrobione i potwierdzone:** Vault raft+PVC, audit, KV v2, TLS :8203, Transit PII, ESO + dynamiczne creds DB, cert-manager + Vault PKI (9 cert READY), NetworkPolicy default-deny, Kyverno (3 polityki — choć nieaktywne), snapshot Vaulta (naprawiony), Kafka mTLS (naprawiony w KROK 12), GitOps CI/CD + ArgoCD.

**Realny następny krok (w tej kolejności):**

1. **P0 git**: `git pull --rebase` — jesteś **1 commit za `origin/main`** (`b0a0476`). Zaktualizować `scripts/plan_etapy_kroki.md` (wpis „commit niewypchnięty a0b1861” jest już nieprawdziwy).
2. **P0 Vault metrics 403** (z planu): `rollout restart sts/vault` → Vault wczyta nowy `telemetry{}`; sprawdzić `up{job="vault"}==1`. Potem **test restore ze snapshotu** (wciąż nietestowany).
3. **P0/cichy defekt**: `scripts/port-forward.sh` — `svc/davtro-ingress` **nie istnieje** → poprawić na `-n ingress svc/traefik` (a po migracji `-n istio-system svc/istio-ingressgateway`).
4. **P1**: naprawić namespace w `kyverno-policy.yaml` (`davtro02`) — inaczej cała polityka to atrapa.
5. **Dopiero potem migracja na Istio** wg §2.3–2.4 (Gateway → weryfikacja → dopiero wtedy `microk8s disable ingress`).

Chcesz, żebym zaczął realizować? Mogę iść w dwóch wariantach — wybierz jeden:

- **A) „naprawy P0 najpierw”**: pull + restart Vaulta + weryfikacja metryk + fix `port-forward.sh` + fix namespace Kyverno.
- **B) „od razu Istio”**: dodać `istio-gateway.yaml` + `istio-virtualservices.yaml` + label namespace + NP dla `istio-system` i przeprowadzić kontrolowaną migrację wejścia (Traefik zostaje jako droga powrotu).


################
Zweryfikowałem Twoją listę **punkt po punkcie** na realnym repo i klastrze. Werdykt ogólny: **kierunek (3 z 4 punktów „co zostaje”) jest poprawny, ale lista „co usunąć” zawiera 3 błędy rzeczowe, a jeden punkt jest technicznie fałszywy i niebezpieczny** (NetworkPolicy ≠ do zastąpienia przez Istio). Do tego jest jeden **twardy bloker**, którego lista w ogóle nie zauważa.

---

# 0. Werdykt w skrócie

| Teza z Twojej listy | Ocena | Dowód / korekta |
|---|---|---|
| Istio robi mTLS Envoy↔Envoy, app gada po HTTP/TCP | ✅ **prawda** | klasyczne sidecar-mTLS; wymaga sidecarów na **obu** końcach |
| Envoy rotuje certy bez restartu i bez wolumenów (24 h) | ✅ **prawda** | Istio SDS, default workload cert TTL = 24 h |
| Usuwasz `fastapi-kafka-mtls`, `processor-kafka-mtls`, `spring-kafka-mtls` | ❌ **nie istnieją** | realne nazwy: `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls`, `kafka-server-tls` |
| Usuwasz initContainery `keytool`/`openssl` „dla Javy i Pythona” | ❌ **nieprawda** | initContainery są **tylko na brokerze** (`kafka-kraft`); Java **nie używa JKS** — `application.properties` → `keystore.type=PEM`, `truststore.type=PEM` |
| Usuwasz NetworkPolicy, bo zastępuje je `AuthorizationPolicy` (L7) | ❌ **FAŁSZ / groźne** | Istio **nie zastępuje** NetworkPolicy; AP bez reguł = **allow-all** → usunięcie `default-deny` = **większe** otwarcie |
| Istio daje mTLS do Postgresa i Redisa „bez dotykania konfiguracji” | ⚠️ **częściowo** | tylko po wstrzyknięciu sidecarów **do Postgresa i Redisa**; nie rozwiązuje „Redis bez hasła” |
| Vault PKI staje się Root CA dla istiod | ❌ **nieprawda dziś** | `PILOT_CERT_PROVIDER=istiod`, `istio-ca-root-cert`: `subject=O=cluster.local`, `issuer=O=cluster.local`, 2026→2036 = **własne self-signed CA Istio** |
| Zastępujesz `ingress-nginx` | ❌ **nie ma nginx** | `IngressClass public/nginx/traefik` → **wszystkie** `CONTROLLER: traefik.io/ingress-controller`; to addon `ingress` = **Traefik** |
| Kyverno „blokuje tag `latest` / Cosign” | ❌ **nieprawda** | live policy: `auto-fix-non-root`, `check-run-as-non-root`, `davtro-baseline-policy` — i baseline **nie działa** (matchuje ns `davtro`, a workloady są w `davtro02`) |
| Vault (Transit/dynamic/KV), ESO, Kyverno, cert-manager dla domeny — zostają | ✅ **prawda** | potwierdzone w repo i na klastrze |

---

# 1. Trzy realne błędy w „co usunąć” (z dowodami)

### 1.1. Nazwy certyfikatów i **pułapka w tym samym pliku**
Twoje `fastapi-kafka-mtls / processor-kafka-mtls / spring-kafka-mtls` nie istnieją. Realnie w `manifests/base/mtls-certificates.yaml` siedzi **5 obiektów**:

- `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` → to **jedyne** kandydaty do usunięcia,
- **`kafka-server-tls`** → cert **serwera brokera**, nie klienta,
- **`vault-tls`** → cert **serwera Vaulta** (`CN vault.davtro02.svc`) — usunięcie go **zabija Vaulta** (a jego brakiem zajmuje się `deployment.yaml` przez `optional: true`).

➡️ **Nie wolno „usunąć pliku”.** Można usunąć tylko 3 bloki.

### 1.2. Te 3 certy to **wyłącznie Kafka**, nie „mTLS app↔app”
```
deployment.yaml:26         - fastapi-mtls          -> /etc/mtls
deployment.yaml:45-47      KAFKA_TLS_CERT_FILE=/etc/mtls/tls.crt ...
message-processor.yaml:22  message-processor-mtls -> /etc/mtls  (env: KAFKA_TLS_*)
spring-app.yaml:20/31-33   spring-app-mtls        -> /etc/mtls  (env: KAFKA_TLS_*)
```
Czyli: **mTLS „app↔app” w tym projekcie nie istnieje** — te sekrety są konsumowane jako certy klienta do Kafki. Usunięcie ich = usunięcie mTLS Kafki (= cofnięcie KROK 11, który dopiero co naprawiłeś `keytool -importcert`).

### 1.3. initContainery to **strona brokera**, nie klienci
`manifests/base/kafka.yaml`: `keystores` (openssl → `kafka.keystore.p12`) + `truststore` (`keytool -importcert ... -alias davtro-internal-ca`). To wynika z tego, że obraz `apache/kafka:3.7.0` **wymaga plików PKCS12 i plików z hasłami** (`KAFKA_SSL_KEYSTORE_FILENAME`…) i **nie zna zmiennych PEM**. Komentarze w pliku opisują to wprost. Java klient (`java-app/src/main/resources/application.properties`) używa **PEM** — **żadnego JKS/PKCS12 w kliencie nie ma**.

➡️ „Usuniesz skrypty JKS dla Javy i Pythona” = merytorycznie nie ten plik i nie ta przyczyna.

---

# 2. Jedna teza technicznie fałszywa i ryzykowna: NetworkPolicy vs AuthorizationPolicy

Nie wolno usunąć `manifests/base/network-policies.yaml`. Powody, konkretne dla tego klastra:

1. **AP działa L7 tylko dla HTTP.** Dla Postgresa, Redisa, Kafki (czysty TCP) `AuthorizationPolicy` daje najwyżej reguły po tożsamości/porcie — nie po komendzie/ścieżce.
2. **Puste AP = allow-all.** `AuthorizationPolicy` bez reguł **nic nie blokuje**. Usunięcie `default-deny-ingress` + `allow-intra-namespace` = **zniesienie** `default-deny`. To regres bezpieczeństwa, nie uproszczenie.
3. **Sidecar + `default-deny` = pody nigdy nie będą Ready.** Istio przepisuje probe kubeleta na porty **15020/15021** agenta, a `kubectl`/Prometheus skrobią **15090**. Jeśli NP nie wpuszcza tych portów, liveness/readiness padają. Czyli przy Istio **musisz NP rozszerzyć**, a nie usunąć:
   ```yaml
   # do allow-ingress-controller-to-* / nowej reguły:
   - ports: [{protocol: TCP, port: 15020}, {protocol: TCP, port: 15021}, {protocol: TCP, port: 15090}]
   ```
4. Dodatkowo dziś masz **dziurę**, której lista nie widzi: `allow-ingress-to-web` i `allow-ingress-to-frontend` mają `from: []` („wpuszczam każdego”). To **należy** usunąć/naprawić — ale to porządki, nie Istio.

---

# 3. Twardy bloker, którego lista nie zauważa: wersja Istio

```
istiod / proxyv2              : docker.io/istio/*:1.18.2
PILOT_CERT_PROVIDER           : istiod
istio-ca-root-cert            : O=cluster.local ... 2026→2036 (self-signed)
kubernetes (server)           : v1.36.2
mesh config                   : sidecar mode (discoveryAddress=istiod:15012), enablePrometheusMerge=true
```
- **Istio 1.18.2 to wydanie z 2023 r. (EOL)**; wspierany zakres to ~K8s 1.24–1.27, a Ty masz **K8s 1.36.2**. Budowanie nowej architektury na EOL-owym meshu w połączeniu z 9 wersjami nowszym Kubernetes to największe ryzyko w całym pomyśle.
- **Istio 1.18 obsługuje `networking.istio.io` `Gateway`/`VirtualService`. Nie planuj `HTTPRoute`/`gateway.networking.k8s.io` dla Istio** — te CRD-y są zainstalowane, ale obsługiwane przez Traefika, nie przez istiod 1.18.
- **„Vault PKI jako Root CA dla istiod” = osobny projekt**, nie „konfiguruje się samo”. Dziś istiod podpisuje własnym CA. Żeby użyć Vaulta potrzebujesz **intermediate CA w Vault PKI** — a Twój audyt mówi wprost: `pki/issuers → 1 (bez intermediate)`. Więc najpierw: nowy `pki/intermediate`, `pki/sign`, sekret `cacerts` dla istiod + restart istiod.

**Koszt sidecarów (sprostowanie „+50 MB RAM”):** domyślne `istio-proxy` to **requests ~100m CPU / ~128Mi RAM na pod**. Przy ~25–30 podach w `davtro02` to **~+3–4 Gi RAM i ~+2,5–3 vCPU requests** na jednowęzłowym MicroK8s — plus restart wszystkich podów po włączeniu injection.

---

# 4. Skorygowana lista dla TEGO repo

## 🗑️ Usunąć / zrezygnować (dopiero po weryfikacji Istio)

| Co | Plik | Warunek |
|---|---|---|
| Traefik = addon `ingress` | `microk8s disable ingress` | **po** tym, jak Istio Gateway serwuje `davtro.local` (Traefik = rollback) |
| 2× `Ingress` + adnotacja `ignore-healthcheck` | `manifests/base/ingress.yaml` (cały plik) | zastąpione `Gateway` + `VirtualService` (te same ho­sty i 5 ścieżek) |
| NP dla ns `ingress` | `network-policies.yaml` → `allow-ingress-controller-to-web`, `-frontend` | zamienić `namespaceSelector` na `istio-system` |
| Dziura `from: []` | `network-policies.yaml` → `allow-ingress-to-web`, `-frontend` | **usunąć niezależnie od Istio** |
| 3 certy klienta | `mtls-certificates.yaml`: `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` | **dopiero gdy** klienci przestaną mTLS-ować do Kafki |
| Rola Vault `davtro-internal` | `pki-issuer.yaml` (`vault-issuer-internal`) | dopiero po powyższym (rola `davtro-ingress` zostaje) |

## 🛡️ Zostawić (potwierdzone, Istio nie zastępuje)

- **Vault**: raft/PVC, TLS :8203, **Transit PII**, database engine (dynamic creds), KV v2, snapshot, audit
- **ESO** (`secret-store.yaml`, `external-secrets*.yaml`) — Istio nie wstrzykuje sekretów do k8s Secrets
- **cert-manager + Vault PKI** — Istio `Gateway` **też** potrzebuje sekretu TLS (`davtro-tls`, `spark-tls`) → `certificates.yaml`, `pki-issuer.yaml`, `vault-server-tls.yaml` zostają
- **`kafka-server-tls`** i cały initContainerowy mechanizm brokera (jeśli Kafka ma zostać L4-TLS)
- **NetworkPolicy** — uzupełnia Istio; przy sidecarach trzeba **dodać** porty 15020/15021/15090
- **Kyverno** — ale **napraw namespace** (`davtro` → `davtro02`), bo obecnie to atrapa
- Postgres, Redis, ELK/Loki/Tempo/Grafana/Prometheus, ArgoCD, Kustomize, HPA/PDB, `frontend/nginx.conf` (to serwer aplikacji, nie ingress), `scripts/port-forward.sh` (z poprawką `svc/davtro-ingress` → nie istnieje)

## ➕ Dodać (przy realnej migracji)

`namespace.yaml` → `istio-injection: enabled` (per-workload, nie hurtem) · `istio-gateway.yaml` (`networking.istio.io/v1alpha3`, 80/443, `credentialName: davtro-tls`/`spark-tls`) · `istio-virtualservices.yaml` · `PeerAuthentication` (`PERMISSIVE` → `STRICT`) · `AuthorizationPolicy` · **porty Envoy w NP** · `sidecar.istio.io/inject: "false"` na `vault`, `kafka-kraft`, `postgres-db`, `redis` (start) · upgrade Istio z 1.18.2.

---

# 5. Co faktycznie jest zrobione i jaki następny krok

**Zrobione/potwierdzone:** Vault raft+TLS+Transit, ESO + dynamic creds, cert-manager + Vault PKI (10 certów READY), Kafka mTLS (naprawione `keytool`), snapshot, NetworkPolicy default-deny, GitOps/ArgoCD. **Repo nie ma nic niewypchniętego** — jesteś **1 commit ZA `origin/main`** (`b0a0476`) → `git pull --rebase`.

**Realne P0 (przed jakimkolwiek Istio):**
1. `git pull --rebase` + sprostować `scripts/plan_etapy_kroki.md` (wpis „niewypchnięte a0b1861” jest nieprawdziwy).
2. **Redis `requirepass`** — Istio **tego nie rozwiąże** (mTLS ≠ autoryzacja); to nadal najsłabsze ogniwo.
3. Vault: `rollout restart sts/vault` → metryki `up{job="vault"}==1`; **test restore ze snapshotu** (nadal nieprzetestowany).
4. `scripts/port-forward.sh`: `svc/davtro-ingress` **nie istnieje** → `-n ingress svc/traefik`.
5. `kyverno-policy.yaml`: namespace `davtro` → `davtro02`.
6. **Upgrade Istio 1.18.2** (EOL) — zanim cokolwiek na nim zbudujesz.

**Dopiero potem Istio, etapami i odwracalnie:**
- **Etap A (zero ryzyka dla aplikacji):** tylko wejście — `Gateway` + `VirtualService`, **bez** `istio-injection`, Traefik zostaje jako droga powrotu. Weryfikacja: `curl` na NodePort `31426`/`31411`.
- **Etap B:** injection dla **jednego** workloadu (fastapi), `PeerAuthentication: PERMISSIVE`, AP + porty Envoy w NP.
- **Etap C:** `STRICT` + drugi workload; metryki (uwaga: job `fastapi` i tak zwraca 404).
- **Etap D (ostatni):** infra (Postgres → Redis). **Kafka — zostaw jej własny TLS** (KRaft + `ADVERTISED_LISTENERS` + `apiserver`-style intercept to najtrudniejszy i najmniej zyskowny kawałek).

Chcesz, żebym zaczął? Proponuję **wariant bezpieczny**: (1) `git pull --rebase` + fix `port-forward.sh` + fix namespace Kyverno, (2) Redis `requirepass` przez ESO, (3) restart Vaulta + weryfikacja metryk — a migrację Istio trzymamy jako osobny, zaplanowany etap po upgradzie mesha. Powiedz „start" i który zakres.


$$$$$$$$$$$$$$$$
# ##########################
Zweryfikowałem Twoją listę **punkt po punkcie** na realnym repo i klastrze. Werdykt ogólny: **kierunek (3 z 4 punktów „co zostaje”) jest poprawny, ale lista „co usunąć” zawiera 3 błędy rzeczowe, a jeden punkt jest technicznie fałszywy i niebezpieczny** (NetworkPolicy ≠ do zastąpienia przez Istio). Do tego jest jeden **twardy bloker**, którego lista w ogóle nie zauważa.

---

# 0. Werdykt w skrócie

| Teza z Twojej listy | Ocena | Dowód / korekta |
|---|---|---|
| Istio robi mTLS Envoy↔Envoy, app gada po HTTP/TCP | ✅ **prawda** | klasyczne sidecar-mTLS; wymaga sidecarów na **obu** końcach |
| Envoy rotuje certy bez restartu i bez wolumenów (24 h) | ✅ **prawda** | Istio SDS, default workload cert TTL = 24 h |
| Usuwasz `fastapi-kafka-mtls`, `processor-kafka-mtls`, `spring-kafka-mtls` | ❌ **nie istnieją** | realne nazwy: `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls`, `kafka-server-tls` |
| Usuwasz initContainery `keytool`/`openssl` „dla Javy i Pythona” | ❌ **nieprawda** | initContainery są **tylko na brokerze** (`kafka-kraft`); Java **nie używa JKS** — `application.properties` → `keystore.type=PEM`, `truststore.type=PEM` |
| Usuwasz NetworkPolicy, bo zastępuje je `AuthorizationPolicy` (L7) | ❌ **FAŁSZ / groźne** | Istio **nie zastępuje** NetworkPolicy; AP bez reguł = **allow-all** → usunięcie `default-deny` = **większe** otwarcie |
| Istio daje mTLS do Postgresa i Redisa „bez dotykania konfiguracji” | ⚠️ **częściowo** | tylko po wstrzyknięciu sidecarów **do Postgresa i Redisa**; nie rozwiązuje „Redis bez hasła” |
| Vault PKI staje się Root CA dla istiod | ❌ **nieprawda dziś** | `PILOT_CERT_PROVIDER=istiod`, `istio-ca-root-cert`: `subject=O=cluster.local`, `issuer=O=cluster.local`, 2026→2036 = **własne self-signed CA Istio** |
| Zastępujesz `ingress-nginx` | ❌ **nie ma nginx** | `IngressClass public/nginx/traefik` → **wszystkie** `CONTROLLER: traefik.io/ingress-controller`; to addon `ingress` = **Traefik** |
| Kyverno „blokuje tag `latest` / Cosign” | ❌ **nieprawda** | live policy: `auto-fix-non-root`, `check-run-as-non-root`, `davtro-baseline-policy` — i baseline **nie działa** (matchuje ns `davtro`, a workloady są w `davtro02`) |
| Vault (Transit/dynamic/KV), ESO, Kyverno, cert-manager dla domeny — zostają | ✅ **prawda** | potwierdzone w repo i na klastrze |

---

# 1. Trzy realne błędy w „co usunąć” (z dowodami)

### 1.1. Nazwy certyfikatów i **pułapka w tym samym pliku**
Twoje `fastapi-kafka-mtls / processor-kafka-mtls / spring-kafka-mtls` nie istnieją. Realnie w `manifests/base/mtls-certificates.yaml` siedzi **5 obiektów**:

- `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` → to **jedyne** kandydaty do usunięcia,
- **`kafka-server-tls`** → cert **serwera brokera**, nie klienta,
- **`vault-tls`** → cert **serwera Vaulta** (`CN vault.davtro02.svc`) — usunięcie go **zabija Vaulta** (a jego brakiem zajmuje się `deployment.yaml` przez `optional: true`).

➡️ **Nie wolno „usunąć pliku”.** Można usunąć tylko 3 bloki.

### 1.2. Te 3 certy to **wyłącznie Kafka**, nie „mTLS app↔app”
```
deployment.yaml:26         - fastapi-mtls          -> /etc/mtls
deployment.yaml:45-47      KAFKA_TLS_CERT_FILE=/etc/mtls/tls.crt ...
message-processor.yaml:22  message-processor-mtls -> /etc/mtls  (env: KAFKA_TLS_*)
spring-app.yaml:20/31-33   spring-app-mtls        -> /etc/mtls  (env: KAFKA_TLS_*)
```
Czyli: **mTLS „app↔app” w tym projekcie nie istnieje** — te sekrety są konsumowane jako certy klienta do Kafki. Usunięcie ich = usunięcie mTLS Kafki (= cofnięcie KROK 11, który dopiero co naprawiłeś `keytool -importcert`).

### 1.3. initContainery to **strona brokera**, nie klienci
`manifests/base/kafka.yaml`: `keystores` (openssl → `kafka.keystore.p12`) + `truststore` (`keytool -importcert ... -alias davtro-internal-ca`). To wynika z tego, że obraz `apache/kafka:3.7.0` **wymaga plików PKCS12 i plików z hasłami** (`KAFKA_SSL_KEYSTORE_FILENAME`…) i **nie zna zmiennych PEM**. Komentarze w pliku opisują to wprost. Java klient (`java-app/src/main/resources/application.properties`) używa **PEM** — **żadnego JKS/PKCS12 w kliencie nie ma**.

➡️ „Usuniesz skrypty JKS dla Javy i Pythona” = merytorycznie nie ten plik i nie ta przyczyna.

---

# 2. Jedna teza technicznie fałszywa i ryzykowna: NetworkPolicy vs AuthorizationPolicy

Nie wolno usunąć `manifests/base/network-policies.yaml`. Powody, konkretne dla tego klastra:

1. **AP działa L7 tylko dla HTTP.** Dla Postgresa, Redisa, Kafki (czysty TCP) `AuthorizationPolicy` daje najwyżej reguły po tożsamości/porcie — nie po komendzie/ścieżce.
2. **Puste AP = allow-all.** `AuthorizationPolicy` bez reguł **nic nie blokuje**. Usunięcie `default-deny-ingress` + `allow-intra-namespace` = **zniesienie** `default-deny`. To regres bezpieczeństwa, nie uproszczenie.
3. **Sidecar + `default-deny` = pody nigdy nie będą Ready.** Istio przepisuje probe kubeleta na porty **15020/15021** agenta, a `kubectl`/Prometheus skrobią **15090**. Jeśli NP nie wpuszcza tych portów, liveness/readiness padają. Czyli przy Istio **musisz NP rozszerzyć**, a nie usunąć:
   ```yaml
   # do allow-ingress-controller-to-* / nowej reguły:
   - ports: [{protocol: TCP, port: 15020}, {protocol: TCP, port: 15021}, {protocol: TCP, port: 15090}]
   ```
4. Dodatkowo dziś masz **dziurę**, której lista nie widzi: `allow-ingress-to-web` i `allow-ingress-to-frontend` mają `from: []` („wpuszczam każdego”). To **należy** usunąć/naprawić — ale to porządki, nie Istio.

---

# 3. Twardy bloker, którego lista nie zauważa: wersja Istio

```
istiod / proxyv2              : docker.io/istio/*:1.18.2
PILOT_CERT_PROVIDER           : istiod
istio-ca-root-cert            : O=cluster.local ... 2026→2036 (self-signed)
kubernetes (server)           : v1.36.2
mesh config                   : sidecar mode (discoveryAddress=istiod:15012), enablePrometheusMerge=true
```
- **Istio 1.18.2 to wydanie z 2023 r. (EOL)**; wspierany zakres to ~K8s 1.24–1.27, a Ty masz **K8s 1.36.2**. Budowanie nowej architektury na EOL-owym meshu w połączeniu z 9 wersjami nowszym Kubernetes to największe ryzyko w całym pomyśle.
- **Istio 1.18 obsługuje `networking.istio.io` `Gateway`/`VirtualService`. Nie planuj `HTTPRoute`/`gateway.networking.k8s.io` dla Istio** — te CRD-y są zainstalowane, ale obsługiwane przez Traefika, nie przez istiod 1.18.
- **„Vault PKI jako Root CA dla istiod” = osobny projekt**, nie „konfiguruje się samo”. Dziś istiod podpisuje własnym CA. Żeby użyć Vaulta potrzebujesz **intermediate CA w Vault PKI** — a Twój audyt mówi wprost: `pki/issuers → 1 (bez intermediate)`. Więc najpierw: nowy `pki/intermediate`, `pki/sign`, sekret `cacerts` dla istiod + restart istiod.

**Koszt sidecarów (sprostowanie „+50 MB RAM”):** domyślne `istio-proxy` to **requests ~100m CPU / ~128Mi RAM na pod**. Przy ~25–30 podach w `davtro02` to **~+3–4 Gi RAM i ~+2,5–3 vCPU requests** na jednowęzłowym MicroK8s — plus restart wszystkich podów po włączeniu injection.

---

# 4. Skorygowana lista dla TEGO repo

## 🗑️ Usunąć / zrezygnować (dopiero po weryfikacji Istio)

| Co | Plik | Warunek |
|---|---|---|
| Traefik = addon `ingress` | `microk8s disable ingress` | **po** tym, jak Istio Gateway serwuje `davtro.local` (Traefik = rollback) |
| 2× `Ingress` + adnotacja `ignore-healthcheck` | `manifests/base/ingress.yaml` (cały plik) | zastąpione `Gateway` + `VirtualService` (te same ho­sty i 5 ścieżek) |
| NP dla ns `ingress` | `network-policies.yaml` → `allow-ingress-controller-to-web`, `-frontend` | zamienić `namespaceSelector` na `istio-system` |
| Dziura `from: []` | `network-policies.yaml` → `allow-ingress-to-web`, `-frontend` | **usunąć niezależnie od Istio** |
| 3 certy klienta | `mtls-certificates.yaml`: `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` | **dopiero gdy** klienci przestaną mTLS-ować do Kafki |
| Rola Vault `davtro-internal` | `pki-issuer.yaml` (`vault-issuer-internal`) | dopiero po powyższym (rola `davtro-ingress` zostaje) |

## 🛡️ Zostawić (potwierdzone, Istio nie zastępuje)

- **Vault**: raft/PVC, TLS :8203, **Transit PII**, database engine (dynamic creds), KV v2, snapshot, audit
- **ESO** (`secret-store.yaml`, `external-secrets*.yaml`) — Istio nie wstrzykuje sekretów do k8s Secrets
- **cert-manager + Vault PKI** — Istio `Gateway` **też** potrzebuje sekretu TLS (`davtro-tls`, `spark-tls`) → `certificates.yaml`, `pki-issuer.yaml`, `vault-server-tls.yaml` zostają
- **`kafka-server-tls`** i cały initContainerowy mechanizm brokera (jeśli Kafka ma zostać L4-TLS)
- **NetworkPolicy** — uzupełnia Istio; przy sidecarach trzeba **dodać** porty 15020/15021/15090
- **Kyverno** — ale **napraw namespace** (`davtro` → `davtro02`), bo obecnie to atrapa
- Postgres, Redis, ELK/Loki/Tempo/Grafana/Prometheus, ArgoCD, Kustomize, HPA/PDB, `frontend/nginx.conf` (to serwer aplikacji, nie ingress), `scripts/port-forward.sh` (z poprawką `svc/davtro-ingress` → nie istnieje)

## ➕ Dodać (przy realnej migracji)

`namespace.yaml` → `istio-injection: enabled` (per-workload, nie hurtem) · `istio-gateway.yaml` (`networking.istio.io/v1alpha3`, 80/443, `credentialName: davtro-tls`/`spark-tls`) · `istio-virtualservices.yaml` · `PeerAuthentication` (`PERMISSIVE` → `STRICT`) · `AuthorizationPolicy` · **porty Envoy w NP** · `sidecar.istio.io/inject: "false"` na `vault`, `kafka-kraft`, `postgres-db`, `redis` (start) · upgrade Istio z 1.18.2.

---

# 5. Co faktycznie jest zrobione i jaki następny krok

**Zrobione/potwierdzone:** Vault raft+TLS+Transit, ESO + dynamic creds, cert-manager + Vault PKI (10 certów READY), Kafka mTLS (naprawione `keytool`), snapshot, NetworkPolicy default-deny, GitOps/ArgoCD. **Repo nie ma nic niewypchniętego** — jesteś **1 commit ZA `origin/main`** (`b0a0476`) → `git pull --rebase`.

**Realne P0 (przed jakimkolwiek Istio):**
1. `git pull --rebase` + sprostować `scripts/plan_etapy_kroki.md` (wpis „niewypchnięte a0b1861” jest nieprawdziwy).
2. **Redis `requirepass`** — Istio **tego nie rozwiąże** (mTLS ≠ autoryzacja); to nadal najsłabsze ogniwo.
3. Vault: `rollout restart sts/vault` → metryki `up{job="vault"}==1`; **test restore ze snapshotu** (nadal nieprzetestowany).
4. `scripts/port-forward.sh`: `svc/davtro-ingress` **nie istnieje** → `-n ingress svc/traefik`.
5. `kyverno-policy.yaml`: namespace `davtro` → `davtro02`.
6. **Upgrade Istio 1.18.2** (EOL) — zanim cokolwiek na nim zbudujesz.

**Dopiero potem Istio, etapami i odwracalnie:**
- **Etap A (zero ryzyka dla aplikacji):** tylko wejście — `Gateway` + `VirtualService`, **bez** `istio-injection`, Traefik zostaje jako droga powrotu. Weryfikacja: `curl` na NodePort `31426`/`31411`.
- **Etap B:** injection dla **jednego** workloadu (fastapi), `PeerAuthentication: PERMISSIVE`, AP + porty Envoy w NP.
- **Etap C:** `STRICT` + drugi workload; metryki (uwaga: job `fastapi` i tak zwraca 404).
- **Etap D (ostatni):** infra (Postgres → Redis). **Kafka — zostaw jej własny TLS** (KRaft + `ADVERTISED_LISTENERS` + `apiserver`-style intercept to najtrudniejszy i najmniej zyskowny kawałek).

Chcesz, żebym zaczął? Proponuję **wariant bezpieczny**: (1) `git pull --rebase` + fix `port-forward.sh` + fix namespace Kyverno, (2) Redis `requirepass` przez ESO, (3) restart Vaulta + weryfikacja metryk — a migrację Istio trzymamy jako osobny, zaplanowany etap po upgradzie mesha. Powiedz „start" i który zakres.



$$$$$$$$$$$$$$$$
# ###
Mam wszystkie dokładne wartości potrzebne do komend 1:1. Poniżej **plan wdrożenia Istio „na szybko”** — zoptymalizowany pod minimalne ryzyko: **etapy 1–5 przejmują wejście do aplikacji w ~30 min i nie dotykają żadnej aplikacji** (bez sidecarów = zero ryzyka regresu), sidecary dopiero potem, jako osobne, odwracalne etapy.

**Zweryfikowane dane wejściowe (na których opieram YAML):**
```
istiod/proxyv2                    1.18.2
gateway pod label                 istio: ingressgateway        <- selector Gatewaya
svc istio-ingressgateway          LB (<pending>)  80->8080  NodePort 31426
                                                  443->8443 NodePort 31411
served API (CRD)                  networking.istio.io: v1alpha3, v1beta1
                                  security.istio.io:   PeerAuthentication v1beta1,
                                                       AuthorizationPolicy v1, v1beta1
Istio Gateway CR                  BRAK (jest tylko traefik-gateway)  <- tworzymy od zera
davtro02                          brak labela istio-injection  <- NIE zmieniamy w etapach 1-5
ArgoCD                            auto-sync + self-heal + PRUNE <- wszystko musi iść przez Git
```

---

# ETAP 0 — przygotowanie (5 min)

```bash
cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
git pull --rebase                 # jesteś 1 commit za origin/main (b0a0476)
git checkout -b feat/istio-ingress
```
- **Nie ruszamy** `microk8s enable istio` — addon już działa (127 dni). Ponowne `enable` może zresetować istiod.
- **Zapisujemy punkt powrotu**: Traefik i oba `Ingress` **zostają** nietknięte przez etapy 1–5 — to nasz rollback.
- ⚠️ **ArgoCD ma `prune`+`self-heal`** → `kubectl apply -f` „obok Git” zostanie **usunięty przy najbliższym syncu**. Dlatego pliki **muszą** trafić do `manifests/base/kustomization.yaml` i do Git.

---

# ETAP 1 — Gateway Istio (2 nowe pliki)

### 1a. `manifests/base/istio-gateway.yaml` (nowy plik)

```yaml
# ETAP 1: wejście do klastra przez istio-ingressgateway (zamiast Traefika).
# UWAGA (weryfikacja 1.18.2): networking.istio.io servuje v1alpha3/v1beta1 - v1 NIE MA.
# Sekrety TLS (davtro-tls, spark-tls) MUSZA byc w tym samym namespace co Gateway
# (davtro02) - istiod pobiera je przez SDS i podaje do istio-ingressgateway.
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: davtro-gateway
  namespace: davtro02
spec:
  selector:
    istio: ingressgateway     # label poda istio-ingressgateway (potwierdzony na klastrze)
  servers:
    # HTTP (bez TLS) - zostawiony dla testow i dla port-forward; HTTPS obok.
    - port: { number: 80, name: http, protocol: HTTP }
      hosts: ["davtro.local", "spark.davtro.local"]
    # HTTPS: dwa servery na :443 rozrozniane po SNI/hoscie - kazdy wlasny cert.
    - port: { number: 443, name: https, protocol: HTTPS }
      tls: { mode: SIMPLE, credentialName: davtro-tls }
      hosts: ["davtro.local"]
    - port: { number: 443, name: https-spark, protocol: HTTPS }
      tls: { mode: SIMPLE, credentialName: spark-tls }
      hosts: ["spark.davtro.local"]
```

### 1b. `manifests/base/istio-virtualservices.yaml` (nowy plik)

```yaml
# ETAP 1: 1:1 routing z manifests/base/ingress.yaml.
# KLUCZOWA ROZNICA vs Ingress: w VirtualService KOLEJNOSC reguł ma znaczenie
# (Ingress dopasowuje "longest prefix" sam) - dlatego "/" (catch-all) MUSI byc OSTATNI.
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: davtro-vs
  namespace: davtro02
spec:
  hosts: ["davtro.local"]
  gateways: ["davtro-gateway"]
  http:
    - match: [{ uri: { prefix: /api } }]
      route:
        - destination: { host: fastapi-web-app-svc.davtro02.svc.cluster.local, port: { number: 80 } }
    - match: [{ uri: { prefix: /grafana } }]
      route:
        - destination: { host: grafana.davtro02.svc.cluster.local, port: { number: 3000 } }
    - match: [{ uri: { prefix: /kafka-ui } }]
      route:
        - destination: { host: kafka-ui.davtro02.svc.cluster.local, port: { number: 80 } }
    - match: [{ uri: { prefix: /pgadmin } }]
      route:
        - destination: { host: pgadmin.davtro02.svc.cluster.local, port: { number: 80 } }
    - route:                                  # catch-all = "/" (frontend SPA)
        - destination: { host: frontend-svc.davtro02.svc.cluster.local, port: { number: 80 } }
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: spark-vs
  namespace: davtro02
spec:
  hosts: ["spark.davtro.local"]
  gateways: ["davtro-gateway"]
  http:
    - route:
        - destination: { host: spark-master-svc.davtro02.svc.cluster.local, port: { number: 8082 } }
```

**Uwaga o parytecie:** VirtualService **nie zdejmuje** prefiksu ścieżki (tak samo jak Twój `Ingress`). Czyli `/grafana` dociera do Grafany jako `/grafana` — zachowanie **identyczne z obecnym Traefikiem** (jeśli teraz działa, będzie działać; jeśli nie — to osobny, istniejący temat z `GF_SERVER_ROOT_URL`).

---

# ETAP 2 — NetworkPolicy dla gatewaya (JEDEN nowy plik)

To jest ten punkt, który lista „co usunąć” pomijała: `default-deny-ingress` **odcina** ruch z `istio-system` do aplikacji. Dodajemy jawnie (nie usuwamy niczego):

### `manifests/base/network-policies-istio.yaml` (nowy plik)

```yaml
# ETAP 2: istio-ingressgateway (ns istio-system) -> back­endy.
# Bez tego default-deny-ingress blokuje ruch z Gatewaya (analogicznie do
# allow-ingress-controller-to-* dla Traefika, ktore zostaja nietkniete).
# Porty 15020/15021/15090 dodamy dopiero przy sidecarach (ETAP 6).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-istio-ingressgateway
  namespace: davtro02
spec:
  podSelector:
    matchExpressions:
      - { key: app, operator: In, values: [fastapi-web-app, frontend, grafana, kafka-ui, pgadmin, spark-master] }
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: istio-system }
  policyTypes: [Ingress]
```
> Świadomie **bez `ports:`** (aplikacje mają różne porty: 8080/3000/80/8082, a w ETAPIE 6 dojdą porty Envoy). Jeśli wolisz twardo, rozbij na 6 reguł z portami — wtedy pamiętaj o 15020/15021/15090.

---

# ETAP 3 — rejestracja w Kustomize + walidacja + deploy

```bash
# 3a. dopisz 3 pliki do manifests/base/kustomization.yaml (resources:)
#     - istio-gateway.yaml
#     - istio-virtualservices.yaml
#     - network-policies-istio.yaml

# 3b. walidacja lokalna PRZED pushem (kustomize z microk8s)
microk8s kubectl kustomize manifests/overlays/production > /tmp/render.yaml
grep -nE 'kind: (Gateway|VirtualService|NetworkPolicy)' /tmp/render.yaml

# 3c. commit -> push -> ArgoCD zrobi sync (auto-sync ~3 min)
git add manifests/base/kustomization.yaml manifests/base/istio-gateway.yaml \
        manifests/base/istio-virtualservices.yaml manifests/base/network-policies-istio.yaml
git commit -m "KROK 13 (Istio): Gateway + VirtualService + NP dla istio-ingressgateway (Traefik nietkniety = rollback)"
git push -u origin feat/istio-ingress
```

Weryfikacja stanu obiektów:
```bash
microk8s kubectl -n davtro02 get gateway,virtualservice
microk8s kubectl -n davtro02 describe gateway davtro-gateway | grep -iE 'status|hosts|secret'
microk8s kubectl -n istio-system logs deploy/istio-ingressgateway --tail=50 | grep -iE 'davtro|error'
```
Oczekiwane: `Gateway` ma `PROGRAMMED: True`, brak `error` o `credentialName`/SDS.

---

# ETAP 4 — testy przez Istio (Traefik nadal żyje, nic nie wyłączamy)

```bash
# HTTP (NodePort 31426)
curl -s -o /dev/null -w 'frontend  %{http_code}\n' -H 'Host: davtro.local' http://127.0.0.1:31426/
curl -s -o /dev/null -w 'api/health %{http_code}\n' -H 'Host: davtro.local' http://127.0.0.1:31426/api/health
curl -s -o /dev/null -w 'grafana   %{http_code}\n' -H 'Host: davtro.local' http://127.0.0.1:31426/grafana
curl -s -o /dev/null -w 'kafka-ui  %{http_code}\n' -H 'Host: davtro.local' http://127.0.0.1:31426/kafka-ui
curl -s -o /dev/null -w 'pgadmin   %{http_code}\n' -H 'Host: davtro.local' http://127.0.0.1:31426/pgadmin

# HTTPS + SNI (NodePort 31411) - cert davtro-tls / spark-tls z cert-managera
curl -sk -o /dev/null -w 'https davtro %{http_code}\n' --resolve davtro.local:31411:127.0.0.1 https://davtro.local:31411/
curl -sk -o /dev/null -w 'https spark  %{http_code}\n' --resolve spark.davtro.local:31411:127.0.0.1 https://spark.davtro.local:31411/
curl -skv --resolve davtro.local:31411:127.0.0.1 https://davtro.local:31411/api/health 2>&1 | grep -iE 'subject:|issuer:|HTTP/'
```
Alternatywa bez NodePortów (dla LAN/PC):
```bash
microk8s kubectl -n istio-system port-forward --address 0.0.0.0 svc/istio-ingressgateway 8443:443
# potem: curl -sk --resolve davtro.local:8443:<IP> https://davtro.local:8443/api/health
```
**Kryterium „GO”:** 200/3xx na wszystkich 5 ścieżkach + `api/health` zwraca `transit: True`, cert ma `issuer` z Vault PKI.

---

# ETAP 5 — cutover (wyłączenie Traefika) — DOPIERO PO „GO”

```bash
# 5a. najpierw usuń Ingressy z Git (zastąpione przez Gateway/VirtualService)
#     - usun manifests/base/ingress.yaml + wpis w kustomization.yaml
#     - commit + push + ArgoCD sync  ->  Ingressy znikają, Istio routuje dalej

# 5b. dopiero teraz zrezygnuj z addonu (usuwa Traefika, ns ingress, IngressClass public/nginx/traefik)
microk8s disable ingress
microk8s kubectl get ingressclass          # oczekiwane: pusto
microk8s kubectl -n istio-system get svc istio-ingressgateway   # 80/443 nadal NodePort 31426/31411
```
Rób to **osobnym commitem**, żeby rollback był jednym `git revert`.

### Rollback (jeśli coś nie gra)
```bash
git revert <commit-z-etapu-5a> && git push        # wraca ingress.yaml
microk8s enable ingress                            # wraca Traefik (IngressClass public = default)
```
(Odtworzenie Traefika to ~1 min; sekrety `davtro-tls`/`spark-tls` są nietknięte, więc certy wracają od razu.)

---

# ETAP 6 — sidecary (osobne okno, najwyższe ryzyko) — skrót

Dopiero gdy etapy 1–5 są stabilne **≥1 dobę**. Kolejność **per-workload**, nigdy hurtem:

| Krok | Co | Ryzyko |
|---|---|---|
| 6.1 | `ProxyConfig`/`proxy.istio.io/config` z **requests/limits** dla istio-proxy — ale najpierw **napraw `kyverno-policy.yaml`** (`namespaces: [davtro]` → `davtro02`), bo inaczej polityka to atrapa, a po naprawie zacznie **blokować** sidecary bez limits/requests i obrazy `docker.io/istio/*` (dodaj je do `require-ghcr-images`) | 🔴 duże |
| 6.2 | Osobna NP z portami **15020/15021/15090** (inaczej kubelet-probes i Prometheus padną przy `default-deny`) | 🔴 duże |
| 6.3 | `istio-injection: enabled` **na jednym** workloadzie (label `sidecar.istio.io/inject: "true"` na `fastapi-web-app`), `PeerAuthentication: PERMISSIVE` | 🟡 |
| 6.4 | Drugi workload (`frontend`), potem `STRICT` w `davtro02` | 🟡 |
| 6.5 | Infra: `postgres-db`, `redis` (na start `sidecar.istio.io/inject: "false"` dla `vault` i `kafka-kraft`) | 🔴 |
| 6.6 | `AuthorizationPolicy` (uzupełnienie NP, **nie** zamiennik — AP bez reguł = allow-all) | 🟡 |
| 6.7 | Kafka zostaje na własnym mTLS (`kafka-server-tls` + initContainery). „Wyłączenie `CLIENT_AUTH=required`” z Twojej listy = **cofnięcie KROK 11** i wymaga przepisania klientów na `:9092` — **nie robimy tego w tym wdrożeniu** | ⚪ |

**Budżet:** sidecar = domyślnie **~100m CPU / ~128Mi RAM per pod** (nie 50 MB). ~25–30 podów → **+2,5–3 vCPU i +3–4 Gi RAM requests** na jednym węźle.

---

# Blokery do świadomej akceptacji (nie „naprawiamy” teraz, ale musisz wiedzieć)

1. **Istio 1.18.2 (EOL, 2023) vs Kubernetes v1.36.2** — etapy 1–5 jadą na **już działającym** control plane, więc ryzyko jest małe, ale **pełnego mesha (sidecary) nie budowałbym bez upgrade'u Istio**. To osobny temat zaraz po etapie 5.
2. **Vault PKI nie jest CA istiod** (`PILOT_CERT_PROVIDER=istiod`, root `O=cluster.local` 2026→2036). „Istio bierze root z Vaulta” = osobny projekt (Vault PKI **nie ma** intermediate) — **nie jest częścią tego wdrożenia**.
3. **LoadBalancer `<pending>`** (brak MetalLB) — dlatego wejście = NodePort `31426`/`31411` lub port-forward. Instalacja MetalLB to opcjonalny, osobny krok, jeśli chcesz prawdziwy VIP.
4. **P0 poza Istio nadal otwarte:** Redis bez `requirepass` (Istio tego nie naprawia!), `scripts/port-forward.sh` → `svc/davtro-ingress` **nie istnieje** (poprawić na `-n ingress svc/traefik`, potem `-n istio-system svc/istio-ingressgateway`), Vault `up{job="vault"}` = 403, snapshot bez testu restore.

---

# Ściąga: co robimy, w jakiej kolejności

```
ETAP 0  git pull --rebase + branch                              ~5 min
ETAP 1  3 nowe pliki: Gateway, 2x VirtualService                ~10 min
ETAP 2  1 nowy plik: NP allow-istio-ingressgateway              ~5 min
ETAP 3  kustomization + kustomize build + commit/push           ~5 min
ETAP 4  curl 7 testów przez NodePort 31426/31411                ~10 min  -> decyzja GO/NO-GO
ETAP 5  usunięcie ingress.yaml (commit) + microk8s disable ingress ~5 min
        (rollback: revert + microk8s enable ingress)
--- od tego miejsca oddzielny projekt, po ~1 dniu obserwacji ---
ETAP 6  sidecary per-workload + NP porty Envoy + AP             godzinы
ETAP 7  upgrade Istio 1.18.2 -> aktualne; potem ew. Vault PKI jako CA
```

**Zaczynam od ETAPU 1?** Mogę od razu wygenerować te 4 pliki (`istio-gateway.yaml`, `istio-virtualservices.yaml`, `network-policies-istio.yaml` + wpisy w `kustomization.yaml`) i zwalidować `kustomize build` lokalnie — bez commita i bez pusha, żebyś zobaczył gotowy render. Powiedz „rób ETAP 1–3”, a przygotuję pliki i pokażę wynik walidacji; commit/push i `disable ingress` zostawię do Twojej decyzji.