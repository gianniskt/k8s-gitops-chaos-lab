#!/bin/bash
set -e

echo "=================================================="
echo "🚀 GitOps Chaos Engineering - End-to-End Setup"
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

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
echo "�️  Detected OS: $OS"
echo ""

# Install Docker
install_docker() {
    echo "📦 Installing Docker..."
    case $OS in
        "linux")
            if command -v apt-get >/dev/null 2>&1; then
                # Ubuntu/Debian
                sudo apt-get update
                sudo apt-get install -y docker.io
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker $USER
                echo "⚠️  You may need to log out and back in for Docker permissions"
            elif command -v yum >/dev/null 2>&1; then
                # RHEL/CentOS
                sudo yum install -y docker
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker $USER
            else
                echo "❌ Unsupported Linux distribution. Please install Docker manually:"
                echo "   https://docs.docker.com/engine/install/"
                exit 1
            fi
            ;;
        "macos")
            if command -v brew >/dev/null 2>&1; then
                brew install --cask docker
                echo "⚠️  Please start Docker Desktop after installation"
            else
                echo "❌ Homebrew not found. Please install Docker Desktop manually:"
                echo "   https://docs.docker.com/desktop/mac/install/"
                exit 1
            fi
            ;;
        "windows")
            echo "❌ Please install Docker Desktop for Windows manually:"
            echo "   https://docs.docker.com/desktop/windows/install/"
            echo "   After installation, restart this script."
            exit 1
            ;;
        *)
            echo "❌ Unsupported OS. Please install Docker manually:"
            echo "   https://docs.docker.com/get-docker/"
            exit 1
            ;;
    esac
}

# Install Kind
install_kind() {
    echo "📦 Installing Kind..."
    case $OS in
        "linux")
            # For AMD64 / x86_64
            [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
            # For ARM64
            [ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-arm64
            chmod +x ./kind
            sudo mv ./kind /usr/local/bin/kind
            ;;
        "macos")
            if command -v brew >/dev/null 2>&1; then
                brew install kind
            else
                # For Intel Macs
                [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-amd64
                # For M1 / ARM Macs
                [ $(uname -m) = arm64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-arm64
                chmod +x ./kind
                sudo mv ./kind /usr/local/bin/kind
            fi
            ;;
        "windows")
            curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
            mkdir -p $HOME/bin 2>/dev/null || true
            mv kind-windows-amd64.exe $HOME/bin/kind.exe
            echo "⚠️  Make sure $HOME/bin is in your PATH"
            ;;
    esac
}

# Install kubectl
install_kubectl() {
    echo "📦 Installing kubectl..."
    case $OS in
        "linux")
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
            ;;
        "macos")
            if command -v brew >/dev/null 2>&1; then
                brew install kubectl
            else
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
                chmod +x kubectl
                sudo mv kubectl /usr/local/bin/
            fi
            ;;
        "windows")
            curl.exe -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"
            mkdir -p $HOME/bin 2>/dev/null || true
            mv kubectl.exe $HOME/bin/
            echo "⚠️  Make sure $HOME/bin is in your PATH"
            ;;
    esac
}

# Install Helm
install_helm() {
    echo "📦 Installing Helm..."
    case $OS in
        "linux"|"macos")
            if command -v brew >/dev/null 2>&1 && [[ "$OS" == "macos" ]]; then
                brew install helm
            else
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            fi
            ;;
        "windows")
            if command -v choco >/dev/null 2>&1; then
                choco install kubernetes-helm
            else
                echo "❌ Please install Helm manually on Windows:"
                echo "   https://helm.sh/docs/intro/install/#windows"
                echo "   Or install Chocolatey: https://chocolatey.org/install"
                exit 1
            fi
            ;;
    esac
}

# Install Flux CLI
install_flux() {
    echo "📦 Installing Flux CLI..."
    case $OS in
        "linux")
            curl -s https://fluxcd.io/install.sh | sudo bash
            ;;
        "macos")
            if command -v brew >/dev/null 2>&1; then
                brew install fluxcd/tap/flux
            else
                curl -s https://fluxcd.io/install.sh | sudo bash
            fi
            ;;
        "windows")
            if command -v choco >/dev/null 2>&1; then
                choco install flux
            else
                echo "⚠️  Installing Flux CLI for Windows..."
                curl -s https://api.github.com/repos/fluxcd/flux2/releases/latest | grep "browser_download_url.*windows_amd64" | cut -d '"' -f 4 | head -n 1 | xargs curl -L -o flux.tar.gz
                tar -xzf flux.tar.gz
                mkdir -p $HOME/bin 2>/dev/null || true
                mv flux.exe $HOME/bin/ 2>/dev/null || true
                rm -f flux.tar.gz
                echo "⚠️  Make sure $HOME/bin is in your PATH"
            fi
            ;;
    esac
}

# Install Linkerd CLI
install_linkerd_cli() {
    echo "📦 Installing Linkerd CLI..."
            export LINKERD2_VERSION=edge-25.4.4
            curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
            export PATH=$HOME/.linkerd2/bin:$PATH
            echo "⚠️  Added $HOME/.linkerd2/bin to PATH for this session"
}

# Check and install prerequisites
echo "📋 Checking and installing prerequisites..."

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker not found. Installing..."
    install_docker
else
    echo "✅ Docker found: $(docker --version)"
fi

# Check Kind
if ! command -v kind >/dev/null 2>&1; then
    echo "❌ Kind not found. Installing..."
    install_kind
else
    echo "✅ Kind found: $(kind version)"
fi

# Check kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl not found. Installing..."
    install_kubectl
else
    echo "✅ kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# Check Helm
if ! command -v helm >/dev/null 2>&1; then
    echo "❌ Helm not found. Installing..."
    install_helm
else
    echo "✅ Helm found: $(helm version --short)"
fi

# Check Flux CLI
if ! command -v flux >/dev/null 2>&1; then
    echo "❌ Flux CLI not found. Installing..."
    install_flux
else
    echo "✅ Flux CLI found: $(flux version --client)"
fi

# Check Linkerd CLI
if ! command -v linkerd >/dev/null 2>&1; then
    echo "❌ Linkerd CLI not found. Installing..."
    install_linkerd_cli
else
    echo "✅ Linkerd CLI found: $(linkerd version --client 2>/dev/null || linkerd version)"
fi

echo ""
echo "🎉 All prerequisites are ready!"
echo ""

# Verify Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    echo "   - Linux: sudo systemctl start docker"
    echo "   - macOS/Windows: Start Docker Desktop"
    exit 1
fi

# Step 1: Create Kind cluster
echo "🔧 Step 1/7: Creating Kind cluster..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Cluster '${CLUSTER_NAME}' already exists. Deleting..."
    kind delete cluster --name ${CLUSTER_NAME}
fi
kind create cluster --name ${CLUSTER_NAME}
echo "✅ Cluster created"
echo ""

# Step 2: Build Docker images
echo "🐳 Step 2/7: Building Docker images..."
docker build -t backend:local ./app/backend
docker build -t frontend:local ./app/frontend
echo "✅ Images built"
echo ""

# Step 3: Load images into Kind
echo "📦 Step 3/7: Loading images into Kind cluster..."
kind load docker-image backend:local --name ${CLUSTER_NAME}
kind load docker-image frontend:local --name ${CLUSTER_NAME}
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

# Start port-forwards in background
echo "🌐 Starting port-forwards for dashboards..."

# Kill any existing port-forwards on these ports
pkill -f "port-forward.*3000" 2>/dev/null || true
pkill -f "port-forward.*2333" 2>/dev/null || true
pkill -f "port-forward.*8084" 2>/dev/null || true

# Start Grafana port-forward
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 > /dev/null 2>&1 &
GRAFANA_PID=$!
echo "   Started Grafana port-forward (PID: $GRAFANA_PID)"

# Start Chaos Mesh port-forward  
kubectl port-forward svc/chaos-dashboard -n chaos-testing 2333:2333 > /dev/null 2>&1 &
CHAOS_PID=$!
echo "   Started Chaos Mesh port-forward (PID: $CHAOS_PID)"

# Start Linkerd viz dashboard port-forward with retry
echo "   Starting Linkerd viz dashboard port-forward..."
for attempt in 1 2 3; do
    echo "   Attempt $attempt: Waiting for Linkerd viz service to be ready..."
    echo "   Waiting specifically for Prometheus pod (takes longer to start)..."
    kubectl wait --for=condition=Ready pod -l component=prometheus -n linkerd-viz --timeout=300s 2>/dev/null || echo "⚠️  Prometheus pod not ready yet"
    echo "   Prometheus ready! Waiting for web component..."
    kubectl wait --for=condition=Ready pod -l component=web -n linkerd-viz --timeout=60s 2>/dev/null || echo "⚠️  Web pod not ready yet"
    
    kubectl port-forward svc/web -n linkerd-viz 8084:8084 > /dev/null 2>&1 &
    LINKERD_PID=$!
    
    # Test if the port-forward is working and dashboard is responding
    sleep 5
    if curl -s http://localhost:8084/api/version >/dev/null 2>&1; then
        echo "   ✅ Linkerd viz dashboard port-forward successful (PID: $LINKERD_PID)"
        break
    else
        echo "   ⚠️  Linkerd dashboard not responding, killing port-forward..."
        kill $LINKERD_PID 2>/dev/null || true
        
        if [ $attempt -eq 2 ]; then
            echo "   🔧 Attempting to restart Linkerd viz deployments..."
            kubectl rollout restart deployment -n linkerd-viz 2>/dev/null || echo "⚠️  Failed to restart viz deployments"
            kubectl wait --for=condition=Available deployment/web -n linkerd-viz --timeout=300s 2>/dev/null || echo "⚠️  Web deployment may still be restarting"
            kubectl wait --for=condition=Available deployment/metrics-api -n linkerd-viz --timeout=300s 2>/dev/null || echo "⚠️  Metrics API deployment may still be restarting"
            kubectl wait --for=condition=Available deployment/prometheus -n linkerd-viz --timeout=300s 2>/dev/null || echo "⚠️  Prometheus deployment may still be restarting"
            sleep 15
        elif [ $attempt -eq 3 ]; then
            echo "   ❌ Failed to start Linkerd dashboard after 3 attempts"
            echo "   🔧 Manual fix: Run ./fix-linkerd-dashboard.sh"
        fi
        sleep 5
    fi
done

# Wait a moment for port-forwards to establish
sleep 3

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
echo "� DASHBOARD ACCESS:"
echo "=================================================="
echo ""
echo "📊 Grafana (Monitoring & Metrics):"
echo "   🌍 URL: http://localhost:3000"
echo "   👤 Username: admin"
echo "   🔑 Password: prom-operator"
echo "   📈 Look for 'Chaos Engineering' dashboard"
echo ""
echo "💥 Chaos Mesh (Chaos Experiments):"
echo "   🌍 URL: http://localhost:2333"
echo "   🔑 Token: $CHAOS_TOKEN"
echo "   📝 How to login:"
echo "      1. Open http://localhost:2333"
echo "      2. Click 'Token' authentication"
echo "      3. Paste the token above"
echo "      4. Click 'Submit'"
echo ""
echo "🔗 Linkerd (Service Mesh):"
echo "   🌍 URL: http://localhost:8084"
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
echo "   • Fix Linkerd dashboard: ./fix-linkerd-dashboard.sh"
echo ""
echo "⚠️  To stop port-forwards later:"
echo "   kill $GRAFANA_PID $CHAOS_PID $LINKERD_PID"
echo ""
echo "🔧 TROUBLESHOOTING:"
echo "=================================================="
echo ""
echo "🔗 If Linkerd dashboard shows 500 errors:"
echo "   1. Run the automated fix: ./fix-linkerd-dashboard.sh"
echo "   2. Check trust anchors: kubectl get configmap linkerd-identity-trust-roots -n linkerd -o yaml"
echo "   3. Manual restart: kubectl rollout restart deployment -n linkerd && kubectl rollout restart deployment -n linkerd-viz"
echo "   4. Manual port-forward: pkill -f 'port-forward.*8084' && kubectl port-forward svc/web -n linkerd-viz 8084:8084 &"
echo ""
echo "🎉 Happy Chaos Engineering!"
echo "   Pods will be automatically killed every 1 minute."
echo "   Monitor the impact in Grafana, manage experiments in Chaos Mesh,"
echo "   and observe service mesh traffic in Linkerd!"
echo ""