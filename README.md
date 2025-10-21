# GitOps Chaos Engineering Demo

Kubernetes GitOps Homelab with Flux, Linkerd, Cert-Manager, Chaos Mesh & Prometheus

## Architecture Overview

![GitOps Chaos Engineering Architecture](k8s-chaos-gitops-diagram.png)

## What This Repo Contains

- **Applications**: FastAPI backend + JavaScript frontend microservices
- **GitOps**: FluxCD configuration for automated deployments
- **Chaos Engineering**: Chaos Mesh schedules and experiments
- **Monitoring**: Prometheus + Grafana dashboards for observability
- **Ingress**: Nginx ingress controller for external access
- **Service Mesh**: Linkerd for observability and mTLS
- **Autoscaling**: KEDA ScaledObjects wired to Prometheus metrics and optionally triggered by chaos experiments
- **Deployment**: One-command setup script for local k3d (recommended)

## What It Does


1. **Creates K3d Cluster** using K3d Cli
2. **Deploys microservices** using FluxCD GitOps from this Git repository
3. **Apply Chaos Experiments** regarding pods, network and other k8s components
4. **Monitors chaos impact** with Prometheus metrics and Grafana dashboards
5. **Auto-scales applications** through KEDA when chaos experiments trigger load changes
6. **Self-heals** through Kubernetes Deployment controllers and service mesh
7. **Syncs changes** - any Git commits automatically deploy to cluster

## Quick Start

### Option 1: Local Installation (Auto-Setup)

- Fork current repository: https://github.com/gianniskt/k8s-gitops-chaos-lab.git
```bash
cd k8s-gitops-chaos-lab
chmod +x scripts/
./scripts/deploy-k3d.sh
# Insert your github username when prompted, and your github repo name if you change it after fork.
```

### Option 2: DevContainer (Recommended for Windows/Complex Setups)

You can use devcontainer.json which pulls the [gianniskt/azure-gitops-image](https://github.com/gianniskt/azure-gitops-image):

```bash
# 1. Open k8s-gitops-chaos-lab in VS Code
# Press F1 → "Dev Containers: Reopen in Container"

# 2. Run k3d deployment inside devcontainer
./scripts/deploy-k3d.sh
# Insert your github username when prompted, and your github repo name if you change it after fork.
```

### Alternative: DevContainer CLI
```bash
# Rebuild and open using DevContainer CLI
devcontainer rebuild --workspace-folder . && devcontainer open --workspace-folder .
``` 

### What Gets Installed
- **k3d** (K3s in Docker)
- **kubectl** (Kubernetes CLI)
- **Helm** (Package manager)
- **Flux CLI** (GitOps status and management)

The k3d script will:
- Create k3d cluster (K3s in Docker containers)
- Build container images and import them into k3d
	- The script re-exports the k3d kubeconfig after import to avoid transient API routing issues
- Install FluxCD Operator
- Deploy GitOps components (Flux, cert-manager, Linkerd service mesh, KEDA, monitoring stack, ingress-nginx)
- Deploy applications (FastAPI backend, JavaScript frontend microservices)
- Deploy chaos engineering experiments and schedules
- Configure monitoring and observability dashboards

## Access Dashboards and Services

All services are accessible via traefik.me domains (no port-forwarding needed):

```bash
# Grafana (monitoring)
open http://grafana.127.0.0.1.traefik.me
# Login: admin/prom-operator
# Navigate to Dashboards: "Chaos Engineering Dashboard"

# Linkerd (service mesh observability)
open http://linkerd.127.0.0.1.traefik.me

# Chaos Mesh (experiments)
open http://chaos.127.0.0.1.traefik.me
# Use token from script output

# Frontend UI (demo application)
open http://frontend.127.0.0.1.traefik.me
# Click "Fetch Message from Backend" to test connectivity
```

## Watch Chaos in Action

```bash
# Watch pods getting killed
kubectl get pods -n app-backend -w

# Check chaos schedule status
kubectl get schedule -n chaos-testing

# Check KEDA ScaledObjects (if deployed)
kubectl get scaledobject -A || true
```

## Project Structure

```
k8s-gitops-chaos-lab/
├── scripts/                    # Deployment and troubleshooting scripts
├── app/                        # Demo applications (backend/frontend microservices)
└── gitops/                     # GitOps configurations and Kubernetes manifests
```

## Cleanup

```bash
cd k8s-gitops-chaos-lab
./scripts/cleanup-k3d.sh
```

**Note**: You can redeploy everything by running `./scripts/deploy-k3d.sh` again.

---

**Stack**: K3d • FluxCD • Chaos Mesh • Linkerd • Prometheus • Grafana • cert-manager • KEDA • Reloader • ingress-nginx