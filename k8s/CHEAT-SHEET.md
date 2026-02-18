# ⚡ Kubernetes Cheat Sheet - Quick Reference

## 🚀 Quick Deploy

```bash
# Deploy everything
kubectl apply -f k8s/

# Delete everything
kubectl delete namespace async-tasks
```

---

## 📊 Monitoring Commands

```bash
# View all resources
kubectl get all -n async-tasks

# View pods
kubectl get pods -n async-tasks
kubectl get pods -n async-tasks -o wide  # With node info

# View services
kubectl get svc -n async-tasks

# View HPA (autoscalers)
kubectl get hpa -n async-tasks
kubectl get hpa -n async-tasks -w  # Watch mode

# View resource usage
kubectl top pods -n async-tasks
kubectl top nodes

# View events (troubleshooting)
kubectl get events -n async-tasks --sort-by='.lastTimestamp'
```

---

## 🔍 Debugging Commands

```bash
# View pod logs
kubectl logs <pod-name> -n async-tasks
kubectl logs -f <pod-name> -n async-tasks  # Follow mode
kubectl logs --previous <pod-name> -n async-tasks  # Previous container

# Describe resources (shows events, errors)
kubectl describe pod <pod-name> -n async-tasks
kubectl describe hpa fastapi-hpa -n async-tasks
kubectl describe svc fastapi-service -n async-tasks

# Execute commands inside pod
kubectl exec -it <pod-name> -n async-tasks -- /bin/bash
kubectl exec -it <pod-name> -n async-tasks -- env  # View env vars

# Port forwarding
kubectl port-forward <pod-name> -n async-tasks 8080:80
kubectl port-forward svc/flower-service -n async-tasks 5555:5555
```

---

## 🔄 Scaling Commands

```bash
# Manual scaling (HPA will override)
kubectl scale deployment fastapi -n async-tasks --replicas=5
kubectl scale deployment celery-worker -n async-tasks --replicas=10

# Disable HPA temporarily
kubectl delete hpa fastapi-hpa -n async-tasks

# Re-enable HPA
kubectl apply -f k8s/07-hpa-fastapi.yaml
```

---

## 🔧 Update Commands

```bash
# Edit resource
kubectl edit deployment fastapi -n async-tasks
kubectl edit configmap app-config -n async-tasks

# Update image
kubectl set image deployment/fastapi fastapi=new-image:v2 -n async-tasks

# Rollout status
kubectl rollout status deployment/fastapi -n async-tasks

# Restart deployment (to pick up ConfigMap changes)
kubectl rollout restart deployment/fastapi -n async-tasks

# Rollback to previous version
kubectl rollout undo deployment/fastapi -n async-tasks

# View rollout history
kubectl rollout history deployment/fastapi -n async-tasks
```

---

## 📦 Resource Management

```bash
# View resource quotas
kubectl get resourcequota -n async-tasks
kubectl describe resourcequota async-tasks-quota -n async-tasks

# View limit ranges
kubectl get limitrange -n async-tasks
kubectl describe limitrange async-tasks-limits -n async-tasks

# View PVC (storage)
kubectl get pvc -n async-tasks
kubectl describe pvc shared-data-pvc -n async-tasks
```

---

## 🧪 Testing Commands

```bash
# Test service connectivity
kubectl run test-pod -n async-tasks --image=curlimages/curl -it --rm -- sh
# Inside pod: curl http://fastapi-service/health/celery

# Generate load (quick test)
for i in {1..100}; do
  kubectl run load-$i -n async-tasks --image=curlimages/curl --rm -- \
    curl -X POST http://fastapi-service/async-process/ \
    -H "Content-Type: application/json" \
    -d '{"name":"test"}' &
done
```

---

## 📋 Get Specific Information

```bash
# Get pod IPs
kubectl get pods -n async-tasks -o wide

# Get service external IP
kubectl get svc fastapi-service -n async-tasks -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get pod CPU/Memory requests
kubectl get pods -n async-tasks -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.requests}{"\n"}{end}'

# Get HPA metrics
kubectl get hpa -n async-tasks -o yaml

# List all pods sorted by CPU
kubectl top pods -n async-tasks --sort-by=cpu

# List all pods sorted by memory
kubectl top pods -n async-tasks --sort-by=memory
```

---

## 🔐 Secrets & ConfigMaps

```bash
# Create secret
kubectl create secret generic my-secret \
  --from-literal=password=secret123 \
  -n async-tasks

# View secret (base64 encoded)
kubectl get secret my-secret -n async-tasks -o yaml

# Decode secret
kubectl get secret my-secret -n async-tasks -o jsonpath='{.data.password}' | base64 -d

# Update ConfigMap
kubectl create configmap app-config --from-file=config.yaml -n async-tasks --dry-run=client -o yaml | kubectl apply -f -
```

---

## 🌐 Networking

```bash
# View all services
kubectl get svc -n async-tasks

# Test DNS resolution
kubectl run dns-test -n async-tasks --image=busybox -it --rm -- nslookup fastapi-service

# View endpoints (pod IPs behind service)
kubectl get endpoints -n async-tasks
kubectl get endpoints fastapi-service -n async-tasks -o yaml
```

---

## 📊 HPA Specific Commands

```bash
# View HPA details
kubectl describe hpa fastapi-hpa -n async-tasks

# Get current metrics
kubectl get hpa -n async-tasks -o yaml

# Force HPA to recalculate
kubectl annotate hpa fastapi-hpa -n async-tasks force-refresh="$(date)"

# View scaling events
kubectl get events -n async-tasks --field-selector involvedObject.kind=HorizontalPodAutoscaler
```

---

## 🧹 Cleanup Commands

```bash
# Delete specific resource
kubectl delete deployment fastapi -n async-tasks
kubectl delete service fastapi-service -n async-tasks
kubectl delete hpa fastapi-hpa -n async-tasks

# Delete all pods (will restart)
kubectl delete pods --all -n async-tasks

# Delete namespace (deletes everything)
kubectl delete namespace async-tasks

# Force delete stuck resources
kubectl delete pod <pod-name> -n async-tasks --grace-period=0 --force
```

---

## 🔄 Context & Namespaces

```bash
# View current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Switch context
kubectl config use-context <context-name>

# Set default namespace
kubectl config set-context --current --namespace=async-tasks

# View all namespaces
kubectl get namespaces
```

---

## 📈 Metrics Server

```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

# View metrics server logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# Restart metrics server
kubectl rollout restart deployment metrics-server -n kube-system

# Install metrics server (if missing)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## 🏷️ Labels & Selectors

```bash
# Get pods by label
kubectl get pods -n async-tasks -l app=fastapi
kubectl get pods -n async-tasks -l component=worker

# Add label to pod
kubectl label pod <pod-name> -n async-tasks environment=production

# Remove label
kubectl label pod <pod-name> -n async-tasks environment-

# View labels
kubectl get pods -n async-tasks --show-labels
```

---

## 📝 YAML Validation

```bash
# Dry run (validate without applying)
kubectl apply -f k8s/03-fastapi-deployment.yaml --dry-run=client

# Server-side validation
kubectl apply -f k8s/03-fastapi-deployment.yaml --dry-run=server

# Diff before applying
kubectl diff -f k8s/03-fastapi-deployment.yaml
```

---

## 🔧 Advanced Debugging

```bash
# Copy files from pod
kubectl cp <pod-name>:/path/to/file ./local-file -n async-tasks

# Copy files to pod
kubectl cp ./local-file <pod-name>:/path/to/file -n async-tasks

# View pod YAML
kubectl get pod <pod-name> -n async-tasks -o yaml

# View pod JSON
kubectl get pod <pod-name> -n async-tasks -o json

# Filter with JSONPath
kubectl get pods -n async-tasks -o jsonpath='{.items[*].metadata.name}'

# View container logs (multi-container pod)
kubectl logs <pod-name> -c <container-name> -n async-tasks
```

---

## 🎯 Common Workflows

### Deploy New Version

```bash
# 1. Build new image
docker build -f DockerfileWebApi -t username/fastapi:v2 .
docker push username/fastapi:v2

# 2. Update deployment
kubectl set image deployment/fastapi fastapi=username/fastapi:v2 -n async-tasks

# 3. Watch rollout
kubectl rollout status deployment/fastapi -n async-tasks

# 4. Verify
kubectl get pods -n async-tasks
```

### Troubleshoot Failing Pod

```bash
# 1. Check pod status
kubectl get pods -n async-tasks

# 2. Describe pod
kubectl describe pod <pod-name> -n async-tasks

# 3. View logs
kubectl logs <pod-name> -n async-tasks

# 4. Check events
kubectl get events -n async-tasks --sort-by='.lastTimestamp'

# 5. Exec into pod (if running)
kubectl exec -it <pod-name> -n async-tasks -- /bin/bash
```

### Scale for Traffic Spike

```bash
# 1. Manually scale up
kubectl scale deployment fastapi -n async-tasks --replicas=10
kubectl scale deployment celery-worker -n async-tasks --replicas=20

# 2. Monitor
kubectl get pods -n async-tasks -w

# 3. Check resource usage
kubectl top pods -n async-tasks

# 4. Let HPA take over (remove manual scaling)
kubectl delete hpa -n async-tasks
kubectl apply -f k8s/07-hpa-fastapi.yaml
kubectl apply -f k8s/08-hpa-celery.yaml
```

---

## 🔗 Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kaf='kubectl apply -f'
alias kdel='kubectl delete'
alias kn='kubectl config set-context --current --namespace'

# Async-tasks specific
alias kgpa='kubectl get pods -n async-tasks'
alias kgha='kubectl get hpa -n async-tasks'
alias ktpa='kubectl top pods -n async-tasks'
alias kla='kubectl logs -f -n async-tasks'
```

---

## 📚 Quick Reference URLs

- **kubectl Cheat Sheet**: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- **Resource Limits**: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- **HPA Docs**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- **Debugging Pods**: https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/

---

**Print this sheet and keep it handy!** 📄
