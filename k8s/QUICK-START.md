# ⚡ Kubernetes Quick Start - 5 Minutes to Deploy

The fastest way to deploy your autoscaling system to Kubernetes.

---

## 🎯 Prerequisites Checklist

- [ ] Docker installed
- [ ] kubectl installed
- [ ] Kubernetes cluster running (Docker Desktop K8s OR Minikube)
- [ ] Docker Hub account (or other registry)

---

## 🚀 Quick Deploy (Copy-Paste Commands)

### 1. Build & Push Images

```bash
# Set your Docker Hub username
export DOCKER_USERNAME="your-dockerhub-username"

# Build images
docker build -f DockerfileWebApi -t ${DOCKER_USERNAME}/fastapi-celery:v1 .
docker build -f DockerfileCelery -t ${DOCKER_USERNAME}/celery-worker:v1 .

# Push to registry
docker push ${DOCKER_USERNAME}/fastapi-celery:v1
docker push ${DOCKER_USERNAME}/celery-worker:v1
```

### 2. Update Image Names

```bash
# Update deployment files with your image names
sed -i "s|your-docker-registry/fastapi:latest|${DOCKER_USERNAME}/fastapi-celery:v1|g" k8s/03-fastapi-deployment.yaml
sed -i "s|your-docker-registry/celery-worker:latest|${DOCKER_USERNAME}/celery-worker:v1|g" k8s/04-celery-deployment.yaml
```

### 3. Install Metrics Server

```bash
# Required for autoscaling!
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For local clusters (minikube/Docker Desktop)
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

### 4. Deploy Everything

```bash
# One command to deploy all!
kubectl apply -f k8s/

# Wait for pods to be ready
kubectl wait --for=condition=ready pod --all -n async-tasks --timeout=300s
```

### 5. Access Services

```bash
# For Minikube
minikube service fastapi-service -n async-tasks --url
minikube service flower-service -n async-tasks --url

# For Docker Desktop / Cloud
kubectl get svc -n async-tasks
# Use EXTERNAL-IP shown in output
```

---

## ✅ Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n async-tasks

# Check HPA is working
kubectl get hpa -n async-tasks

# Check resource usage
kubectl top pods -n async-tasks
```

Expected output:
```
NAME                            READY   STATUS    RESTARTS   AGE
redis-xxx                       1/1     Running   0          2m
fastapi-xxx                     1/1     Running   0          2m
fastapi-yyy                     1/1     Running   0          2m
celery-worker-xxx               1/1     Running   0          2m
celery-worker-yyy               1/1     Running   0          2m
flower-xxx                      1/1     Running   0          2m
```

---

## 🧪 Test Autoscaling (Quick)

### Test 1: Check API Health

```bash
# Get FastAPI URL (minikube)
FASTAPI_URL=$(minikube service fastapi-service -n async-tasks --url)

# Test health endpoint
curl ${FASTAPI_URL}/health/celery
```

### Test 2: Generate Load

```bash
# Submit 100 tasks
for i in {1..100}; do
  curl -X POST ${FASTAPI_URL}/async-process/ \
    -H "Content-Type: application/json" \
    -d '{"name":"test"}' &
done

# Watch autoscaling happen!
kubectl get hpa -n async-tasks -w
```

---

## 📊 Monitor

```bash
# Open Flower dashboard
kubectl port-forward -n async-tasks svc/flower-service 5555:5555
# Browser: http://localhost:5555
# Credentials: admin / test@123

# Watch HPA in real-time
kubectl get hpa -n async-tasks -w

# View pod resource usage
watch kubectl top pods -n async-tasks
```

---

## 🧹 Clean Up

```bash
# Delete everything
kubectl delete namespace async-tasks

# For minikube
minikube stop
```

---

## 🔧 Troubleshooting

### Pods stuck in "Pending"
```bash
kubectl describe pod -n async-tasks <pod-name>
# Look for events at the bottom
```

### HPA shows "<unknown>"
```bash
# Wait 1-2 minutes for metrics to populate
# Or check metrics server
kubectl get deployment metrics-server -n kube-system
```

### Can't pull images
```bash
# Make sure you pushed images
docker images | grep fastapi-celery

# Check image name in deployment
kubectl get deployment fastapi -n async-tasks -o yaml | grep image:
```

---

## 📚 Next Steps

1. ✅ **Completed Quick Start** - Your system is running!
2. 📖 Read [KUBERNETES-GUIDE.md](../KUBERNETES-GUIDE.md) for deep dive
3. 🧪 Run [load-test.sh](load-test.sh) for advanced testing
4. 🏭 Deploy to production (AWS/GCP/Azure)

---

## 💡 Key Concepts You Just Used

- **Namespace**: Isolated environment for your app
- **Deployment**: Manages your pods (containers)
- **Service**: Load balancer for your pods
- **HPA**: Auto-scales pods based on CPU/Memory
- **ConfigMap**: Stores configuration
- **PVC**: Shared storage for files

**Congratulations!** You've deployed a production-grade autoscaling system! 🎉
