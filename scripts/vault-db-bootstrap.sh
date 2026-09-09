#!/usr/bin/env bash
# KROK 3: bootstrap database engine w Vault - dynamiczne credsy PostgreSQL.
# Uruchom RAZ (idempotentny w wiekszosci) PRZED pushem commita z
# external-secrets-db-dynamic.yaml. Wymagania:
#   - VAULT_ADDR + VAULT_TOKEN (root lub policy z update na database/*),
#   - Vault unsealowany, KV davtro/db zaladowany (Krok 2),
#   - kubectl z dostepem do klastra (dla czesci SQL).
set -euo pipefail

VAULT_DB_MOUNT="database"
VAULT_CONN_NAME="davtro-postgresql"
VAULT_ROLE="davtro-app-rw"
PG_HOST="postgres-clusterip.davtro02.svc.cluster.local"
PG_DB="davtro_rentals"
PG_ADMIN_USER="davtro"

# --- 0. Haslo admina bierze z KV (nie wpisuj w skrypcie!) ---------------------
DB_PASSWORD="$(vault kv get -field=DB_PASSWORD davtro/db)"
export VAULT_ADDR VAULT_TOKEN

# --- 1. SQL: grupa davtro_app + uprawnienia (idempotentne) --------------------
# Uruchamiane w podzie Postgresa (local socket = trust w obrazie postgres).
SQL=$(cat <<'EOSQL'
ALTER ROLE davtro CREATEROLE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'davtro_app') THEN
    CREATE ROLE davtro_app NOLOGIN;
  END IF;
END $$;
DO $$ BEGIN
  GRANT davtro_app TO davtro WITH ADMIN OPTION;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT ALL ON SCHEMA public TO davtro_app;
GRANT ALL ON ALL TABLES IN SCHEMA public TO davtro_app;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO davtro_app;
ALTER DEFAULT PRIVILEGES FOR ROLE davtro IN SCHEMA public GRANT ALL ON TABLES TO davtro_app;
ALTER DEFAULT PRIVILEGES FOR ROLE davtro IN SCHEMA public GRANT ALL ON SEQUENCES TO davtro_app;
EOSQL
)
kubectl -n davtro02 exec postgres-db-0 -- psql -U "$PG_ADMIN_USER" -d "$PG_DB" -c "$SQL"
echo "[OK] SQL: grupa davtro_app + uprawnienia"

# --- 2. Vault: database secrets engine ---------------------------------------
if ! vault secrets list | grep -q '^database/'; then
  vault secrets enable "$VAULT_DB_MOUNT"
fi
echo "[OK] Vault: engine database"

# --- 3. Polaczenie do Postgresa (admin = davtro + haslo z KV) -----------------
vault write "$VAULT_DB_MOUNT/config/$VAULT_CONN_NAME" \
  plugin_name=postgresql-database-plugin \
  allowed_roles="$VAULT_ROLE" \
  connection_url="postgresql://{{username}}:{{password}}@${PG_HOST}:5432/${PG_DB}?sslmode=disable" \
  username="$PG_ADMIN_USER" \
  password="$DB_PASSWORD"
vault write -force "$VAULT_DB_MOUNT/reset/$VAULT_CONN_NAME"   # wymus test polaczenia
echo "[OK] Vault: polaczenie $VAULT_CONN_NAME"

# --- 4. Rola davtro-app-rw ----------------------------------------------------
# creation: temp user IN davtro_app (uprawnienia DML/DDL przez grupe) + IN davtro
#           (zeby revocation mogl zrobic REASSIGN OWNED obiektow stworzonych przez temp usera)
# revocation: przeniesie wlasnosc obiektow na grupe, wyczysci i usunie role
TMPDIR_DB="$(mktemp -d)"
cat > "$TMPDIR_DB/creation.sql" <<'EOSQL'
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT IN ROLE davtro_app ROLE davtro;
EOSQL
cat > "$TMPDIR_DB/revocation.sql" <<'EOSQL'
REASSIGN OWNED BY "{{name}}" TO davtro_app;
DROP OWNED BY "{{name}}";
DROP ROLE IF EXISTS "{{name}}";
EOSQL
vault write "$VAULT_DB_MOUNT/roles/$VAULT_ROLE" \
  db_name="$VAULT_CONN_NAME" \
  creation_statements="@$TMPDIR_DB/creation.sql" \
  revocation_statements="@$TMPDIR_DB/revocation.sql" \
  default_ttl="1h" \
  max_ttl="24h"
rm -rf "$TMPDIR_DB"
echo "[OK] Vault: rola $VAULT_ROLE (TTL 1h, max 24h)"

# --- 5. Test ------------------------------------------------------------------
vault read "$VAULT_DB_MOUNT/creds/$VAULT_ROLE"
echo "[DONE] Pobierz probne credsy wyzej; ExternalSecret (ESO) moze teraz syncowac."
