#!/bin/bash
echo "🔨 Budowanie obrazów Docker..."
docker build -t fastapi-app:latest ../apps/fastapi-app
docker build -t message-processor:latest ../apps/message-processor
docker build -t redis-to-kafka:latest ../apps/redis-to-kafka
echo "✅ Obrazy zbudowane"
docker images | grep -E "fastapi-app|message-processor|redis-to-kafka"
