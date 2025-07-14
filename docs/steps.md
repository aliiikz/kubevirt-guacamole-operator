# KubeVirt Guacamole Operator - Deployment Steps

This document provides clear, step-by-step instructions for deploying the KubeVirt Guacamole Operator, monitoring stack, and custom VM images.

## Prerequisites

- Kubernetes cluster (tested with K3s)
- kubectl configured to connect to your cluster
- Docker installed and configured
- Go 1.21+ (for building from source)
- Make utility
- **KubeVirt and CDI** (Containerized Data Importer) - required for VirtualMachines and DataVolumes

## Quick Start (Automated)

The easiest way to deploy everything is using the automated workflow script:

```bash
# Complete setup - installs KubeVirt/CDI, deploys registry, operator, and monitoring
./workflow.sh full-setup

# Check status of all components
./workflow.sh status

# Clean up everything
./workflow.sh cleanup-all
```

## Manual Deployment Steps

If you prefer manual control or need to troubleshoot, follow these detailed steps:

### Step 0: Install KubeVirt and CDI Prerequisites

**IMPORTANT:** KubeVirt and CDI must be installed before creating VirtualMachines or DataVolumes.

```bash
# Install KubeVirt and CDI separately
./workflow.sh setup-kubevirt
./workflow.sh setup-cdi

# Or install manually:
```

**Install KubeVirt:**

```bash
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo $VERSION
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"

# Wait for KubeVirt to be deployed
kubectl wait --for=condition=Available kubevirt.kubevirt.io/kubevirt -n kubevirt --timeout=300s

# Check status (should show "Deployed")
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"
```

**Install CDI (Containerized Data Importer):**

```bash
export VERSION=$(basename $(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest))
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml"
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml"

# Configure for insecure registry
kubectl patch cdi cdi --type='merge' -p='{"spec":{"config":{"insecureRegistries":["192.168.1.4:30500"]}}}'

# Check status (should show "Deployed")
kubectl get cdi cdi -n cdi
kubectl get pods -n cdi
```

### Step 1: Configure Docker and Kubernetes for Insecure Registry

First, configure Docker to allow HTTP connections to your local registry:

```bash
# Edit Docker daemon configuration
sudo vim /etc/docker/daemon.json
```

Add the following content (replace with your actual node IP):

```json
{
  "insecure-registries": ["192.168.1.4:30500"]
}
```

Restart Docker:

```bash
sudo systemctl restart docker
```

**For Kubernetes (K3s), also configure the registry as insecure:**

```bash
# Edit K3s registries configuration
sudo mkdir -p /etc/rancher/k3s
sudo vim /etc/rancher/k3s/registries.yaml
```

Add the following content:

```yaml
mirrors:
  "${NODE_IP}:30500":
    endpoint:
      - "http://${NODE_IP}:30500"
configs:
  "${NODE_IP}:30500":
    tls:
      insecure_skip_verify: true
```

Restart K3s:

```bash
sudo systemctl restart k3s
```

### Step 2: Deploy Container Registry

```bash
# Deploy registry with persistent storage
./workflow.sh setup-registry

# Or manually:
kubectl apply -f repository/registry-storage.yaml
kubectl apply -f repository/docker-registry.yaml

# Wait for registry to be ready
kubectl wait --for=condition=ready pod -l app=docker-registry -n docker-registry --timeout=300s
```

### Step 3: Build and Push Operator Image

```bash
# Build operator image
./workflow.sh build-operator

# Push to registry
./workflow.sh push-operator

# Or manually:
make docker-build
make docker-push
```

### Step 4: Deploy Operator

```bash
# Install CRDs and deploy operator
make install
make deploy

# Verify operator is running
kubectl get pods -n kubebuilderproject-system
```

### Step 5: Deploy Monitoring Stack

```bash
# Deploy monitoring
./workflow.sh monitoring

# Or manually:
kubectl apply -f monitoring/persistent-storage.yaml
kubectl apply -f monitoring/01-namespace-rbac.yaml
kubectl apply -f monitoring/02-prometheus-config.yaml
kubectl apply -f monitoring/03-prometheus.yaml
kubectl apply -f monitoring/04-node-exporter.yaml
kubectl apply -f monitoring/05-grafana-config.yaml
kubectl apply -f monitoring/06-grafana.yaml
```

### Step 6: Deploy Guacamole Stack

```bash
# Deploy the complete Guacamole stack (Guacamole, Postgres, Keycloak)
./workflow.sh deploy-stack

# Or manually:
kubectl apply -f stack/stack.yaml

# Wait for all components to be ready
kubectl wait --for=condition=Ready pod -l app=postgres -n guacamole --timeout=300s
kubectl wait --for=condition=Ready pod -l app=guacd -n guacamole --timeout=300s
kubectl wait --for=condition=Ready pod -l app=guacamole -n guacamole --timeout=300s
kubectl wait --for=condition=Ready pod -l app=keycloak -n guacamole --timeout=300s

# Check stack status
kubectl get pods -n guacamole
```

### Step 7: Build Custom VM Images (Optional - for Docker containers, not VMs)

**Note:** The custom Ubuntu desktop image is a Docker container image for running desktop applications, not a VM disk image. DataVolumes should use proper VM images like Ubuntu Cloud Images.

```bash
# Build custom Ubuntu desktop container image (optional)
./workflow.sh push-custom-vm

# Or manually:
cd virtualmachines/custom_image
docker build -t custom-ubuntu-desktop:22.04 .
docker tag custom-ubuntu-desktop:22.04 192.168.1.4:30500/custom-ubuntu-desktop:22.04
docker push 192.168.1.4:30500/custom-ubuntu-desktop:22.04
```

### Step 8: Deploy VirtualMachines

```bash
# Create VMs
kubectl create -f virtualmachines/dv_ubuntu1.yml
sleep 3
kubectl create -f virtualmachines/vm1_pvc.yml

## VM2
kubectl create -f virtualmachines/dv_ubuntu2.yml
sleep 3
kubectl create -f virtualmachines/vm2_pvc.yml

## IMPORTANT: Delete VM first to trigger Guacamole connection cleanup because the operator needs the VM object with its connection ID annotation to properly delete the Guacamole connection. Delete in this order:

# Delete VMs
## VM1
kubectl delete -f virtualmachines/vm1_pvc.yml
kubectl delete -f virtualmachines/dv_ubuntu1.yml

## VM2
kubectl delete -f virtualmachines/vm2_pvc.yml
kubectl delete -f virtualmachines/dv_ubuntu2.yml

```

## Workflow Commands Reference

| Command                        | Description                                            |
| ------------------------------ | ------------------------------------------------------ |
| `./workflow.sh full-setup`     | Complete automated setup (includes KubeVirt/CDI)       |
| `./workflow.sh setup-kubevirt` | Install KubeVirt                                       |
| `./workflow.sh setup-cdi`      | Install CDI (Containerized Data Importer)              |
| `./workflow.sh setup-registry` | Deploy container registry                              |
| `./workflow.sh build-operator` | Build operator image                                   |
| `./workflow.sh push-operator`  | Push operator to registry                              |
| `./workflow.sh deploy`         | Install CRDs and deploy operator                       |
| `./workflow.sh deploy-stack`   | Deploy Guacamole stack (Guacamole, Postgres, Keycloak) |
| `./workflow.sh monitoring`     | Deploy monitoring stack                                |
| `./workflow.sh push-custom-vm` | Build and push custom Docker image                     |
| `./workflow.sh status`         | Show status of all components                          |
| `./workflow.sh cleanup`        | Clean up monitoring                                    |
| `./workflow.sh cleanup-all`    | Clean up everything (including KubeVirt/CDI)           |

## Makefile Targets Reference

| Target              | Description                     |
| ------------------- | ------------------------------- |
| `make docker-build` | Build operator Docker image     |
| `make docker-push`  | Push operator image to registry |
| `make install`      | Install CRDs to cluster         |
| `make uninstall`    | Remove CRDs from cluster        |
| `make deploy`       | Deploy operator to cluster      |
| `make undeploy`     | Remove operator from cluster    |
| `make manifests`    | Generate manifests              |
| `make generate`     | Generate code                   |
| `make fmt`          | Format Go code                  |
| `make vet`          | Run go vet                      |
| `make test`         | Run tests                       |
| `make build`        | Build operator binary           |
| `make run`          | Run operator locally            |

## Access Points

After deployment, you can access:

- **Guacamole**: `http://<node-ip>:30080/guacamole/` (authenticate via Keycloak)
- **Keycloak**: `http://<node-ip>:30081/` (admin/admin)
- **Registry UI**: `http://<node-ip>:30501`
- **Prometheus**: `http://<node-ip>:30090`
- **Grafana**: `http://<node-ip>:30300` (admin/admin)

## Troubleshooting

### Registry Issues

```bash
# Check registry status
kubectl get pods -n docker-registry
kubectl logs -n docker-registry deployment/docker-registry

# Test registry connectivity
curl http://192.168.1.4:30500/v2/_catalog
```

### KubeVirt/CDI Issues

```bash
# Check KubeVirt status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt
kubectl get pods -n kubevirt

# Check CDI status
kubectl get cdi cdi -n cdi
kubectl get pods -n cdi
```

**If DataVolume creation fails with "no matches for kind DataVolume":**

This means CDI is not installed. Install it with:

```bash
./workflow.sh setup-cdi
```

**If KubeVirt VMs fail to start:**

Check that KubeVirt is fully deployed:

```bash
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"
# Should return "Deployed"
```

### Operator Issues

```bash
# Check operator status
kubectl get pods -n kubebuilderproject-system
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager

# Check CRDs
kubectl get crd virtualmachines.kubevirt.setofangdar.polito.it
```

**If you see ImagePullBackOff errors:**

This usually means Kubernetes is trying to pull from the registry via HTTPS. Fix by:

1. **Configure K3s registries (most important):**

   ```bash
   sudo mkdir -p /etc/rancher/k3s
   sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
   mirrors:
     "192.168.1.4:30500":
       endpoint:
         - "http://192.168.1.4:30500"
   configs:
     "192.168.1.4:30500":
       tls:
         insecure_skip_verify: true
   EOF
   sudo systemctl restart k3s
   ```

2. **Restart the operator deployment:**
   ```bash
   kubectl rollout restart deployment/kubebuilderproject-controller-manager -n kubebuilderproject-system
   ```

### Monitoring Issues

```bash
# Check monitoring pods
kubectl get pods -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then visit http://192.168.1.4:9090/targets
```

## Clean Up

To completely remove all components:

```bash
# Automated cleanup (WARNING: This removes KubeVirt and CDI too!)
./workflow.sh cleanup-all

# Manual cleanup (preserves KubeVirt/CDI)
make undeploy
make uninstall
kubectl delete -f monitoring/
kubectl delete namespace monitoring
kubectl delete -f repository/
kubectl delete namespace docker-registry
```

**⚠️ WARNING:** The `cleanup-all` command removes **everything** including KubeVirt and CDI. You'll need to run `./workflow.sh setup-kubevirt` and `./workflow.sh setup-cdi` again after cleanup-all.

## Important Notes

1. **Node IP Configuration**: Update the registry IP (192.168.1.4) in DataVolume manifests and Docker configuration to match your actual node IP.

2. **Persistent Storage**: The setup uses `local-path` storage class for persistence. Ensure your cluster has this or update the storage class in the YAML files.

3. **Image Registry**: The operator image is pushed to the local registry. Ensure the registry is accessible from all cluster nodes.

4. **CRD Installation**: CRDs must be installed before deploying the operator. The workflow ensures this order.

5. **Custom Images**: Custom VM images are optional but provide a better desktop experience with VNC access.

6. **K3s Insecure Registry**: For K3s clusters, you MUST configure the registry as insecure in `/etc/rancher/k3s/registries.yaml` or pods will fail with ImagePullBackOff errors.

7. **Namespace**: The operator deploys to `kubebuilderproject-system` namespace, not `kubevirt-guacamole-operator-system`.

8. **Prerequisites Warning**: If you run `cleanup-all`, it removes KubeVirt and CDI. You must reinstall them with `./workflow.sh setup-kubevirt` and `./workflow.sh setup-cdi` before creating VMs.

9. **Custom Images**: The custom Ubuntu desktop image is a Docker container image, not a VM disk image. For VMs, use proper disk images like Ubuntu Cloud Images via HTTP source in DataVolumes.
