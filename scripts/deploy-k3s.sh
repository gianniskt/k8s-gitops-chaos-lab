#!/bin/bash
set -e

echo "=================================================="
echo "🚀 GitOps Chaos Engineering - K3s Setup"
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

# Step 1: Start K3s cluster
echo "🔧 Step 1/7: Starting K3s cluster..."

# Check if K3s is already running
if pgrep -f "k3s server" > /dev/null; then
    echo "⚠️  K3s is already running. Stopping..."
    sudo pkill -f "k3s server" || true
    sleep 3
fi

# Clean up any existing K3s data
sudo rm -rf /var/lib/rancher/k3s/server/db || true
sudo rm -rf /etc/rancher/k3s || true

# Start K3s server in background
echo "Starting K3s server..."
sudo mkdir -p /etc/rancher/k3s
sudo k3s server \
    --disable traefik \
    --disable servicelb \
    --disable local-storage \
    --write-kubeconfig-mode 644 \
    --node-name ${CLUSTER_NAME}-node \
    --cluster-cidr 10.42.0.0/16 \
    --service-cidr 10.43.0.0/16 \
    --data-dir /var/lib/rancher/k3s \
    > /tmp/k3s.log 2>&1 &

K3S_PID=$!
echo "K3s started with PID: $K3S_PID"

echo "⏳ Waiting for K3s to be ready..."
# Wait for K3s to create the kubeconfig
for i in {1..60}; do
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        echo "  K3s kubeconfig found"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "❌ K3s failed to start. Check logs:"
        tail -20 /tmp/k3s.log
        exit 1
    fi
    echo "  Waiting for K3s kubeconfig... (${i}/60)"
    sleep 5
done

# Setup kubeconfig for regular user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Wait for K3s API server to be ready
echo "⏳ Waiting for K3s API server..."
for i in {1..30}; do
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✅ K3s cluster is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ K3s API server not responding. Check logs:"
        tail -20 /tmp/k3s.log
        exit 1
    fi
    echo "  Waiting for API server... (${i}/30)"
    sleep 10
done

# Verify cluster is working
echo "🔍 Verifying cluster..."
kubectl get nodes
kubectl get namespaces

echo "✅ K3s cluster created successfully"
echo ""

# Step 2: Build application images
echo "📦 Step 2/7: Building application images..."

# Check if we have the app directory
if [ ! -d "app" ]; then
    echo "❌ App directory not found. Make sure you're in the project root."
    exit 1
fi

cd app/

# Check if Docker is available for building
if command -v docker &> /dev/null; then
    echo "Using Docker to build images..."
    BUILDER="docker"
elif command -v nerdctl &> /dev/null; then
    echo "Using nerdctl to build images..."
    BUILDER="nerdctl --namespace k8s.io"
else
    echo "Installing nerdctl for image building..."
    NERDCTL_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    sudo curl -sSL "https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz" | sudo tar -xz -C /usr/local/bin
    BUILDER="sudo nerdctl --namespace k8s.io"
fi

# Build backend image
echo "Building backend image..."
if [ -f backend/Dockerfile ]; then
    $BUILDER build -t backend:local backend/
    echo "✅ Backend image built"
else
    echo "⚠️  No backend/Dockerfile found, skipping backend build"
fi

# Build frontend image  
echo "Building frontend image..."
if [ -f frontend/Dockerfile ]; then
    $BUILDER build -t frontend:local frontend/
    echo "✅ Frontend image built"
else
    echo "⚠️  No frontend/Dockerfile found, skipping frontend build"
fi

echo "✅ Image building completed"
cd ..
echo ""

# Step 3: Install Flux Operator
echo "⚙️  Step 3/7: Installing Flux Operator..."
kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/install.yaml

echo "⏳ Waiting for Flux Operator to be ready..."
kubectl wait --for=condition=Available deployment/flux-operator -n flux-operator-system --timeout=300s

echo "✅ Flux Operator installed successfully"
echo ""

# Step 4: Install NGINX Ingress
echo "🔌 Step 4/7: Installing NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

echo "⏳ Waiting for NGINX Ingress to be ready..."
kubectl wait --for=condition=Available deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s

echo "✅ NGINX Ingress installed successfully"
echo ""

# Step 5: Create FluxInstance
echo "🔧 Step 5/7: Creating Flux Instance..."
cat > /tmp/flux-instance.yaml << EOF
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
  cluster:
    type: kubernetes
    multitenant: false
    networkPolicy: false
    domain: "cluster.local"
  kustomize:
    patches:
      - target:
          kind: Deployment
          name: "(kustomize-controller|helm-controller)"
        patch: |
          - op: add
            path: /spec/template/spec/containers/0/args/-
            value: --concurrent=10
          - op: add
            path: /spec/template/spec/containers/0/args/-
            value: --kube-api-qps=500
          - op: add
            path: /spec/template/spec/containers/0/args/-
            value: --kube-api-burst=1000
          - op: add
            path: /spec/template/spec/containers/0/args/-
            value: --requeue-dependency=5s
EOF

kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f /tmp/flux-instance.yaml

echo "⏳ Waiting for Flux controllers to be ready..."
kubectl wait --for=condition=Ready fluxinstance/flux -n flux-system --timeout=300s

echo "✅ Flux Instance created successfully"
echo ""

# Step 6: Setup GitOps repository
echo "📚 Step 6/7: Setting up GitOps repository..."

# Apply the existing GitOps manifests directly
echo "Applying GitOps manifests from ./gitops directory..."

if [ -d "gitops" ]; then
    # Apply the main kustomization that includes everything
    kubectl apply -k gitops/ || {
        echo "⚠️  Direct kustomization failed, trying individual components..."
        
        # Apply components in order
        [ -d "gitops/flux" ] && kubectl apply -k gitops/flux/
        [ -d "gitops/kustomizations" ] && kubectl apply -k gitops/kustomizations/
        
        echo "✅ GitOps manifests applied"
    }
else
    echo "⚠️  No gitops directory found, creating basic GitRepository..."
    
    cat > /tmp/git-repository.yaml << EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-chaos-repo
  namespace: flux-system
spec:
  interval: 1m
  url: ${GIT_URL}
  ref:
    branch: main
  ignore: |
    /*
    !/gitops/
EOF

    kubectl apply -f /tmp/git-repository.yaml
    
    echo "⏳ Waiting for GitRepository to be ready..."
    kubectl wait --for=condition=Ready gitrepository/gitops-chaos-repo -n flux-system --timeout=300s || echo "⚠️  GitRepository not ready yet"
fi
echo ""

# Step 7: Install Chaos Engineering tools  
echo "💥 Step 7/7: Installing Chaos Engineering tools..."

# Install Chaos Mesh using Helm (better for K3s)
echo "Installing Chaos Mesh..."
kubectl create namespace chaos-testing --dry-run=client -o yaml | kubectl apply -f -

# Install Chaos Mesh using kubectl
kubectl apply -f https://raw.githubusercontent.com/chaos-mesh/chaos-mesh/master/manifests/crd.yaml
kubectl apply -f https://raw.githubusercontent.com/chaos-mesh/chaos-mesh/master/manifests/chaos-mesh.yaml

echo "⏳ Waiting for Chaos Mesh to be ready..."
kubectl wait --for=condition=Available deployment/chaos-controller-manager -n chaos-testing --timeout=300s || {
    echo "⚠️  Chaos Mesh controller not ready yet, checking status..."
    kubectl get pods -n chaos-testing
}

echo "✅ Chaos Engineering tools installed"
echo ""

# Final verification
echo "🎉 Setup Complete!"
echo "=================================================="
echo ""
echo "📊 Cluster Status:"
kubectl get nodes
echo ""
echo "🔧 Flux Status:"
kubectl get fluxinstance -A 2>/dev/null || echo "No FluxInstances found"
echo ""
echo "📦 Deployed Resources:"
kubectl get pods -A | head -20
echo ""
echo "💥 Chaos Mesh Status:"
kubectl get pods -n chaos-testing 2>/dev/null || echo "Chaos Mesh not yet ready"
echo ""
echo "🌐 Next Steps:"
echo "  1. Check cluster status: kubectl get pods -A"
echo "  2. Monitor Flux: kubectl get gitrepositories,kustomizations -A"
echo "  3. Port forward services as needed"
echo "  4. Check logs if issues: kubectl logs -n flux-system deployment/source-controller"
echo ""
echo "✅ GitOps Chaos Engineering lab setup completed!"
echo "📋 If you encounter issues, check /tmp/k3s.log for K3s logs"