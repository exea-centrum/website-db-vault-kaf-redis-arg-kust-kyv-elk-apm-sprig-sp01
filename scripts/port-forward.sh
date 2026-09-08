#!/bin/bash
# Port-forwarding uslug DavTro - dostep z innych maszyn w LAN.
#
# Domyslnie bindowanie na 0.0.0.0 (widoczne z sieci).
# Lokalnie:  ADDR=127.0.0.1 ./scripts/port-forward.sh
#
# UWAGA: port 8080 jest ZAJETY przez port-forward ArgoCD (patrz nizej),
# wiec FastAPI poszedl na 8082, a frontend na 8083.
#
# ArgoCD (uruchamiane recznie, port 8080 -> 443, TLS/HTTPS):
#   kubectl port-forward --address 0.0.0.0 -n argocd service/argo-cd-argocd-server 8080:443
#   UI: https://<IP-HOSTA>:8080/   (HTTP -> 307 na HTTPS; zaakceptuj certyfikat self-signed)

ADDR="${ADDR:-0.0.0.0}"

echo "Port-forwarding uslug DavTro na $ADDR ..."

kubectl port-forward --address "$ADDR" -n davtro02 svc/fastapi-web-app-svc 8082:80 &
kubectl port-forward --address "$ADDR" -n davtro02 svc/frontend-svc 8083:80 &
kubectl port-forward --address "$ADDR" -n davtro02 svc/grafana 3000:3000 &
kubectl port-forward --address "$ADDR" -n davtro02 svc/prometheus 9090:9090 &
kubectl port-forward --address "$ADDR" -n davtro02 svc/kafka-ui 8081:80 &

echo
echo "FastAPI:    http://<IP-HOSTA>:8082   (health: /api/health)"
echo "Frontend:   http://<IP-HOSTA>:8083"
echo "Grafana:    http://<IP-HOSTA>:3000"
echo "Prometheus: http://<IP-HOSTA>:9090"
echo "Kafka UI:   http://<IP-HOSTA>:8081"
echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno)"
echo
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
