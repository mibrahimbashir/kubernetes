# ⚖️ Kubernetes Autoscaling Implementation Guide

**Project**: FastAPI + Celery + Redis Distributed Task Processing System
**Objective**: Implement horizontal pod autoscaling based on CPU and Memory metrics
**Platform**: Kubernetes (Docker Desktop / Minikube / Cloud K8s)

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Autoscaling Strategy](#autoscaling-strategy)
4. [Implementation Steps](#implementation-steps)
5. [Configuration Details](#configuration-details)
6. [Testing Autoscaling](#testing-autoscaling)
7. [Monitoring & Validation](#monitoring--validation)
8. [Troubleshooting](#troubleshooting)

---

## 🏗️ Architecture Overview

### **System Components:**

```
┌──────────────────────────────────────────────────────┐
│                Kubernetes Cluster                     │
│                                                       │
│  ┌─────────────────────────────────────────────┐    │
│  │  FastAPI Pods (Autoscaling: 2-10)           │    │
│  │  - REST API endpoints                        │    │
│  │  - Task submission                           │    │
│  │  - Status checking                           │    │
│  └─────────────────────────────────────────────┘    │
│                      │                                │
│                      ↓                                │
│  ┌─────────────────────────────────────────────┐    │
│  │  Redis Pod (1 replica, stable)              │    │
│  │  - Message broker                            │    │
│  │  - Result backend                            │    │
│  └─────────────────────────────────────────────┘    │
│                      │                                │
│                      ↓                                │
│  ┌─────────────────────────────────────────────┐    │
│  │  Celery Worker Pods (Autoscaling: 2-20)     │    │
│  │  - Background task processing                │    │
│  │  - CPU/Memory intensive work                 │    │
│  └─────────────────────────────────────────────┘    │
│                                                       │
│  ┌─────────────────────────────────────────────┐    │
│  │  HorizontalPodAutoscaler (HPA)              │    │
│  │  - Monitors metrics every 15s                │    │
│  │  - Scales pods based on CPU/Memory           │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### **Why Autoscaling?**

- **Cost Optimization**: Pay only for resources you use
- **Performance**: Maintain response times under varying load
- **Availability**: Handle traffic spikes automatically
- **Efficiency**: Scale down during low traffic

---

## ✅ Prerequisites

### **1. Kubernetes Cluster Running**
```bash
kubectl cluster-info
```

### **2. Metrics Server Installed** (CRITICAL for autoscaling!)
```bash
# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For local testing (Docker Desktop/Minikube), disable TLS:
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Verify metrics server is running
kubectl get deployment metrics-server -n kube-system

# Wait ~1 minute, then test:
kubectl top nodes
kubectl top pods -n kube-system
```

### **3. Docker Images Built**
```bash
docker build -f DockerfileWebApi -t fastapi-celery:v1 .
docker build -f DockerfileCelery -t celery-worker:v1 .
```

---

## 📊 Autoscaling Strategy

### **Service-Specific Thresholds**

| Service | Min Pods | Max Pods | CPU Threshold | Memory Threshold | Reasoning |
|---------|----------|----------|---------------|------------------|-----------|
| **FastAPI** | 2 | 10 | 70% | 80% | User-facing API, moderate scaling |
| **Celery Workers** | 2 | 20 | 60% | 75% | Background tasks, aggressive scaling |

### **Why Different Thresholds?**

**FastAPI (70% CPU):**
- User-facing, latency-sensitive
- Needs headroom for response time consistency
- Conservative scaling to maintain quality of service

**Celery Workers (60% CPU):**
- Background processing can queue up
- More aggressive scaling prevents backlog
- Can handle more replicas without quality impact

---

## 🚀 Implementation Steps

### **Step 1: Define Resource Requests & Limits**

Resource requests and limits are **MANDATORY** for HPA to work!

**FastAPI Deployment** (`k8s/03-fastapi-deployment.yaml`):
```yaml
spec:
  template:
    spec:
      containers:
      - name: fastapi
        image: fastapi-celery:v1
        resources:
          requests:
            memory: "256Mi"  # Minimum guaranteed
            cpu: "200m"      # 0.2 CPU cores
          limits:
            memory: "1Gi"    # Maximum allowed
            cpu: "1000m"     # 1 CPU core max
```

**Celery Worker Deployment** (`k8s/04-celery-deployment.yaml`):
```yaml
spec:
  template:
    spec:
      containers:
      - name: celery-worker
        image: celery-worker:v1
        resources:
          requests:
            memory: "512Mi"  # Workers need more memory
            cpu: "300m"      # 0.3 CPU cores
          limits:
            memory: "2Gi"    # Allow 2GB for image processing
            cpu: "2000m"     # 2 CPU cores max
```

**Why These Values?**
- `requests`: Used by scheduler to place pods, and by HPA to calculate utilization
- `limits`: Prevents pods from consuming all node resources
- HPA calculates: `actual_usage / requested_resources * 100 = utilization %`

---

### **Step 2: Create HorizontalPodAutoscaler**

**FastAPI HPA** (`k8s/07-hpa-fastapi.yaml`):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-hpa
  namespace: async-tasks
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi

  minReplicas: 2
  maxReplicas: 10

  metrics:
  # CPU-based scaling
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Scale when avg CPU > 70%

  # Memory-based scaling
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Scale when avg memory > 80%

  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60  # Wait 60s before scaling up again
      policies:
      - type: Percent
        value: 50        # Increase by max 50% of current pods
        periodSeconds: 60
      - type: Pods
        value: 2         # Or add max 2 pods at once
        periodSeconds: 60
      selectPolicy: Max  # Use whichever scales faster

    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
      policies:
      - type: Percent
        value: 50        # Decrease by max 50% of current pods
        periodSeconds: 60
      - type: Pods
        value: 1         # Or remove max 1 pod at a time
        periodSeconds: 60
      selectPolicy: Min  # Use whichever scales slower (conservative)
```

**Celery Worker HPA** (`k8s/08-hpa-celery.yaml`):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: celery-worker-hpa
  namespace: async-tasks
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: celery-worker

  minReplicas: 2
  maxReplicas: 20  # Can scale higher than FastAPI

  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60  # More aggressive (lower threshold)

  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 75

  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30  # Scale up faster than FastAPI
      policies:
      - type: Percent
        value: 100       # Can DOUBLE workers quickly
        periodSeconds: 30
      - type: Pods
        value: 4         # Or add 4 workers at once
        periodSeconds: 30
      selectPolicy: Max

    scaleDown:
      stabilizationWindowSeconds: 600  # Wait 10 min (longer than FastAPI)
      policies:
      - type: Percent
        value: 25        # Remove only 25% at a time
        periodSeconds: 120
      - type: Pods
        value: 2
        periodSeconds: 120
      selectPolicy: Min
```

---

### **Step 3: Deploy Everything**

```bash
# Apply all manifests
kubectl apply -f k8s/

# Verify deployments
kubectl get deployments -n async-tasks

# Verify HPA created
kubectl get hpa -n async-tasks

# Expected output:
# NAME                REFERENCE                  TARGETS         MINPODS   MAXPODS   REPLICAS
# fastapi-hpa         Deployment/fastapi         5%/70%, 10%/80% 2         10        2
# celery-worker-hpa   Deployment/celery-worker   3%/60%, 8%/75%  2         20        2
```

---

## 🔍 Configuration Details

### **HPA Calculation Formula**

```
desiredReplicas = ceil(currentReplicas * (currentMetricValue / targetMetricValue))
```

**Example:**
- Current: 2 FastAPI pods
- Current CPU: 140% (average across pods)
- Target CPU: 70%
- Calculation: `ceil(2 * (140 / 70)) = ceil(2 * 2) = 4 pods`
- HPA scales from 2 → 4 pods

### **Scaling Behavior Parameters**

| Parameter | Purpose | FastAPI | Workers |
|-----------|---------|---------|---------|
| `stabilizationWindowSeconds` (up) | Prevent flapping | 60s | 30s |
| `stabilizationWindowSeconds` (down) | Conservative scale-down | 300s | 600s |
| Scale-up policy | How fast to add pods | +50% or +2 | +100% or +4 |
| Scale-down policy | How fast to remove pods | -50% or -1 | -25% or -2 |

### **Why Stabilization Windows?**

- **Prevents flapping**: Rapid scale up/down cycles
- **Smooths metric spikes**: Waits to confirm sustained load
- **Cost optimization**: Don't add pods for brief spikes

---

## 🧪 Testing Autoscaling

### **Test 1: Verify HPA is Monitoring**

```bash
# Check HPA status (wait 1-2 minutes after deployment)
kubectl get hpa -n async-tasks

# Expected: Should show actual percentages (not <unknown>)
# NAME                REFERENCE                  TARGETS         MINPODS   MAXPODS   REPLICAS
# fastapi-hpa         Deployment/fastapi         5%/70%, 10%/80% 2         10        2
# celery-worker-hpa   Deployment/celery-worker   3%/60%, 8%/75%  2         20        2
```

If you see `<unknown>`, wait 1-2 minutes for metrics to populate.

---

### **Test 2: Generate API Load**

**Terminal 1** - Watch HPA:
```bash
kubectl get hpa -n async-tasks -w
```

**Terminal 2** - Watch Pods:
```bash
kubectl get pods -n async-tasks -w
```

**Terminal 3** - Generate Load:
```bash
# Submit 100 tasks
for i in {1..100}; do
  curl -X POST http://localhost/async-process/ \
    -H "Content-Type: application/json" \
    -d '{"name":"loadtest"}' &
done

# Wait for background jobs
wait
```

---

### **Test 3: Heavy Load (Trigger Aggressive Scaling)**

```bash
# Generate 500 requests
for i in {1..500}; do
  curl -X POST http://localhost/async-process/ \
    -H "Content-Type: application/json" \
    -d '{"name":"stress-test"}' &
done
```

**Expected Behavior:**
1. CPU/Memory spikes on FastAPI and Workers
2. HPA detects high utilization
3. New pods created (FastAPI: 2→4→6, Workers: 2→4→8)
4. Load distributes across pods
5. Metrics stabilize
6. After 5-10 minutes of low traffic, pods scale back down

---

### **Test 4: Scale-Down Behavior**

```bash
# After load test, stop generating requests
# Watch pods scale down gradually

kubectl get hpa -n async-tasks -w
```

**Expected:**
- Wait ~5 minutes (stabilization window)
- Pods removed one at a time
- Eventually returns to min replicas (2)

---

## 📊 Monitoring & Validation

### **Check Current Metrics**

```bash
# View pod resource usage
kubectl top pods -n async-tasks

# Example output:
# NAME                            CPU(cores)   MEMORY(bytes)
# fastapi-xxx                     150m         200Mi
# celery-worker-xxx               450m         800Mi
```

### **Calculate Utilization Percentage**

```
CPU Utilization = (Current CPU / Requested CPU) * 100
Memory Utilization = (Current Memory / Requested Memory) * 100
```

**Example:**
- FastAPI using 150m CPU, requested 200m
- Utilization: (150/200) * 100 = **75%** ← Above 70% threshold!
- HPA will scale up

---

### **HPA Events**

```bash
# View scaling events
kubectl describe hpa fastapi-hpa -n async-tasks

# Look for events like:
# Normal   SuccessfulRescale  2m    horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

---

### **Scaling History**

```bash
# Get all events in namespace
kubectl get events -n async-tasks --sort-by='.lastTimestamp' | grep HorizontalPodAutoscaler

# View HPA status in detail
kubectl get hpa -n async-tasks -o yaml
```

---

## 🐛 Troubleshooting

### **Issue 1: HPA Shows `<unknown>` Metrics**

**Symptoms:**
```
NAME          REFERENCE            TARGETS           MINPODS   MAXPODS   REPLICAS
fastapi-hpa   Deployment/fastapi   <unknown>/70%     2         10        2
```

**Causes & Fixes:**

1. **Metrics Server not installed:**
   ```bash
   kubectl get deployment metrics-server -n kube-system
   # If not found, install it
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

2. **Metrics Server not ready:**
   ```bash
   # Wait 1-2 minutes, then check
   kubectl top nodes
   ```

3. **No resource requests defined:**
   ```bash
   # Check deployment has requests
   kubectl get deployment fastapi -n async-tasks -o yaml | grep -A5 resources
   ```

4. **Pods just started:**
   - Wait 1-2 minutes for first metrics scrape

---

### **Issue 2: Pods Not Scaling**

**Check HPA conditions:**
```bash
kubectl describe hpa fastapi-hpa -n async-tasks

# Look for errors like:
# - "unable to get metrics"
# - "missing request for cpu"
# - "the HPA was unable to compute the replica count"
```

**Common causes:**
- Deployment has 0 replicas
- Pods are not ready (failing health checks)
- Resource requests not defined
- HPA min/max replica conflict

---

### **Issue 3: Pods Scale Up But Not Down**

**Check stabilization window:**
```bash
# HPA might be waiting (default 5 minutes)
kubectl get hpa -n async-tasks -o yaml | grep stabilization

# Monitor and wait
kubectl get hpa -n async-tasks -w
```

**Scale-down is intentionally slow to prevent flapping!**

---

### **Issue 4: Excessive Scaling (Flapping)**

**Symptoms:** Pods constantly scaling up and down

**Solutions:**
1. Increase stabilization windows
2. Adjust thresholds (e.g., 70% → 75%)
3. Use wider min/max replica range
4. Check for metric spikes

---

### **Issue 5: Resource Limits Too Low**

**Symptoms:** Pods at 100% CPU, constantly hitting limits

**Fix:**
```bash
# Check current usage
kubectl top pods -n async-tasks

# If consistently at limits, increase in deployment:
resources:
  requests:
    cpu: "500m"     # Increase from 200m
    memory: "512Mi" # Increase from 256Mi
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

---

## 📈 Real-World Scaling Example

### **Scenario: Traffic Spike**

**Time 0s** - Normal load:
```
Pods: 2 FastAPI, 2 Workers
CPU: 30%, Memory: 40%
HPA: No action needed
```

**Time 30s** - Traffic increases 5x:
```
Pods: 2 FastAPI, 2 Workers
CPU: 150%, Memory: 90% ← Above thresholds!
HPA: Scaling detected, calculating...
```

**Time 60s** - HPA scales up:
```
Pods: 4 FastAPI, 5 Workers ← Scaled!
CPU: 80%, Memory: 60%
HPA: Stabilization window active
```

**Time 120s** - Load continues:
```
Pods: 6 FastAPI, 10 Workers ← Scaled again!
CPU: 65%, Memory: 55%
HPA: Load balanced, stable
```

**Time 600s** - Traffic returns to normal:
```
Pods: 6 FastAPI, 10 Workers
CPU: 25%, Memory: 30%
HPA: Waiting (stabilization window)
```

**Time 900s** - Scale down begins:
```
Pods: 5 FastAPI, 8 Workers ← Gradual scale-down
CPU: 28%, Memory: 35%
HPA: Continuing scale-down
```

**Time 1200s** - Back to baseline:
```
Pods: 2 FastAPI, 2 Workers ← Minimum replicas
CPU: 30%, Memory: 40%
HPA: Stable
```

---

## 🎯 Key Takeaways

### **Autoscaling Checklist:**

- ✅ Metrics Server installed and running
- ✅ Resource requests/limits defined on all pods
- ✅ HPA created with appropriate thresholds
- ✅ Stabilization windows configured
- ✅ Min/max replicas set reasonably
- ✅ Different thresholds for different services
- ✅ Monitoring in place (kubectl top, HPA status)
- ✅ Load testing performed
- ✅ Scale-up and scale-down validated

### **Best Practices:**

1. **Always define resource requests** - HPA requires them
2. **Use different thresholds per service** - One size doesn't fit all
3. **Conservative scale-down** - Prevent flapping
4. **Aggressive scale-up for workers** - Handle backlogs quickly
5. **Monitor and adjust** - Tune based on real-world metrics
6. **Test regularly** - Verify autoscaling works before production
7. **Set reasonable limits** - Don't scale infinitely (cost control)

---

## 📚 Additional Resources

- **Kubernetes HPA Docs**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- **Metrics Server**: https://github.com/kubernetes-sigs/metrics-server
- **HPA Walkthrough**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

---

**This configuration enables production-ready autoscaling that balances performance, cost, and reliability!** 🚀
