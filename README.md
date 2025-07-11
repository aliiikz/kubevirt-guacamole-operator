# KubeVirt Guacamole Operator

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Go Version](https://img.shields.io/badge/go-1.21+-blue.svg)](https://golang.org)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.20+-blue.svg)](https://kubernetes.io)

A Kubernetes operator that manages KubeVirt virtual machines with integrated Apache Guacamole remote desktop access, complete monitoring stack, and automated deployment workflows.

## Overview

This operator provides:

- **Integrated Remote Access**: Apache Guacamole web-based remote desktop access for VMs
- **Identity Management**: Keycloak integration for SSO and user authentication
- **Monitoring Stack**: Prometheus and Grafana for comprehensive monitoring
- **Container Registry**: Private Docker registry for custom images
- **Automated Workflows**: Scripts for easy deployment and management

## Architecture

![alt text](./docs/Architecture.png)

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Automated Setup](#automated-setup)
  - [Manual Setup](#manual-setup)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Creating Virtual Machines](#creating-virtual-machines)
  - [Managing VMs](#managing-vms)
- [Access Points](#access-points)
- [Components](#components)
- [Monitoring](#monitoring)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

Deploy everything with a single command:

```bash
# Clone the repository
git clone <repository-url>
cd kubevirt-guacamole-operator

# Complete automated deployment (automatically detects IP)
./workflow.sh full-setup

# Check deployment status
./workflow.sh status

# View detected endpoints
./workflow.sh detect-ip
```

**What you get:**

- ✅ KubeVirt virtual machines with web-based remote access
- ✅ Apache Guacamole for RDP/VNC connections
- ✅ Keycloak for identity management
- ✅ Private container registry
- ✅ Prometheus & Grafana monitoring
- ✅ Automatic IP detection and configuration

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

1. Detects and configures IP addresses (automatically)
2. Installs KubeVirt and CDI
3. Configures insecure registry settings
4. Deploys container registry with persistent storage
5. Builds and pushes operator image
6. Installs CRDs and deploys operator
7. Deploys Guacamole stack (Guacamole + PostgreSQL + Keycloak)
8. Sets up monitoring stack (Prometheus + Grafana)

### Manual Setup

For more control or troubleshooting, follow these steps:

#### 1. Automatic IP Detection

First, configure your environment with the correct IP addresses:

```bash
# Detect current IP and show endpoints
./workflow.sh detect-ip

# Update all configuration files with current IP
./workflow.sh update-configs
```

> This step is **critical** - it must be done before deploying any components, otherwise they will be configured with incorrect IP addresses.

#### 2. Install Prerequisites

**Install KubeVirt:**

```bash
./workflow.sh setup-kubevirt
```

**Install CDI (Containerized Data Importer):**

```bash
./workflow.sh setup-cdi
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

### Automatic IP Detection

The project automatically detects your node IP address, eliminating the need for manual configuration when moving between different environments.

#### How It Works

1. **IP Detection**: The system automatically detects your current node IP using `hostname -I`
2. **Environment Variables**: All configurations use environment variables that are automatically populated
3. **System Configuration**: Docker and K3s configurations are updated automatically

> **Important**: IP detection and configuration must be done **before** deploying any components. Components deployed with incorrect IP addresses will not function properly.

#### Usage

```bash
# Detect current IP and show endpoints
./workflow.sh detect-ip

# Update all configuration files with current IP
./workflow.sh update-configs
```

#### Manual Environment Configuration

If you need to override the automatic detection, you can source the environment file:

```bash
# Source environment configuration
source .env

# Or set specific variables
export NODE_IP=192.168.1.100
export REGISTRY_PORT=30500
```

### Environment Variables

The following environment variables are automatically detected and can be overridden:

| Variable          | Auto-Detected | Description                       |
| ----------------- | ------------- | --------------------------------- |
| `NODE_IP`         | ✓             | IP address of the Kubernetes node |
| `REGISTRY_PORT`   | 30500         | Port for the container registry   |
| `GUACAMOLE_PORT`  | 30080         | Port for Guacamole web interface  |
| `KEYCLOAK_PORT`   | 30081         | Port for Keycloak admin interface |
| `GRAFANA_PORT`    | 30300         | Port for Grafana dashboard        |
| `PROMETHEUS_PORT` | 30090         | Port for Prometheus metrics       |

## Usage

### Creating Virtual Machines

1. **Deploy VM with Ubuntu Cloud Image:**

```bash
# Create DataVolume (downloads Ubuntu Cloud Image)
kubectl apply -f virtualmachines/dv_ubuntu1.yml

# Create VirtualMachine
kubectl apply -f virtualmachines/vm1_pvc.yml
```

2. **Monitor VM status:**

```bash
# Check VM status
kubectl get virtualmachine
kubectl get vmi  # VirtualMachineInstance (running VMs)

# Check VM launcher pods (these are the actual VM pods)
kubectl get pods -l kubevirt.io/domain

# Get VNC access info
kubectl get virtualmachine ubuntu1-vm -o yaml | grep -A 5 "guacamole"
```

3. **Access via Guacamole:**
   - Navigate to `http://<node-ip>:30080/guacamole/`
   - Login via Keycloak (admin/admin) or directly with Guacamole credentials
   - VMs will appear automatically in the connection list

### Supported Protocols

The operator supports **RDP** and **VNC** protocols for remote access to VMs.

### Managing VMs

```bash
# Start VM
kubectl patch virtualmachine ubuntu1-vm --type merge -p '{"spec":{"running":true}}'

# Stop VM
kubectl patch virtualmachine ubuntu1-vm --type merge -p '{"spec":{"running":false}}'

# Delete VM (IMPORTANT: Delete in correct order to clean up Guacamole connections)
kubectl delete virtualmachine ubuntu1-vm    # Delete VM first
kubectl delete datavolume ubuntu1-dv        # Then delete DataVolume
```

> **Important**: Always delete the VirtualMachine before deleting the DataVolume. The operator needs the VM object with its connection ID annotation to properly clean up the Guacamole connection.

## Access Points

Once deployed, you can access the following services:

| Service         | URL                                 | Credentials         |
| --------------- | ----------------------------------- | ------------------- |
| **Guacamole**   | `http://<node-ip>:30080/guacamole/` | guacadmin/guacadmin |
| **Keycloak**    | `http://<node-ip>:30081/`           | admin/admin         |
| **Grafana**     | `http://<node-ip>:30300/`           | admin/admin         |
| **Prometheus**  | `http://<node-ip>:30090/`           | -                   |
| **Registry**    | `http://<node-ip>:30500/`           | -                   |
| **Registry UI** | `http://<node-ip>:30501/`           | -                   |

> **Note**: Replace `<node-ip>` with your actual node IP address. Use `./workflow.sh detect-ip` to see your current endpoints.

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

- **Keycloak**: admin / admin
- **Guacamole**: guacadmin / guacadmin
- **Grafana**: admin / admin

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

### Troubleshooting Commands

```bash
# Check overall system status
./workflow.sh status

# Check operator logs
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager -f

# Check VM status
kubectl get vm,vmi,dv,pvc

# Reset everything if needed
./workflow.sh cleanup-all && ./workflow.sh full-setup
```

## Known Limitations

### Connection Sharing

- **Manual Group Assignment**: Auto-created Guacamole connections are only accessible by the admin user who created them
- **No Automatic Sharing**: Connections must be manually shared with users/groups through the Guacamole UI after creation
- **Scale Limitations**: Manual sharing becomes burdensome with many VMs and users
- **Admin Dependency**: Each new VM connection requires administrator intervention for user access

### Workaround

After a VM connection is automatically created:

1. Login to Guacamole as admin
2. Navigate to Settings → Connections
3. Select the auto-created connection
4. Click "Permissions" tab
5. Manually add users or groups with appropriate permissions

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
