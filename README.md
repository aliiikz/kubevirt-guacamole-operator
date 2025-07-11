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

> **💡 Need help?** If you encounter any issues, check the [Troubleshooting Guide](docs/troubleshoot.md) for common problems and solutions.

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

#### 3. Create Groups for Access Control

- Go to the **Groups** section in the realm.
- Create the following groups:
  - `vm-users` (regular users who can access VMs)
  - `vm-admins` (administrators who can manage connections)

#### 4. Create a User

- Go to the **Users** section in the realm.
- Create a new user and assign a password.
- **Assign the user to a group** (e.g., `vm-users`)

  > **Important**: Users must be assigned to either `vm-users` or `vm-admins` group to access VM connections.

#### 5. Configure Group Claims in Client

- In the `guacamole` client, go to **Client Scopes**
- Click on **roles**
- Click on **Mappers**
- **Delete the existing `groups` mapper** (click on it and delete it)
- Click **Add Mapper** and from `By Configuration` add the `Group Membership` mapper and name it `groups`
- Click **Add Mapper** and from `By Configuration` add the `User Realm Role` mapper and name it `admin-role`

**Configure the new mapper with these settings:**

- **Add to ID token**: ON
- **Add to access token**: ON

#### 6. Share VM Connections with Groups

**Current Behavior**: VM connections are created for individual users and require manual sharing.

**Manual Sharing Process**:

1. **Login to Guacamole** as admin (guacadmin/guacadmin)
2. **Go to Settings** → **Connections**
3. **Select your VM connection** (e.g., ubuntu1-vm)
4. **Go to Sharing tab**
5. **Add the groups**: `vm-users` and/or `vm-admins`
6. **Grant permissions**:
   - `vm-users`: READ permission (can connect to VMs)
   - `vm-admins`: READ + UPDATE + DELETE permissions (can manage VMs)

**Automated Sharing (Future Enhancement)**:
The operator can be enhanced to automatically share new VM connections with predefined groups by:

- Adding group annotations to VirtualMachine resources
- Automatically calling Guacamole's sharing API when connections are created
- Supporting connection templates with default group permissions

**Example of future VM annotation**:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ubuntu1-vm
  annotations:
    vm-watcher.setofangdar.polito.it/auto-share-groups: "vm-users:READ,vm-admins:ADMIN"
```

#### 7. Sign In via Guacamole

- Open the Guacamole UI in your browser.
- Choose the **OpenID Connect** option to be redirected to Keycloak for authentication.
- **VM connections will appear** based on your group membership and sharing permissions.

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

### Supported Protocols and Configuration

The operator supports **RDP** and **VNC** protocols for remote access to VMs

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

## Troubleshooting

For detailed troubleshooting information, common issues, and solutions, please refer to the [Troubleshooting Guide](docs/troubleshoot.md).

### Quick Diagnostic Commands

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

## Acknowledgments

- [KubeVirt](https://kubevirt.io/) - Kubernetes Virtualization API
- [Apache Guacamole](https://guacamole.apache.org/) - Clientless remote desktop gateway
- [Keycloak](https://www.keycloak.org/) - Identity and access management
- [Kubebuilder](https://book.kubebuilder.io/) - SDK for building Kubernetes APIs
