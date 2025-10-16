#!/bin/bash

# Manual Chaos Trigger Script
# Use this to immediately trigger chaos experiments without waiting for schedules

echo "🔥 Manual Chaos Experiment Triggers 🔥"
echo "======================================="

# Function to create immediate chaos experiments
trigger_chaos() {
    local chaos_type=$1
    local name=$2
    local experiment_yaml=$3
    
    echo "🎯 Triggering $chaos_type: $name"
    
    # Create temporary immediate experiment
    echo "$experiment_yaml" | kubectl apply -f -
    
    echo "✅ $name triggered successfully"
    echo "   Monitor with: kubectl get $chaos_type $name -n chaos-testing"
    echo "   View logs: kubectl describe $chaos_type $name -n chaos-testing"
    echo ""
}

# 1. CPU Stress (immediate, 3 minutes)
CPU_STRESS_YAML='
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: immediate-cpu-stress
  namespace: chaos-testing
  labels:
    purpose: "immediate-testing"
spec:
  selector:
    namespaces:
      - app-backend
    labelSelectors:
      app: backend
  mode: all
  stressors:
    cpu:
      workers: 16
      load: 90
  duration: "3m"
'

# 2. Memory Stress (immediate, 3 minutes)
MEMORY_STRESS_YAML='
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: immediate-memory-stress
  namespace: chaos-testing
  labels:
    purpose: "immediate-testing"
spec:
  selector:
    namespaces:
      - app-backend
    labelSelectors:
      app: backend
  mode: one
  stressors:
    memory:
      workers: 1
      size: "128MiB"
  duration: "3m"
'

# 3. Network Latency (immediate, 2 minutes)
LATENCY_YAML='
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: immediate-latency-test
  namespace: chaos-testing
  labels:
    purpose: "immediate-testing"
spec:
  selector:
    namespaces:
      - app-backend
    labelSelectors:
      app: backend
  mode: one
  action: delay
  delay:
    latency: "400ms"
    correlation: "100"
    jitter: "200ms"
  duration: "2m"
  direction: to
'

# 4. Pod Kill (immediate)
POD_KILL_YAML='
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: immediate-pod-kill
  namespace: chaos-testing
  labels:
    purpose: "immediate-testing"
spec:
  selector:
    namespaces:
      - app-backend
    labelSelectors:
      app: backend
  mode: one
  action: pod-kill
  duration: "0s"
'

# Menu for selecting chaos type
echo "Select chaos experiment to trigger immediately:"
echo "1) CPU Stress (3 minutes) - Triggers KEDA CPU scaling"
echo "2) Memory Stress (3 minutes) - Triggers KEDA memory scaling"  
echo "3) Network Latency (2 minutes) - Triggers KEDA latency scaling"
echo "4) Pod Kill (instant) - Triggers KEDA error rate scaling"
echo "5) All experiments (sequential)"
echo "6) Cleanup all immediate experiments"
echo ""
read -p "Enter choice (1-6): " choice

case $choice in
    1)
        trigger_chaos "stresschaos" "immediate-cpu-stress" "$CPU_STRESS_YAML"
        echo "💡 Watch KEDA scaling: kubectl get pods -n app-backend -w"
        echo "💡 Check CPU metrics: kubectl top nodes && kubectl top pods -n app-backend"
        ;;
    2)
        trigger_chaos "stresschaos" "immediate-memory-stress" "$MEMORY_STRESS_YAML"
        echo "💡 Watch KEDA scaling: kubectl get pods -n app-backend -w"
        echo "💡 Check memory metrics: kubectl top pods -n app-backend"
        ;;
    3)
        trigger_chaos "networkchaos" "immediate-latency-test" "$LATENCY_YAML"
        echo "💡 Watch KEDA scaling: kubectl get pods -n app-frontend -w"
        echo "💡 Test latency: time curl -s http://frontend.127.0.0.1.nip.io/"
        ;;
    4)
        trigger_chaos "podchaos" "immediate-pod-kill" "$POD_KILL_YAML"
        echo "💡 Watch pod recovery: kubectl get pods -n app-backend -w"
        echo "💡 Watch KEDA scaling: kubectl get pods -n app-frontend -w"
        ;;
    5)
        echo "🚀 Triggering ALL experiments sequentially..."
        trigger_chaos "podchaos" "immediate-pod-kill" "$POD_KILL_YAML"
        sleep 30
        trigger_chaos "stresschaos" "immediate-cpu-stress" "$CPU_STRESS_YAML"
        sleep 60
        trigger_chaos "networkchaos" "immediate-latency-test" "$LATENCY_YAML"
        sleep 60
        trigger_chaos "stresschaos" "immediate-memory-stress" "$MEMORY_STRESS_YAML"
        echo "💡 Watch overall impact: kubectl get pods -A -w"
        ;;
    6)
        echo "🧹 Cleaning up immediate experiments..."
        kubectl delete stresschaos immediate-cpu-stress -n chaos-testing 2>/dev/null || true
        kubectl delete stresschaos immediate-memory-stress -n chaos-testing 2>/dev/null || true
        kubectl delete networkchaos immediate-latency-test -n chaos-testing 2>/dev/null || true
        kubectl delete podchaos immediate-pod-kill -n chaos-testing 2>/dev/null || true
        echo "✅ Cleanup completed"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "📊 Useful monitoring commands:"
echo "   kubectl get scaledobjects -A"
echo "   kubectl describe scaledobjects -n app-backend"
echo "   kubectl describe scaledobjects -n app-frontend"
echo "   kubectl logs -l app.kubernetes.io/name=keda-operator -n keda -f"
echo ""
echo "🌐 Dashboard URLs (with port-forward):"
echo "   Grafana: https://grafana.127.0.0.1.nip.io/"
echo "   Chaos Mesh: https://chaos.127.0.0.1.nip.io/"
echo "   Linkerd: https://linkerd-viz.127.0.0.1.nip.io/"