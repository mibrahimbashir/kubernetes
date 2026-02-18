# 🚀 Kubernetes Deployment Guide - Complete Tutorial

This guide will teach you Kubernetes from scratch while deploying your FastAPI + Celery system with **autoscaling**.

---

## 📚 Table of Contents

1. [What is Kubernetes?](#what-is-kubernetes)
2. [Core Concepts Explained](#core-concepts-explained)
3. [Prerequisites](#prerequisites)
4. [Local Setup (Learning)](#local-setup-learning)
5. [Deployment Steps](#deployment-steps)
6. [Understanding Autoscaling](#understanding-autoscaling)
7. [Testing Autoscaling](#testing-autoscaling)
8. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
9. [Production Deployment](#production-deployment)
10. [Common Issues](#common-issues)

---

## 🤔 What is Kubernetes?

**Kubernetes (K8s)** is a container orchestration platform that automates:
- **Deployment**: Run your containers across multiple servers
- **Scaling**: Automatically add/remove containers based on load
- **Self-healing**: Restart failed containers automatically
- **Load balancing**: Distribute traffic across containers
- **Rolling updates**: Deploy new versions with zero downtime

### Why Kubernetes for Your Project?

Your FastAPI + Celery system has **variable workload**:
- Low traffic at night → Need few workers
- High traffic during day → Need many workers
- Image processing tasks → Memory/CPU intensive

**Without Kubernetes**: You manually manage servers, can't scale automatically, waste money on idle resources.

**With Kubernetes**: Automatic scaling based on CPU/Memory, pay only for what you use, self-healing if containers crash.

---

## 🧠 Core Concepts Explained

### 1. **Cluster**
A group of machines (nodes) that run your containers.
```
Cluster = Master Node + Worker Nodes
```

### 2. **Node**
A physical or virtual machine. Your containers run on nodes.

### 3. **Pod**
The smallest unit in Kubernetes. Wraps one or more containers.
```
Pod = One or more containers + shared storage + network
```
Think of it like a "wrapper" around your Docker container.

### 4. **Deployment**
Defines the desired state for your pods.
```yaml
Deployment says: "I want 3 FastAPI pods running"
Kubernetes ensures: Always 3 pods running (auto-restarts if they crash)
```

### 5. **Service**
A stable network endpoint to access pods (pods have changing IPs!).
```
Service = Load balancer for your pods
```

### 6. **ConfigMap**
Stores configuration (like environment variables).

### 7. **Horizontal Pod Autoscaler (HPA)**
Automatically scales pods based on CPU/Memory/Custom metrics.
```
Traffic high → HPA adds more pods
Traffic low → HPA removes pods
```

### 8. **PersistentVolumeClaim (PVC)**
Requests storage for your pods (for file uploads in your case).

---

## 📋 Prerequisites

### For Learning (Local)
- **Docker Desktop** with Kubernetes enabled, OR
- **Minikube** (local Kubernetes cluster)
- **kubectl** (Kubernetes CLI tool)

### For Production (Cloud)
- AWS EKS / Google GKE / Azure AKS account
- Docker registry (Docker Hub, AWS ECR, Google GCR)

---

## 🏠 Local Setup (Learning)

### Option 1: Docker Desktop (Easiest)

1. **Install Docker Desktop**
   - Download from [docker.com](https://www.docker.com/products/docker-desktop)

2. **Enable Kubernetes**
   - Docker Desktop → Settings → Kubernetes → Enable Kubernetes
   - Wait for "Kubernetes is running" (takes 2-5 minutes)

3. **Verify Installation**
   ```bash
   kubectl version --client
   kubectl cluster-info
   ```

### Option 2: Minikube

1. **Install Minikube**
   ```bash
   # Windows (with Chocolatey)
   choco install minikube

   # macOS
   brew install minikube

   # Linux
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install minikube-linux-amd64 /usr/local/bin/minikube
   ```

2. **Start Minikube**
   ```bash
   minikube start --cpus=4 --memory=8192 --disk-size=20g
   ```

3. **Verify**
   ```bash
   kubectl get nodes
   # Should show one node (minikube)
   ```

### Install Metrics Server (Required for Autoscaling!)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For minikube/local testing, you may need to disable TLS:
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Verify metrics server is running
kubectl get deployment metrics-server -n kube-system
```

---

## 🚀 Deployment Steps

### Step 1: Build and Push Docker Images

You need to push your images to a registry (Docker Hub, AWS ECR, etc.)

```bash
# Build FastAPI image
docker build -f DockerfileWebApi -t YOUR_USERNAME/fastapi-celery:v1 .

# Build Celery worker image
docker build -f DockerfileCelery -t YOUR_USERNAME/celery-worker:v1 .

# Push to Docker Hub (or your registry)
docker push YOUR_USERNAME/fastapi-celery:v1
docker push YOUR_USERNAME/celery-worker:v1
```

**IMPORTANT**: Update image names in these files:
- `k8s/03-fastapi-deployment.yaml` (line 57)
- `k8s/04-celery-deployment.yaml` (line 53)

Replace `your-docker-registry/fastapi:latest` with `YOUR_USERNAME/fastapi-celery:v1`

### Step 2: Deploy to Kubernetes

```bash
# Apply all manifests in order
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/06-persistent-volume.yaml
kubectl apply -f k8s/02-redis-deployment.yaml
kubectl apply -f k8s/03-fastapi-deployment.yaml
kubectl apply -f k8s/04-celery-deployment.yaml
kubectl apply -f k8s/05-flower-deployment.yaml
kubectl apply -f k8s/07-hpa-fastapi.yaml
kubectl apply -f k8s/08-hpa-celery.yaml
kubectl apply -f k8s/09-resource-quota.yaml

# Or apply all at once:
kubectl apply -f k8s/
```

### Step 3: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n async-tasks

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# redis-xxx                       1/1     Running   0          2m
# fastapi-xxx                     1/1     Running   0          2m
# fastapi-yyy                     1/1     Running   0          2m
# celery-worker-xxx               1/1     Running   0          2m
# celery-worker-yyy               1/1     Running   0          2m
# flower-xxx                      1/1     Running   0          2m

# Check services
kubectl get svc -n async-tasks

# Check HPA status
kubectl get hpa -n async-tasks
```

### Step 4: Access Your Application

```bash
# Get FastAPI service URL
kubectl get svc fastapi-service -n async-tasks

# For LoadBalancer (cloud):
# External IP will be shown (may take 2-5 minutes)

# For local testing (minikube):
minikube service fastapi-service -n async-tasks --url

# Access Flower monitoring
minikube service flower-service -n async-tasks --url
# Or port-forward:
kubectl port-forward -n async-tasks svc/flower-service 5555:5555
# Then open: http://localhost:5555
```

---

## 🔄 Understanding Autoscaling

### How HPA Works

**HPA (Horizontal Pod Autoscaler)** monitors metrics every 15 seconds:

```
1. HPA checks current CPU/Memory usage
2. Compares to target utilization
3. Calculates desired replicas:

   desiredReplicas = ceil(currentReplicas * (currentMetric / targetMetric))

4. Scales up/down gradually (respects min/max limits)
```

### Example: FastAPI Scaling

**Configuration** (from `07-hpa-fastapi.yaml`):
- Min replicas: 2
- Max replicas: 10
- Target CPU: 70%
- Target Memory: 80%

**Scenario**: Traffic spike!
```
Time 0s:  2 pods running, CPU at 50% each → OK
Time 30s: Traffic doubles, CPU at 100% → OVERLOADED!
Time 45s: HPA detects high CPU (100% > 70% target)
Time 60s: HPA calculates: 2 * (100/70) = 2.86 → scale to 3 pods
Time 75s: 3 pods running, CPU at 66% each → GOOD
Time 90s: Traffic triples, CPU at 90% → HIGH!
Time 120s: HPA scales to 5 pods
Time 150s: 5 pods running, CPU at 60% → STABLE
```

**Scenario**: Traffic drops
```
Time 0s:  5 pods running, CPU at 60%
Time 300s: Traffic decreases, CPU at 30%
Time 600s: HPA waits 5 minutes (stabilization window)
Time 620s: Still at 30% CPU → safe to scale down
Time 640s: HPA removes 1 pod → 4 pods
Time 900s: Still low traffic → removes 1 more → 3 pods
```

### Why Different Thresholds for Workers?

**FastAPI**: Target CPU 70%
- API is latency-sensitive (users waiting for responses)
- Better to have spare capacity

**Celery Workers**: Target CPU 60%
- More aggressive scaling
- Background tasks can queue up
- Better to over-provision than have huge queue

---

## 🧪 Testing Autoscaling

### Test 1: API Load Test

Generate load to trigger FastAPI autoscaling:

```bash
# Install load testing tool
# Option 1: Apache Bench
apt-get install apache2-utils  # Linux
brew install httpd             # macOS

# Option 2: Hey (better)
go install github.com/rakyll/hey@latest

# Get FastAPI URL
FASTAPI_URL=$(kubectl get svc fastapi-service -n async-tasks -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Generate load: 100 concurrent requests for 2 minutes
hey -c 100 -z 120s -m POST -H "Content-Type: application/json" \
  -d '{"name":"loadtest"}' \
  http://${FASTAPI_URL}/async-process/

# Watch pods scale in real-time (separate terminal)
kubectl get hpa -n async-tasks -w
```

**What you'll see**:
```
NAME           REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
fastapi-hpa    Deployment/fastapi   45%/70%   2         10        2          5m
fastapi-hpa    Deployment/fastapi   89%/70%   2         10        2          6m
fastapi-hpa    Deployment/fastapi   89%/70%   2         10        3          6m
fastapi-hpa    Deployment/fastapi   120%/70%  2         10        3          7m
fastapi-hpa    Deployment/fastapi   120%/70%  2         10        5          7m
```

### Test 2: Worker Load Test

Generate tasks to trigger worker autoscaling:

```bash
# Submit many file processing tasks
for i in {1..100}; do
  curl -X POST http://${FASTAPI_URL}/async-file \
    -F "uploaded_file=@test-image.jpg"
  sleep 1
done

# Watch workers scale
kubectl get hpa celery-worker-hpa -n async-tasks -w
```

### Test 3: Monitor with Flower

```bash
# Access Flower dashboard
kubectl port-forward -n async-tasks svc/flower-service 5555:5555

# Open browser: http://localhost:5555
# Username: admin
# Password: test@123
```

**What to watch in Flower**:
- **Tasks**: See active, succeeded, failed tasks
- **Workers**: Watch new workers appear as HPA scales
- **Monitor**: Real-time task processing rate

---

## 📊 Monitoring & Troubleshooting

### View Pod Logs

```bash
# List all pods
kubectl get pods -n async-tasks

# View logs for specific pod
kubectl logs -n async-tasks POD_NAME

# Follow logs (real-time)
kubectl logs -n async-tasks POD_NAME -f

# Previous container logs (if pod restarted)
kubectl logs -n async-tasks POD_NAME --previous
```

### Check Resource Usage

```bash
# View current CPU/Memory usage
kubectl top pods -n async-tasks

# View node resource usage
kubectl top nodes

# Describe HPA (shows scaling decisions)
kubectl describe hpa fastapi-hpa -n async-tasks
```

### Check HPA Events

```bash
# See scaling events
kubectl get events -n async-tasks --sort-by='.lastTimestamp'

# Filter HPA events only
kubectl get events -n async-tasks --field-selector involvedObject.kind=HorizontalPodAutoscaler
```

### Common Commands

```bash
# Get all resources in namespace
kubectl get all -n async-tasks

# Describe a pod (shows events, status, errors)
kubectl describe pod POD_NAME -n async-tasks

# Execute command inside pod
kubectl exec -it POD_NAME -n async-tasks -- /bin/bash

# Port forward to a pod
kubectl port-forward POD_NAME -n async-tasks 8080:80

# Delete a pod (will auto-restart)
kubectl delete pod POD_NAME -n async-tasks

# Scale manually (temporary - HPA will override)
kubectl scale deployment fastapi -n async-tasks --replicas=5
```

---

## 🏭 Production Deployment

### 1. Use a Managed Kubernetes Service

**AWS EKS**:
```bash
eksctl create cluster --name async-tasks-prod --region us-east-1 --nodegroup-name workers --node-type t3.medium --nodes 3
```

**Google GKE**:
```bash
gcloud container clusters create async-tasks-prod --num-nodes=3 --machine-type=n1-standard-2
```

**Azure AKS**:
```bash
az aks create --resource-group myResourceGroup --name async-tasks-prod --node-count 3 --node-vm-size Standard_D2s_v3
```

### 2. Use Production Storage

Replace `emptyDir` with cloud storage:

**AWS EFS** (Elastic File System):
```yaml
# Install EFS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"

# Create EFS filesystem in AWS Console
# Update PVC to use EFS storage class
storageClassName: efs-sc
```

**Google Cloud Filestore** / **Azure Files**: Similar process

### 3. Secure Credentials

Use **Secrets** instead of hardcoding:

```bash
# Create secret for Redis password
kubectl create secret generic redis-password \
  --from-literal=password=YOUR_SECURE_PASSWORD \
  -n async-tasks

# Create secret for Flower auth
kubectl create secret generic flower-auth \
  --from-literal=username=admin \
  --from-literal=password=YOUR_SECURE_PASSWORD \
  -n async-tasks
```

Update deployments to reference secrets.

### 4. Use Ingress (Not LoadBalancer)

```yaml
# Install Ingress Controller (nginx)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Create Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastapi-ingress
  namespace: async-tasks
spec:
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-service
            port:
              number: 80
```

### 5. Enable SSL/TLS

Use **cert-manager** for automatic SSL:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### 6. Set Up Monitoring

**Prometheus + Grafana**:
```bash
# Install Prometheus Operator
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Install kube-prometheus-stack (includes Grafana)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

---

## ❗ Common Issues

### Issue 1: Metrics Server Not Working

**Symptom**: `kubectl top pods` shows "error: Metrics API not available"

**Fix**:
```bash
# For minikube/local
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

### Issue 2: HPA Shows "Unknown" Metrics

**Symptom**: `kubectl get hpa` shows `<unknown>/70%`

**Cause**: Pods don't have resource requests defined, or metrics server not ready

**Fix**:
1. Ensure resource requests are set (we did this!)
2. Wait 1-2 minutes for metrics to populate
3. Check: `kubectl top pods -n async-tasks`

### Issue 3: Pods Stuck in Pending

**Symptom**: `kubectl get pods` shows pods in "Pending" state

**Cause**: Not enough resources in cluster

**Fix**:
```bash
# Check events
kubectl describe pod POD_NAME -n async-tasks

# Check node resources
kubectl describe nodes

# For minikube: increase resources
minikube stop
minikube start --cpus=4 --memory=8192
```

### Issue 4: ImagePullBackOff

**Symptom**: Pods show "ImagePullBackOff" error

**Cause**: Can't pull Docker image from registry

**Fix**:
1. Verify image exists: `docker pull YOUR_IMAGE`
2. Check image name in deployment YAML
3. For private registries, create image pull secret:
```bash
kubectl create secret docker-registry regcred \
  --docker-server=YOUR_REGISTRY \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  -n async-tasks
```

### Issue 5: PVC Stuck in Pending

**Symptom**: PersistentVolumeClaim shows "Pending"

**Cause**: No storage provisioner, or RWX not supported

**Fix for local testing**:
```yaml
# Use ReadWriteOnce instead
accessModes:
  - ReadWriteOnce

# Add node affinity to ensure all pods on same node
```

---

## 🎓 Learning Resources

- **Official Docs**: https://kubernetes.io/docs/
- **Interactive Tutorial**: https://kubernetes.io/docs/tutorials/kubernetes-basics/
- **Playground**: https://labs.play-with-k8s.com/
- **Autoscaling Deep Dive**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

---

## 🎯 Next Steps

1. **Deploy locally** with minikube (learning)
2. **Test autoscaling** with load tests
3. **Monitor** with Flower and kubectl
4. **Deploy to cloud** (AWS/GCP/Azure)
5. **Advanced**: Queue-based autoscaling with Prometheus

**You're now ready to deploy a production-grade autoscaling system!** 🚀
