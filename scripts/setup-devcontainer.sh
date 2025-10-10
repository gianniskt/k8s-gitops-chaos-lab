#!/bin/bash
set -e

echo "=================================================="
echo "🚀 Setting up GitOps Chaos Lab Environment"
echo "=================================================="

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Make sure Docker is installed and available."
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "❌ Docker daemon is not running. Starting Docker..."
    sudo service docker start || {
        echo "❌ Failed to start Docker. Please check your Docker installation."
        exit 1
    }
fi

# Add current user to docker group if not already
if ! groups | grep -q docker; then
    echo "🔧 Adding user to docker group..."
    sudo usermod -aG docker $(whoami)
    echo "⚠️  You may need to restart your shell or devcontainer for docker group changes to take effect"
fi

# Verify Docker access
echo "🐳 Verifying Docker access..."
if docker ps &> /dev/null; then
    echo "✅ Docker is accessible"
else
    echo "❌ Docker is not accessible. You may need to restart the devcontainer."
    exit 1
fi

# Check if Kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ Kind not found. Installing Kind..."
    # Kind should be installed in the base image, but just in case
    KIND_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
    chmod +x kind
    sudo mv kind /usr/local/bin/
    echo "✅ Kind installed"
else
    echo "✅ Kind is available"
fi

# Check other required tools
echo "🔧 Verifying required tools..."
for tool in kubectl helm flux; do
    if command -v $tool &> /dev/null; then
        echo "✅ $tool is available"
    else
        echo "❌ $tool not found. Please check the base image."
    fi
done

echo ""
echo "=================================================="
echo "✅ Environment setup complete!"
echo "=================================================="
echo ""
echo "🚀 Ready to deploy GitOps Chaos Lab!"
echo ""
echo "📝 Next steps:"
echo "   1. Run: cd /workspaces/k8s-gitops-chaos-lab"
echo "   2. Run: ./scripts/deploy.sh"
echo ""
echo "💡 Quick commands:"
echo "   • Check Docker: docker ps"
echo "   • Check Kind clusters: kind get clusters"
echo "   • Check kubectl: kubectl version --client"
echo ""