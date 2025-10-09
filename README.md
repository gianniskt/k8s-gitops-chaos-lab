# GitOps Chaos Engineering Demo

A Kubernetes chaos engineering lab using GitOps for continuous deployment and automated resilience testing.

## Architecture Overview

![GitOps Chaos Engineering Architecture](k8s-chaos-gitops-diagram.png)

## What This Repo Contains

- **Applications**: Python backend + HTML frontend microservices
- **GitOps**: FluxCD configuration for automated deployments
- **Chaos Engineering**: Chaos Mesh schedules that kill pods every minute
- **Monitoring**: Prometheus + Grafana dashboards for observability
- **Deployment**: One-command setup script for local Kind cluster

## What It Does

1. **Deploys microservices** using FluxCD GitOps from this Git repository
2. **Automatically kills backend pods** every minute using Chaos Mesh Schedule
3. **Monitors chaos impact** with Prometheus metrics and Grafana dashboards
4. **Self-heals** through Kubernetes Deployment controllers (pods auto-restart)
5. **Syncs changes** - any Git commits automatically deploy to cluster

## Quick Start

```bash
# Clone and deploy everything (auto-installs prerequisites)
git clone https://github.com/gianniskt/k8s-gitops-chaos-lab.git
cd k8s-gitops-chaos-lab
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

**No manual installation needed!** The script automatically detects and installs:
- **Docker** (Linux: apt/yum, macOS: Homebrew, Windows: manual prompt)
- **Kind** (Kubernetes in Docker)
- **kubectl** (Kubernetes CLI)
- **Helm** (Package manager)
- **Flux CLI** (GitOps status and management)

The script will:
- Create Kind cluster `gitops-chaos`
- Build and load Docker images locally
- Install FluxCD Operator
- Deploy GitOps components (Flux, cert-manager, Linkerd service mesh, monitoring stack)
- Deploy applications (backend, frontend microservices)
- Deploy chaos engineering experiments and schedules
- Configure monitoring and observability dashboards

## Access Dashboards

```bash
# Grafana (monitoring)
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Open: http://localhost:3000 (admin/prom-operator)

# Linkerd (service mesh observability)
kubectl port-forward svc/web -n linkerd-viz 8084:8084
# Open: http://localhost:8084

# Chaos Mesh (experiments)  
kubectl port-forward svc/chaos-dashboard -n chaos-testing 2333:2333
# Open: http://localhost:2333 (copy/paste chaos token from output)
```

## Watch Chaos in Action

```bash
# Watch pods getting killed
kubectl get pods -n app-backend -w

# Check chaos schedule status
kubectl get schedule -n chaos-testing
```

## Project Structure

```
k8s-gitops-chaos-lab/
├── scripts/
│   ├── deploy.sh                # One-command deployment script
│   └── fix-linkerd-dashboard.sh # Linkerd dashboard troubleshooting script
├── app/
│   ├── backend/                 # Python Flask microservice
│   └── frontend/                # Static HTML frontend
└── gitops/
    ├── flux/
    │   ├── kustomization.yaml   # Flux configuration orchestration
    │   └── fluxinstance.yaml    # FluxCD Git sync configuration
    ├── manifests/
    │   ├── kustomization.yaml   # Main GitOps orchestration
    │   ├── namespaces.yaml      # Kubernetes namespaces
    │   ├── backend.yaml         # Backend app deployment
    │   ├── frontend.yaml        # Frontend app deployment
    │   └── chaos-experiments-kustomization.yaml  # Dependent kustomization
    ├── chaos-mesh/
    │   ├── kustomization.yaml   # Chaos Mesh orchestration
    │   ├── chaosmesh-repo.yaml  # Helm repository
    │   └── chaosmesh-install.yaml  # Chaos Mesh installation
    ├── monitoring/
    │   ├── kustomization.yaml   # Monitoring orchestration
    │   ├── helmrepo.yaml        # Prometheus Helm repository
    │   ├── monitoring-stack.yaml  # Prometheus + Grafana stack
    │   └── dashboards/
    │       └── chaos-dashboard.yaml  # Custom Grafana dashboard
    └── chaos-experiments/
        ├── kustomization.yaml   # Chaos experiments orchestration
        ├── pod-chaos.yaml       # One-time pod kill chaos
        ├── pod-chaos-schedule.yaml  # Scheduled pod kills (every 1min)
        └── chaos-servicemonitor.yaml  # Prometheus monitoring integration
```

## Cleanup

```bash
kind delete cluster --name gitops-chaos
```

**Note**: You can redeploy everything by running `./scripts/deploy.sh` again.

---

**Stack**: Kind • FluxCD • Chaos Mesh • Linkerd • Prometheus • Grafana • cert-manager • Reloader • Docker