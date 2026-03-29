#!/bin/bash
# scripts/bootstrap-k8s.sh
#
# PURPOSE: One-time setup of k3s + Metrics Server on a fresh Ubuntu EC2 instance.
# IDEMPOTENT: Safe to run multiple times. Each step checks before acting.
# USAGE: Called by GitHub Actions bootstrap workflow, or run manually via SSH.

# ─────────────────────────────────────────────
# STRICT MODE
# -e = exit immediately if any command fails
# -u = treat unset variables as errors
# -o pipefail = a pipeline fails if ANY command in it fails (not just the last)
# ─────────────────────────────────────────────
set -euo pipefail

# ─────────────────────────────────────────────
# COLOUR HELPERS (makes output easier to read in logs)
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }

# ─────────────────────────────────────────────
# CONFIGURATION — edit these if needed
# ─────────────────────────────────────────────
K3S_VERSION="v1.29.3+k3s1"           # Pin to a specific version for reproducibility
METRICS_SERVER_VERSION="v0.7.1"      # Pin metrics-server version
APP_NAMESPACE="myapp"                # The Kubernetes namespace for your application

# ─────────────────────────────────────────────
# STEP 1: System update
# ─────────────────────────────────────────────
log_info "Step 1/7: Updating system packages..."

sudo apt-get update -q
# -y = yes to all prompts
# DEBIAN_FRONTEND=noninteractive = don't show interactive prompts (important in CI)
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q

# Install tools we'll need later
sudo apt-get install -y -q curl wget jq

log_success "System packages updated."

# ─────────────────────────────────────────────
# STEP 2: Install k3s (if not already installed)
# ─────────────────────────────────────────────
log_info "Step 2/7: Checking k3s installation..."

if command -v k3s &> /dev/null; then
    # k3s binary exists — check if the service is actually running
    if sudo systemctl is-active --quiet k3s; then
        log_warn "k3s is already installed and running. Skipping installation."
        log_warn "Installed version: $(k3s --version | head -1)"
    else
        log_warn "k3s is installed but not running. Attempting to start..."
        sudo systemctl start k3s
        log_success "k3s service started."
    fi
else
    log_info "Installing k3s ${K3S_VERSION}..."

    # INSTALL_K3S_VERSION pins the version so your environment is reproducible
    # --write-kubeconfig-mode 644 makes the kubeconfig readable by non-root users
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="${K3S_VERSION}" \
        K3S_KUBECONFIG_MODE="644" \
        sh -s - \
        --write-kubeconfig-mode 644

    # Wait for k3s to be fully up before continuing
    log_info "Waiting for k3s to be ready (up to 60 seconds)..."
    for i in $(seq 1 12); do
        if sudo systemctl is-active --quiet k3s; then
            log_success "k3s service is active."
            break
        fi
        if [ $i -eq 12 ]; then
            log_error "k3s did not start within 60 seconds."
            sudo journalctl -u k3s --no-pager -n 50
            exit 1
        fi
        log_info "Waiting... attempt $i/12"
        sleep 5
    done
fi

# ─────────────────────────────────────────────
# STEP 3: Configure kubectl for the current user
# ─────────────────────────────────────────────
log_info "Step 3/7: Configuring kubectl..."

# Create .kube directory if it doesn't exist (-p = no error if already exists)
mkdir -p ~/.kube

# Copy the kubeconfig k3s generated into the standard location
# k3s writes it to /etc/rancher/k3s/k3s.yaml
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Make the current user the owner (sudo cp creates it as root)
sudo chown "$(id -u):$(id -g)" ~/.kube/config

# Restrict permissions — kubeconfig contains credentials, should not be world-readable
chmod 600 ~/.kube/config

# Set KUBECONFIG for this script session
export KUBECONFIG=~/.kube/config

# Make it permanent for future SSH sessions
BASHRC_EXPORT='export KUBECONFIG=~/.kube/config'
if ! grep -qF "$BASHRC_EXPORT" ~/.bashrc; then
    echo "$BASHRC_EXPORT" >> ~/.bashrc
    log_info "Added KUBECONFIG export to ~/.bashrc"
fi

# ─────────────────────────────────────────────
# STEP 4: Wait for the node to be Ready
# ─────────────────────────────────────────────
log_info "Step 4/7: Waiting for Kubernetes node to be Ready..."

# Give k3s a few seconds to register the node before we try to wait on it
log_info "Giving k3s 15 seconds to register the node..."
sleep 15

# kubectl wait blocks until the condition is met or timeout is reached
kubectl wait node \
    --all \
    --for=condition=Ready \
    --timeout=120s

log_success "Node is Ready."
kubectl get nodes -o wide    # Print node info for confirmation

# ─────────────────────────────────────────────
# STEP 5: Install Metrics Server
# (Required for HPA — Horizontal Pod Autoscaling)
# ─────────────────────────────────────────────
log_info "Step 5/7: Installing Metrics Server ${METRICS_SERVER_VERSION}..."

# Check if metrics-server is already deployed
if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    log_warn "Metrics Server is already deployed. Skipping."
else
    # Apply the official metrics-server manifest
    kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

    # k3s uses self-signed TLS certificates for the kubelet.
    # By default, metrics-server verifies these certs and fails.
    # --kubelet-insecure-tls tells it to skip verification — acceptable for single-node.
    log_info "Patching Metrics Server to work with k3s self-signed certificates..."
    kubectl patch deployment metrics-server \
        -n kube-system \
        --type='json' \
        -p='[{
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--kubelet-insecure-tls"
        }]'

    # Wait for the metrics-server pod to be running
    log_info "Waiting for Metrics Server to be ready (up to 120 seconds)..."
    kubectl wait deployment metrics-server \
        -n kube-system \
        --for=condition=Available \
        --timeout=120s

    log_success "Metrics Server is ready."
fi

# ─────────────────────────────────────────────
# STEP 6: Verify Traefik Ingress Controller
# (k3s ships Traefik built-in — we just confirm it's running)
# ─────────────────────────────────────────────
log_info "Step 6/7: Verifying Traefik Ingress Controller..."

# Wait for Traefik to be ready (k3s installs it, we just wait)
kubectl wait deployment traefik \
    -n kube-system \
    --for=condition=Available \
    --timeout=120s

log_success "Traefik Ingress Controller is running."
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# ─────────────────────────────────────────────
# STEP 7: Create the application namespace
# ─────────────────────────────────────────────
log_info "Step 7/7: Creating application namespace '${APP_NAMESPACE}'..."

# --dry-run=client -o yaml | apply is the idempotent pattern:
# It generates what the resource WOULD look like, then applies it.
# This works whether the namespace exists or not — no "already exists" errors.
kubectl create namespace "${APP_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_success "Namespace '${APP_NAMESPACE}' is ready."

# ─────────────────────────────────────────────
# FINAL: Print cluster summary
# ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
log_success "Bootstrap complete! Cluster summary:"
echo "════════════════════════════════════════════════════════"
echo ""
echo "── Nodes ──────────────────────────────────────────────"
kubectl get nodes -o wide
echo ""
echo "── System Pods ─────────────────────────────────────────"
kubectl get pods -n kube-system
echo ""
echo "── Metrics (wait ~60s after bootstrap for data) ───────"
kubectl top nodes || log_warn "Metrics not yet available — wait 60s and run: kubectl top nodes"
echo ""
echo "── App Namespace ───────────────────────────────────────"
kubectl get all -n "${APP_NAMESPACE}"
echo ""
echo "════════════════════════════════════════════════════════"
log_success "Your cluster is ready to receive deployments!"
echo "════════════════════════════════════════════════════════"
