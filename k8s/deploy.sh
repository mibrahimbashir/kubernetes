#!/bin/bash
# =============================================================================
# Kubernetes Deployment Script
# =============================================================================
# This script automates the deployment process
# Usage: ./k8s/deploy.sh [environment]
# Example: ./k8s/deploy.sh local
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Environment (default: local)
ENV=${1:-local}

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}Deploying FastAPI + Celery + Redis to Kubernetes${NC}"
echo -e "${GREEN}Environment: ${ENV}${NC}"
echo -e "${GREEN}==============================================================================${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "\n${YELLOW}[1/7] Checking prerequisites...${NC}"
if ! command_exists kubectl; then
    echo -e "${RED}ERROR: kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

if ! command_exists docker; then
    echo -e "${RED}ERROR: docker not found. Please install Docker first.${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster.${NC}"
    echo -e "${YELLOW}For local testing:${NC}"
    echo -e "  - Docker Desktop: Enable Kubernetes in settings"
    echo -e "  - Minikube: Run 'minikube start'"
    exit 1
fi

echo -e "${GREEN}✓ kubectl found${NC}"
echo -e "${GREEN}✓ docker found${NC}"
echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"

# Check metrics server
echo -e "\n${YELLOW}[2/7] Checking Metrics Server (required for autoscaling)...${NC}"
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    echo -e "${GREEN}✓ Metrics Server already installed${NC}"
else
    echo -e "${YELLOW}Installing Metrics Server...${NC}"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    # For local clusters, disable TLS verification
    if [[ "$ENV" == "local" ]]; then
        echo -e "${YELLOW}Patching Metrics Server for local testing...${NC}"
        kubectl patch deployment metrics-server -n kube-system --type='json' \
          -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]' || true
    fi
    echo -e "${GREEN}✓ Metrics Server installed${NC}"
fi

# Build and push Docker images (skip for local with minikube)
echo -e "\n${YELLOW}[3/7] Building Docker images...${NC}"

# Check if we should build images
if [[ "$ENV" == "local" ]] && command_exists minikube; then
    echo -e "${YELLOW}Using minikube - building images directly in minikube...${NC}"
    eval $(minikube docker-env)
fi

# Check if images need to be built
read -p "Do you want to build Docker images? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your Docker registry username (e.g., dockerhub username): " DOCKER_USERNAME

    echo -e "${YELLOW}Building FastAPI image...${NC}"
    docker build -f DockerfileWebApi -t ${DOCKER_USERNAME}/fastapi-celery:v1 .

    echo -e "${YELLOW}Building Celery Worker image...${NC}"
    docker build -f DockerfileCelery -t ${DOCKER_USERNAME}/celery-worker:v1 .

    # Push images (skip for local minikube)
    if [[ "$ENV" != "local" ]] || ! command_exists minikube; then
        echo -e "${YELLOW}Pushing images to registry...${NC}"
        docker push ${DOCKER_USERNAME}/fastapi-celery:v1
        docker push ${DOCKER_USERNAME}/celery-worker:v1
    fi

    # Update deployment files with image names
    echo -e "${YELLOW}Updating deployment files with image names...${NC}"
    sed -i.bak "s|your-docker-registry/fastapi:latest|${DOCKER_USERNAME}/fastapi-celery:v1|g" k8s/03-fastapi-deployment.yaml
    sed -i.bak "s|your-docker-registry/celery-worker:latest|${DOCKER_USERNAME}/celery-worker:v1|g" k8s/04-celery-deployment.yaml
    rm -f k8s/*.bak

    echo -e "${GREEN}✓ Docker images built and pushed${NC}"
else
    echo -e "${YELLOW}Skipping image build. Make sure your deployment files have correct image names!${NC}"
fi

# Apply Kubernetes manifests
echo -e "\n${YELLOW}[4/7] Applying Kubernetes manifests...${NC}"

echo -e "${YELLOW}Creating namespace...${NC}"
kubectl apply -f k8s/00-namespace.yaml

echo -e "${YELLOW}Creating ConfigMap...${NC}"
kubectl apply -f k8s/01-configmap.yaml

echo -e "${YELLOW}Creating PersistentVolumeClaim...${NC}"
kubectl apply -f k8s/06-persistent-volume.yaml

echo -e "${YELLOW}Deploying Redis...${NC}"
kubectl apply -f k8s/02-redis-deployment.yaml

echo -e "${YELLOW}Deploying FastAPI...${NC}"
kubectl apply -f k8s/03-fastapi-deployment.yaml

echo -e "${YELLOW}Deploying Celery Workers...${NC}"
kubectl apply -f k8s/04-celery-deployment.yaml

echo -e "${YELLOW}Deploying Flower (monitoring)...${NC}"
kubectl apply -f k8s/05-flower-deployment.yaml

echo -e "${YELLOW}Creating HPA for FastAPI...${NC}"
kubectl apply -f k8s/07-hpa-fastapi.yaml

echo -e "${YELLOW}Creating HPA for Celery Workers...${NC}"
kubectl apply -f k8s/08-hpa-celery.yaml

echo -e "${YELLOW}Applying Resource Quotas...${NC}"
kubectl apply -f k8s/09-resource-quota.yaml

echo -e "${GREEN}✓ All manifests applied${NC}"

# Wait for pods to be ready
echo -e "\n${YELLOW}[5/7] Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=redis -n async-tasks --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=fastapi -n async-tasks --timeout=180s || true
kubectl wait --for=condition=ready pod -l app=celery-worker -n async-tasks --timeout=180s || true
kubectl wait --for=condition=ready pod -l app=flower -n async-tasks --timeout=120s || true

# Show deployment status
echo -e "\n${YELLOW}[6/7] Deployment Status:${NC}"
echo -e "\n${YELLOW}Pods:${NC}"
kubectl get pods -n async-tasks

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc -n async-tasks

echo -e "\n${YELLOW}HPA (Autoscalers):${NC}"
kubectl get hpa -n async-tasks

# Get access URLs
echo -e "\n${YELLOW}[7/7] Getting access URLs...${NC}"

if command_exists minikube && [[ "$ENV" == "local" ]]; then
    echo -e "\n${GREEN}Access your services:${NC}"
    echo -e "${YELLOW}FastAPI:${NC}"
    minikube service fastapi-service -n async-tasks --url

    echo -e "\n${YELLOW}Flower Dashboard:${NC}"
    minikube service flower-service -n async-tasks --url
else
    echo -e "\n${YELLOW}Waiting for LoadBalancer IPs (may take 2-5 minutes)...${NC}"

    FASTAPI_IP=$(kubectl get svc fastapi-service -n async-tasks -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    FLOWER_IP=$(kubectl get svc flower-service -n async-tasks -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

    echo -e "\n${GREEN}Access your services:${NC}"
    echo -e "${YELLOW}FastAPI:${NC} http://${FASTAPI_IP}"
    echo -e "${YELLOW}Flower Dashboard:${NC} http://${FLOWER_IP}:5555"

    if [[ "$FASTAPI_IP" == "pending" ]]; then
        echo -e "\n${YELLOW}LoadBalancer IPs are still pending. Check status with:${NC}"
        echo -e "  kubectl get svc -n async-tasks -w"
    fi
fi

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}Deployment Complete! 🚀${NC}"
echo -e "${GREEN}==============================================================================${NC}"

echo -e "\n${YELLOW}Useful commands:${NC}"
echo -e "  ${YELLOW}View pods:${NC}        kubectl get pods -n async-tasks"
echo -e "  ${YELLOW}View logs:${NC}        kubectl logs -f <pod-name> -n async-tasks"
echo -e "  ${YELLOW}Watch HPA:${NC}        kubectl get hpa -n async-tasks -w"
echo -e "  ${YELLOW}Port forward:${NC}     kubectl port-forward svc/flower-service -n async-tasks 5555:5555"
echo -e "  ${YELLOW}Scale manually:${NC}   kubectl scale deployment fastapi -n async-tasks --replicas=5"
echo -e "  ${YELLOW}Delete all:${NC}       kubectl delete namespace async-tasks"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Test the API: curl http://<FASTAPI_URL>/health/celery"
echo -e "  2. Access Flower at http://<FLOWER_URL>:5555 (admin/test@123)"
echo -e "  3. Run load tests to see autoscaling in action!"
echo -e "  4. Read KUBERNETES-GUIDE.md for detailed testing instructions"
