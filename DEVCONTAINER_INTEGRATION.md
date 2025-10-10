# GitOps Chaos Lab DevContainer Integration

This document explains how to run the `k8s-gitops-chaos-lab` within the `azure-gitops-image` devcontainer.

## Overview

The integration allows you to:
- Use the `azure-gitops-image` as a base devcontainer with all DevOps tools pre-installed
- Run Kind clusters inside the devcontainer
- Deploy the GitOps chaos engineering stack without host machine dependencies

## Prerequisites

1. **Docker Desktop** (or Docker Engine) running on your host machine
2. **VS Code** with the Dev Containers extension
3. **Git** for cloning repositories

## Setup Instructions

### Option 1: Run from azure-gitops-image devcontainer

1. **Build the base image** (if not already built):
   ```bash
   cd c:/tsak/gianniskt-github/azure-gitops-image
   docker build -t gitops-custom:latest .
   ```

2. **Open azure-gitops-image in devcontainer**:
   - Open VS Code
   - Open the `azure-gitops-image` folder
   - Press `F1` → `Dev Containers: Reopen in Container`

3. **Clone chaos lab inside the devcontainer**:
   ```bash
   cd /workspaces
   git clone https://github.com/gianniskt/k8s-gitops-chaos-lab.git
   cd k8s-gitops-chaos-lab
   ```

4. **Run the deployment**:
   ```bash
   ./scripts/deploy.sh
   ```

### Option 2: Direct chaos lab devcontainer

1. **Build the base image** (if not already built):
   ```bash
   cd c:/tsak/gianniskt-github/azure-gitops-image
   docker build -t gitops-custom:latest .
   ```

2. **Open k8s-gitops-chaos-lab in devcontainer**:
   - Open VS Code
   - Open the `k8s-gitops-chaos-lab` folder
   - Press `F1` → `Dev Containers: Reopen in Container`

3. **Run the setup and deployment**:
   ```bash
   # Optional: Verify environment setup
   ./scripts/setup-devcontainer.sh
   
   # Deploy the chaos lab
   ./scripts/deploy.sh
   ```

## What's Included

The devcontainer provides:
- **Docker-in-Docker**: Full Docker support for Kind clusters
- **Pre-installed tools**:
  - kubectl
  - helm
  - flux CLI
  - kind
  - terraform
  - yq, jq
  - kubectx
  - Azure CLI
  - Flux Operator MCP Server
- **User**: `myuser` with sudo access
- **Docker group membership**: No permission issues

## How It Works

### Docker-in-Docker Setup
- The devcontainer mounts the host Docker socket (`/var/run/docker.sock`)
- Uses the `docker-outside-of-docker` feature for seamless Docker access
- Kind creates Kubernetes clusters using the host Docker daemon

### Tool Installation Skip
- The `deploy.sh` script detects when running in a container environment
- Skips tool installations and uses pre-installed tools
- Speeds up deployment significantly

### Key Changes Made

1. **azure-gitops-image/Dockerfile**:
   - Added Kind installation
   - Enhanced tool installation process

2. **azure-gitops-image/.devcontainer/devcontainer.json**:
   - Improved Docker-in-Docker configuration
   - Added proper workspace mounting
   - Enhanced user permissions

3. **k8s-gitops-chaos-lab/.devcontainer/devcontainer.json** (new):
   - Dedicated devcontainer configuration
   - Same base image with optimized settings

4. **k8s-gitops-chaos-lab/scripts/deploy.sh**:
   - Added container environment detection
   - Conditional tool installation
   - Enhanced verification process

5. **k8s-gitops-chaos-lab/scripts/setup-devcontainer.sh** (new):
   - Environment verification script
   - Docker access validation
   - Tool availability checks

## Troubleshooting

### Docker Permission Issues
```bash
# If you see permission denied errors:
sudo usermod -aG docker $USER
# Then restart the devcontainer
```

### Kind Cluster Issues
```bash
# Check if Docker is accessible:
docker ps

# Check existing Kind clusters:
kind get clusters

# Delete and recreate if needed:
kind delete cluster --name gitops-chaos
./scripts/deploy.sh
```

### Tool Not Found Errors
```bash
# Verify tools are in PATH:
which kubectl helm flux kind

# Check if tools are installed:
ls -la /usr/local/bin/
```

### Port Forward Issues
```bash
# Kill existing port forwards:
pkill -f "port-forward"

# Restart port forwards manually:
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &
kubectl port-forward svc/chaos-dashboard -n chaos-testing 2333:2333 &
kubectl port-forward svc/web -n linkerd-viz 8084:8084 &
```

## Accessing Dashboards

After deployment, access the following dashboards:

- **Grafana**: http://localhost:3000 (admin/prom-operator)
- **Chaos Mesh**: http://localhost:2333 (use provided token)
- **Linkerd**: http://localhost:8084

## Advanced Usage

### Using VS Code MCP Integration
The devcontainer includes Flux Operator MCP Server for advanced cluster management through VS Code chat.

### Custom Configurations
You can modify the devcontainer configurations to:
- Add additional tools
- Change user settings
- Customize VS Code extensions
- Add custom startup scripts

## Contributing

When making changes:
1. Test both devcontainer options
2. Ensure Docker-in-Docker works correctly
3. Verify all tools are accessible
4. Update documentation as needed