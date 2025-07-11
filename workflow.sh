#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source IP detection script
source scripts/detect-ip.sh

# Configuration
IMAGE_NAME="vm-watcher"
IMAGE_TAG="latest"
REGISTRY_HOST="$NODE_IP"
REGISTRY_PORT="30500"

print_header() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "$1"
    echo "=================================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

show_help() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  detect-ip          Show detected IP addresses and endpoints"
    echo "  update-configs     Update configuration files with current IP"
    echo "  setup-kubevirt     Setup KubeVirt (required for VMs)"
    echo "  setup-cdi          Setup CDI (required for VMs)"
    echo "  setup-registry     Setup Docker Registry"
    echo "  build-operator     Build operator image"
    echo "  push-operator      Build and push operator to Docker Registry"
    echo "  deploy             Deploy operator (installs CRDs and deploys operator)"
    echo "  deploy-stack       Deploy Guacamole stack (Guacamole, Postgres, Keycloak)"
    echo "  monitoring         Deploy monitoring stack (Prometheus & Grafana)"
    echo "  push-custom-vm     Build and push custom Ubuntu Docker image to Registry"
    echo "  status             Show status of all components"
    echo "  cleanup-monitoring Clean up monitoring stack"
    echo "  cleanup-all        COMPLETE CLEANUP - Reset cluster to clean slate"
    echo "  force-clean-ns     Force clean stuck namespaces"
    echo "  full-setup         Complete setup: KubeVirt + CDI + Registry + Build + Push + Deploy + Stack + Monitoring"
    echo "  help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 detect-ip          # Show detected IP and endpoints"
    echo "  $0 update-configs     # Update configs with current IP"
    echo "  $0 full-setup         # Complete setup from scratch"
    echo "  $0 build-operator     # Just build the operator image"
    echo "  $0 push-operator      # Build and push operator to registry"
    echo "  $0 cleanup-all        # Complete cleanup - removes everything!"
}

setup_registry() {
    print_header "SETTING UP DOCKER REGISTRY"
    
    # Deploy Docker registry (this creates the namespace first)
    echo -e "${BLUE}Deploying Docker Registry from repository/docker-registry.yaml...${NC}"
    kubectl apply -f repository/docker-registry.yaml
    
    # Wait a moment for namespace to be created
    echo -e "${BLUE}Waiting for namespace to be ready...${NC}"
    kubectl wait --for=condition=Ready --timeout=30s namespace/docker-registry || true
    
    # Now apply the persistent storage
    echo -e "${BLUE}Setting up persistent storage for registry...${NC}"
    kubectl apply -f repository/registry-storage.yaml
    
    # Wait for registry to be ready
    echo -e "${BLUE}Waiting for Docker Registry to be ready...${NC}"
    kubectl wait --for=condition=Ready pods -l app=docker-registry -n docker-registry --timeout=180s || true
    
    # Check registry status
    echo -e "${BLUE}Checking Docker Registry deployment status...${NC}"
    kubectl get pods -n docker-registry

    # Wait Until It starts
    sleep 30
    
    print_success "Docker Registry setup completed"
    echo -e "${GREEN}Registry is available at: ${BLUE}http://$NODE_IP:30500${NC}"
    echo -e "${GREEN}Registry UI is available at: ${BLUE}http://$NODE_IP:30501${NC}"
    echo -e "${GREEN}To use: ${BLUE}docker tag <image> $NODE_IP:30500/<image> && docker push $NODE_IP:30500/<image>${NC}"
}

build_operator() {
    print_header "BUILDING OPERATOR IMAGE"
    
    FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    echo "Building operator image..."
    echo "Image name: ${FULL_IMAGE_NAME}"
    
    # Build the Docker image with registry tag
    docker build -t "${FULL_IMAGE_NAME}" .
    
    echo ""
    echo "Build completed successfully!"
    echo "Image: ${FULL_IMAGE_NAME}"
    
    print_success "Operator build completed"
}

build_custom_vm_image() {
    print_header "BUILDING CUSTOM VM IMAGE"
    
    CUSTOM_IMAGE_NAME="custom-ubuntu-desktop"
    CUSTOM_IMAGE_TAG="22.04"
    FULL_CUSTOM_IMAGE_NAME="${CUSTOM_IMAGE_NAME}:${CUSTOM_IMAGE_TAG}"
    
    echo "Building custom Ubuntu desktop image..."
    echo "Image name: ${FULL_CUSTOM_IMAGE_NAME}"
    
    # Change to custom image directory and build
    cd virtualmachines/custom_image
    docker build -t "${FULL_CUSTOM_IMAGE_NAME}" .
    cd ../..
    
    echo ""
    echo "Build completed successfully!"
    echo "Image: ${FULL_CUSTOM_IMAGE_NAME}"
    echo ""
    echo "Default credentials:"
    echo "  Username: ubuntu"
    echo "  Password: ubuntu"
    echo "  VNC Password: vm2test"
    echo ""
    echo "Exposed ports:"
    echo "  SSH: 22"
    echo "  RDP: 3389"
    echo "  VNC: 5900, 5901"
    
    print_success "Custom VM image build completed"
}

push_custom_vm_image() {
    print_header "PUSHING CUSTOM VM IMAGE TO DOCKER REGISTRY"
    
    CUSTOM_IMAGE_NAME="custom-ubuntu-desktop"
    CUSTOM_IMAGE_TAG="22.04"
    LOCAL_IMAGE_NAME="${CUSTOM_IMAGE_NAME}:${CUSTOM_IMAGE_TAG}"
    REGISTRY_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${CUSTOM_IMAGE_NAME}:${CUSTOM_IMAGE_TAG}"
    
    echo "Building custom Ubuntu desktop image..."
    cd virtualmachines/custom_image
    docker build -t "${LOCAL_IMAGE_NAME}" .
    cd ../..
    
    echo "Tagging image for registry..."
    docker tag "${LOCAL_IMAGE_NAME}" "${REGISTRY_IMAGE_NAME}"
    
    echo "Pushing to Docker registry..."
    if docker push "${REGISTRY_IMAGE_NAME}" 2>/dev/null; then
        print_success "Successfully pushed custom VM image to Docker Registry"
        echo "Registry image: ${REGISTRY_IMAGE_NAME}"
    else
        print_warning "Docker Registry push failed. Possible reasons:"
        echo "      - Docker Registry is not running (run: ./workflow.sh setup-registry)"
        echo "      - Network connectivity issues"
        echo ""
        echo "   📋 To push manually later:"
        echo "      docker tag ${LOCAL_IMAGE_NAME} ${REGISTRY_IMAGE_NAME}"
        echo "      docker push ${REGISTRY_IMAGE_NAME}"
    fi
    
    print_success "Custom VM image push completed"
}

push_operator() {
    print_header "PUSHING OPERATOR TO DOCKER REGISTRY"
    
    FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    echo "Pushing to Docker registry..."
    if docker push ${FULL_IMAGE_NAME} 2>/dev/null; then
        print_success "Successfully pushed to Docker Registry"
    else
        print_warning "Docker Registry push failed. Possible reasons:"
        echo "      - Docker Registry is not running (run: ./workflow.sh setup-registry)"
        echo "      - Network connectivity issues"
        echo ""
        echo "   📋 To push manually later:"
        echo "      docker push ${FULL_IMAGE_NAME}"
    fi
    
    print_success "Push to registry completed"
}

deploy_monitoring() {
    print_header "DEPLOYING MONITORING STACK"
    
    cd monitoring
    
    echo "Creating monitoring namespace and RBAC..."
    kubectl apply -f 01-namespace-rbac.yaml
    
    echo "Setting up persistent storage..."
    kubectl apply -f persistent-storage.yaml
    
    echo "Generating and configuring Prometheus..."
    # Generate prometheus config
    kubectl create configmap prometheus-config \
      --from-file=prometheus.yml=prometheus.yml \
      --namespace=monitoring \
      --dry-run=client -o yaml > 02-prometheus-config.yaml
    
    kubectl apply -f 02-prometheus-config.yaml
    
    echo "Deploying Prometheus..."
    kubectl apply -f 03-prometheus.yaml
    
    echo "Deploying Node Exporter..."
    kubectl apply -f 04-node-exporter.yaml
    
    echo "Configuring Grafana..."
    kubectl apply -f 05-grafana-config.yaml
    
    echo "Deploying Grafana..."
    kubectl apply -f 06-grafana.yaml
    
    echo "Waiting for pods to be ready..."
    kubectl wait --for=condition=Ready pod -l app=prometheus -n monitoring --timeout=300s || true
    kubectl wait --for=condition=Ready pod -l app=grafana -n monitoring --timeout=300s || true
    
    cd ..
    
    print_success "Monitoring stack deployed successfully!"
    echo ""
    echo "Access URLs:"
    echo "  Prometheus: http://$NODE_IP:30090"
    echo "  Grafana: http://$NODE_IP:30300 (admin/admin)"
}

cleanup_monitoring() {
    print_header "CLEANING UP MONITORING STACK"
    
    cd monitoring
    
    # Remove components in reverse order
    echo "Removing Grafana..."
    kubectl delete -f 06-grafana.yaml --ignore-not-found=true
    
    echo "Removing Grafana configs..."
    kubectl delete -f 05-grafana-config.yaml --ignore-not-found=true
    
    echo "Removing Node Exporter..."
    kubectl delete -f 04-node-exporter.yaml --ignore-not-found=true
    
    echo "Removing Prometheus..."
    kubectl delete -f 03-prometheus.yaml --ignore-not-found=true
    
    echo "Removing Prometheus config..."
    kubectl delete -f 02-prometheus-config.yaml --ignore-not-found=true
    
    echo "Removing namespace and RBAC..."
    kubectl delete -f 01-namespace-rbac.yaml --ignore-not-found=true
    
    echo "Waiting for namespace cleanup..."
    kubectl wait --for=delete namespace/monitoring --timeout=60s || true
    
    cd ..
    
    print_success "Monitoring stack cleanup completed!"
}

deploy_stack() {
    print_header "DEPLOYING GUACAMOLE STACK"
    
    # Substitute environment variables in stack.yaml
    substitute_env_vars
    
    echo "Deploying Guacamole stack (Guacamole, Postgres, Keycloak)..."
    kubectl apply -f stack/stack.yaml
    
    echo "Waiting for components to be ready..."
    echo "  Waiting for Postgres..."
    kubectl wait --for=condition=Ready pod -l app=postgres -n guacamole --timeout=300s || true
    
    echo "  Waiting for Guacd..."
    kubectl wait --for=condition=Ready pod -l app=guacd -n guacamole --timeout=300s || true
    
    echo "  Waiting for Guacamole..."
    kubectl wait --for=condition=Ready pod -l app=guacamole -n guacamole --timeout=300s || true
    
    echo "  Waiting for Keycloak..."
    kubectl wait --for=condition=Ready pod -l app=keycloak -n guacamole --timeout=300s || true
    
    echo "Checking stack status..."
    kubectl get pods -n guacamole
    
    print_success "Guacamole stack deployed successfully!"
    echo ""
    echo "Access URLs:"
    echo "  Guacamole: http://$NODE_IP:30080/guacamole/"
    echo "  Keycloak: http://$NODE_IP:30081/"
    echo ""
    echo "Default Keycloak admin credentials:"
    echo "  Username: admin"
    echo "  Password: admin"
}

cleanup_all() {
    print_header "COMPLETE CLUSTER CLEANUP - RESET TO CLEAN SLATE"
    
    print_warning "This will delete EVERYTHING: deployments, secrets, configs, persisted data..."
    echo -e "${YELLOW}Are you sure you want to proceed? This action cannot be undone!${NC}"
    read -p "Type 'YES' to confirm: " confirmation
    
    if [ "$confirmation" != "YES" ]; then
        print_error "Cleanup cancelled"
        exit 1
    fi
    
    print_header "DELETING ALL PROJECT RESOURCES"
    
    # 1. Remove operator deployment
    echo -e "${BLUE}Removing operator deployment...${NC}"
    make undeploy 2>/dev/null || true
    
    # 2. Remove monitoring stack
    echo -e "${BLUE}Removing monitoring stack...${NC}"
    cleanup_monitoring 2>/dev/null || true
    
    # 3. Remove CRDs
    echo -e "${BLUE}Removing Custom Resource Definitions...${NC}"
    make uninstall 2>/dev/null || true
    
    # 4. Delete project namespaces
    echo -e "${BLUE}Deleting project namespaces...${NC}"
    for ns in kubebuilderproject-system kubevirt cdi monitoring docker-registry guacamole; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            echo "  Deleting namespace: $ns"
            kubectl delete namespace $ns --ignore-not-found=true --timeout=30s 2>/dev/null || true
        fi
    done
    
    # 5. Force cleanup stuck namespaces
    echo -e "${BLUE}Force cleaning any stuck namespaces...${NC}"
    for ns in kubebuilderproject-system kubevirt cdi monitoring docker-registry guacamole; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            echo "  Force cleaning namespace: $ns"
            kubectl patch namespace $ns --type='merge' -p='{"spec":{"finalizers":[]}}' 2>/dev/null || true
        fi
    done
    
    # 6. Clean up Docker resources
    echo -e "${BLUE}Cleaning up Docker resources...${NC}"
    docker ps -a | grep -E "(registry|vm-watcher)" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true
    docker images | grep -E "(vm-watcher|registry)" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
    
    # 7. Verification
    echo -e "${BLUE}Cleanup verification...${NC}"
    echo "Remaining namespaces:"
    kubectl get namespaces | grep -E "(kubebuilder|kubevirt|cdi|monitoring|docker-registry|guacamole)" || echo "✅ No project namespaces found"
    
    print_success "Cleanup completed!"
    echo -e "${GREEN}You can now run: ${BLUE}./workflow.sh full-setup${GREEN} to deploy everything fresh${NC}"
}

show_status() {
    print_header "SYSTEM STATUS"
    
    echo -e "${BLUE}KubeVirt Status:${NC}"
    if kubectl get namespace kubevirt >/dev/null 2>&1; then
        KUBEVIRT_PHASE=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}" 2>/dev/null || echo "Unknown")
        echo "KubeVirt phase: $KUBEVIRT_PHASE"
        if [ "$KUBEVIRT_PHASE" = "Deployed" ]; then
            print_success "KubeVirt is deployed and ready"
        else
            print_warning "KubeVirt is not fully deployed"
        fi
    else
        print_warning "KubeVirt is not installed"
    fi
    echo ""
    
    echo -e "${BLUE}CDI Status:${NC}"
    if kubectl get namespace cdi >/dev/null 2>&1; then
        CDI_PHASE=$(kubectl get cdi cdi -n cdi -o=jsonpath="{.status.phase}" 2>/dev/null || echo "Unknown")
        echo "CDI phase: $CDI_PHASE"
        if [ "$CDI_PHASE" = "Deployed" ]; then
            print_success "CDI is deployed and ready"
        else
            print_warning "CDI is not fully deployed"
        fi
    else
        print_warning "CDI is not installed"
    fi
    echo ""
    
    echo -e "${BLUE}Docker Images:${NC}"
    docker images | grep -E "(vm-watcher|controller|custom-ubuntu)" || echo "No operator images found"
    echo ""
    
    echo -e "${BLUE}Docker Registry Status:${NC}"
    if curl -s http://$REGISTRY_HOST:$REGISTRY_PORT/v2/ >/dev/null 2>&1; then
        print_success "Docker Registry is running at http://$REGISTRY_HOST:$REGISTRY_PORT"
        print_success "Registry UI is available at http://$REGISTRY_HOST:30501"
    else
        print_warning "Docker Registry is not accessible"
    fi
    echo ""
    
    echo -e "${BLUE}Kubernetes Pods:${NC}"
    kubectl get pods --all-namespaces | grep -E "(vm-watcher|controller|monitoring)" || echo "No operator or monitoring pods found"
    
    echo -e "${BLUE}Operator Status:${NC}"
    if kubectl get namespace kubebuilderproject-system >/dev/null 2>&1; then
        echo "Operator namespace exists"
        kubectl get pods -n kubebuilderproject-system || echo "No operator pods found"
    else
        echo "Operator not deployed"
    fi
    echo ""
    
    echo -e "${BLUE}Monitoring Status:${NC}"
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        echo "Monitoring namespace exists"
        kubectl get pods -n monitoring || echo "No monitoring pods found"
        echo ""
        echo "Access URLs:"
        echo "  Prometheus: http://$NODE_IP:30090"
        echo "  Grafana: http://$NODE_IP:30300 (admin/admin)"
    else
        echo "Monitoring not deployed"
    fi
}

force_clean_namespaces() {
    print_header "FORCE CLEANING STUCK NAMESPACES"
    
    echo -e "${BLUE}Checking for stuck namespaces...${NC}"
    stuck_namespaces=$(kubectl get namespaces | grep -E "(kubevirt|cdi|kubebuilder|monitoring|docker-registry|guacamole)" | grep "Terminating" | awk '{print $1}' || true)
    
    if [ -z "$stuck_namespaces" ]; then
        print_success "No stuck namespaces found"
        return
    fi
    
    echo -e "${YELLOW}Found stuck namespaces: $stuck_namespaces${NC}"
    
    for ns in $stuck_namespaces; do
        echo -e "${BLUE}Force cleaning namespace: $ns${NC}"
        
        # Remove finalizers
        kubectl get namespace $ns -o json 2>/dev/null | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
        kubectl patch namespace $ns --type='merge' -p='{"spec":{"finalizers":[]}}' 2>/dev/null || true
        
        # Force delete all resources
        kubectl delete all --all -n $ns --force --grace-period=0 2>/dev/null || true
    done
    
    sleep 5
    
    # Check result
    remaining=$(kubectl get namespaces | grep -E "(kubevirt|cdi|kubebuilder|monitoring|docker-registry|guacamole)" | grep "Terminating" || true)
    if [ -z "$remaining" ]; then
        print_success "All namespaces cleaned successfully"
    else
        print_warning "Some namespaces still stuck: $remaining"
        echo -e "${YELLOW}You may need to restart your cluster if issues persist${NC}"
    fi
}

install_kubevirt() {
    print_header "INSTALLING KUBEVIRT"
    
    # Check if KubeVirt is already installed
    if kubectl get namespace kubevirt >/dev/null 2>&1; then
        PHASE=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}" 2>/dev/null || echo "Unknown")
        if [ "$PHASE" = "Deployed" ]; then
            print_success "KubeVirt is already installed and deployed"
            return 0
        else
            echo "KubeVirt exists but status is: $PHASE"
        fi
    fi
    
    echo "Getting latest KubeVirt version..."
    KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
    echo "Installing KubeVirt version: $KUBEVIRT_VERSION"
    
    if [ -z "$KUBEVIRT_VERSION" ]; then
        print_error "Failed to get KubeVirt version. Using fallback version v1.5.2"
        KUBEVIRT_VERSION="v1.5.2"
    fi
    
    echo "Installing KubeVirt operator..."
    kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
    
    echo "Installing KubeVirt custom resources..."
    kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
    
    echo "Waiting for KubeVirt to be deployed..."
    sleep 180
    
    echo "Checking KubeVirt status..."
    PHASE=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}" 2>/dev/null || echo "Unknown")
    echo "KubeVirt phase: $PHASE"
    
    if [ "$PHASE" = "Deployed" ]; then
        print_success "KubeVirt installation completed successfully"
    else
        print_warning "KubeVirt may still be deploying. Check status with: kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt"
    fi
    
    echo "KubeVirt pods:"
    kubectl get pods -n kubevirt
}

install_cdi() {
    print_header "INSTALLING CDI (CONTAINERIZED DATA IMPORTER)"
    
    # Check if CDI is already installed
    if kubectl get namespace cdi >/dev/null 2>&1; then
        PHASE=$(kubectl get cdi cdi -n cdi -o=jsonpath="{.status.phase}" 2>/dev/null || echo "Unknown")
        if [ "$PHASE" = "Deployed" ]; then
            print_success "CDI is already installed and deployed"
            return 0
        else
            echo "CDI exists but status is: $PHASE"
        fi
    fi
    
    echo "Getting latest CDI version..."
    CDI_VERSION=$(basename $(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest))
    echo "Installing CDI version: $CDI_VERSION"
    
    if [ -z "$CDI_VERSION" ]; then
        print_error "Failed to get CDI version. Using fallback version v1.61.3"
        CDI_VERSION="v1.61.3"
    fi
    
    echo "Installing CDI operator..."
    kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml"
    
    echo "Installing CDI custom resources..."
    kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml"
    
    echo "Waiting for CDI to be deployed..."
    sleep 30
    
    echo "Checking CDI status..."
    PHASE=$(kubectl get cdi cdi -n cdi -o=jsonpath="{.status.phase}" 2>/dev/null || echo "Unknown")
    echo "CDI phase: $PHASE"
    
    if [ "$PHASE" = "Deployed" ]; then
        print_success "CDI installation completed successfully"
    else
        print_warning "CDI may still be deploying. Check status with: kubectl get cdi cdi -n cdi"
    fi
    
    echo "CDI pods:"
    kubectl get pods -n cdi
}

# Function to substitute environment variables in configuration files
substitute_env_vars() {
    print_header "SUBSTITUTING ENVIRONMENT VARIABLES"
    
    # Create backup directory
    mkdir -p .backup
    
    # List of files to process
    local files=(
        "config/manager/manager.yaml"
        "stack/stack.yaml"
        "config/default/kustomization.yaml"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "Processing $file"
            # Create backup
            cp "$file" ".backup/$(basename $file).backup"
            # Substitute environment variables
            envsubst < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        fi
    done
    
    print_success "Environment variable substitution completed"
}

# Function to update system configurations
update_system_configs() {
    print_header "UPDATING SYSTEM CONFIGURATIONS"
    
    # Update Docker daemon configuration
    if command -v docker >/dev/null 2>&1; then
        print_success "Updating Docker configuration for registry at $NODE_IP:30500"
        sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["$NODE_IP:30500"]
}
EOF
        sudo systemctl restart docker
        print_success "Docker configuration updated"
    fi
    
    # Update K3s configuration
    if systemctl is-active --quiet k3s; then
        print_success "Updating K3s configuration for registry at $NODE_IP:30500"
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
        print_success "K3s configuration updated"
    fi
    
    # Update CDI configuration
    if kubectl get cdi cdi >/dev/null 2>&1; then
        print_success "Updating CDI configuration for insecure registry"
        kubectl patch cdi cdi --type='merge' -p="{\"spec\":{\"config\":{\"insecureRegistries\":[\"$NODE_IP:30500\"]}}}"
        print_success "CDI configuration updated"
    fi
}

# Function to show detected endpoints
show_endpoints() {
    print_header "DETECTED ENDPOINTS"
    echo -e "${GREEN}Node IP: ${BLUE}$NODE_IP${NC}"
    echo -e "${GREEN}Registry: ${BLUE}http://$NODE_IP:30500${NC}"
    echo -e "${GREEN}Registry UI: ${BLUE}http://$NODE_IP:30501${NC}"
    echo -e "${GREEN}Guacamole: ${BLUE}http://$NODE_IP:30080/guacamole/${NC}"
    echo -e "${GREEN}Keycloak: ${BLUE}http://$NODE_IP:30081${NC}"
    echo -e "${GREEN}Grafana: ${BLUE}http://$NODE_IP:30300${NC}"
    echo -e "${GREEN}Prometheus: ${BLUE}http://$NODE_IP:30090${NC}"
    echo ""
}

case "${1:-help}" in
    setup-kubevirt)
        install_kubevirt
        ;;
    setup-cdi)
        install_cdi
        ;;        
    setup-registry)
        setup_registry
        ;;
    build-operator)
        build_operator
        ;;
    build-custom-vm)
        build_custom_vm_image
        ;;
    push-operator)
        build_operator
        push_operator
        ;;
    push-custom-vm)
        push_custom_vm_image
        ;;
    deploy)
        make install  # Install CRDs before deploying operator
        make deploy
        ;;
    deploy-stack)
        deploy_stack
        ;;
    monitoring)
        deploy_monitoring
        ;;
    cleanup-monitoring)
        cleanup_monitoring
        ;;
    cleanup-all)
        cleanup_all
        ;;
    force-clean-ns)
        force_clean_namespaces
        ;;
    status)
        show_status
        ;;
    full-setup)
        print_header "COMPLETE SETUP WORKFLOW"
        show_endpoints
        update_system_configs
        install_kubevirt
        sleep 180
        install_cdi
        sleep 30
        setup_registry
        sleep 30
        build_operator
        push_operator
        make install
        make deploy
        deploy_stack
        deploy_monitoring
        print_header "SETUP COMPLETE!"
        show_endpoints
        show_status
        ;;
    detect-ip)
        show_endpoints
        ;;
    update-configs)
        substitute_env_vars
        update_system_configs
        ;;
    help|*)
        show_help
        ;;
esac
