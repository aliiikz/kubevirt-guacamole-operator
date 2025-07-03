# KubeVirt Guacamole Operator

A Kubernetes operator that manages KubeVirt virtual machines with integrated Apache Guacamole remote desktop access.

## Description

This operator provides automated management of KubeVirt virtual machines with built-in remote desktop access through Apache Guacamole. It simplifies the deployment and management of virtual machines in Kubernetes clusters while providing web-based remote access capabilities.

## Getting Started

### Prerequisites
- go version v1.24.0+
- docker version 17.03+
- kubectl version v1.11.3+
- Access to a Kubernetes v1.11.3+ cluster with KubeVirt installed

### Quick Start

Use the provided workflow script for easy setup and deployment:

```sh
# Complete setup from scratch
./workflow.sh full-setup

# Individual commands
./workflow.sh setup-registry    # Setup Docker registry
./workflow.sh build             # Build operator image
./workflow.sh build-custom-vm   # Build custom Ubuntu VM image
./workflow.sh push               # Build and push operator to Docker Registry
./workflow.sh deploy             # Deploy operator
./workflow.sh monitoring        # Deploy monitoring stack

# Show all available commands
./workflow.sh help
```

### Manual Deployment

**Build operator image:**

```sh
make docker-build
# OR
./workflow.sh build
```

**Build custom VM image:**

```sh
make build-custom-vm
# OR
./workflow.sh build-custom-vm
```

**Install the CRDs into the cluster:**

```sh
make install
```

**Deploy the operator to the cluster:**

```sh
make deploy
# OR
./workflow.sh deploy
```

**Create VirtualMachine instances:**

```sh
kubectl apply -k config/samples/
```

### Cleanup

**Complete cleanup (removes everything):**

```sh
./workflow.sh cleanup-all
```

**Remove monitoring only:**

```sh
./workflow.sh cleanup
```

**Manual cleanup:**

```sh
make undeploy
make uninstall
```

## Project Structure

- `workflow.sh` - Main automation script for building, deploying, and managing the operator
- `Makefile` - Build targets for the operator
- `config/` - Kubernetes manifests and configurations
- `api/` - Custom Resource Definitions (CRDs)
- `internal/controller/` - Operator controller logic
- `stack/` - Complete deployment stack with Guacamole integration
- `monitoring/` - Prometheus and Grafana monitoring setup

## Monitoring

Deploy monitoring stack:

```sh
./workflow.sh monitoring
```

This sets up Prometheus and Grafana for monitoring your virtual machines and operator.

**Access URLs:**
- Prometheus: http://localhost:30090
- Grafana: http://localhost:30091 (admin/admin)

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

