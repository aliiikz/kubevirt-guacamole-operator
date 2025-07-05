# KubeVirt Guacamole Operator

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Go Version](https://img.shields.io/badge/go-1.21+-blue.svg)](https://golang.org)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.20+-blue.svg)](https://kubernetes.io)

A Kubernetes operator that manages KubeVirt virtual machines with integrated Apache Guacamole remote desktop access, complete monitoring stack, and automated deployment workflows.

## Overview

This operator provides:

- **Automated VM Management**: Create, manage, and delete KubeVirt virtual machines with custom resource definitions
- **Integrated Remote Access**: Apache Guacamole web-based remote desktop access for VMs
- **Identity Management**: Keycloak integration for SSO and user authentication
- **Monitoring Stack**: Prometheus and Grafana for comprehensive monitoring
- **Container Registry**: Private Docker registry for custom images
- **Automated Workflows**: Scripts for easy deployment and management

## Architecture

//TODO

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Automated Setup](#automated-setup)
  - [Manual Setup](#manual-setup)
- [Configuration](#configuration)
- [Usage](#usage)
- [Components](#components)
- [Access Points](#access-points)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

Deploy everything with a single command:

```bash
# Complete automated deployment
./workflow.sh full-setup

# Check deployment status
./workflow.sh status
```

## Prerequisites

### Required Kubernetes Components

- **KubeVirt** - Virtual machine management
- **CDI** (Containerized Data Importer) - For VM disk image handling
- **Local Path Provisioner** - For persistent storage (default in K3s)

> **Important**: KubeVirt and CDI are automatically installed by the workflow script. Manual installation instructions are provided in the [Manual Setup](#manual-setup) section.

## Installation

### Automated Setup

The recommended easy approach is using the workflow script:

```bash
# Clone the repository
git clone <repository-url>
cd kubevirt-guacamole-operator

# Complete setup (installs all dependencies)
./workflow.sh full-setup

# Monitor deployment progress
watch kubectl get pods --all-namespaces
```

**What this does:**

1. Installs KubeVirt and CDI
2. Configures insecure registry settings
3. Deploys container registry with persistent storage
4. Builds and pushes operator image
5. Installs CRDs and deploys operator
6. Deploys Guacamole stack (Guacamole + PostgreSQL + Keycloak)
7. Sets up monitoring stack (Prometheus + Grafana)

### Manual Setup

For more control or troubleshooting, follow these steps:

#### 1. Install Prerequisites

**Install KubeVirt:**

```bash
./workflow.sh setup-kubevirt

# Or manually:
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"
kubectl wait --for=condition=Available kubevirt.kubevirt.io/kubevirt -n kubevirt --timeout=300s
```

**Install CDI (Containerized Data Importer):**

```bash
./workflow.sh setup-cdi

# Or manually:
export VERSION=$(basename $(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest))
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml"
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml"
```

#### 2. Configure Registry (Required for K3s and Docker)

Update IP addresses in the following files to match your node IP:

```bash
# Find your node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
echo "Node IP: $NODE_IP"

# Configure Docker for insecure registry
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["$NODE_IP:30500"]
}
EOF
sudo systemctl restart docker

# Configure K3s for insecure registry
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  "$NODE_IP:30500":
    endpoint:
      - "http://$NODE_IP:30500"
configs:
  "$NODE_IP:30500":
    tls:
      insecure_skip_verify: true
EOF
sudo systemctl restart k3s
```

#### 3. Deploy Components

```bash
# Deploy container registry
./workflow.sh setup-registry

# Build and push operator
./workflow.sh build-operator
./workflow.sh push-operator

# Deploy operator
./workflow.sh deploy

# Deploy Guacamole stack
./workflow.sh deploy-stack

# Deploy monitoring (optional)
./workflow.sh monitoring
```

## Configuration

### Environment Variables

Key configuration options can be set via environment variables:

| Variable         | Default       | Description                                 |
| ---------------- | ------------- | ------------------------------------------- |
| `REGISTRY_IP`    | `192.168.1.4` | IP address of the container registry (Host) |
| `REGISTRY_PORT`  | `30500`       | Port for the container registry             |
| `GUACAMOLE_PORT` | `30080`       | Port for Guacamole web interface            |
| `KEYCLOAK_PORT`  | `30081`       | Port for Keycloak admin interface           |

### Updating Registry IP

Your node IP is different from the default IP `192.168.1.4`, update the following files:

1. Find and replace in DataVolume manifests

```bash
find virtualmachines/ -name "*.yml" -exec sed -i 's/192.168.1.4/YOUR_NODE_IP/g' {} \;
```

2. Update Docker configuration
   Change the IP of the `insecure-registries` in the `/etc/docker/daemon.json` file then, restart Docker service.

3. Update K3S configuration
   Change the IP of the `mirrors` and `mirrors` in the `/etc/rancher/k3s/registries.yaml` file then, restart K3S service.

### Guacamole Login via Keycloak

Keycloak integration with Guacamole has been configured, but a few manual steps are required to finalize the setup:

#### 1. Create a Realm in Keycloak

- Name the new realm: `GuacamoleRealm`.

#### 2. Configure the Guacamole Client

In the `GuacamoleRealm`, navigate to the **Clients** section and:

- Click **Create** and set the following:

  - **Client ID**: `guacamole`
  - Enable **Implicit Flow**
  - Set the following URLs:

    - **Root URL**: `http://192.168.1.4:30080/guacamole/`
    - **Home URL**: `http://192.168.1.4:30080/guacamole/`
    - **Web Origins**: `http://192.168.1.4:30080/guacamole/`
    - **Valid Redirect URIs**: `http://192.168.1.4:30080/guacamole/*`

#### 3. Create a User

- Go to the **Users** section in the realm.
- Create a new user and assign a password.

  > **Important**: The Keycloak username must match the Guacamole username exactly.

#### 4. Sign In via Guacamole

- Open the Guacamole UI in your browser.
- Choose the **OpenID Connect** option to be redirected to Keycloak for authentication.

## Usage

### Creating Virtual Machines

1. **Deploy VM with Ubuntu Cloud Image:**

```bash
# Create DataVolume (downloads Ubuntu Cloud Image)
kubectl apply -f virtualmachines/dv_ubuntu1.yml

# Wait for DataVolume to be ready
kubectl wait --for=condition=Ready dv/ubuntu1-dv --timeout=600s

# Create VirtualMachine
kubectl apply -f virtualmachines/vm1_pvc.yml
```

2. **Monitor VM status:**

```bash
# Check VM status
kubectl get virtualmachine
kubectl get pod -l kubevirt.io/created-by
```

3. **Access via Guacamole:**
   - Navigate to `http://<node-ip>:30080/guacamole/`
   - Login via Keycloak (admin/admin) or the Quacamole UI itself
   - VMs will appear automatically in the connection list

### Managing VMs

```bash
# Start VM
kubectl patch virtualmachine ubuntu1-vm --type merge -p '{"spec":{"running":true}}'

# Stop VM
kubectl patch virtualmachine ubuntu1-vm --type merge -p '{"spec":{"running":false}}'

# Delete VM (deletes Guacamole connection automatically)
kubectl delete virtualmachine ubuntu1-vm
kubectl delete datavolume ubuntu1-dv
```

## Components

### Core Components

| Component      | Namespace                   | Purpose                        | Port        |
| -------------- | --------------------------- | ------------------------------ | ----------- |
| **Operator**   | `kubebuilderproject-system` | VM lifecycle management        | -           |
| **Guacamole**  | `guacamole`                 | Web-based remote desktop       | 30080       |
| **Keycloak**   | `guacamole`                 | Identity and access management | 30081       |
| **PostgreSQL** | `guacamole`                 | Database for Guacamole         | -           |
| **Registry**   | `docker-registry`           | Container image storage        | 30500/30501 |

### Monitoring Components

| Component         | Namespace    | Purpose               | Port  |
| ----------------- | ------------ | --------------------- | ----- |
| **Prometheus**    | `monitoring` | Metrics collection    | 30090 |
| **Grafana**       | `monitoring` | Metrics visualization | 30300 |
| **Node Exporter** | `monitoring` | Node metrics          | -     |

### Default Credentials

- Keycloak:
  - username: admin
  - password: admin
- Guacamole:
  - username: guacadmin
  - password: guacadmin
- Grafana:
  - username: admin
  - passsword: admin

## Monitoring

The monitoring stack provides comprehensive observability:

### Prometheus Metrics

- **VM Resource Usage**: CPU, memory, disk I/O
- **Operator Metrics**: Reconciliation times, error rates
- **Cluster Metrics**: Node resources, pod status
- **Guacamole Metrics**: Active connections, session duration

### Grafana Dashboards

Access pre-configured dashboards at `http://<node-ip>:30300`:

1. **KubeVirt VMs Dashboard**: VM performance and status
2. **Operator Dashboard**: Operator health and metrics
3. **Cluster Overview**: Overall cluster health
4. **Guacamole Sessions**: Remote access session analytics

### Setting up Monitoring

```bash
# Deploy monitoring stack
./workflow.sh monitoring

# Check monitoring components
kubectl get pods -n monitoring

# Port forward for local access (optional)
kubectl port-forward -n monitoring svc/grafana 3000:3000
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

### Reset and Cleanup

```bash
# Clean up specific components
## Remove monitoring only
./workflow.sh cleanup-monitoring

## Remove operator only
make undeploy

## Remove Guacamole stack
kubectl delete namespace guacamole

# Force delete namespaces
./workflow.sh force-clean-ns

# Complete reset (WARNING: removes everything including KubeVirt/CDI)
./workflow.sh cleanup-all

# Rebuild after cleanup
./workflow.sh full-setup
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Acknowledgments

- [KubeVirt](https://kubevirt.io/) - Kubernetes Virtualization API
- [Apache Guacamole](https://guacamole.apache.org/) - Clientless remote desktop gateway
- [Keycloak](https://www.keycloak.org/) - Identity and access management
- [Kubebuilder](https://book.kubebuilder.io/) - SDK for building Kubernetes APIs
