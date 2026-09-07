# Focused deploy script (replaces generator output)

# This file was updated to be a minimal, safe deploy script limited to this repository.
# It only operates on manifests under ./manifests/base and will not touch other folders.

#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

PROJECT="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
NAMESPACE="${NAMESPACE:-davtro}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${ROOT_DIR}/manifests/base"

usage(){
  cat <<EOF
Usage: $0 <command>

Commands:
  apply    Apply manifests in ${MANIFESTS_DIR} to namespace ${NAMESPACE}
  delete   Delete manifests from namespace ${NAMESPACE}
  status   Show pods and services in namespace ${NAMESPACE}
EOF
  exit 1
}

ensure_kubectl(){
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found in PATH; please install / configure kubectl and kubeconfig"
    exit 2
  fi
}

apply(){
  ensure_kubectl

  if [ ! -d "${MANIFESTS_DIR}" ]; then
    echo "Manifests directory ${MANIFESTS_DIR} not found. Nothing to apply."
    exit 1
  fi

  echo "📦 Creating namespace ${NAMESPACE} if missing..."
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

  echo "📥 Applying manifests from ${MANIFESTS_DIR}..."
  kubectl apply -f "${MANIFESTS_DIR}" -n "${NAMESPACE}"

  echo "⏳ Waiting for key components to become ready (this may take a few minutes)..."
  set +e
  kubectl wait --for=condition=ready pod -l component=fastapi -n "${NAMESPACE}" --timeout=180s
  kubectl wait --for=condition=ready pod -l component=spring -n "${NAMESPACE}" --timeout=180s
  kubectl wait --for=condition=ready pod -l component=spark-master -n "${NAMESPACE}" --timeout=240s
  kubectl wait --for=condition=ready pod -l component=postgres -n "${NAMESPACE}" --timeout=180s
  kubectl wait --for=condition=ready pod -l component=redis -n "${NAMESPACE}" --timeout=120s
  kubectl wait --for=condition=ready pod -l component=kafka -n "${NAMESPACE}" --timeout=240s
  set -e

  if kubectl get job vault-init -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "🔐 Waiting for vault initialization job to complete..."
    kubectl wait --for=condition=complete job/vault-init -n "${NAMESPACE}" --timeout=120s || echo "Vault init job did not complete within timeout or already completed."
  fi

  echo "🔄 Performing rollout restart for FastAPI to pick up potential new routes..."
  kubectl rollout restart deployment/fastapi-web-app -n "${NAMESPACE}" 2>/dev/null || true

  echo "\n✅ Apply complete. Access hints:"
  echo "   Main App:  http://app.${PROJECT}.local"
  echo "   New Survey: http://app.${PROJECT}.local/new-survey"
  echo "   Spring API: http://spring.${PROJECT}.local"
  echo "   Spark UI:   http://spark.${PROJECT}.local"
  echo "   Kibana:     http://kibana.${PROJECT}.local"
  echo "   Grafana:    http://grafana.${PROJECT}.local"
  echo "   PgAdmin:    http://pgadmin.${PROJECT}.local"
}

_delete(){
  echo "🗑️ Deleting resources defined in ${MANIFESTS_DIR} from namespace ${NAMESPACE}..."
  kubectl delete -f "${MANIFESTS_DIR}" -n "${NAMESPACE}" --ignore-not-found
}

delete(){
  ensure_kubectl
  read -p "Are you sure you want to delete all resources in ${NAMESPACE} defined by ${MANIFESTS_DIR}? [y/N] " yn
  case "${yn}" in
    [Yy]* ) _delete; echo "✅ Delete requested." ;;
    * ) echo "Aborted."; exit 0 ;;
  esac
}

status(){
  ensure_kubectl
  echo "📋 Pods in namespace ${NAMESPACE}:"
  kubectl get pods -n "${NAMESPACE}"
  echo "\n🔌 Services in namespace ${NAMESPACE}:"
  kubectl get svc -n "${NAMESPACE}"
}

case "${1:-}" in
  apply) apply ;;
  delete) delete ;;
  status) status ;;
  *) usage ;;
esac

