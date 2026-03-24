# K8s Autoscaling Deployment — Progress & Plan

## What We Are Building

A production-grade Kubernetes setup for the FastAPI + Celery + Redis app that:
- **Never goes down** under heavy load
- **Scales pods automatically** (HPA) when CPU/Memory spikes
- **Adds new EC2 nodes automatically** (Cluster Autoscaler) when pods can't fit
- **Removes idle EC2 nodes** when load drops — so you only pay when needed
- **Zero downtime deploys** — rolling updates with readiness probes

---

## Why This Architecture

Previously the app ran on a single EC2 with docker-compose. Problems:
- One intense task → node OOM → everything crashes
- Code push → downtime while containers restart
- No way to handle traffic spikes

Solution: k3s (lightweight Kubernetes) with:
- **HPA** — watches pod CPU/Memory, adds more pod replicas automatically
- **Cluster Autoscaler** — watches for Pending pods, adds/removes EC2 nodes via AWS ASG
- **Rolling deploys** — Kubernetes replaces pods one by one, readiness probe gates traffic

---

## Architecture

```
Your App (FastAPI + Celery + Redis + Flower)
        ↓
  k3s Kubernetes Cluster
        ↓
  ┌─────────────────────────────────┐
  │  Master Node (always on)        │
  │  t3.medium — fixed EC2          │
  │  Runs: control plane +          │
  │         Cluster Autoscaler      │
  └─────────────────────────────────┘
        ↓ (when pods need more room)
  ┌─────────────────────────────────┐
  │  Worker Nodes (auto scale)      │
  │  t3.small — AWS ASG             │
  │  Min: 0  →  Max: 5              │
  │  Launched/terminated by         │
  │  Cluster Autoscaler             │
  └─────────────────────────────────┘
```

### How Intelligent Scaling Works
```
High load hits Celery workers
        ↓
HPA detects CPU > 60% threshold
        ↓
HPA adds more Celery pod replicas
        ↓
No room on existing nodes → pods stuck Pending
        ↓
Cluster Autoscaler sees Pending pods
        ↓
Cluster Autoscaler tells AWS ASG → launch new EC2
        ↓
New node joins k3s cluster automatically (via user-data script)
        ↓
Pending pods schedule on new node
        ↓
Load drops → HPA removes pods
        ↓
Node becomes empty
        ↓
Cluster Autoscaler terminates the EC2
        ↓
You stop paying for it
```

---

## AWS Infrastructure

| Resource | Value |
|----------|-------|
| Region | `us-east-2` (Ohio) |
| Master EC2 ID | `i-0cb23943c8af6a171` (t3.medium) |
| Master Private IP | `172.31.12.157` |
| Master AZ | `us-east-2a` |
| Security Group | `sg-0bc12dc5ece16f3d9` (launch-wizard-46) |
| ASG Name | `k3s-workers` |
| Launch Template | `k3s-worker-template` (lt-0f780786e59320dd2) |
| IAM Role | `k3s-cluster-autoscaler-role` |
| IAM Policy | `k3s-cluster-autoscaler-policy` |
| Docker Hub | `chemsa/fastapi-celery:v1`, `chemsa/celery-worker:v1` |

### Security Group Rules (sg-0bc12dc5ece16f3d9)
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | My IP (39.58.170.172/32) | SSH access |
| 6443 | TCP | 0.0.0.0/0 | k3s API server (worker joins here) |
| 10250 | TCP | 0.0.0.0/0 | kubelet communication |
| 8472 | UDP | 0.0.0.0/0 | Flannel VXLAN pod networking |
| All traffic | All | sg-0bc12dc5ece16f3d9 | Node-to-node communication |

---

## Everything We Did This Session (Step by Step)

### 1. Decided on Architecture
- Evaluated EKS vs k3s
- Chose k3s for vendor independence (VPE requirement — not locked to AWS)
- Chose fixed master + ASG workers for cost efficiency (pay only under load)

### 2. Cleaned Up Old Broken Cluster
Old cluster had 60+ evicted/crashed pods from previous OOM testing.
```bash
kubectl delete namespace async-tasks
```

### 3. Reinstalled k3s Clean on Master
```bash
/usr/local/bin/k3s-uninstall.sh

# First install (without provider ID — mistake)
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik --disable servicelb --node-name k3s-server

# Had to reinstall again with correct AWS provider ID
/usr/local/bin/k3s-uninstall.sh

curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik --disable servicelb \
  --node-name k3s-server \
  --kubelet-arg="provider-id=aws:///us-east-2a/i-0cb23943c8af6a171"
```

Why provider ID matters: Cluster Autoscaler expects nodes to have AWS provider ID format `aws:///zone/instance-id`. Without it, it throws `wrong id: expected format aws:///<zone>/<name>` errors.

### 4. Configured kubectl Without sudo
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

### 5. Got Instance Metadata (needed for provider ID)
IMDSv2 required on this EC2 — plain curl doesn't work, need token:
```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
# Result: i-0cb23943c8af6a171, us-east-2a
```

### 6. Created AWS Launch Template
- Name: `k3s-worker-template`
- AMI: Ubuntu 22.04, t3.small, same security group
- User data script auto-installs k3s agent and joins the cluster on boot:
```bash
#!/bin/bash
curl -sfL https://get.k3s.io | K3S_URL=https://172.31.12.157:6443 \
  K3S_TOKEN=<TOKEN> \
  sh -s - agent --node-name $(hostname)
```

### 7. Created AWS Auto Scaling Group
- Name: `k3s-workers`
- Launch template: `k3s-worker-template`
- Min: 0, Desired: 0, Max: 5
- All availability zones selected
- No load balancer

### 8. Created IAM Policy and Role for Cluster Autoscaler
Policy `k3s-cluster-autoscaler-policy` allows:
- `autoscaling:DescribeAutoScalingGroups`
- `autoscaling:DescribeAutoScalingInstances`
- `autoscaling:SetDesiredCapacity`
- `autoscaling:TerminateInstanceInAutoScalingGroup`
- `ec2:DescribeLaunchTemplateVersions`
- `ec2:DescribeInstanceTypes`
- `ec2:DescribeInstances`

Role `k3s-cluster-autoscaler-role` attached to master EC2 instance.

### 9. Added ASG Discovery Tags
On the `k3s-workers` ASG:
- `k8s.io/cluster-autoscaler/enabled` = `true`
- `k8s.io/cluster-autoscaler/k3s-cluster` = `owned`

### 10. Deployed Cluster Autoscaler
```bash
kubectl apply -f ~/cluster-autoscaler.yaml
```
File at `~/cluster-autoscaler.yaml` on master. Contains:
- Deployment, ServiceAccount, ClusterRole, ClusterRoleBinding
- Also a Role + RoleBinding for configmaps in kube-system

Fixed issues along the way:
- Missing `namespaces` RBAC permission → added to ClusterRole
- Missing `configmaps` permission → added separate Role in kube-system
- Wrong region `us-east-1` → fixed to `us-east-2`
- Master node providerID mismatch → fixed by reinstalling k3s with correct provider ID
- Added annotation to disable scale-down on master node

### 11. Confirmed Cluster Autoscaler Working
Log confirmed:
```
Setting asg k3s-workers size to 1
```
ASG activity history showed `Launching a new EC2 instance: i-038eac3159de7fe8b` — successful.

### 12. Fixed Security Group
Original security group was missing k3s ports. Added:
- 6443 (k3s API)
- 10250 (kubelet)
- 8472 UDP (Flannel)
- All traffic from same SG (node-to-node)

### 13. Worker Node Launched but Token Mismatch
Worker `i-003b2c1f2507bfaf2` launched, k3s agent installed, but:
```
Failed to validate connection to cluster: token CA mismatch
```
Root cause: k3s was reinstalled on master in step 3, which generated a new token. Launch template still has old token.

---

## Current State

- Master: Running, k3s Ready, Cluster Autoscaler Running
- Worker: Running, k3s agent installed but NOT joined (wrong token)
- App: NOT deployed yet

---

## Current Blocker ❌

Worker node has wrong token. Launch template also has wrong token.

---

## Next Session — Complete Step by Step

### Step 1: SSH into master, get current token
```bash
ssh -i your-key.pem ubuntu@<MASTER_PUBLIC_IP>
sudo cat /var/lib/rancher/k3s/server/node-token
# Save this token — you'll need it in next steps
```

### Step 2: SSH into worker, fix the token
Get worker public IP from: AWS Console → EC2 → Instances → find `i-003b2c1f2507bfaf2`
```bash
# From your LOCAL machine
ssh -i your-key.pem ubuntu@<WORKER_PUBLIC_IP>

sudo systemctl stop k3s-agent
sudo sed -i 's/K3S_TOKEN=.*/K3S_TOKEN=<NEW_TOKEN_HERE>/' \
  /etc/systemd/system/k3s-agent.service.env
sudo systemctl daemon-reload
sudo systemctl start k3s-agent
sudo systemctl status k3s-agent
# Should show: active (running) with no token errors
```

### Step 3: Update Launch Template with new token
Future ASG-launched nodes need the correct token too:
- AWS Console → EC2 → Launch Templates → `k3s-worker-template`
- Actions → **Modify template (Create new version)**
- Scroll to Advanced → User data → update token value
- New user data:
```bash
#!/bin/bash
curl -sfL https://get.k3s.io | K3S_URL=https://172.31.12.157:6443 \
  K3S_TOKEN=<NEW_TOKEN_HERE> \
  sh -s - agent --node-name $(hostname)
```
- Save → go to ASG `k3s-workers` → Edit → update Launch Template version to **Latest**

### Step 4: Verify cluster has 2 nodes
```bash
# On master
kubectl get nodes
# Expected output:
# NAME              STATUS   ROLES           AGE
# k3s-server        Ready    control-plane   Xh
# ip-172-31-7-90    Ready    <none>          Xm
```

### Step 5: Install Metrics Server (required for HPA to read CPU/Memory)
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# k3s needs this patch (no TLS cert on kubelet by default)
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait 60 seconds then verify
kubectl top nodes
# Should show CPU and Memory usage for both nodes
```

### Step 6: Upload k8s manifests to master
```bash
# From your LOCAL machine in project root
scp -i your-key.pem -r k8s/ ubuntu@<MASTER_PUBLIC_IP>:~/k8s/
```

### Step 7: Deploy the application
```bash
# On master
kubectl apply -f ~/k8s/
kubectl get pods -n async-tasks -w
# Wait for all pods to show Running
```

### Step 8: Verify everything is up
```bash
kubectl get pods -n async-tasks
kubectl get hpa -n async-tasks
kubectl get nodes

# Test FastAPI health
curl http://localhost:30080/health/celery
# Expected: {"status":"ok","celery":"running",...}
```

### Step 9: Test HPA scaling
```bash
# Terminal 1 — watch pods
kubectl get hpa -n async-tasks -w

# Terminal 2 — watch nodes
kubectl get nodes -w

# From local machine — hit the API repeatedly with large image
# POST http://<MASTER_PUBLIC_IP>:30080/async-file
# Use sizetwo.png (28MB) or any large image
# Send 10-20 requests rapidly
```

### Step 10: Verify Cluster Autoscaler adds a node
When HPA scales pods and worker node runs out of RAM:
- New pods go Pending
- Cluster Autoscaler detects Pending pods
- ASG launches new t3.small
- New node joins cluster
- Pods schedule on new node

Watch it happen:
```bash
kubectl get nodes -w
# You should see a new node appear within 2-3 minutes
```

### Step 11: Verify scale down
Stop sending load. After ~2 minutes:
- HPA scales Celery pods back down
- Worker node becomes empty
- After 2 more minutes, Cluster Autoscaler terminates the extra node
- ASG desired capacity goes back to 1 (or 0 if master handles everything)

---

## Expected End Result

| Scenario | What Happens |
|----------|-------------|
| Normal traffic | 2 Celery pods, 2 FastAPI pods, 1 worker node |
| High load | HPA scales Celery to 10-20 pods, ASG adds nodes |
| Load drops | HPA scales pods down, Cluster Autoscaler terminates idle nodes |
| Code push | Rolling deploy — old pods alive until new ones pass health check |
| Node crash | Pods reschedule to surviving node automatically |
| Node OOM | Cluster Autoscaler adds new node — system stays up |

---

## Cost

| State | Cost/hr |
|-------|---------|
| Idle (master only) | ~$0.017/hr |
| 1 worker active | ~$0.040/hr |
| 3 workers active | ~$0.086/hr |
| Master stopped (not testing) | ~$0 (only EBS ~$3/month) |

---

## App Access (after Step 7)

| Service | URL | Auth |
|---------|-----|------|
| FastAPI | `http://<MASTER_PUBLIC_IP>:30080` | — |
| FastAPI Docs | `http://<MASTER_PUBLIC_IP>:30080/docs` | admin / test@123 |
| Flower Dashboard | `http://<MASTER_PUBLIC_IP>:30555` | admin / test@123 |

---

## Key Files on Master EC2

| File | Purpose |
|------|---------|
| `~/cluster-autoscaler.yaml` | Cluster Autoscaler K8s manifest |
| `~/.kube/config` | kubectl config |
| `/var/lib/rancher/k3s/server/node-token` | Token for worker nodes to join |
| `~/k8s/` | App K8s manifests (need to upload via scp) |

---

## Troubleshooting Reference

| Issue | Fix |
|-------|-----|
| Worker token mismatch | Get new token from master, update `/etc/systemd/system/k3s-agent.service.env` on worker |
| HPA shows `<unknown>` metrics | Metrics server not installed or not patched with `--kubelet-insecure-tls` |
| Pods stuck Pending | Check `kubectl describe pod <name> -n async-tasks` — usually resource limits or PVC issue |
| Cluster Autoscaler not scaling | Check logs: `kubectl logs -n kube-system deployment/cluster-autoscaler` |
| Flower CrashLoopBackOff | Use `mher/flower:2.0.1` not latest. Set broker via env vars not CLI args |
| FastAPI pods restarting | Liveness probe fires too early — needs `initialDelaySeconds: 60` minimum |
