# System Architecture - Complete Visual Guide

This document explains the complete architecture from Docker Compose to Kubernetes with autoscaling.

---

## 🏗️ Architecture Evolution

### Level 1: Docker Compose (Development)

```
┌─────────────────────────────────────────────────────────────┐
│  Docker Compose - Single Host                               │
│                                                              │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │ FastAPI  │   │  Worker  │   │  Redis   │   │ Flower  │ │
│  │Container │   │Container │   │Container │   │Container│ │
│  │          │   │          │   │          │   │         │ │
│  │  Port    │   │  (x2)    │   │  Port    │   │  Port   │ │
│  │   :80    │   │          │   │  :6379   │   │  :5555  │ │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬────┘ │
│       │              │              │              │       │
│       └──────────────┴──────────────┴──────────────┘       │
│                      │                                      │
│              ┌───────▼────────┐                            │
│              │  Docker Bridge │                            │
│              │    Network     │                            │
│              └────────────────┘                            │
└─────────────────────────────────────────────────────────────┘

LIMITATIONS:
❌ No autoscaling (manual scaling only)
❌ Single point of failure (one host)
❌ No automatic recovery
❌ Limited resource management
✅ Good for: Development, small deployments
```

---

### Level 2: Kubernetes (Production)

```
┌───────────────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster - Multi-Node, Auto-scaling                            │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Control Plane (Master)                                              │ │
│  │  - API Server                                                         │ │
│  │  - Scheduler (decides where pods run)                                │ │
│  │  - Controller Manager (maintains desired state)                      │ │
│  │  - etcd (stores cluster state)                                       │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                    │                                       │
│                     ┌──────────────┴──────────────┐                       │
│                     │                              │                       │
│  ┌──────────────────▼────────────┐  ┌─────────────▼──────────────┐       │
│  │  Worker Node 1                │  │  Worker Node 2             │       │
│  │                                │  │                            │       │
│  │  ┌──────────┐  ┌──────────┐  │  │  ┌──────────┐ ┌──────────┐│       │
│  │  │FastAPI   │  │Worker    │  │  │  │FastAPI   │ │Worker    ││       │
│  │  │Pod 1     │  │Pod 1     │  │  │  │Pod 2     │ │Pod 2     ││       │
│  │  └──────────┘  └──────────┘  │  │  └──────────┘ └──────────┘│       │
│  │                                │  │                            │       │
│  │  ┌──────────┐                 │  │  ┌──────────┐             │       │
│  │  │Redis     │                 │  │  │Flower    │             │       │
│  │  │Pod       │                 │  │  │Pod       │             │       │
│  │  └──────────┘                 │  │  └──────────┘             │       │
│  └────────────────────────────────┘  └─────────────────────────────┘     │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Kubernetes Services (Load Balancers)                                │ │
│  │  - fastapi-service  → Routes to all FastAPI pods                    │ │
│  │  - redis-service    → Routes to Redis pod                           │ │
│  │  - flower-service   → Routes to Flower pod                          │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Horizontal Pod Autoscaler (HPA)                                     │ │
│  │  - Monitors metrics every 15 seconds                                 │ │
│  │  - FastAPI: Scale 2-10 pods (CPU>70%, Mem>80%)                      │ │
│  │  - Workers: Scale 2-20 pods (CPU>60%, Mem>75%)                      │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘

BENEFITS:
✅ Automatic scaling based on load
✅ Self-healing (auto-restart failed pods)
✅ Load balancing across pods
✅ Rolling updates (zero downtime)
✅ Resource limits and quotas
✅ Multi-node deployment (high availability)
```

---

## 📊 Data Flow - Request Lifecycle

### Scenario 1: API Request (Sync)

```
1. Client Request
   │
   ▼
┌─────────────────────┐
│  Internet / LB      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Kubernetes Service  │ ◄─── ClusterIP/LoadBalancer
│ (fastapi-service)   │      Stable IP: 10.0.0.10
└──────────┬──────────┘
           │
           │  Load balances across pods
           │
     ┌─────┴─────┬─────────┬─────────┐
     ▼           ▼         ▼         ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│FastAPI  │ │FastAPI  │ │FastAPI  │ │FastAPI  │
│Pod 1    │ │Pod 2    │ │Pod 3    │ │Pod 4    │
└─────────┘ └─────────┘ └─────────┘ └─────────┘

Each pod can handle requests independently!
```

### Scenario 2: Async Task Submission

```
1. Client submits task
   │
   ▼
2. FastAPI receives POST /async-process/
   │
   ▼
3. FastAPI sends task to Celery
   │
   ▼
┌─────────────────────┐
│  Redis Service      │ ◄─── Message Queue
│  (redis-service)    │
└──────────┬──────────┘
           │
           │  Workers pull tasks
           │
     ┌─────┴─────┬─────────┬─────────┐
     ▼           ▼         ▼         ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│Worker   │ │Worker   │ │Worker   │ │Worker   │
│Pod 1    │ │Pod 2    │ │Pod 3    │ │Pod 4    │
│         │ │         │ │         │ │         │
│BUSY ⚙️ │ │IDLE 😴  │ │BUSY ⚙️ │ │IDLE 😴  │
└─────────┘ └─────────┘ └─────────┘ └─────────┘
     │           │         │           │
     └───────────┴─────────┴───────────┘
                 │
                 ▼
         Updates task status
         back to Redis
```

---

## 🔄 Autoscaling in Action

### Timeline: Traffic Spike Example

```
Time: 00:00 - Normal Load
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 2 pods (40% CPU each)                          │
│ Workers: 2 pods (30% CPU each)                          │
│                                                          │
│ Status: ✅ Healthy, all green                           │
└─────────────────────────────────────────────────────────┘

Time: 00:05 - Traffic Increases (2x)
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 2 pods (85% CPU each) ⚠️ HIGH!                │
│ Workers: 2 pods (45% CPU each) ✅ OK                    │
│                                                          │
│ HPA Decision: FastAPI CPU > 70% target                  │
│ Action: Scale FastAPI 2 → 4 pods                        │
└─────────────────────────────────────────────────────────┘

Time: 00:06 - Scaling Up
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 4 pods (creating...)                           │
│   - Pod 1: 85% CPU                                      │
│   - Pod 2: 85% CPU                                      │
│   - Pod 3: Starting... 🚀                               │
│   - Pod 4: Starting... 🚀                               │
└─────────────────────────────────────────────────────────┘

Time: 00:07 - Stabilized
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 4 pods (45% CPU each) ✅ BALANCED              │
│ Workers: 2 pods (45% CPU each) ✅ OK                    │
│                                                          │
│ Load distributed across more pods!                      │
└─────────────────────────────────────────────────────────┘

Time: 00:10 - Task Queue Grows
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 4 pods (45% CPU) ✅                            │
│ Workers: 2 pods (80% CPU each) ⚠️ HIGH!                │
│                                                          │
│ HPA Decision: Worker CPU > 60% target                   │
│ Action: Scale Workers 2 → 4 pods                        │
└─────────────────────────────────────────────────────────┘

Time: 00:11 - Both Scaled Up
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 4 pods (45% CPU) ✅                            │
│ Workers: 4 pods (40% CPU each) ✅ BALANCED              │
│                                                          │
│ System can handle high load!                            │
└─────────────────────────────────────────────────────────┘

Time: 00:20 - Traffic Decreases
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 4 pods (25% CPU) 📉 LOW                        │
│ Workers: 4 pods (20% CPU) 📉 LOW                        │
│                                                          │
│ HPA Decision: Wait 5 minutes (stabilization window)     │
│ Action: None yet (avoiding flapping)                    │
└─────────────────────────────────────────────────────────┘

Time: 00:25 - Still Low, Scale Down
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 4 pods → 3 pods (conservative scale-down)      │
│ Workers: 4 pods → 3 pods                                │
│                                                          │
│ Gradually reducing to save resources                    │
└─────────────────────────────────────────────────────────┘

Time: 00:35 - Back to Normal
┌─────────────────────────────────────────────────────────┐
│ FastAPI: 2 pods (40% CPU) ✅                            │
│ Workers: 2 pods (30% CPU) ✅                            │
│                                                          │
│ System back to baseline, cost optimized!                │
└─────────────────────────────────────────────────────────┘
```

---

## 🧮 Resource Calculation Example

### Scenario: 100 Concurrent Users

**Without Autoscaling (Static):**
```
- 5 FastAPI pods (always running)
- 10 Worker pods (always running)
- Total cost: High (wasted during low traffic)
```

**With Autoscaling:**
```
Low Traffic (2am):
- 2 FastAPI pods (minimum)
- 2 Worker pods (minimum)
- Cost: $10/hour

High Traffic (2pm):
- 8 FastAPI pods (scaled up)
- 15 Worker pods (scaled up)
- Cost: $50/hour

Average Daily Cost:
- Without autoscaling: $600/day (constant $25/hour)
- With autoscaling: $300/day (variable, optimized)
- SAVINGS: 50%! 💰
```

---

## 🎯 Key Kubernetes Concepts Visualized

### 1. Pod vs Deployment

```
POD (Single Instance)
┌─────────────────┐
│   FastAPI Pod   │
│                 │
│ If it crashes:  │
│ ❌ Gone forever│
└─────────────────┘

DEPLOYMENT (Managed Group)
┌─────────────────────────────────────┐
│  Deployment: fastapi                │
│  Desired State: 3 replicas          │
│                                      │
│  ┌────────┐ ┌────────┐ ┌────────┐  │
│  │Pod 1   │ │Pod 2   │ │Pod 3   │  │
│  └────────┘ └────────┘ └────────┘  │
│                                      │
│  If Pod 2 crashes:                  │
│  ✅ Deployment auto-creates Pod 4! │
└─────────────────────────────────────┘
```

### 2. Service (Load Balancer)

```
WITHOUT SERVICE:
Client → Pod IP: 10.0.1.5:80
         (Changes if pod restarts!) ❌

WITH SERVICE:
Client → Service: fastapi-service.svc.cluster.local
         (Stable DNS name) ✅
         │
         ├─► Pod 1: 10.0.1.5:80
         ├─► Pod 2: 10.0.1.6:80
         └─► Pod 3: 10.0.1.7:80

Service automatically load balances!
```

### 3. ConfigMap vs Secret

```
CONFIGMAP (Non-sensitive)
┌─────────────────────────────┐
│ REDIS_SERVER: redis:6379    │ ← Visible to everyone
│ LOG_LEVEL: INFO             │
│ TIMEOUT: 30                 │
└─────────────────────────────┘

SECRET (Sensitive)
┌─────────────────────────────┐
│ DB_PASSWORD: ********       │ ← Base64 encoded
│ API_KEY: ********           │ ← Encrypted at rest
└─────────────────────────────┘
```

### 4. PersistentVolumeClaim (Storage)

```
WITHOUT PVC:
┌────────────┐     ┌────────────┐
│ FastAPI    │     │ Worker     │
│ Pod        │     │ Pod        │
│            │     │            │
│ /tmp/file1 │ ❌  │ Can't see! │
└────────────┘     └────────────┘
Isolated filesystems!

WITH PVC:
┌────────────┐     ┌────────────┐
│ FastAPI    │     │ Worker     │
│ Pod        │     │ Pod        │
│     ↓      │     │     ↓      │
│ /app/data  │ ✅  │ /app/data  │
└─────┬──────┘     └─────┬──────┘
      │                  │
      └────────┬─────────┘
               ▼
      ┌────────────────┐
      │   Shared PVC   │
      │   10Gi storage │
      └────────────────┘
Both pods see same files!
```

---

## 🔍 Monitoring & Observability

```
┌───────────────────────────────────────────────────────────┐
│  Kubernetes Metrics Pipeline                              │
│                                                            │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐             │
│  │  Pods    │   │  Pods    │   │  Pods    │             │
│  │          │   │          │   │          │             │
│  │ CPU: 70% │   │ CPU: 65% │   │ CPU: 80% │             │
│  │ Mem: 45% │   │ Mem: 50% │   │ Mem: 60% │             │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘             │
│       │              │              │                     │
│       └──────────────┴──────────────┘                     │
│                      ▼                                     │
│           ┌──────────────────┐                            │
│           │ Metrics Server   │                            │
│           │ (collects data)  │                            │
│           └────────┬─────────┘                            │
│                    │                                       │
│        ┌───────────┴───────────┐                          │
│        │                       │                          │
│        ▼                       ▼                          │
│  ┌──────────┐          ┌──────────────┐                  │
│  │   HPA    │          │   kubectl    │                  │
│  │(scales)  │          │  top pods    │                  │
│  └──────────┘          └──────────────┘                  │
│                                                            │
│  Optional: Add Prometheus + Grafana for advanced metrics  │
└───────────────────────────────────────────────────────────┘
```

---

## 🎓 Learning Path Recommendation

1. **Week 1**: Understand Docker Compose setup
   - Run `docker-compose up`
   - Test all endpoints
   - Understand task lifecycle

2. **Week 2**: Learn Kubernetes basics
   - Deploy to local cluster (minikube)
   - Understand pods, deployments, services
   - Read KUBERNETES-GUIDE.md

3. **Week 3**: Master autoscaling
   - Configure HPA
   - Run load tests
   - Monitor scaling behavior

4. **Week 4**: Production deployment
   - Deploy to cloud (AWS/GCP/Azure)
   - Set up monitoring (Prometheus)
   - Implement CI/CD

---

## 📚 Further Reading

- **Kubernetes Official Docs**: https://kubernetes.io/docs/
- **HPA Walkthrough**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- **Production Best Practices**: https://kubernetes.io/docs/setup/best-practices/
- **Celery on Kubernetes**: https://docs.celeryproject.org/en/stable/userguide/deploying.html

**You now have a complete understanding of the system!** 🚀
