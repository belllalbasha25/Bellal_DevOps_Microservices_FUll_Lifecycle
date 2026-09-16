#!/bin/bash
set -e

AWS_REGION="us-east-1"
ECR_REGISTRY="722769295788.dkr.ecr.us-east-1.amazonaws.com"
NETWORK="ecommerce-network"
IMAGE_TAG="${1:-latest}"

echo "Deploying image tag: $IMAGE_TAG"

echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "Creating Docker network..."
docker network inspect "$NETWORK" >/dev/null 2>&1 || \
  docker network create "$NETWORK"

echo "Pulling images..."
docker pull "$ECR_REGISTRY/devops-auth:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/devops-catalog:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/devops-orders:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/devops-notification:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/devops-frontend:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/devops-nginx:$IMAGE_TAG"

echo "Stopping old containers..."
docker rm -f \
  ecom-auth \
  ecom-product \
  ecom-order \
  ecom-notification \
  ecom-frontend \
  ecom-nginx \
  ecom-postgres \
  2>/dev/null || true

echo "Starting PostgreSQL..."
docker run -d \
  --name ecom-postgres \
  --network-alias postgres \
  --network "$NETWORK" \
  -e POSTGRES_USER=ecommerce \
  -e POSTGRES_PASSWORD=devpassword \
  -e POSTGRES_DB=ecommerce \
  -v postgres_data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:15-alpine

echo "Waiting for PostgreSQL..."
until docker exec ecom-postgres pg_isready -U ecommerce -d ecommerce >/dev/null 2>&1; do
  sleep 2
done

echo "Starting auth-service..."
docker run -d \
  --name ecom-auth \
  --network-alias auth-service \
  --network "$NETWORK" \
  -e DB_HOST=postgres \
  -e DB_USER=ecommerce \
  -e DB_PASSWORD=devpassword \
  -e DB_NAME=ecommerce \
  -e JWT_SECRET=dev-secret \
  -e PORT=3001 \
  "$ECR_REGISTRY/devops-auth:$IMAGE_TAG"

echo "Starting product-service..."
docker run -d \
  --name ecom-product \
  --network-alias product-service \
  --network "$NETWORK" \
  -e DB_HOST=postgres \
  -e DB_USER=ecommerce \
  -e DB_PASSWORD=devpassword \
  -e DB_NAME=ecommerce \
  -e PORT=3002 \
  -e SEED_ON_BOOT=true \
  "$ECR_REGISTRY/devops-catalog:$IMAGE_TAG"

echo "Starting notification-service..."
docker run -d \
  --name ecom-notification \
  --network-alias notification-service \
  --network "$NETWORK" \
  -e DB_HOST=postgres \
  -e DB_USER=ecommerce \
  -e DB_PASSWORD=devpassword \
  -e DB_NAME=ecommerce \
  -e PORT=3004 \
  "$ECR_REGISTRY/devops-notification:$IMAGE_TAG"

echo "Starting order-service..."
docker run -d \
  --name ecom-order \
  --network-alias order-service \
  --network "$NETWORK" \
  -e DB_HOST=postgres \
  -e DB_USER=ecommerce \
  -e DB_PASSWORD=devpassword \
  -e DB_NAME=ecommerce \
  -e PORT=3003 \
  -e PRODUCT_SERVICE_URL=http://product-service:3002 \
  -e NOTIFICATION_SERVICE_URL=http://notification-service:3004 \
  "$ECR_REGISTRY/devops-orders:$IMAGE_TAG"

echo "Starting frontend..."
docker run -d \
  --name ecom-frontend \
  --network-alias frontend \
  --network "$NETWORK" \
  "$ECR_REGISTRY/devops-frontend:$IMAGE_TAG"

echo "Starting nginx..."
docker run -d \
  --name ecom-nginx \
  --network-alias nginx \
  --network "$NETWORK" \
  -p 8080:8080 \
  "$ECR_REGISTRY/devops-nginx:$IMAGE_TAG"

echo "Waiting for application..."
sleep 5

echo "Checking application health..."
curl -fsS http://localhost:8080/healthz

echo
echo "Deployment completed successfully."

echo "Container status:"
docker ps