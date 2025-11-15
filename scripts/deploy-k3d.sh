#!/bin/bash
set -e

echo "=================================================="
echo "🚀 GitOps Chaos Engineering - End-to-End Setup (k3d)"
echo "=================================================="
echo ""

# Configuration
CLUSTER_NAME="gitops-chaos"

# Prompt for GITHUB_USER if not supplied so the script can be run interactively
if [ -z "${1:-}" ]; then
    read -p "Enter your GitHub username (this will be used to build the repo URL): " GITHUB_USER
    if [ -z "${GITHUB_USER:-}" ]; then
        echo "Usage: $0 <GITHUB_USER> [GITHUB_REPO]"
        echo "  Example (non-interactive): $0 my-github-user k8s-gitops-chaos-lab"
        echo "You can also re-run the script and pass the username as the first argument."
        exit 2
    fi
else
    GITHUB_USER="$1"
fi

# Prompt for optional repo name; default to 'k8s-gitops-chaos-lab' when empty
if [ -z "${2:-}" ]; then
    read -p "Enter GitHub repo name [k8s-gitops-chaos-lab]: " GITHUB_REPO
    # If user pressed Enter, use default
    if [ -z "${GITHUB_REPO:-}" ]; then
        GITHUB_REPO="k8s-gitops-chaos-lab"
    fi
else
    GITHUB_REPO="$2"
fi

# Build the Git URL (no .git suffix to match how flux instances often reference repos)
GIT_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}"

echo "Configuration:"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Git URL: ${GIT_URL}"
echo ""

# Environment detection and configuration
if [ -n "$REMOTE_CONTAINERS" ] || [ -n "$CODESPACES" ] || [ -f /.dockerenv ]; then
    echo "🐳 Detected devcontainer/container environment"
    ENVIRONMENT="devcontainer"
    SKIP_INSTALLATIONS=true
    
    # Check if host .kube is mounted
    if [ -d "/host-kube" ]; then
        HOST_KUBE_PATH="/host-kube"
        echo "📂 Host .kube directory mounted at: ${HOST_KUBE_PATH}"
    else
        HOST_KUBE_PATH=""
        echo "⚠️  Host .kube directory not mounted - host kubeconfig won't be updated"
        echo "    To enable: add mount in devcontainer.json"
    fi
else
    echo "💻 Detected local/host environment"
    ENVIRONMENT="localhost"
    SKIP_INSTALLATIONS=false
    
    # Detect host .kube path based on OS
    if [ -n "$USERPROFILE" ]; then
        # Windows
        HOST_KUBE_PATH="$(echo "$USERPROFILE" | sed 's|\\|/|g')/.kube"
    elif [ -n "$HOME" ]; then
        # Linux/macOS
        HOST_KUBE_PATH="$HOME/.kube"
    else
        HOST_KUBE_PATH="~/.kube"
    fi
    echo "🏠 Host .kube directory: ${HOST_KUBE_PATH}"
fi
echo ""

# When running inside a devcontainer, force port-forwards by default because
# the k3d loadbalancer published ports may not be reachable from the host
# (for example: Windows host vs devcontainer network namespaces). Users can
# still override by exporting FORCE_PORT_FORWARDS=0 before running the script.
if [ "$SKIP_INSTALLATIONS" = "true" ] ; then
    # Running inside a devcontainer. Using k3d loadbalancer + traefik.me for hostnames.
    # Port-forwards are not needed when using traefik.me with the k3d loadbalancer publishing port 80.
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

# Function to clean up k3d cluster and host kubeconfig
cleanup_cluster() {
    local cluster_name="$1"
    echo "🧹 Cleaning up cluster: ${cluster_name}"
    
    # Determine kubeconfig path based on environment
    local kube_path=""
    if [ "$ENVIRONMENT" = "devcontainer" ] && [ -n "$HOST_KUBE_PATH" ] && [ -d "$HOST_KUBE_PATH" ]; then
        kube_path="$HOST_KUBE_PATH"
    elif [ "$ENVIRONMENT" = "localhost" ] && [ -n "$HOST_KUBE_PATH" ]; then
        kube_path="$HOST_KUBE_PATH"
    fi
    
    # Remove context from host kubeconfig if accessible
    if [ -n "$kube_path" ] && [ -f "$kube_path/config" ]; then
        echo "  🏠 Removing k3d-${cluster_name} context from host kubeconfig..."
        
        # Backup host config
        CLEANUP_BACKUP="$kube_path/config.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$kube_path/config" "$CLEANUP_BACKUP"
        
        # Remove the context, cluster, and user entries
        KUBECONFIG="$kube_path/config" kubectl config delete-context "k3d-${cluster_name}" 2>/dev/null || true
        KUBECONFIG="$kube_path/config" kubectl config delete-cluster "k3d-${cluster_name}" 2>/dev/null || true
        KUBECONFIG="$kube_path/config" kubectl config delete-user "admin@k3d-${cluster_name}" 2>/dev/null || true
        
        # Clean up backup after successful cleanup
        rm -f "$CLEANUP_BACKUP"
        echo "  ✅ Cleaned up k3d contexts from host kubeconfig"
    else
        echo "  ⚠️  Host kubeconfig cleanup skipped (not accessible)"
    fi
    
    # Delete the k3d cluster
    k3d cluster delete ${cluster_name}
    echo "  ✅ k3d cluster deleted"
}

# Step 1: Create k3d cluster
echo "🔧 Step 1/7: Creating k3d cluster..."

# Ensure .kube directory exists to prevent k3d kubeconfig creation warnings
echo "📁 Preparing kubeconfig setup..."
mkdir -p ~/.kube
if [ "$ENVIRONMENT" = "devcontainer" ] && [ -n "$HOST_KUBE_PATH" ]; then
    mkdir -p "$HOST_KUBE_PATH"
    echo "  ✅ Created ~/.kube and $HOST_KUBE_PATH"
else
    echo "  ✅ Created ~/.kube"
fi

if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo "⚠️  Cluster '${CLUSTER_NAME}' already exists. Deleting..."
    cleanup_cluster ${CLUSTER_NAME}
fi

k3d cluster create "${CLUSTER_NAME}" \
    --api-port 6550 \
    --servers 1 \
    --agents 3 \
    --port "80:80@loadbalancer" \
    --port "3000:3000@loadbalancer" \
    --port "2333:2333@loadbalancer" \
    --port "8084:8084@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--tls-san=host.docker.internal@server:0" \
    --k3s-arg "--tls-san=127.0.0.1@server:0" \
    --wait --timeout 10m

echo "✅ Cluster created"
echo ""

# Manual kubeconfig management (since --kubeconfig-update-default is removed)
echo "🔐 Managing kubeconfig for k3d cluster..."

# Get k3d kubeconfig to a temporary location
k3d kubeconfig get ${CLUSTER_NAME} > /tmp/k3d-config

# Determine server URL based on environment
if [ "$ENVIRONMENT" = "devcontainer" ]; then
    K3D_SERVER_URL="https://host.docker.internal:6550"
else
    K3D_SERVER_URL="https://127.0.0.1:6550"
fi

# Update the k3d kubeconfig with the correct server URL
sed -i "s|https://.*:6550|${K3D_SERVER_URL}|g" /tmp/k3d-config

# Check if existing kubeconfig has actual content (not just empty/null values)
HAS_CONTENT=false
if [ -f ~/.kube/config ] && [ -s ~/.kube/config ]; then
    # Check if config has any real clusters/contexts (not just null values)
    if grep -q "clusters:" ~/.kube/config && ! grep -q "clusters: null" ~/.kube/config && ! grep -q "clusters: \[\]" ~/.kube/config; then
        HAS_CONTENT=true
    fi
fi

# Merge k3d context with existing kubeconfig
if [ "$HAS_CONTENT" = true ]; then
    # Backup existing kubeconfig
    cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
    
    # Merge using kubectl with proper KUBECONFIG format
    if [ -n "$USERPROFILE" ]; then
        # Windows - use semicolon separator and try both path formats
        KUBECONFIG="$(cygpath -w ~/.kube/config 2>/dev/null);$(cygpath -w /tmp/k3d-config 2>/dev/null)" kubectl config view --flatten > /tmp/merged-config 2>/dev/null || \
        KUBECONFIG="$HOME/.kube/config;/tmp/k3d-config" kubectl config view --flatten > /tmp/merged-config
    else
        # Unix/Linux/macOS - use colon separator
        KUBECONFIG="$HOME/.kube/config:/tmp/k3d-config" kubectl config view --flatten > /tmp/merged-config
    fi
    
    if [ -s /tmp/merged-config ]; then
        cp /tmp/merged-config ~/.kube/config
        echo "  ✅ Merged k3d context with existing kubeconfig"
    else
        echo "  ⚠️  Merge failed, using k3d config only"
        cp /tmp/k3d-config ~/.kube/config
    fi
else
    # No existing config, empty config, or config with no content - just use k3d config
    if [ -f ~/.kube/config ]; then
        cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
    fi
    cp /tmp/k3d-config ~/.kube/config
    echo "  ✅ Created kubeconfig with k3d context"
fi

# Set k3d context as current
kubectl config use-context k3d-${CLUSTER_NAME}

# Clean up temporary files
rm -f /tmp/k3d-config /tmp/merged-config

echo "✅ k3d context merged into existing kubeconfig with server: ${K3D_SERVER_URL}"

# Sync kubeconfig to host if running from devcontainer
if [ "$ENVIRONMENT" = "devcontainer" ] && [ -n "$HOST_KUBE_PATH" ] && [ -d "$HOST_KUBE_PATH" ]; then
    echo "🏠 Syncing devcontainer kubeconfig to host..."
    
    # Create host version with 127.0.0.1 instead of host.docker.internal
    sed 's|host.docker.internal:6550|127.0.0.1:6550|g' ~/.kube/config > /tmp/kubeconfig-host
    
    # Backup and merge with host kubeconfig
    BACKUP_FILE=""
    if [ -f "$HOST_KUBE_PATH/config" ]; then
        BACKUP_FILE="$HOST_KUBE_PATH/config.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$HOST_KUBE_PATH/config" "$BACKUP_FILE"
        echo "  📋 Backed up existing host kubeconfig"
        
        # Merge - preserve all contexts, update k3d context with correct server URL
        # Use proper path separator for the OS (: for Unix, ; for Windows)
        if [ -n "$USERPROFILE" ]; then
            # Windows - use semicolon separator
            KUBECONFIG="$HOST_KUBE_PATH/config;/tmp/kubeconfig-host" kubectl config view --flatten > "$HOST_KUBE_PATH/config.merged"
        else
            # Unix/Linux/macOS - use colon separator
            KUBECONFIG="$HOST_KUBE_PATH/config:/tmp/kubeconfig-host" kubectl config view --flatten > "$HOST_KUBE_PATH/config.merged"
        fi
        mv "$HOST_KUBE_PATH/config.merged" "$HOST_KUBE_PATH/config"
        
        # Set k3d context as current on host
        KUBECONFIG="$HOST_KUBE_PATH/config" kubectl config use-context "k3d-gitops-chaos"
        
        # Clean up backup after successful merge
        rm -f "$BACKUP_FILE"
        echo "  ✅ Merged k3d context into host kubeconfig with 127.0.0.1 server URL"
    else
        # First time: copy our kubeconfig to host
        cp /tmp/kubeconfig-host "$HOST_KUBE_PATH/config"
        echo "  ✅ Created host kubeconfig with k3d context (127.0.0.1 server URL)"
    fi
    
    rm -f /tmp/kubeconfig-host
else
    echo "⚠️  Host kubeconfig sync skipped (not in devcontainer or no host mount)"
fi


# Step 2: Build Docker images
echo "🐳 Step 2/6: Building Docker images..."
docker build -t backend:local ./app/backend
docker build -t frontend:local ./app/frontend
echo "✅ Images built"
echo ""

# Step 3: Load images into k3d
echo "📦 Step 3/6: Loading images into k3d cluster..."
k3d image import backend:local -c ${CLUSTER_NAME}
k3d image import frontend:local -c ${CLUSTER_NAME}
echo "✅ Images loaded"
echo ""

# Step 4: Install Flux Operator
echo "⚙️  Step 4/6: Installing Flux Operator..."

# Install Flux Operator using the official install.yaml
kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/install.yaml

# Wait for the operator to be ready
kubectl wait --for=condition=Available deployment/flux-operator -n flux-system --timeout=300s

echo "✅ Flux Operator installed successfully"
FLUX_OPERATOR_INSTALLED=true

echo ""

# Step 5: Configure FluxInstance for GitOps sync
echo "🔗 Step 5/6: Configuring FluxInstance for GitOps sync..."
# Render a temporary copy of fluxinstance.yaml with the user inputs substituted
# This avoids modifying the repo file and works even when running non-interactively
TMP_FLUX_INSTANCE="$(mktemp -t fluxinstance.XXXX 2>/dev/null || mktemp)"
sed -e "s|\${GITHUB_USER}|${GITHUB_USER}|g" -e "s|\${GITHUB_REPO}|${GITHUB_REPO}|g" gitops/flux/fluxinstance.yaml > "$TMP_FLUX_INSTANCE"

# Apply the rendered file. If it fails, try applying the original file as a fallback
if kubectl apply -f "$TMP_FLUX_INSTANCE" >/dev/null 2>&1; then
    echo "✅ FluxInstance configured"
else
    echo "⚠️  Applying rendered FluxInstance failed; attempting to apply original file (may fail if placeholders are unresolved)"
    kubectl apply -f gitops/flux/fluxinstance.yaml 2>/dev/null || echo "⚠️  Failed to apply fluxinstance.yaml"
fi

rm -f "$TMP_FLUX_INSTANCE"

echo ""

# Step 6: Wait for Flux to sync
echo "⏳ Step 6/6: Waiting for Flux to sync resources (this may take 2-3 minutes)..."

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

echo "    - 1/12: Reconciling flux-system kustomization..."
flux reconcile kustomization flux-system --with-source 2>/dev/null || echo "⚠️  flux-system reconciliation failed"
sleep 5

# Helper: wait for a service to have endpoints (useful for validating webhooks)
wait_for_service_endpoints() {
    local ns=$1
    local svc=$2
    local timeout=${3:-160}
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

# Wait for Traefik to be ready before applying ingresses
echo "    Waiting for Traefik to be ready..."
if ! kubectl -n traefik wait --for=condition=Available deployment/traefik --timeout=180s 2>/dev/null; then
    echo "    ⚠️  Traefik not ready yet, continuing anyway..."
fi

echo "    - 2/12: Reconciling monitoring kustomization..."
flux resume kustomization monitoring -n flux-system 2>/dev/null || true
flux reconcile kustomization monitoring -n flux-system 2>/dev/null || echo "⚠️  monitoring reconciliation failed"
sleep 5

echo "    - 3/12: Reconciling reloader kustomization..."
flux reconcile kustomization reloader 2>/dev/null || echo "⚠️  reloader reconciliation failed"
sleep 10

echo "    - 4/12: Reconciling cert-manager kustomization..."
flux reconcile kustomization cert-manager 2>/dev/null || echo "⚠️  cert-manager reconciliation failed"
sleep 10

echo "    - 5/12: Reconciling cert-manager helmrelease..."
flux reconcile helmrelease cert-manager -n cert-manager 2>/dev/null || echo "⚠️  cert-manager reconciliation failed"
sleep 20

echo "    - 6/12: Reconciling linkerd-certificates kustomization..."
flux reconcile kustomization linkerd-certificates 2>/dev/null || echo "⚠️  linkerd-certificates reconciliation failed"
sleep 10

echo "    - 7/12: Reconciling linkerd kustomization..."
flux reconcile kustomization linkerd 2>/dev/null || echo "⚠️  linkerd reconciliation failed"
sleep 10

echo "    - 7.5/12: Waiting for trust anchor sync and restarting Linkerd control plane..."
# Wait for the trust sync job to complete
kubectl wait --for=condition=Complete job/linkerd-trust-sync-initial -n linkerd --timeout=120s 2>/dev/null || echo "⚠️  Trust sync job may still be running"
# Restart Linkerd control plane to pick up updated trust anchors
kubectl rollout restart deployment -n linkerd 2>/dev/null || echo "⚠️  Failed to restart Linkerd deployments"
# Wait for the deployments to be ready
kubectl wait --for=condition=Available deployment/linkerd-destination -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd destination may still be restarting"
kubectl wait --for=condition=Available deployment/linkerd-identity -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd identity may still be restarting"
kubectl wait --for=condition=Available deployment/linkerd-proxy-injector -n linkerd --timeout=300s 2>/dev/null || echo "⚠️  Linkerd proxy-injector may still be restarting"

echo "    - 8/12: Reconciling manifests kustomization..."
flux reconcile kustomization manifests 2>/dev/null || echo "⚠️  manifests reconciliation failed"
sleep 5

echo "    - 9/12: Reconciling chaos-mesh kustomization..."
flux reconcile kustomization chaos-mesh 2>/dev/null || echo "⚠️  chaos-mesh reconciliation failed"
sleep 5

echo "    - 9.1/12: Applying Chaos Mesh values ConfigMap from repo (idempotent)"
# Apply the values ConfigMap that HelmRelease references via valuesFrom so the
# Helm controller can read environment-specific values from Git.
kubectl apply -f gitops/chaos-mesh/chaos-mesh-values.yaml 2>/dev/null || echo "⚠️  Failed to apply chaos-mesh-values ConfigMap"
sleep 2

echo "    - 9.2/12: Forcing HelmRelease reconcile for chaos-mesh (so Helm controller re-renders with the applied ConfigMap)"
# Prefer `flux` if present; fall back to annotating the HelmRelease to force a reconcile.
if command -v flux >/dev/null 2>&1; then
    flux reconcile helmrelease chaos-mesh -n chaos-testing --with-source 2>/dev/null || echo "⚠️  flux helmrelease reconcile failed"
else
    kubectl -n chaos-testing annotate helmrelease chaos-mesh reconcile.fluxcd.io/forceAt="$(date -Iseconds)" --overwrite 2>/dev/null || echo "⚠️  fallback annotate to force HelmRelease reconcile failed"
fi
sleep 3

echo "    - 9.3/12: Restarting Chaos Mesh controller & dashboard and recreating daemon pods (pick up mounted hostPath/socket changes)"
kubectl -n chaos-testing rollout restart deployment chaos-controller-manager 2>/dev/null || echo "⚠️  Failed to restart chaos-controller-manager"
kubectl -n chaos-testing rollout restart deployment chaos-dashboard 2>/dev/null || echo "⚠️  Failed to restart chaos-dashboard"
# Delete daemon pods so the DaemonSet recreates them and picks up new hostPath mounts/args
kubectl -n chaos-testing delete pod -l app.kubernetes.io/component=chaos-daemon --ignore-not-found 2>/dev/null || echo "⚠️  Failed to delete chaos-daemon pods"
sleep 5

echo "    - 10/12: Reconciling chaos-experiments kustomization..."
flux reconcile kustomization chaos-experiments 2>/dev/null || echo "⚠️  chaos-experiments reconciliation failed"
sleep 5
echo "    - 11/12: Reconciling KEDA kustomizations and HelmRelease..."
flux reconcile kustomization keda -n flux-system --with-source 2>/dev/null || echo "⚠️  keda (helmrepo/helmrelease) reconciliation failed"
sleep 5

echo "    - Reconciling KEDA kustomization that includes ScaledObjects..."
flux reconcile kustomization keda-scaledobjects --with-source 2>/dev/null || echo "⚠️  keda-scaledobjects reconciliation failed"
sleep 10

# Reconcile the HelmRelease for keda to ensure the operator is installed
echo "    - Reconciling keda HelmRelease..."
flux reconcile helmrelease keda -n keda 2>/dev/null || echo "⚠️  keda helmrelease reconciliation failed"
sleep 20

# Wait for KEDA pods to be ready
echo "    - Waiting for KEDA pods to be ready..."
kubectl -n keda wait --for=condition=Ready pod -l app.kubernetes.io/name=keda-operator --timeout=180s 2>/dev/null || echo "⚠️  KEDA pods may still be starting"

echo "    - 12/12: Restarting all Linkerd viz deployments..."
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
kubectl wait --for=condition=Ready kustomization/keda -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  KEDA (helmrepo/helmrelease) may still be applying..."
kubectl wait --for=condition=Ready kustomization/keda-scaledobjects -n flux-system --timeout=300s 2>/dev/null || echo "⚠️  KEDA ScaledObjects may still be applying..."
kubectl wait --for=condition=Ready helmrelease/keda -n keda --timeout=300s 2>/dev/null || echo "⚠️  KEDA helmrelease may still be applying..."
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

# Ensure Chaos Mesh workloads pick up any rendered/merged value changes by restarting
# the controller and dashboard Deployments and recreating daemon pods. This mirrors
# what we do manually during troubleshooting so the cluster state matches the
# GitOps-applied manifests without requiring extra manual steps.
echo "  Restarting Chaos Mesh controller, dashboard and recreating daemon pods..."
kubectl -n chaos-testing rollout restart deployment chaos-controller-manager 2>/dev/null || echo "⚠️  Failed to restart chaos-controller-manager"
kubectl -n chaos-testing rollout restart deployment chaos-dashboard 2>/dev/null || echo "⚠️  Failed to restart chaos-dashboard"
# Delete daemon pods so the DaemonSet recreates them (pick up hostPath mounts/args)
kubectl -n chaos-testing delete pod -l app.kubernetes.io/component=chaos-daemon --ignore-not-found 2>/dev/null || echo "⚠️  Failed to delete chaos-daemon pods"
sleep 5

echo "✅ Deployment complete!"
echo ""

# No port-forwards needed: using traefik.me hostnames mapped to the k3d loadbalancer IP (127.0.0.1 via traefik.me)
# If you want explicit port-forwarding you can enable it manually, but it's not required for traefik.me usage.

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
echo "   🌍 URL: http://grafana.127.0.0.1.traefik.me"
echo "   👤 Username: admin"
echo "   🔑 Password: prom-operator"
echo "   📈 Look for 'Chaos Engineering' dashboard"
echo ""
echo "💥 Chaos Mesh (Chaos Experiments):"
echo "   🌍 URL: http://chaos.127.0.0.1.traefik.me"
echo "   🔑 Token: $CHAOS_TOKEN"
echo "   📝 How to login:"
echo "      1. Open http://chaos.127.0.0.1.traefik.me"
echo "      2. Click 'Token' authentication"
echo "      3. Paste the token above"
echo "      4. Click 'Submit'"
echo ""
echo "🔗 Linkerd (Service Mesh):"
echo "   🌍 URL: http://linkerd.127.0.0.1.traefik.me"
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
echo ""
echo "🛠️  k3d Commands:"
echo "   • Import new images: k3d image import <image:tag> -c ${CLUSTER_NAME}"
echo "   • Restart cluster: k3d cluster stop ${CLUSTER_NAME} && k3d cluster start ${CLUSTER_NAME}"
echo "   • Delete cluster: ./scripts/cleanup-k3d.sh"
echo ""