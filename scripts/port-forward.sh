#!/bin/bash
# Port-forwarding uslug DavTro - dostep z innych maszyn w LAN.
#
# Domyslnie bindowanie na 0.0.0.0 (widoczne z sieci).
# Lokalnie (tylko ta maszyna):  ADDR=127.0.0.1 ./scripts/port-forward.sh
#
# UWAGA: port 8080 jest ZAJETY przez port-forward ArgoCD, wiec:
#   FastAPI -> 8082, frontend -> 8083, spring -> 8084, spark-ui -> 8085
#
# ArgoCD (uruchamiane recznie, port 8080 -> 443, TLS/HTTPS):
#   kubectl port-forward --address 0.0.0.0 -n argocd service/argo-cd-argocd-server 8080:443
#   UI: https://<IP-HOSTA>:8080/   (HTTP -> 307 na HTTPS; zaakceptuj certyfikat self-signed)

ADDR="${ADDR:-0.0.0.0}"

echo "Port-forwarding uslug DavTro na $ADDR ..."

#              local:target-branch   |  usluga / opis
# ---------------------------------------------------------
#   FastAPI     8082 -> fastapi-web-app-svc:80      | REST API (/api/health)
#   Frontend    8083 -> frontend-svc:80             | strona WWW (nginx non-root)
#   Grafana     3000 -> grafana:3000                | dashboards
#   Kafka UI    8081 -> kafka-ui:80                 | konsola Kafka
#   Loki        3100 -> loki:3100                   | logi
#   Tempo       3200 -> tempo:3200                  | trace'e (APM)
#   Prometheus  9090 -> prometheus:9090             | metryki
#   pgAdmin     5050 -> pgadmin:80                  | PostgreSQL UI
#   PostgreSQL  5432 -> postgres-clusterip:5432     | baza danych
#   Redis       6379 -> redis:6379                  | cache
#   Vault       8200 -> vault:8200                  | sekrety
#   Spring      8084 -> spring-app-svc:80           | Spring Boot
#   Spark UI    8085 -> spark-master-svc:8082       | Spark dashboard
#   Spark       7077 -> spark-master-svc:7077       | Spark protocol
#   Kafka       9092 -> kafka-kraft:9092            | broker Kafka
#   Kafka Exp   9308 -> kafka-exporter:9308         | metryki Kafka
#   PG Exp      9187 -> postgres-exporter:9187      | metryki Postgres
#   Node Exp    9101 -> node-exporter:9100          | metryki Node (9100 lokalnie zajete przez node_exporter na hoscie)
# ---------------------------------------------------------

start() {
  local NAME="$1" LOCAL="$2" SVC="$3" TARGET="$4"
  kubectl port-forward --address "$ADDR" -n davtro02 "svc/$SVC" "$LOCAL:$TARGET" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: http://<IP>:${LOCAL}/  -> $SVC:$TARGET"
}

start fastapi     8082 fastapi-web-app-svc 80
start frontend    8083 frontend-svc        80
start grafana     3000 grafana             3000
start kafka-ui    8081 kafka-ui            80
start loki        3100 loki                3100
start tempo       3200 tempo               3200
start prometheus  9090 prometheus          9090
start pgadmin     5050 pgadmin             80
start postgres    5432 postgres-clusterip  5432
start redis       6379 redis               6379
start vault       8200 vault               8200
start spring      8084 spring-app-svc      80
start spark-ui    8085 spark-master-svc    8082
start spark       7077 spark-master-svc    7077
start kafka       9092 kafka-kraft         9092
start kafka-exp   9308 kafka-exporter      9308
start pg-exp      9187 postgres-exporter   9187
start node-exp    9101 node-exporter       9100

echo
echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno, port 8080 = ArgoCD)"
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
echo
echo "Logi pojedynczych forwardow: /tmp/pf-<nazwa>.log"
