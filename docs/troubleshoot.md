# Troubleshooting Guide

This document provides comprehensive troubleshooting information for the KubeVirt Guacamole Operator and its integrated components.

## Table of Contents

- [Authentication and Access Issues](#authentication-and-access-issues)
- [Infrastructure Issues](#infrastructure-issues)
- [VM Management Issues](#vm-management-issues)
- [Reset and Cleanup Procedures](#reset-and-cleanup-procedures)
- [Diagnostic Commands](#diagnostic-commands)
- [Development Issues](#development-issues)
- [Performance and Resource Issues](#performance-and-resource-issues)
- [Network and Connectivity Issues](#network-and-connectivity-issues)
- [Additional Resources](#additional-resources)

## Authentication and Access Issues

### 1. Keycloak User Can Login but Can't See VM Connections

**Problem**: User successfully logs in via Keycloak but VM connections don't appear

**Root Cause**: Auto-created VM connections are only accessible by the admin user who created them (current limitation)

**Solution**: Manually share connections with users/groups in Guacamole:

```bash
# Via Guacamole Web UI (Recommended)
# 1. Login as admin (guacadmin/guacadmin)
# 2. Settings → Connections → Select the auto-created VM connection
# 3. Click "Permissions" tab
# 4. Add users or groups with appropriate permissions (READ, UPDATE, DELETE, ADMINISTER)
# 5. Save changes

# Method 2: Via Database (Advanced)
kubectl exec -n guacamole deployment/postgres -- psql -U guacamole -d guacamole_db -c "
-- Find the connection ID
SELECT connection_id, connection_name FROM guacamole_connection;

-- Find the user entity ID
SELECT entity_id, name FROM guacamole_entity WHERE type = 'USER';

-- Grant READ permission to specific user for connection
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, c.connection_id, 'READ'
FROM guacamole_entity e, guacamole_connection c
WHERE e.name = 'username' AND e.type = 'USER'
  AND c.connection_name = 'ubuntu1-vm'
ON CONFLICT DO NOTHING;
"
```

**Note**: This manual sharing process is required for each auto-created connection and represents a current limitation of the operator.

### 2. Keycloak Authentication Issues

**Problem**: Users cannot login through Keycloak SSO

**Solution**: Verify Keycloak configuration:

```bash
# Check Keycloak client configuration
# 1. Go to Keycloak → GuacamoleRealm → Clients → guacamole
# 2. Verify Client ID: guacamole
# 3. Verify Valid Redirect URIs: http://192.168.1.4:30080/guacamole/*
# 4. Check Client Scopes are properly configured

# Check Keycloak connectivity
curl -f http://192.168.1.4:30081/realms/GuacamoleRealm/.well-known/openid_configuration
```

### 3. Guacamole Connection Failed

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

## Infrastructure Issues

### 1. ImagePullBackOff Errors

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

### 2. Registry Connection Issues

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

### 3. kubectl apply Warning about Missing Annotation

**Problem**: Warning about missing `kubectl.kubernetes.io/last-applied-configuration` annotation

```bash
Warning: resource datavolumes/ubuntu1 is missing the kubectl.kubernetes.io/last-applied-configuration annotation
```

**Solution**: This happens when resources were created with `kubectl create` instead of `kubectl apply`. To fix:

```bash
# Delete and recreate the resource
kubectl delete datavolume ubuntu1-dv
kubectl apply -f virtualmachines/dv_ubuntu1.yml

# Or add the annotation manually
kubectl annotate datavolume ubuntu1-dv kubectl.kubernetes.io/last-applied-configuration-
```

## VM Management Issues

### 1. DataVolume Creation Fails

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

### 2. VMs Stuck in Provisioning

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

### 3. VM Network Issues

**Problem**: VM doesn't have IP address or network connectivity

**Solution**: Check network configuration and pod networking

```bash
# Check VM network interface
kubectl get vmi ubuntu1-vm -o yaml | grep -A 20 "interfaces:"

# Check pod network
kubectl get pods -l kubevirt.io/created-by
kubectl describe pod <vm-launcher-pod>

# Check if multus or other CNI plugins are needed
kubectl get network-attachment-definitions
```

## Reset and Cleanup Procedures

### Clean Up Specific Components

```bash
# Remove monitoring only
./workflow.sh cleanup-monitoring

# Remove operator only
make undeploy

# Remove Guacamole stack
kubectl delete namespace guacamole

# Force delete stuck namespaces
./workflow.sh force-clean-ns
```

### Complete Reset

**WARNING**: This removes everything including KubeVirt/CDI

```bash
# Complete reset
./workflow.sh cleanup-all

# Rebuild after cleanup
./workflow.sh full-setup
```

### Manual Cleanup Commands

```bash
# Delete stuck resources
kubectl patch virtualmachinetypes <vm-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete virtualmachinetypes <vm-name> --force --grace-period=0

# Clear persistent volumes if needed
kubectl delete pvc --all
kubectl delete pv --all

# Reset Docker registry data
docker volume rm docker-registry-data
```

## Diagnostic Commands

### System Status Checks

```bash
# Check all component status
./workflow.sh status

# Detailed component checks
kubectl get all -n kubebuilderproject-system
kubectl get all -n guacamole
kubectl get all -n monitoring
kubectl get all -n docker-registry
kubectl get all -n keycloak

# Check VM and CDI resources
kubectl get vm,vmi,dv,pvc
kubectl get pods -l kubevirt.io/created-by
```

### Log Analysis

```bash
# Check operator logs
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager -f

# Check Guacamole logs
kubectl logs -n guacamole deployment/guacamole -f

# Check Keycloak logs
kubectl logs -n guacamole deployment/keycloak -f

# Check PostgreSQL logs
kubectl logs -n guacamole deployment/postgres -f

# Check resource events
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Database Troubleshooting

```bash
# Connect to PostgreSQL
kubectl exec -n guacamole deployment/postgres -it -- psql -U guacamole

# Check databases
\l

# Check Guacamole database
\c guacamole_db
\dt

# Check Keycloak database
\c keycloak
\dt

# Check user groups and permissions
\c guacamole_db
SELECT * FROM guacamole_entity WHERE type = 'USER_GROUP';
SELECT * FROM guacamole_connection_permission;
```

## Development Issues

### Building and Testing

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

### Development Workflow Issues

```bash
# Format code
make fmt

# Lint code
make vet

# Build and push operator image
make docker-build docker-push

# Deploy to cluster
make deploy

# View development logs
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager -f
```

### Common Build Issues

**Problem**: Dependencies not found or version conflicts

**Solution**:

```bash
# Clean and reinstall dependencies
go clean -modcache
go mod download
go mod tidy
```

**Problem**: Code generation fails

**Solution**:

```bash
# Regenerate all code
make clean
make generate
make manifests
```

### Testing Issues

**Problem**: Tests fail due to missing CRDs

**Solution**:

```bash
# Install test environment
make test-env-install

# Run tests with proper setup
make test
```

## Performance and Resource Issues

### High Resource Usage

**Problem**: Pods consuming too much CPU/memory

**Solution**: Adjust resource limits

```bash
# Check current resource usage
kubectl top pods --all-namespaces
kubectl top nodes

# Modify resource limits in deployment manifests
# For development, you can patch existing deployments:
kubectl patch deployment guacamole -n guacamole -p '{"spec":{"template":{"spec":{"containers":[{"name":"guacamole","resources":{"limits":{"memory":"1Gi","cpu":"500m"}}}]}}}}'
```

### Disk Space Issues

**Problem**: Node running out of disk space

**Solution**: Clean up unused resources

```bash
# Clean up Docker
docker system prune -a

# Clean up Kubernetes
kubectl delete pods --field-selector=status.phase=Succeeded
kubectl delete pods --field-selector=status.phase=Failed

# Check disk usage
df -h
du -sh /var/lib/rancher/k3s
```

## Network and Connectivity Issues

### Service Discovery Problems

**Problem**: Services can't reach each other

**Solution**: Check service discovery and DNS

```bash
# Test DNS resolution
kubectl run test-pod --image=busybox -it --rm -- nslookup guacamole.guacamole.svc.cluster.local

# Check service endpoints
kubectl get endpoints -A

# Check network policies
kubectl get networkpolicies -A
```

### NodePort Access Issues

**Problem**: Can't access services via NodePort

**Solution**: Check firewall and service configuration

```bash
# Check node ports
kubectl get services --all-namespaces | grep NodePort

# Check if ports are accessible
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
nc -zv $NODE_IP 30080  # Guacamole
nc -zv $NODE_IP 30090  # Keycloak
nc -zv $NODE_IP 30500  # Registry

# Check firewall (if applicable)
sudo ufw status
sudo iptables -L
```

## Additional Resources

For more information, consult:

- [KubeVirt Documentation](https://kubevirt.io/user-guide/)
- [Apache Guacamole Manual](https://guacamole.apache.org/doc/gug/)
- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug-application-cluster/)

If you encounter issues not covered here, please check the project's GitHub issues or create a new issue with detailed information about your problem.

## Up Interface

sudo ip link set enp1s0 up
sudo dhclient enp1s0
ip addr show enp1s0

## Force Delete VM Resources Without YAML

**Problem**: You need to delete a VM, PVC, and DataVolume but lost the original YAML file

**Solution**: Use kubectl delete commands with resource names

```bash
# First, list all VMs to see what needs to be deleted
kubectl get vm,vmi,dv,pvc

# Method 1: Delete by resource name (recommended)
# Replace 'vm-name' with your actual VM name
kubectl delete vm vm-name
kubectl delete vmi vm-name  # If VM instance is still running
kubectl delete dv datavolume-name
kubectl delete pvc pvc-name

# Method 2: Force delete stuck resources
# If resources are stuck in terminating state, patch finalizers
kubectl patch vm vm-name -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl patch vmi vm-name -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl patch dv datavolume-name -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl patch pvc pvc-name -p '{"metadata":{"finalizers":[]}}' --type=merge

# Then force delete with grace period 0
kubectl delete vm vm-name --force --grace-period=0
kubectl delete vmi vm-name --force --grace-period=0
kubectl delete dv datavolume-name --force --grace-period=0
kubectl delete pvc pvc-name --force --grace-period=0

# Method 3: Delete all VMs in a namespace (use with caution!)
kubectl delete vm --all -n default
kubectl delete vmi --all -n default
kubectl delete dv --all -n default
kubectl delete pvc --all -n default

# Method 4: Interactive deletion with confirmation
kubectl get vm -o name | xargs -I {} kubectl delete {}

# Check if resources are completely removed
kubectl get vm,vmi,dv,pvc
```

**Example for ubuntu1-vm-cloudinit:**

```bash
# Check current resources
kubectl get vm,vmi,dv,pvc

# Delete the specific VM and related resources
kubectl delete vm ubuntu1-vm-cloudinit
kubectl delete vmi ubuntu1-vm-cloudinit
kubectl delete dv ubuntu1
kubectl delete pvc ubuntu1

# If stuck, force delete
kubectl patch vm ubuntu1-vm-cloudinit -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete vm ubuntu1-vm-cloudinit --force --grace-period=0
kubectl patch dv ubuntu1 -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete dv ubuntu1 --force --grace-period=0
```

**Additional cleanup for persistent storage:**

```bash
# If using local storage, clean up directories
sudo rm -rf /var/lib/rancher/k3s/storage/pvc-*

# Check for any remaining pods
kubectl get pods | grep virt-launcher
kubectl delete pod --force --grace-period=0 pod-name
```

## Ansible Commands

```bash
python3 ansible/dynamic_inventory.py --list
```

```bash
pip3 install --user ansible
sudo apt update && sudo apt install -y ansible
```

kubectl delete vm,vmi,dv,pvc --all
