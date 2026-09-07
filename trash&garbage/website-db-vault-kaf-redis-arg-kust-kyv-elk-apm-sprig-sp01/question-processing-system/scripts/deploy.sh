#!/bin/bash
echo "🚀 Deployment do Kubernetes..."
kubectl cluster-info || { echo "❌ Brak połączenia z K8s"; exit 1; }
for file in ../k8s/base/*.yaml ../k8s/monitoring/*.yaml ../k8s/tools/*.yaml ../k8s/policies/*.yaml; do
    echo "Aplikowanie $file..."
    kubectl apply -f "$file"
    sleep 1
done
echo "✅ Deployment zakończony"
kubectl get pods -n question-system
