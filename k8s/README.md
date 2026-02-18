# Kubernetes Manifests - File Overview

This directory contains all Kubernetes configuration files for deploying the FastAPI + Celery system with **autoscaling**.

## 📁 Files Explained

### Core Resources

| File | Purpose | Key Concepts |
|------|---------|--------------|
| `00-namespace.yaml` | Creates isolated environment | **Namespace** - logical grouping |
| `01-configmap.yaml` | Stores configuration (env vars) | **ConfigMap** - non-sensitive config |
| `06-persistent-volume.yaml` | Shared storage for files | **PVC** - persistent storage |

### Application Deployments

| File | Purpose | Autoscaling |
|------|---------|-------------|
| `02-redis-deployment.yaml` | Redis broker + backend | ❌ No (single instance) |
| `03-fastapi-deployment.yaml` | REST API pods + LoadBalancer | ✅ Yes (2-10 pods) |
| `04-celery-deployment.yaml` | Worker pods | ✅ Yes (2-20 pods) |
| `05-flower-deployment.yaml` | Monitoring dashboard | ❌ No (single instance) |

### Autoscaling Configuration

| File | Purpose | Metrics |
|------|---------|---------|
| `07-hpa-fastapi.yaml` | FastAPI autoscaler | CPU: 70%, Memory: 80% |
| `08-hpa-celery.yaml` | Worker autoscaler | CPU: 60%, Memory: 75% |
| `09-resource-quota.yaml` | Limits & quotas | Namespace budget |

### Scripts

| File | Purpose |
|------|---------|
| `deploy.sh` | Automated deployment script |
| `load-test.sh` | Generate load to test autoscaling |

---

## 🎯 Deployment Order

The files are numbered in deployment order:

1. **Namespace** (00) - Create isolated environment
2. **ConfigMap** (01) - Load configuration
3. **PVC** (06) - Provision storage
4. **Redis** (02) - Deploy message broker
5. **FastAPI** (03) - Deploy API
6. **Celery** (04) - Deploy workers
7. **Flower** (05) - Deploy monitoring
8. **HPA** (07-08) - Enable autoscaling
9. **Quotas** (09) - Apply resource limits

---

## 🚀 Quick Commands

### Deploy All
```bash
kubectl apply -f k8s/
```

### Deploy Specific Component
```bash
kubectl apply -f k8s/03-fastapi-deployment.yaml
```

### View Resources
```bash
# All resources in namespace
kubectl get all -n async-tasks

# Just pods
kubectl get pods -n async-tasks

# Just HPAs
kubectl get hpa -n async-tasks

# Resource usage
kubectl top pods -n async-tasks
```

### Update Configuration
```bash
# Edit ConfigMap
kubectl edit configmap app-config -n async-tasks

# Restart pods to pick up changes
kubectl rollout restart deployment/fastapi -n async-tasks
kubectl rollout restart deployment/celery-worker -n async-tasks
```

### Scale Manually
```bash
# Override HPA temporarily
kubectl scale deployment fastapi -n async-tasks --replicas=5

# HPA will take over after a few minutes
```

### Delete Everything
```bash
# Delete entire namespace (all resources)
kubectl delete namespace async-tasks

# Delete specific resource
kubectl delete deployment fastapi -n async-tasks
```

---

## 📊 Resource Allocation Summary

### FastAPI Pods
- **Min replicas**: 2
- **Max replicas**: 10
- **Per pod**: 200m CPU, 256Mi memory (request)
- **Per pod limit**: 1 CPU, 1Gi memory

### Celery Worker Pods
- **Min replicas**: 2
- **Max replicas**: 20
- **Per pod**: 300m CPU, 512Mi memory (request)
- **Per pod limit**: 2 CPU, 2Gi memory

### Redis Pod
- **Replicas**: 1
- **Per pod**: 100m CPU, 128Mi memory (request)
- **Per pod limit**: 500m CPU, 512Mi memory

### Total Cluster Resources
- **Max pods**: 50
- **Max CPU**: 20 cores (requests), 40 cores (limits)
- **Max memory**: 50Gi (requests), 100Gi (limits)

---

## 🔧 Customization Guide

### Change Autoscaling Thresholds

Edit `07-hpa-fastapi.yaml`:
```yaml
spec:
  minReplicas: 2      # Change minimum pods
  maxReplicas: 10     # Change maximum pods
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 70  # Change CPU threshold (%)
```

### Change Resource Limits

Edit `03-fastapi-deployment.yaml`:
```yaml
resources:
  requests:
    cpu: "200m"      # Minimum CPU
    memory: "256Mi"  # Minimum memory
  limits:
    cpu: "1000m"     # Maximum CPU
    memory: "1Gi"    # Maximum memory
```

### Add Environment Variables

Edit `01-configmap.yaml`:
```yaml
data:
  REDIS_SERVER: "redis://redis-service:6379"
  NEW_VAR: "new_value"  # Add your variable
```

---

## 🎓 Learning Path

1. **Beginner**: Read [QUICK-START.md](QUICK-START.md) - Get it running in 5 minutes
2. **Intermediate**: Read [KUBERNETES-GUIDE.md](../KUBERNETES-GUIDE.md) - Understand concepts
3. **Advanced**: Study individual YAML files - Deep dive into each resource
4. **Expert**: Customize for production - Add Ingress, Secrets, Prometheus

---

## 📚 Additional Resources

- **Official Kubernetes Docs**: https://kubernetes.io/docs/
- **HPA Walkthrough**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- **Best Practices**: https://kubernetes.io/docs/concepts/configuration/overview/
- **kubectl Cheat Sheet**: https://kubernetes.io/docs/reference/kubectl/cheatsheet/

---

## 🆘 Need Help?

- Check [KUBERNETES-GUIDE.md](../KUBERNETES-GUIDE.md) troubleshooting section
- View pod logs: `kubectl logs -n async-tasks <pod-name>`
- Describe resources: `kubectl describe <resource> -n async-tasks`
- Check events: `kubectl get events -n async-tasks --sort-by='.lastTimestamp'`
