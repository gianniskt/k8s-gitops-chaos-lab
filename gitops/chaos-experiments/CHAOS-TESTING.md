# 🎯 Linkerd Service Mesh Metrics Chaos Testing

## 📊 **Target Metrics & Expected Impacts**

### **HTTP Success Rate (100% → Variable)**
- **Target Metric**: `request_total{classification="success"}` / `request_total`
- **Chaos Experiments**:
  - `http-success-rate-impact`: 15% packet loss → Expect success rate drop to ~85%
  - `multi-pod-failure-mesh`: Kill 50% of pods → Load balancer compensation test
  - `linkerd-proxy-restart`: Kill pods with Linkerd proxy → Test mesh resilience
  - `traffic-loss-test`: 20% packet loss on traffic → Test traffic resilience

### **HTTP Latency (P50/P95)**
- **Target Metrics**: `response_latency_ms{quantile="0.5"}`, `response_latency_ms{quantile="0.95"}`  
- **Chaos Experiments**:
  - `http-latency-impact`: 100ms delay + 50ms jitter → P50: +100ms, P95: +150ms
  - `cpu-stress-latency`: 80% CPU load → Expect 2-5x latency increase
  - `memory-pressure-http`: 100Mi memory stress → Garbage collection delays
  - `traffic-latency-test`: 200ms delay on traffic → Test latency handling

### **TCP Connection Metrics**
  - `tcp-connection-disruption`: Network partition → Connection drops
  - `tcp-bandwidth-limit`: 1Mbps limit → Throughput reduction
  - `network-partition`: Complete network isolation → Test mesh routing
  - `container-kill-graceful`: Graceful pod termination → Test connection recovery

### **Service Mesh Resilience**
  - `linkerd-control-plane-test`: Kill destination controller → Test control plane HA
  - `linkerd-viz-resilience-test`: Kill viz components → Observability resilience
  - `linkerd-load-balancing-test`: Test load balancing under chaos
  - `linkerd-edge-case-test`: Test edge cases and failure scenarios
  - `linkerd-performance-stress-test`: Performance testing under stress

## 🚀 **Experiment Categories**

### **1. Chaos Experiments and Schedules**
```bash
# Apply all chaos schedules and experiments
kubectl apply -f gitops/chaos-experiments/chaos-schedules.yaml
# Optionally, apply service monitors for chaos metrics
kubectl apply -f gitops/chaos-experiments/chaos-servicemonitor.yaml
kubectl apply -f gitops/chaos-experiments/servicemonitor-flux.yaml

# Watch active chaos experiments
kubectl get podchaos,networkchaos,stresschaos,schedule -n chaos-testing
```

**Available Schedules and Experiments**:
- See `chaos-schedules.yaml` for current schedule definitions (e.g., StressChaos, NetworkChaos, PodChaos)
- See `chaos-servicemonitor.yaml` and `servicemonitor-flux.yaml` for Prometheus monitoring integration


### **2. Scheduled Chaos Experiments** (`chaos-schedules.yaml`)
```bash
# Apply all scheduled chaos experiments (run continuously)
kubectl apply -f gitops/chaos-experiments/chaos-schedules.yaml

# Watch scheduled experiments
kubectl get schedule -n chaos-testing
```

**Available Schedules**:
- See `chaos-schedules.yaml` for current schedule definitions (e.g., PodChaos, NetworkChaos, StressChaos)

## 📈 **Monitoring & Observation**

### **Linkerd Dashboard Metrics to Watch**
1. **Open Linkerd Dashboard**: http://linkerd.127.0.0.1.traefik.me
2. **Key Views**:
   - **Namespaces** → `app-backend` → Success rate graphs
   - **Deployments** → `backend` → Latency histograms  
   - **Live Traffic** → Real-time request metrics
   - **Top** → Traffic volume and error rates

### **Grafana Dashboard Metrics**
1. **Open Grafana**: http://grafana.127.0.0.1.traefik.me (admin/prom-operator)
2. **Linkerd Dashboards**:
   - **Linkerd Service** → HTTP success rate, latency percentiles
   - **Linkerd Namespace** → Traffic golden signals
   - **Linkerd Pod** → Per-pod metrics and proxy health

### **Prometheus Queries for Analysis**
```promql
# HTTP Success Rate
rate(request_total{classification="success"}[5m]) / rate(request_total[5m]) * 100

# P95 Latency 
histogram_quantile(0.95, rate(response_latency_ms_bucket[5m]))

# TCP Connection Count
tcp_open_connections{namespace="app-backend"}

# Request Rate
rate(request_total[5m])

# Error Rate  
rate(request_total{classification!="success"}[5m])
```

---

## 🎮 **Testing Scenarios**

### **Scenario 1: Baseline Metrics Capture**
```bash
# Before chaos - capture baseline
curl -s http://chaos.127.0.0.1.traefik.me/  # Ensure dashboard works
# Note: Success rate should be 100%, P95 latency < 50ms
```

### **Scenario 2: HTTP Success Rate Impact**
```bash
# Apply a network packet loss experiment (example)
kubectl apply -f- <<EOF
apiVersion: chaos-mesh.org/v1alpha1  
kind: NetworkChaos
metadata:
  name: test-success-rate
  namespace: chaos-testing
spec:
  action: loss
  mode: one
  selector:
    namespaces: ["app-backend"]
    labelSelectors: {"app": "backend"}
  loss:
    loss: "15"
  duration: "2m"
EOF

# Expected: Success rate drops to ~85%
# Watch: Linkerd dashboard namespace view
```

### **Scenario 3: Latency Degradation**
```bash
# Apply CPU stress experiment
kubectl apply -f- <<EOF  
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: test-latency
  namespace: chaos-testing
spec:
  mode: one
  selector:
    namespaces: ["app-backend"]
    labelSelectors: {"app": "backend"}
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "3m" 
EOF

# Expected: P95 latency increases 2-5x
# Watch: Linkerd service latency graphs
```

### **Scenario 4: Service Mesh Resilience**
```bash
# Kill backend pods while monitoring mesh
kubectl delete pod -l app=backend -n app-backend

# Expected: Brief spike in errors, then recovery via load balancing  
# Watch: Linkerd live traffic view
```

---

## 🔧 **Quick Commands**


### **Start All Chaos Experiments**
```bash
# Deploy all scheduled chaos experiments
kubectl apply -f gitops/chaos-experiments/chaos-schedules.yaml

# Deploy ServiceMonitors for metrics
kubectl apply -f gitops/chaos-experiments/chaos-servicemonitor.yaml
kubectl apply -f gitops/chaos-experiments/servicemonitor-flux.yaml
```

### **Monitor Active Chaos**
```bash
# List all active chaos experiments and schedules
kubectl get podchaos,networkchaos,stresschaos,schedule -n chaos-testing

# Watch pods being affected
kubectl get pods -n app-backend -w

# Check Chaos Mesh dashboard
echo "Chaos Mesh: http://chaos.127.0.0.1.traefik.me"
```

### **Stop All Chaos**
```bash
# Stop all chaos experiments and schedules
kubectl delete podchaos,networkchaos,stresschaos,schedule -n chaos-testing --all
```

---

## 🎯 **Expected Results**

| **Chaos Type** | **Linkerd Metric Impact** | **Expected Change** |
|---|---|---|
| Network Loss (15%) | HTTP Success Rate | 100% → 85% |
| Network Delay (100ms) | P95 Latency | <50ms → 150ms+ |
| CPU Stress (80%) | P50 Latency | <20ms → 100ms+ |
| Memory Pressure (100Mi) | Response Time | Sporadic spikes |
| Pod Kill (50%) | Request Rate | Brief spike down, recovery |
| TCP Partition | Connection Count | Drops to 0, reconnects |
| Bandwidth Limit (1Mbps) | Throughput | Significant reduction |
| Container Kill (Graceful) | Error Rate | Brief spike, recovery |