#!/bin/bash
echo "🧹 Czyszczenie..."
read -p "Usunąć namespace question-system? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    kubectl delete namespace question-system
    echo "✅ Wyczyszczono"
fi
