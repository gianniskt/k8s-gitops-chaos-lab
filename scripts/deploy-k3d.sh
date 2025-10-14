#!/bin/bash
set -e

echo "=================================================="
echo "🚀 GitOps Chaos Engineering - End-to-End Setup (k3d)"
echo "=================================================="
echo ""

# Configuration
CLUSTER_NAME="gitops-chaos"
GITHUB_USER="${1:-gianniskt}"
GITHUB_REPO="${2:-k8s-gitops-chaos-lab}"
GIT_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

echo "Configuration:"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Git URL: ${GIT_URL}"
echo ""

# Check if running in devcontainer
if [ -n "$REMOTE_CONTAINERS" ] || [ -n "$CODESPACES" ] || [ -f /.dockerenv ]; then
    echo "🐳 Detected devcontainer/container environment"
    echo "📦 Using k3d instead of kind for better container compatibility"
    SKIP_INSTALLATIONS=true
else
    echo "💻 Detected local environment"
    SKIP_INSTALLATIONS=false
fi
echo ""

# When running inside a devcontainer, force port-forwards by default because
# the k3d loadbalancer published ports may not be reachable from the host
# (for example: Windows host vs devcontainer network namespaces). Users can
# still override by exporting FORCE_PORT_FORWARDS=0 before running the script.
if [ "$SKIP_INSTALLATIONS" = "true" ] ; then
    # Running inside a devcontainer. Using k3d loadbalancer + nip.io for hostnames.
    # Port-forwards are not needed when using nip.io with the k3d loadbalancer publishing port 80.
    FORCE_PORT_FORWARDS=0
fi

# Install k3d if not present
if ! command -v k3d >/dev/null 2>&1; then
    echo "📦 Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    echo "✅ k3d installed"
else
    echo "✅ k3d found: $(k3d version)"
fi

# Verify Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Step 1: Create k3d cluster
echo "🔧 Step 1/7: Creating k3d cluster..."
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo "⚠️  Cluster '${CLUSTER_NAME}' already exists. Deleting..."
    k3d cluster delete ${CLUSTER_NAME}
fi

k3d cluster create "${CLUSTER_NAME}" \
    --api-port 6550 \
    --port "80:80@loadbalancer" \
    --port "3000:3000@loadbalancer" \
    --port "2333:2333@loadbalancer" \
    --port "8084:8084@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait --timeout 10m

kubectl config use-context k3d-${CLUSTER_NAME}
echo "✅ Cluster created"
echo ""

# Step 2: Build Docker images
echo "🐳 Step 2/7: Building Docker images..."
docker build -t backend:local ./app/backend
docker build -t frontend:local ./app/frontend
echo "✅ Images built"
echo ""

# Step 3: Load images into k3d
echo "📦 Step 3/7: Loading images into k3d cluster..."
k3d image import backend:local -c ${CLUSTER_NAME}
k3d image import frontend:local -c ${CLUSTER_NAME}
echo "✅ Images loaded"
echo ""

# Step 4: Install Flux Operator
echo "⚙️  Step 4/7: Installing Flux Operator..."

# Install Flux Operator using the official install.yaml
kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/install.yaml

# Wait for the operator to be ready
kubectl wait --for=condition=Available deployment/flux-operator -n flux-system --timeout=300s

echo "✅ Flux Operator installed successfully"
FLUX_OPERATOR_INSTALLED=true

echo ""

# Step 5: Configure FluxInstance for GitOps sync
echo "🔗 Step 5/7: Configuring FluxInstance for GitOps sync..."
kubectl apply -f gitops/flux/fluxinstance.yaml
echo "✅ FluxInstance configured"

echo ""

# Step 6: Wait for Flux to sync
echo "⏳ Step 6/7: Waiting for Flux to sync resources (this may take 2-3 minutes)..."

# First, wait for FluxInstance to be ready
echo "  Waiting for FluxInstance to be ready..."
kubectl wait --for=condition=Ready fluxinstance/flux -n flux-system --timeout=300s

# Wait for namespaces to be created by Flux
echo "  Waiting for namespaces to be created..."
for ns in app-backend app-frontend chaos-testing monitoring; do
    while ! kubectl get namespace $ns >/dev/null 2>&1; do
        echo "    Waiting for namespace $ns..."
        sleep 5
    done
done

# Wait for HelmReleases to be reconciled
echo "  Waiting for HelmReleases to be ready..."
echo "    - Monitoring stack (provides ServiceMonitor CRDs)..."
kubectl wait --for=condition=Ready helmrelease/kube-prometheus-stack -n monitoring --timeout=300s 2>/dev/null || echo "⚠️  Monitoring stack still deploying..."
echo "    - Chaos Mesh..."
kubectl wait --for=condition=Ready helmrelease/chaos-mesh -n chaos-testing --timeout=300s 2>/dev/null || echo "⚠️  Chaos Mesh still deploying..."

echo "✅ Core resources deployed"

# Force reconciliation in the correct dependency order
echo "🔄 Reconciling Flux resources in dependency order..."

echo "    - 1/8: Reconciling flux-system kustomization..."
flux reconcile kustomization flux-system --with-source 2>/dev/null || echo "⚠️  flux-system reconciliation failed"
sleep 5

# Helper: wait for a service to have endpoints (useful for validating webhooks)
wait_for_service_endpoints() {
    local ns=$1
    local svc=$2
    local timeout=${3:-120}
    echo "    Waiting up to ${timeout}s for endpoints of service $svc in namespace $ns..."
    local start=$(date +%s)
    while true; do
        # Check if endpoints exist and contain subsets
        if kubectl get endpoints -n "$ns" "$svc" -o jsonpath='{.subsets}' 2>/dev/null | grep -q .; then
            echo "    ✅ Endpoints ready for $svc in $ns"
            return 0
        fi
        local now=$(date +%s)
        if [ $((now - start)) -ge "$timeout" ]; then
            echo "    ⚠️  Timed out waiting for endpoints of $svc in $ns after ${timeout}s"
            return 1
        fi
        sleep 3
    done
}

# Wait for ingress-nginx admission webhook service endpoints before applying ingresses
if ! wait_for_service_endpoints ingress-nginx ingress-nginx-controller-admission 120; then
    echo "    ❌ ingress-nginx admission service endpoints not ready. The monitoring kustomization may fail to apply due to webhook validation errors."
    echo "    🔧 You can try rerunning the script after a short wait or manually check: kubectl get endpoints -n ingress-nginx ingress-nginx-controller-admission -o yaml"
    exit 1
fi

echo "    - 2/9: Reconciling monitoring kustomization..."
flux reconcile kustomization monitoring 2>/dev/null || echo "⚠️  monitoring reconciliation failed"
sleep 5

echo "    - 3/9: Reconciling reloader kustomization..."
flux reconcile kustomization reloader 2>/dev/null || echo "⚠️  reloader reconciliation failed"
sleep 10

echo "    - 4/9: Reconciling cert-manager kustomization..."
flux reconcile kustomization cert-manager 2>/dev/null || echo "⚠️  cert-manager reconciliation failed"
sleep 10

echo "    - 5/9: Reconciling cert-manager helmrelease..."
flux reconcile helmrelease cert-manager -n cert-manager 2>/dev/null || echo "⚠️  cert-manager reconciliation failed"
sleep 20

echo "    - 6/9: Reconciling linkerd-certificates kustomization..."
flux reconcile kustomization linkerd-certificates 2>/dev/null || echo "⚠️  linkerd-certificates reconciliation failed"
sleep 10

echo "    - 7/9: Reconciling linkerd kustomization..."
flux reconcile kustomization linkerd 2>/dev/null || echo "⚠️  linkerd reconciliation failed"
sleep 10

echo "    - 7.5/9: Waiting for trust anchor sync and restarting Linkerd control plane..."
# Wait for the trust sync job to complete
kubectl wait --for=condition=Complete job/linkerd-trust-sync-initial -n linkerd --timeout=120s 2>/dev/null || echo "⚠️  Trust sync job may still be running"
# Restart Linkerd control plane to pick up updated trust anchors
kubectl rollout restart deployment -n linkerd 2>/dev/null || echo "⚠️  Failed to restart Linkerd deployments"
# Wait for the deployments to be ready
kubectl wait --for=condition=Available deployment/linkerd-destination -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd destination may still be restarting"
kubectl wait --for=condition=Available deployment/linkerd-identity -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd identity may still be restarting"
kubectl wait --for=condition=Available deployment/linkerd-proxy-injector -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd proxy-injector may still be restarting"

echo "    - 8/9: Reconciling manifests kustomization..."
flux reconcile kustomization manifests 2>/dev/null || echo "⚠️  manifests reconciliation failed"
sleep 5

echo "    - 9/9: Reconciling chaos-mesh kustomization..."
flux reconcile kustomization chaos-mesh 2>/dev/null || echo "⚠️  chaos-mesh reconciliation failed"
sleep 5

echo "    - 10/9: Reconciling chaos-experiments kustomization..."
flux reconcile kustomization chaos-experiments 2>/dev/null || echo "⚠️  chaos-experiments reconciliation failed"
sleep 5

echo "    - 11/9: Restarting all Linkerd viz deployments..."
kubectl rollout restart deployment -n linkerd-viz 2>/dev/null || echo "⚠️  Failed to restart some Linkerd viz deployments"
# Wait for viz deployments to be ready
kubectl wait --for=condition=Available deployment/web -n linkerd-viz --timeout=120s 2>/dev/null || echo "⚠️  Web deployment may still be restarting"
kubectl wait --for=condition=Available deployment/metrics-api -n linkerd-viz --timeout=120s 2>/dev/null || echo "⚠️  Metrics API deployment may still be restarting"
sleep 5

# Wait for all kustomizations to be ready
echo "    - Waiting for all kustomizations to be ready..."
kubectl wait --for=condition=Ready kustomization/manifests -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Manifests may still be applying..."
kubectl wait --for=condition=Ready kustomization/monitoring -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Monitoring may still be applying..."
kubectl wait --for=condition=Ready kustomization/chaos-mesh -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Chaos Mesh may still be applying..."
kubectl wait --for=condition=Ready kustomization/chaos-experiments -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Chaos experiments may still be applying..."
kubectl wait --for=condition=Ready kustomization/cert-manager -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Cert-manager may still be applying..."
kubectl wait --for=condition=Ready kustomization/linkerd-certificates -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Linkerd certificates may still be applying..."
kubectl wait --for=condition=Ready kustomization/linkerd -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  Linkerd may still be applying..."
echo ""

# Step 7: Wait for all pods
echo "🎯 Step 7/7: Waiting for all pods to be ready..."

# Only wait for pods if the namespace exists and has deployments
if kubectl get namespace app-backend >/dev/null 2>&1 && kubectl get deployment -n app-backend 2>/dev/null | grep -q backend; then
    echo "  Waiting for backend pods..."
    kubectl wait --for=condition=Ready pod -l app=backend -n app-backend --timeout=120s 2>/dev/null || echo "⚠️  Backend pods still starting..."
else
    echo "  Backend deployment not found or namespace not ready"
fi

if kubectl get namespace app-frontend >/dev/null 2>&1 && kubectl get deployment -n app-frontend 2>/dev/null | grep -q frontend; then
    echo "  Waiting for frontend pods..."
    kubectl wait --for=condition=Ready pod -l app=frontend -n app-frontend --timeout=120s 2>/dev/null || echo "⚠️  Frontend pods still starting..."
else
    echo "  Frontend deployment not found or namespace not ready"
fi

echo "  Waiting for monitoring pods..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=kube-prometheus-stack -n monitoring --timeout=300s 2>/dev/null || echo "⚠️  Monitoring pods still starting..."

echo "  Waiting for chaos-mesh pods..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=chaos-mesh -n chaos-testing --timeout=300s 2>/dev/null || echo "⚠️  Chaos Mesh pods still starting..."

echo "  Waiting for linkerd pods..."
kubectl wait --for=condition=Ready pod -l linkerd.io/control-plane-ns=linkerd -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd pods still starting..."

echo "✅ Deployment complete!"
echo ""

# No port-forwards needed: using nip.io hostnames mapped to the k3d loadbalancer IP (127.0.0.1 via nip.io)
# If you want explicit port-forwarding you can enable it manually, but it's not required for nip.io usage.

# Create chaos dashboard token
echo "🔑 Creating Chaos Mesh dashboard token..."
CHAOS_TOKEN=$(kubectl create token chaos-dashboard -n chaos-testing --duration=24h 2>/dev/null || echo "Token creation failed - manual creation needed")

# Display status
echo ""
echo "=================================================="
echo "✅ DEPLOYMENT SUCCESSFUL!"
echo "=================================================="
echo ""
echo "📊 Cluster Status:"
kubectl get pods -A | grep -E "NAMESPACE|app-backend|app-frontend|chaos-testing|monitoring|linkerd" || true
echo ""
echo "🏠 DASHBOARD ACCESS:"
echo "=================================================="
echo ""
echo "📊 Grafana (Monitoring & Metrics):"
echo "   🌍 URL: http://grafana.127.0.0.1.nip.io"
echo "   👤 Username: admin"
echo "   🔑 Password: prom-operator"
echo "   📈 Look for 'Chaos Engineering' dashboard"
echo ""
echo "💥 Chaos Mesh (Chaos Experiments):"
echo "   🌍 URL: http://chaos.127.0.0.1.nip.io"
echo "   🔑 Token: $CHAOS_TOKEN"
echo "   📝 How to login:"
echo "      1. Open http://chaos.127.0.0.1.nip.io"
echo "      2. Click 'Token' authentication"
echo "      3. Paste the token above"
echo "      4. Click 'Submit'"
echo ""
echo "🔗 Linkerd (Service Mesh):"
echo "   🌍 URL: http://linkerd.127.0.0.1.nip.io"
echo "   📊 View service mesh topology, metrics, and traffic patterns"
echo "   🔍 Monitor your backend and frontend services with Linkerd"
echo ""
echo "🔥 CHAOS ENGINEERING STATUS:"
echo "=================================================="
echo ""
echo "🎯 Active Chaos Experiments:"
kubectl get schedule -n chaos-testing 2>/dev/null || echo "   No schedules found - they may still be deploying"
echo ""
echo "🚀 Quick Commands:"
echo "   • Watch backend pods being killed: kubectl get pods -n app-backend -w"
echo "   • Check Flux status: flux get all"
echo "   • View chaos events: kubectl get events -n chaos-testing"
echo "   • Restart Linkerd control plane: kubectl rollout restart deployment -n linkerd"
echo ""
echo "🛠️  k3d Commands:"
echo "   • Delete cluster: k3d cluster delete ${CLUSTER_NAME}"
echo "   • Restart cluster: k3d cluster stop ${CLUSTER_NAME} && k3d cluster start ${CLUSTER_NAME}"
echo "   • Import new images: k3d image import <image:tag> -c ${CLUSTER_NAME}"