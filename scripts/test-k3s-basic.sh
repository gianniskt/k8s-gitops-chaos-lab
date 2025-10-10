#!/bin/bash
set -e

echo "🧪 Testing K3s Basic Setup..."

# Clean start
sudo pkill -f "k3s server" 2>/dev/null || true
sudo rm -rf /var/lib/rancher/k3s 2>/dev/null || true
sudo rm -rf /etc/rancher/k3s 2>/dev/null || true

echo "Starting K3s server..."
sudo k3s server \
    --disable traefik \
    --disable servicelb \
    --write-kubeconfig-mode 644 \
    --data-dir /var/lib/rancher/k3s \
    > /tmp/k3s-test.log 2>&1 &

K3S_PID=$!
echo "K3s started with PID: $K3S_PID"

# Wait for kubeconfig
echo "⏳ Waiting for kubeconfig..."
for i in {1..30}; do
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        echo "✅ Kubeconfig found"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Timeout waiting for kubeconfig"
        tail -10 /tmp/k3s-test.log
        exit 1
    fi
    sleep 2
done

# Setup user kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Test kubectl
echo "⏳ Testing kubectl access..."
for i in {1..20}; do
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✅ kubectl access works!"
        kubectl get nodes
        break
    fi
    if [ $i -eq 20 ]; then
        echo "❌ kubectl access failed"
        tail -10 /tmp/k3s-test.log
        exit 1
    fi
    sleep 3
done

echo "🎉 K3s basic test successful!"
echo "To stop: sudo pkill -f 'k3s server'"