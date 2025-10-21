# GitOps Directory Structure and Deployment Architecture

This document provides an overview of the `gitops/` directory structure, component dependencies, and deployment orchestration for the Kubernetes GitOps Chaos Engineering platform.

## Directory Structure

```
gitops/
├── flux/                          # Flux CD configuration
│   └── fluxinstance.yaml         # Main Flux instance configuration
├── kustomizations/               # Flux Kustomization definitions
│   └── kustomization.yaml        # Master kustomization with dependency chain
├── cert-manager/                 # Certificate management
├── chaos-experiments/            # Chaos engineering experiment definitions
├── chaos-mesh/                   # Chaos Mesh operator and configuration
├── linkerd/                      # Linkerd service mesh
├── linkerd-certificates/         # Linkerd mTLS certificates
├── manifests/                    # Application manifests (backend/frontend)
├── monitoring/                   # Prometheus/Grafana monitoring stack
├── servicemonitor/               # ServiceMonitor CRDs for monitoring
└── reloader/                     # Configuration reloader for secrets/configmaps
```

## Detailed File Structure

```
gitops/
├── README.md                     # This documentation file
├── flux/
│   ├── kustomization.yaml        # Flux configuration orchestration
│   └── fluxinstance.yaml         # FluxCD Git sync configuration
├── kustomizations/               # Flux Kustomization definitions
│   ├── kustomization.yaml        # Master kustomization with dependency chain
│   ├── namespaces.yaml           # Kubernetes namespaces creation
│   ├── cert-manager-kustomization.yaml     # cert-manager deployment
│   ├── linkerd-certificates-kustomization.yaml   # Linkerd certificates
│   ├── linkerd-kustomization.yaml         # Linkerd service mesh
│   ├── manifests-kustomization.yaml       # Application manifests
│   ├── monitoring-kustomization.yaml      # Monitoring stack
│   ├── servicemonitor-kustomization.yaml  # ServiceMonitor CRDs
│   ├── reloader-kustomization.yaml        # Configuration reloader
│   ├── chaos-mesh-kustomization.yaml      # Chaos Mesh operator
│   └── chaos-experiments-kustomization.yaml   # Chaos experiments
├── cert-manager/                 # Certificate management
│   ├── kustomization.yaml        # cert-manager orchestration
│   ├── cert-manager-repo.yaml    # cert-manager Helm repository
│   └── cert-manager.yaml         # cert-manager installation
├── linkerd/                      # Linkerd service mesh
│   ├── kustomization.yaml        # Linkerd orchestration
│   ├── linkerd-repo.yaml         # Linkerd Helm repository
│   ├── linkerd-crds.yaml         # Linkerd CRDs
│   ├── linkerd-control-plane.yaml   # Linkerd control plane
│   └── linkerd-viz.yaml          # Linkerd visualization extension
├── linkerd-certificates/         # Linkerd mTLS certificates
│   ├── kustomization.yaml        # Certificate orchestration
│   └── linkerd-certificates.yaml # Certificate definitions with comments
├── manifests/                    # Application deployments
│   ├── kustomization.yaml        # Application orchestration
│   ├── namespaces.yaml           # Application namespaces
│   ├── backend.yaml              # Backend deployment
│   ├── frontend.yaml             # Frontend deployment
│   └── servicemonitor-apps.yaml  # Application monitoring
├── monitoring/                   # Prometheus/Grafana monitoring
│   ├── kustomization.yaml        # Monitoring orchestration
│   ├── helmrepo.yaml             # Prometheus Helm repository
│   ├── monitoring-stack.yaml     # Prometheus + Grafana stack
│   └── dashboards/
│       └── chaos-dashboard.yaml  # Custom Grafana dashboard
├── servicemonitor/               # ServiceMonitor CRs for monitoring
│   ├── kustomization.yaml        # Orchestration for ServiceMonitors
│   ├── chaos-servicemonitor.yaml # Chaos Mesh ServiceMonitor
│   └── flux-servicemonitor.yaml  # Flux controllers ServiceMonitor
├── reloader/                     # Configuration reloader
│   ├── kustomization.yaml        # Reloader orchestration
│   ├── stakater-helm-repo.yaml   # Reloader Helm repository
│   └── reloader.yaml             # Reloader installation
├── chaos-mesh/                   # Chaos Mesh operator
│   ├── kustomization.yaml        # Chaos Mesh orchestration
│   ├── chaosmesh-repo.yaml       # Chaos Mesh Helm repository
│   └── chaosmesh-install.yaml    # Chaos Mesh installation
└── chaos-experiments/            # Chaos engineering experiments
  ├── kustomization.yaml        # Chaos experiments orchestration
  ├── CHAOS-TESTING.md          # Chaos testing documentation
  ├── chaos-schedules.yaml      # Chaos experiment schedules
```

## Deployment Order and Dependencies

The platform follows a strict deployment order to ensure proper dependency resolution. Components are deployed sequentially using Flux Kustomizations with explicit dependency management.

### 1. Flux Operator Installation
**Location**: `scripts/deploy-k3d.sh` (Step 4)
**Purpose**: Installs the Flux Operator CRDs and controller
**Command**: `kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/install.yaml`
**Dependencies**: None
**Timeout**: 300s for deployment availability

### 2. Flux Instance Configuration
**Location**: `gitops/flux/fluxinstance.yaml`
**Purpose**: Configures the Flux instance to sync this repository
**Dependencies**: Flux Operator
**Configuration**:
- Repository URL: Current repository
- Branch: main
- Path: `gitops/`
- Sync Interval: 1m

### 3. Namespace Creation
**Location**: `gitops/kustomizations/namespaces.yaml`
**Purpose**: Creates all required Kubernetes namespaces
**Namespaces Created**:
- `app-backend`
- `app-frontend`
- `chaos-testing`
- `monitoring`
- `cert-manager`
- `linkerd`
- `linkerd-viz`
- `flux-system`
- `keda`


### 4. Monitoring Stack (Priority 1)
**Location**: `gitops/monitoring/`
**Purpose**: Deploys Prometheus, Grafana, and monitoring infrastructure
**Components**:
- Kube Prometheus Stack (Prometheus, Grafana, Alertmanager)
- Grafana dashboards for visualization
**Dependencies**: Namespaces
**Health Check**: `kubectl wait --for=condition=Ready helmrelease/kube-prometheus-stack -n monitoring`

### 4b. ServiceMonitor CRDs (Priority 1b)
**Location**: `gitops/servicemonitor/`
**Purpose**: Deploys ServiceMonitor resources for monitoring custom targets (e.g., Flux, Chaos Mesh)
**Components**:
- `chaos-servicemonitor.yaml`: ServiceMonitor for Chaos Mesh
- `flux-servicemonitor.yaml`: ServiceMonitor for Flux controllers
**Dependencies**: Monitoring stack (CRDs must exist)
**Dependency Handling**: Applied via `servicemonitor-kustomization.yaml` with `dependsOn: monitoring` in the master kustomization.

### 5. Reloader (Priority 2)
**Location**: `gitops/reloader/`
**Purpose**: Automatically restarts deployments when ConfigMaps/Secrets change
**Dependencies**: Monitoring (provides ServiceMonitor CRDs)
**Use Case**: Certificate rotation, configuration updates

### 6. cert-manager (Priority 3)
**Location**: `gitops/cert-manager/`
**Purpose**: Automated certificate management for TLS
**Components**:
- cert-manager controller
- ClusterIssuers for certificate authorities
- Certificate resources for Linkerd mTLS
**Dependencies**: Reloader
**Health Check**: `kubectl wait --for=condition=Ready helmrelease/cert-manager -n cert-manager`

### 7. Linkerd Certificates (Priority 4)
**Location**: `gitops/linkerd-certificates/`
**Purpose**: Issues certificates for Linkerd mTLS trust anchor
**Dependencies**: cert-manager
**Components**:
- Trust anchor certificate
- Identity issuer certificate
- Certificate rotation jobs

### 8. Linkerd Service Mesh (Priority 5)
**Location**: `gitops/linkerd/`
**Purpose**: Service mesh for observability and traffic management
**Components**:
- Control plane (destination, identity, proxy-injector)
- Data plane injection
- mTLS encryption
- Traffic metrics and visualization
**Dependencies**: Linkerd certificates
**Post-Deployment**:
- Trust anchor synchronization
- Control plane restart for certificate pickup
- Visualization extensions deployment

### 9. Application Manifests (Priority 6)
**Location**: `gitops/manifests/`
**Purpose**: Deploys the demo applications (backend and frontend)
**Components**:
- Backend deployment (FastAPI application)
- Frontend deployment (JavaScript application)
- Services and ingress resources
- Linkerd injection annotations
**Dependencies**: Linkerd (for service mesh injection)

### 10. Chaos Mesh (Priority 7)
**Location**: `gitops/chaos-mesh/`
**Purpose**: Chaos engineering operator for Kubernetes
**Components**:
- Chaos Mesh controller
- Chaos Dashboard
- CRDs for chaos experiments
**Dependencies**: Application manifests
**Health Check**: `kubectl wait --for=condition=Ready helmrelease/chaos-mesh -n chaos-testing`

### 11. Chaos Experiments (Priority 8)
**Location**: `gitops/chaos-experiments/`
**Purpose**: Pre-configured chaos engineering experiments
**Components**:
- Network chaos experiments
- Pod failure simulations
- CPU/memory stress tests
- Application-specific chaos scenarios
**Dependencies**: Chaos Mesh
**Experiments Include**:
- Backend pod failures
- Network latency injection
- Resource exhaustion tests

### 12. KEDA & ScaledObjects (Priority 9)
**Location**: `gitops/keda/` and `gitops/keda-scaledobjects/`
**Purpose**: Configure autoscaling via KEDA using Prometheus metrics or custom scalers. ScaledObjects are used to bind Prometheus queries to the scaler and to create HPA-like behavior when thresholds are met.
**Verification**:
```bash
# Check KEDA deployment
kubectl -n keda get pods

# List ScaledObjects
kubectl get scaledobject -A
```


## Flux Kustomization Dependencies

The master kustomization in `gitops/kustomizations/kustomization.yaml` defines the deployment order:

```yaml
resources:
  - namespaces.yaml                    # 1. Create namespaces
  - monitoring-kustomization.yaml      # 2. Deploy monitoring
  - servicemonitor-kustomization.yaml  # 3. Deploy ServiceMonitor CRDs
  - reloader-kustomization.yaml        # 4. Deploy reloader
  - cert-manager-kustomization.yaml    # 5. Deploy cert-manager
  - linkerd-certificates-kustomization.yaml  # 6. Issue Linkerd certs
  - linkerd-kustomization.yaml         # 7. Deploy Linkerd mesh
  - manifests-kustomization.yaml       # 8. Deploy applications
  - ingress-nginx-kustomization.yaml   # 9. Deploy ingress controller
  - keda-kustomization.yaml            # 10. Deploy KEDA operator
  - keda-scaled-objects-kustomization.yaml # 11. Deploy KEDA ScaledObjects
  - chaos-mesh-kustomization.yaml      # 12. Deploy Chaos Mesh
  - chaos-experiments-kustomization.yaml  # 13. Deploy experiments
```

Each kustomization includes health checks and depends on the previous component being ready. The ServiceMonitor CRs are now applied after the monitoring stack, ensuring CRDs are present.

## Component Usage

### Monitoring Stack
- **Grafana**: `http://grafana.127.0.0.1.traefik.me` (admin/prom-operator)

### Linkerd Service Mesh
- **Dashboard**: `http://linkerd.127.0.0.1.traefik.me`
- **Metrics API**: Internal service for metrics collection
- **mTLS**: Automatic encryption between services

### Chaos Mesh
- **Dashboard**: `http://chaos.127.0.0.1.traefik.me`
- **Experiments**: Defined in `gitops/chaos-experiments/`
- **Scheduling**: Cron-based experiment execution

### Applications
- **Frontend**: `http://frontend.127.0.0.1.traefik.me` (React SPA)

## Deployment Verification

After deployment, verify core components:

```bash
# Check Flux sync status
flux get kustomizations -A

# Check pod health
kubectl get pods -A

# Check certificate status (cert-manager)
kubectl get certificates -A

# Check chaos experiments and schedules
kubectl get schedules,networkchaos,stresschaos,podchaos -n chaos-testing
```

## Troubleshooting

### Common Issues

1. **Flux not syncing**: Check repository URL and branch in `fluxinstance.yaml`
2. **Certificate issues**: Verify cert-manager deployment and ClusterIssuer status
3. **Linkerd injection failures**: Check certificate validity and trust anchor sync
4. **Chaos experiments not running**: Verify Chaos Mesh installation and CRD availability

### Logs and Debugging

Use the standard kubectl logs and describe commands to inspect controllers and CRDs:

```bash
# Flux operator / controllers
kubectl -n flux-system get pods
kubectl -n flux-system logs deploy/flux-operator || kubectl -n flux-system logs deploy/flux

# cert-manager
kubectl -n cert-manager get pods
kubectl -n cert-manager logs deploy/cert-manager

# Linkerd
kubectl -n linkerd get pods
kubectl -n linkerd logs deploy/linkerd-identity

# Chaos Mesh
kubectl -n chaos-testing get pods
kubectl -n chaos-testing logs deploy/chaos-mesh-controller
```

## Architecture Benefits

1. **GitOps-Driven**: All changes are version-controlled and auditable
2. **Dependency Management**: Explicit ordering prevents deployment failures
3. **Observability**: Comprehensive monitoring and tracing
4. **Security**: mTLS encryption and certificate management
5. **Resilience Testing**: Automated chaos engineering experiments
6. **Scalability**: Modular architecture supports component updates

This architecture provides a complete chaos engineering platform with proper dependency management, security, and observability for testing application resilience in Kubernetes environments.