#!/bin/bash
set -e

echo "🔧 Linkerd Dashboard Fix Script"
echo "==============================="
echo ""

echo "1️⃣ Checking Linkerd control plane status..."
kubectl get pods -n linkerd -l linkerd.io/control-plane-component

echo ""
echo "2️⃣ Checking trust anchor ConfigMap..."
if kubectl get configmap linkerd-identity-trust-roots -n linkerd >/dev/null 2>&1; then
    CA_BUNDLE=$(kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}')
    if [ -z "$CA_BUNDLE" ]; then
        echo "❌ ca-bundle.crt is empty - trust anchor sync needed"
        echo "   Running trust anchor sync job..."
        kubectl delete job linkerd-trust-sync-initial -n linkerd 2>/dev/null || true
        flux reconcile kustomization linkerd-certificates --with-source
        echo "   Waiting for trust sync job to complete..."
        kubectl wait --for=condition=Complete job/linkerd-trust-sync-initial -n linkerd --timeout=120s || echo "⚠️  Job may still be running"
    else
        echo "✅ ca-bundle.crt contains certificate data"
    fi
else
    echo "❌ Trust anchor ConfigMap not found"
    exit 1
fi

echo ""
echo "3️⃣ Restarting Linkerd control plane..."
kubectl rollout restart deployment -n linkerd
kubectl wait --for=condition=Available deployment/linkerd-destination -n linkerd --timeout=180s
kubectl wait --for=condition=Available deployment/linkerd-identity -n linkerd --timeout=180s
kubectl wait --for=condition=Available deployment/linkerd-proxy-injector -n linkerd --timeout=180s

echo ""
echo "4️⃣ Restarting Linkerd viz deployments..."
kubectl rollout restart deployment -n linkerd-viz
echo "   Waiting for viz deployments to be ready..."
kubectl wait --for=condition=Available deployment/metrics-api -n linkerd-viz --timeout=300s
kubectl wait --for=condition=Available deployment/prometheus -n linkerd-viz --timeout=300s
kubectl wait --for=condition=Available deployment/tap -n linkerd-viz --timeout=300s
kubectl wait --for=condition=Available deployment/tap-injector -n linkerd-viz --timeout=300s
kubectl wait --for=condition=Available deployment/web -n linkerd-viz --timeout=300s

echo ""
echo "5️⃣ Waiting for Linkerd viz components..."
echo "   Waiting specifically for Prometheus pod (takes longer to start)..."
kubectl wait --for=condition=Ready pod -l component=prometheus -n linkerd-viz --timeout=300s
echo "   Prometheus is ready! Waiting for web component..."
kubectl wait --for=condition=Ready pod -l component=web -n linkerd-viz --timeout=60s
echo "   All viz components are ready!"

echo ""
echo "6️⃣ Setting up port-forward..."
# Kill any existing port-forward
pkill -f "kubectl port-forward.*linkerd-viz.*8084" 2>/dev/null || true
# Start new port-forward in background
kubectl port-forward -n linkerd-viz service/web 8084:8084 &
PORT_FORWARD_PID=$!
echo "   Port-forward started with PID: $PORT_FORWARD_PID"
sleep 15

echo ""
echo "7️⃣ Testing dashboard access..."
echo "   Waiting for dashboard API to be ready..."
for i in {1..30}; do
    if curl -s -f http://localhost:8084/api/version > /dev/null; then
        echo "   ✅ Dashboard API is responding!"
        echo "   � Dashboard available at: http://localhost:8084"
        break
    else
        echo "   ⏳ Attempt $i/30: API not ready yet..."
        sleep 5
    fi
    if [ $i -eq 30 ]; then
        echo "   ❌ Dashboard API still not responding after 2.5 minutes"
        echo "   Check logs: kubectl logs deployment/web -n linkerd-viz"
    fi
done

echo ""
echo "🎉 Linkerd dashboard fix complete!"