#!/bin/bash
set -e

echo "=================================================="
echo "🧹 GitOps Chaos Lab - Cluster Cleanup"
echo "=================================================="
echo ""

# Configuration
CLUSTER_NAME="gitops-chaos"

# Environment detection
if [ -n "$REMOTE_CONTAINERS" ] || [ -n "$CODESPACES" ] || [ -f /.dockerenv ]; then
    echo "🐳 Detected devcontainer/container environment"
    ENVIRONMENT="devcontainer"
    
    # Check if host .kube is mounted
    if [ -d "/host-kube" ]; then
        HOST_KUBE_PATH="/host-kube"
        echo "📂 Host .kube directory mounted at: ${HOST_KUBE_PATH}"
    else
        HOST_KUBE_PATH=""
        echo "⚠️  Host .kube directory not mounted"
    fi
else
    echo "💻 Detected local/host environment"
    ENVIRONMENT="localhost"
    
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

# Check if cluster exists
if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo "⚠️  Cluster '${CLUSTER_NAME}' does not exist. Nothing to clean up."
    exit 0
fi

echo "🗑️  Deleting k3d cluster: ${CLUSTER_NAME}"

# Remove context from host kubeconfig if accessible
if [ -n "$HOST_KUBE_PATH" ] && [ -f "$HOST_KUBE_PATH/config" ]; then
    echo "🏠 Cleaning up host kubeconfig..."
    
    # Backup host config
    cp "$HOST_KUBE_PATH/config" "$HOST_KUBE_PATH/config.backup.$(date +%Y%m%d-%H%M%S)"
    echo "  📋 Backed up host kubeconfig"
    
    # Remove the context, cluster, and user entries
    if command -v kubectl >/dev/null 2>&1; then
        KUBECONFIG="$HOST_KUBE_PATH/config" kubectl config delete-context "k3d-${CLUSTER_NAME}" 2>/dev/null || true
        KUBECONFIG="$HOST_KUBE_PATH/config" kubectl config delete-cluster "k3d-${CLUSTER_NAME}" 2>/dev/null || true
        KUBECONFIG="$HOST_KUBE_PATH/config" kubectl config delete-user "admin@k3d-${CLUSTER_NAME}" 2>/dev/null || true
        echo "  ✅ Removed k3d-${CLUSTER_NAME} context from host kubeconfig"
    fi
else
    echo "⚠️  Host kubeconfig cleanup skipped (not accessible or doesn't exist)"
fi

# Delete the k3d cluster
k3d cluster delete ${CLUSTER_NAME}
echo "✅ Cluster deleted successfully"

# Clean up local kubeconfig files
if [ -f "kubeconfig-host.yaml" ]; then
    rm -f kubeconfig-host.yaml
    echo "🗑️  Removed kubeconfig-host.yaml"
fi

if [ -f "kubeconfig-devcontainer.yaml" ]; then
    rm -f kubeconfig-devcontainer.yaml
    echo "🗑️  Removed kubeconfig-devcontainer.yaml"
fi

echo ""
echo "🎉 Cleanup completed!"
echo "   Your host's ~/.kube/config has been updated to remove the k3d cluster context."

# Remove kubeconfig backup files from host ~/.kube after cluster cleanup
if [ -n "$HOST_KUBE_PATH" ]; then
    echo "🧹 Cleaning up kubeconfig backup files from $HOST_KUBE_PATH..."
    find "$HOST_KUBE_PATH" -maxdepth 1 -type f -name 'config.backup.*' -exec rm -f {} \;
    echo "✅ Removed kubeconfig backups (config.backup.*) from $HOST_KUBE_PATH"
fi