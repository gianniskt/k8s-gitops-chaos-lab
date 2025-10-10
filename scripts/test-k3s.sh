#!/bin/bash
set -e

echo "🧪 Testing K3s installation..."

# Test if K3s is available
if ! command -v k3s &> /dev/null; then
    echo "❌ K3s not found. Please install K3s first."
    echo "Run: curl -sfL https://get.k3s.io | sh -"
    exit 1
fi

echo "✅ K3s binary found"

# Test if we can start K3s (requires sudo)
if ! sudo -n true 2>/dev/null; then
    echo "⚠️  This test requires sudo access to start K3s"
    echo "Please run with sudo or configure passwordless sudo"
    exit 1
fi

echo "✅ Sudo access available"

# Check if K3s is already running
if pgrep -f "k3s server" > /dev/null; then
    echo "✅ K3s is already running"
    echo "Testing kubectl access..."
    
    if sudo k3s kubectl get nodes > /dev/null 2>&1; then
        echo "✅ kubectl access works"
        sudo k3s kubectl get nodes
    else
        echo "❌ kubectl access failed"
        exit 1
    fi
else
    echo "📋 K3s is not running. Use './scripts/deploy-k3s.sh' to start the full setup."
fi

echo ""
echo "🎉 K3s test completed successfully!"
echo "✨ Ready to run: ./scripts/deploy-k3s.sh"