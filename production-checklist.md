# 🚀 Production Readiness Checklist

Before deploying to production, complete these steps:

---

## ✅ **Current Status (Local Kubernetes)**

### **Fixed Issues:**
- ✅ DockerfileWebApi has CMD uncommented
- ✅ Redis hostname is `redis-service` (K8s compatible)
- ✅ Static directory exists
- ✅ Image pull policy is `IfNotPresent`
- ✅ Basic autoscaling configured

---

## ⚠️ **Issues to Fix Before Production**

### **1. Update Docker Image Names**

**Current:** Hardcoded to `chemsa/*`
**Files affected:**
- `k8s/03-fastapi-deployment.yaml` (line 44)
- `k8s/04-celery-deployment.yaml` (line 45)

**Action Required:**

```bash
# Option A: Update to your Docker Hub username
export DOCKER_USER="your-dockerhub-username"
sed -i "s|chemsa/fastapi:latest|${DOCKER_USER}/fastapi-celery:v1|g" k8s/03-fastapi-deployment.yaml
sed -i "s|chemsa/celery-worker:latest|${DOCKER_USER}/celery-worker:v1|g" k8s/04-celery-deployment.yaml

# Option B: Use a private registry (AWS ECR, GCP GCR, Azure ACR)
# Example for AWS ECR:
# image: 123456789.dkr.ecr.us-east-1.amazonaws.com/fastapi-celery:v1
```

---

### **2. Use Kubernetes Secrets for Credentials**

**Current:** Hardcoded passwords in YAML files

**Files affected:**
- `.env` - `SWAGGER_PASSWORD`, `FLOWER_PASSWORD`
- `app/main.py` (lines 24-25) - `VALID_USERNAME`, `VALID_PASSWORD`
- `k8s/05-flower-deployment.yaml` (line 42) - `FLOWER_BASIC_AUTH`

**Action Required:**

```bash
# Create Kubernetes secrets
kubectl create secret generic app-credentials \
  --from-literal=swagger-username=admin \
  --from-literal=swagger-password=YOUR_SECURE_PASSWORD \
  --from-literal=flower-username=admin \
  --from-literal=flower-password=YOUR_SECURE_PASSWORD \
  -n async-tasks

# Update app/main.py to read from environment
# Update k8s deployments to inject secrets as env vars
```

**Example deployment update:**
```yaml
env:
- name: SWAGGER_USERNAME
  valueFrom:
    secretKeyRef:
      name: app-credentials
      key: swagger-username
- name: SWAGGER_PASSWORD
  valueFrom:
    secretKeyRef:
      name: app-credentials
      key: swagger-password
```

---

### **3. Fix Flower Deployment**

**Current:** Flower is crashing (CrashLoopBackOff)

**Possible causes:**
- Can't connect to Redis
- Authentication issues
- Wrong broker URL

**Action Required:**

```bash
# Check Flower logs
kubectl logs -l app=flower -n async-tasks --tail=50

# Common fix: Update broker URL format
# Edit k8s/05-flower-deployment.yaml line 37:
args:
  - --broker=redis://redis-service:6379/0  # Add /0 at the end
  - flower
  - --port=5555
  - --logging=info
```

---

### **4. Add .dockerignore**

**Issue:** Docker builds include unnecessary files

**Action Required:**

Create `.dockerignore`:
```
# Git
.git
.gitignore
.github

# Python
__pycache__
*.pyc
*.pyo
*.pyd
.Python
*.so
*.egg
*.egg-info
dist
build

# Environments
.env
.venv
venv/
ENV/

# IDEs
.vscode
.idea
*.swp
*.swo

# Documentation
*.md
!README.md

# Kubernetes
k8s/

# Logs
*.log
SERVER/

# Tests
tests/
.pytest_cache/

# Docker
Dockerfile*
docker-compose*.yml
```

---

### **5. Use Tagged Images (Not `latest`)**

**Current:** Using `:latest` tag
**Problem:** Can't track versions, can't rollback

**Action Required:**

```bash
# Use semantic versioning
docker build -f DockerfileWebApi -t your-user/fastapi-celery:1.0.0 .
docker build -f DockerfileCelery -t your-user/celery-worker:1.0.0 .

# Update deployments
sed -i 's|:latest|:1.0.0|g' k8s/03-fastapi-deployment.yaml
sed -i 's|:latest|:1.0.0|g' k8s/04-celery-deployment.yaml
```

---

### **6. Configure Resource Limits Based on Load**

**Current:** Default values (may be too low or too high)

**Action Required:**

Test your actual workload and adjust:

```yaml
# k8s/03-fastapi-deployment.yaml
resources:
  requests:
    memory: "256Mi"   # Adjust based on actual usage
    cpu: "200m"
  limits:
    memory: "1Gi"     # Adjust based on actual usage
    cpu: "1000m"
```

Monitor with:
```bash
kubectl top pods -n async-tasks
```

---

### **7. Set Up Persistent Storage for Production**

**Current:** Using `emptyDir` for Redis (data lost on restart)
**Problem:** Task results lost if pod restarts

**Action Required:**

For production, use PersistentVolumeClaim for Redis:

```yaml
# Create redis-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data-pvc
  namespace: async-tasks
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard  # Or your cloud provider's storage class
```

Update `k8s/02-redis-deployment.yaml`:
```yaml
volumes:
- name: redis-data
  persistentVolumeClaim:
    claimName: redis-data-pvc  # Instead of emptyDir
```

---

### **8. Add Health Checks to All Services**

**Current:** Only basic checks

**Action Required:**

Ensure all deployments have:
- `livenessProbe` - Restart if unhealthy
- `readinessProbe` - Don't send traffic if not ready
- `startupProbe` - Allow slow startup

---

### **9. Set Up Ingress (Not LoadBalancer)**

**Current:** Using LoadBalancer type (expensive, gets separate IPs)

**Action Required:**

Install ingress controller:
```bash
# For nginx-ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

Create ingress:
```yaml
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

---

### **10. Enable SSL/TLS**

**Action Required:**

Install cert-manager:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

Create certificate:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fastapi-tls
  namespace: async-tasks
spec:
  secretName: fastapi-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - api.yourdomain.com
```

---

### **11. Set Up Monitoring**

**Current:** Only Flower (which is crashing)

**Action Required:**

Install Prometheus + Grafana:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

---

### **12. Configure Logging**

**Current:** Logs only in pod (lost on restart)

**Action Required:**

Set up centralized logging:
- ELK Stack (Elasticsearch, Logstash, Kibana)
- Loki + Grafana
- Cloud provider logging (CloudWatch, Cloud Logging, Azure Monitor)

---

### **13. Set Up CI/CD**

**Action Required:**

Create GitHub Actions workflow:
```yaml
# .github/workflows/deploy.yml
name: Deploy to Kubernetes
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build images
        run: |
          docker build -f DockerfileWebApi -t ${{ secrets.DOCKER_USER }}/fastapi:${{ github.sha }} .
          docker build -f DockerfileCelery -t ${{ secrets.DOCKER_USER }}/celery:${{ github.sha }} .
      - name: Push images
        run: |
          docker push ${{ secrets.DOCKER_USER }}/fastapi:${{ github.sha }}
      - name: Deploy to K8s
        run: |
          kubectl set image deployment/fastapi fastapi=${{ secrets.DOCKER_USER }}/fastapi:${{ github.sha }}
```

---

### **14. Add Redis Authentication**

**Current:** Redis has no password

**Action Required:**

```bash
# Create Redis password secret
kubectl create secret generic redis-password \
  --from-literal=password=$(openssl rand -base64 32) \
  -n async-tasks

# Update Redis deployment to use password
# Update FastAPI/Celery to use password
```

---

### **15. Configure Backup Strategy**

**Action Required:**

- Schedule Redis backups
- Back up PersistentVolumes
- Document recovery procedures

---

## 🎯 **Priority Order for Production**

### **Critical (Do Before ANY Production Deployment):**
1. ✅ Use Kubernetes Secrets for passwords
2. ✅ Use tagged images (not `:latest`)
3. ✅ Fix Flower or remove it
4. ✅ Add `.dockerignore`
5. ✅ Set up Redis persistence
6. ✅ Configure SSL/TLS
7. ✅ Add Redis authentication

### **Important (Do Within First Week):**
8. ✅ Set up Ingress
9. ✅ Configure monitoring (Prometheus)
10. ✅ Set up centralized logging
11. ✅ Adjust resource limits based on load

### **Nice to Have:**
12. ✅ CI/CD pipeline
13. ✅ Automated backups
14. ✅ Advanced monitoring dashboards

---

## ✅ **Validation Script**

Run this before deploying to production:

```bash
#!/bin/bash
echo "🔍 Production Readiness Check"

# Check 1: No :latest tags
if grep -r ":latest" k8s/*.yaml; then
  echo "❌ Found :latest tags. Use versioned tags!"
  exit 1
fi

# Check 2: No hardcoded passwords
if grep -r "test@123" k8s/*.yaml app/*.py; then
  echo "❌ Found hardcoded passwords!"
  exit 1
fi

# Check 3: .dockerignore exists
if [ ! -f .dockerignore ]; then
  echo "❌ .dockerignore missing!"
  exit 1
fi

# Check 4: Secrets exist
if ! kubectl get secret app-credentials -n async-tasks &>/dev/null; then
  echo "❌ Kubernetes secrets not created!"
  exit 1
fi

echo "✅ All checks passed!"
```

---

## 📝 **Deployment Checklist**

Before `kubectl apply`:

- [ ] Images built and pushed to registry
- [ ] Image names updated in YAML files
- [ ] Secrets created
- [ ] Storage class configured
- [ ] Ingress controller installed
- [ ] SSL certificates configured
- [ ] Monitoring set up
- [ ] Logging configured
- [ ] Backup strategy documented
- [ ] Rollback plan documented

---

**Your current setup works for LOCAL TESTING.
For PRODUCTION, complete the Critical items above!** 🚀
