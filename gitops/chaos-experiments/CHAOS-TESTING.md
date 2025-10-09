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
- **Target Metrics**: `tcp_open_connections`, `tcp_read_bytes_total`, `tcp_write_bytes_total`
- **Chaos Experiments**:
  - `tcp-connection-disruption`: Network partition → Connection drops
  - `tcp-bandwidth-limit`: 1Mbps limit → Throughput reduction
  - `network-partition`: Complete network isolation → Test mesh routing
  - `container-kill-graceful`: Graceful pod termination → Test connection recovery

### **Service Mesh Resilience**
- **Target Metrics**: Mesh proxy health, control plane metrics
- **Chaos Experiments**:
  - `linkerd-control-plane-test`: Kill destination controller → Test control plane HA
  - `linkerd-viz-resilience-test`: Kill viz components → Observability resilience
  - `linkerd-load-balancing-test`: Test load balancing under chaos
  - `linkerd-edge-case-test`: Test edge cases and failure scenarios
  - `linkerd-performance-stress-test`: Performance testing under stress

---

## 🚀 **Experiment Categories**

### **1. Individual Chaos Experiments** (`linkerd-metrics-chaos.yaml`)
```bash
# Apply individual experiments
kubectl apply -f gitops/chaos-experiments/linkerd-metrics-chaos.yaml

# Watch specific experiments
kubectl get podchaos,networkchaos,stresschaos -n chaos-testing
```

**Available Experiments**:
- `http-success-rate-impact`: Network packet loss (15%)
- `http-latency-impact`: Network delay injection (100ms + 50ms jitter)
- `cpu-stress-latency`: CPU resource exhaustion (80% load)
- `memory-pressure-http`: Memory stress testing (100Mi)
- `tcp-connection-disruption`: Network partitioning
- `tcp-bandwidth-limit`: Bandwidth limiting (1Mbps)
- `linkerd-proxy-restart`: Pod restart testing
- `multi-pod-failure-mesh`: Multi-pod failure (50% of pods)
- `network-partition`: Complete network isolation
- `container-kill-graceful`: Graceful container termination

### **2. Scheduled Chaos Experiments** (`linkerd-metrics-schedules.yaml`)
```bash
# Apply scheduled experiments (run continuously)
kubectl apply -f gitops/chaos-experiments/linkerd-metrics-schedules.yaml

# Watch scheduled experiments
kubectl get schedule -n chaos-testing
```

**Available Schedules**:
- `linkerd-http-success-rate-test`: Periodic HTTP success rate testing
- `linkerd-latency-impact-test`: Scheduled latency impact testing
- `linkerd-tcp-metrics-test`: TCP metrics monitoring
- `linkerd-performance-stress-test`: Performance stress testing
- `linkerd-load-balancing-test`: Load balancing validation
- `linkerd-edge-case-test`: Edge case scenario testing
- `linkerd-control-plane-test`: Control plane resilience testing
- `linkerd-viz-resilience-test`: Visualization component testing

### **3. Traffic Generation & Chaos** (`linkerd-traffic-chaos.yaml`)
```bash
# Apply traffic generator with chaos experiments
kubectl apply -f gitops/chaos-experiments/linkerd-traffic-chaos.yaml

# Monitor traffic patterns
kubectl logs -f deployment/traffic-generator -n chaos-testing
```

**Traffic Experiments**:
- `traffic-generator`: Continuous traffic generation to test mesh
- `traffic-latency-test`: Traffic with latency injection (200ms delay)
- `traffic-loss-test`: Traffic with packet loss (20% loss)

### **4. Scheduled Continuous Testing** (`linkerd-metrics-schedules.yaml`)
```bash
# Apply scheduled chaos
kubectl apply -f gitops/chaos-experiments/linkerd-metrics-schedules.yaml

# Monitor schedules
kubectl get schedules -n chaos-testing
```

**Schedule Pattern**:
- **Every 10 min**: HTTP success rate testing (pod kills)
- **Every 15 min**: Latency impact testing (network delays)
- **Every 20 min**: TCP metrics testing (packet loss)
- **Every 25 min**: Performance stress testing (CPU/memory)

### **5. Traffic Load + Chaos Workflows** (`linkerd-traffic-chaos.yaml`)
```bash
# Deploy traffic generator + chaos experiments
kubectl apply -f gitops/chaos-experiments/linkerd-traffic-chaos.yaml

# Monitor traffic generator
kubectl get pods -l app=traffic-generator -n chaos-testing

# Watch chaos experiments
kubectl get networkchaos -n chaos-testing
```

---

## 📈 **Monitoring & Observation**

### **Linkerd Dashboard Metrics to Watch**
1. **Open Linkerd Dashboard**: http://localhost:8084
2. **Key Views**:
   - **Namespaces** → `app-backend` → Success rate graphs
   - **Deployments** → `backend` → Latency histograms  
   - **Live Traffic** → Real-time request metrics
   - **Top** → Traffic volume and error rates

### **Grafana Dashboard Metrics**
1. **Open Grafana**: http://localhost:3000 (admin/prom-operator)
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
curl -s http://localhost:8084/api/version  # Ensure dashboard works
# Note: Success rate should be 100%, P95 latency < 50ms
```

### **Scenario 2: HTTP Success Rate Impact**
```bash
# Apply network packet loss experiment
kubectl apply -f gitops/chaos-experiments/linkerd-metrics-chaos.yaml

# Or apply specific experiment
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

### **Start All Linkerd Chaos Testing**
```bash
# Deploy all individual experiments
kubectl apply -f gitops/chaos-experiments/linkerd-metrics-chaos.yaml

# Deploy scheduled experiments (continuous testing)
kubectl apply -f gitops/chaos-experiments/linkerd-metrics-schedules.yaml  

# Deploy traffic generator with chaos
kubectl apply -f gitops/chaos-experiments/linkerd-traffic-chaos.yaml

# Scale up traffic generator for testing
kubectl scale deployment traffic-generator -n chaos-testing --replicas=2
```

### **Monitor Active Chaos**
```bash
# List all active chaos experiments
kubectl get podchaos,networkchaos,stresschaos,workflows,schedules -n chaos-testing

# Watch pods being affected
kubectl get pods -n app-backend -w

# Check chaos mesh dashboard
echo "Chaos Mesh: http://localhost:2333"
```

### **Stop All Chaos**
```bash
# Stop all chaos experiments
kubectl delete podchaos,networkchaos,stresschaos,workflows,schedules -n chaos-testing --all

# Scale down traffic generator  
kubectl scale deployment traffic-generator -n chaos-testing --replicas=0
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

**🔍 Perfect Chaos**: Look for metrics that show **temporary degradation** followed by **automatic recovery** - this indicates a resilient service mesh!