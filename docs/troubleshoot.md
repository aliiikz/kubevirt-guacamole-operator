## Troubleshooting

### Common Issues and Solutions

#### 1. ImagePullBackOff Errors

**Problem**: Pods can't pull images from registry

```bash
kubectl get pods -n kubebuilderproject-system
# NAME                                                READY   STATUS             RESTARTS   AGE
# controller-manager-xyz                              0/1     ImagePullBackOff   0          2m
```

**Solution**: Configure K3s for insecure registry

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
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
kubectl rollout restart deployment/kubebuilderproject-controller-manager -n kubebuilderproject-system
```

#### 2. DataVolume Creation Fails

**Problem**: `no matches for kind DataVolume`

```bash
kubectl apply -f virtualmachines/dv_ubuntu1.yml
# error: unable to recognize "dv_ubuntu1.yml": no matches for kind "DataVolume"
```

**Solution**: Install CDI

```bash
./workflow.sh setup-cdi
# Wait for CDI to be ready
kubectl wait --for=condition=Ready pod -l app=cdi-operator -n cdi --timeout=300s
```

#### 3. VMs Stuck in Provisioning

**Problem**: VM shows "Provisioning" status indefinitely

```bash
kubectl get vm
# NAME        AGE   STATUS         READY
# ubuntu1-vm  5m    Provisioning   False
```

**Solution**: Check KubeVirt and underlying resources

```bash
# Check KubeVirt status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"
# Should return "Deployed"

# Check DataVolume status
kubectl get dv
kubectl describe dv ubuntu1-dv

# Check PVC status
kubectl get pvc
kubectl describe pvc ubuntu1-dv
```

#### 4. Registry Connection Issues

**Problem**: Cannot push/pull from registry

```bash
docker push 192.168.1.4:30500/operator:latest
# Error: http: server gave HTTP response to HTTPS client
```

**Solution**: Configure Docker for insecure registry

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["$NODE_IP:30500"]
}
EOF
sudo systemctl restart docker
```

#### 5. Guacamole Connection Failed

**Problem**: Cannot connect to VMs via Guacamole

**Solution**: Check VM network and services

```bash
# Check VM status and IP
kubectl get vm ubuntu1-vm -o yaml | grep -A 10 "status:"

# Check if VM is accessible
kubectl get vmi ubuntu1-vm
kubectl describe vmi ubuntu1-vm

# Check Guacamole logs
kubectl logs -n guacamole deployment/guacamole
```

### Diagnostic Commands

```bash
# Check all component status
./workflow.sh status

# Detailed component checks
kubectl get all -n kubebuilderproject-system
kubectl get all -n guacamole
kubectl get all -n monitoring
kubectl get all -n docker-registry

# Check VM and CDI resources
kubectl get vm,vmi,dv,pvc
kubectl get pods -l kubevirt.io/created-by

# Check operator logs
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager -f

# Check resource events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Development

### Building from Source

```bash
# Clone repository
git clone <repository-url>
cd kubevirt-guacamole-operator

# Install dependencies
go mod download

# Generate code and manifests
make generate
make manifests

# Build binary
make build

# Run tests
make test

# Run locally (requires cluster access)
make run
```

### Development Workflow

```bash
# Format code
make fmt

# Lint code
make vet

# Build and push operator image
make docker-build docker-push

# Deploy to cluster
make deploy

# View logs
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager -f
```
