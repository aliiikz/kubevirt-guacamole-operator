#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
IMAGE_NAME="vm-watcher"
IMAGE_TAG="latest"
REGISTRY_HOST="192.168.1.4"
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
    echo "  setup-registry     Setup Docker Registry"
    echo "  build              Build operator image"
    echo "  build-custom-vm    Build custom Ubuntu VM image"
    echo "  push               Build and push operator to Docker Registry"
    echo "  deploy             Deploy operator using Docker Registry"
    echo "  cleanup-all        COMPLETE CLEANUP - Reset cluster to clean slate"
    echo "  force-clean-ns     Force clean stuck namespaces"
    echo "  status             Show status of all components"
    echo "  full-setup         Complete setup: Registry + Build + Push + Deploy"
    echo "  help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 full-setup         # Complete setup from scratch"
    echo "  $0 build              # Just build the operator image"
    echo "  $0 build-custom-vm    # Build custom Ubuntu VM image"
    echo "  $0 push               # Build and push operator to registry"
    echo "  $0 cleanup-all        # Complete cleanup - removes everything!"
}

setup_registry() {
    print_header "SETTING UP DOCKER REGISTRY"
    
    # Deploy simple Docker registry
    echo -e "${BLUE}Deploying Docker Registry from repository/docker-registry.yaml...${NC}"
    kubectl apply -f repository/docker-registry.yaml
    
    # Wait for registry to be ready
    echo -e "${BLUE}Waiting for Docker Registry to be ready...${NC}"
    kubectl wait --for=condition=Ready pods -l app=docker-registry -n docker-registry --timeout=180s || true
    
    # Check registry status
    echo -e "${BLUE}Checking Docker Registry deployment status...${NC}"
    kubectl get pods -n docker-registry
    
    print_success "Docker Registry setup completed"
    echo -e "${GREEN}Registry is available at: ${BLUE}http://localhost:30500${NC}"
    echo -e "${GREEN}Registry UI is available at: ${BLUE}http://localhost:30501${NC}"
    echo -e "${GREEN}To use: ${BLUE}docker tag <image> localhost:30500/<image> && docker push localhost:30500/<image>${NC}"
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
    echo "  Prometheus: http://localhost:30090"
    echo "  Grafana: http://localhost:30091 (admin/admin)"
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
    
    # 1. Stop and remove all VMs first
    echo -e "${BLUE}Stopping all Virtual Machines...${NC}"
    kubectl get vm --all-namespaces --no-headers 2>/dev/null | awk '{print $2 " -n " $1}' | xargs -r -I {} kubectl delete vm {} --force --grace-period=0 || true
    kubectl get vmi --all-namespaces --no-headers 2>/dev/null | awk '{print $2 " -n " $1}' | xargs -r -I {} kubectl delete vmi {} --force --grace-period=0 || true
    
    # 2. Remove monitoring stack
    echo -e "${BLUE}Removing monitoring stack...${NC}"
    cleanup_monitoring || true
    
    # 3. Remove operator deployment
    echo -e "${BLUE}Removing operator deployment...${NC}"
    make undeploy || true
    
    # 4. Force remove stuck KubeVirt and CDI resources
    echo -e "${BLUE}Force removing stuck KubeVirt/CDI resources...${NC}"
    
    # Remove finalizers from KubeVirt resource if it exists
    kubectl get kubevirt --all-namespaces --no-headers 2>/dev/null | while read namespace name rest; do
        echo "  Removing finalizers from kubevirt/$name in namespace $namespace"
        kubectl patch kubevirt $name -n $namespace --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete kubevirt $name -n $namespace --force --grace-period=0 2>/dev/null || true
    done
    
    # Remove finalizers from CDI resource if it exists
    kubectl get cdi --all-namespaces --no-headers 2>/dev/null | while read namespace name rest; do
        echo "  Removing finalizers from cdi/$name in namespace $namespace"
        kubectl patch cdi $name -n $namespace --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete cdi $name -n $namespace --force --grace-period=0 2>/dev/null || true
    done
    
    # Wait a moment for resources to be removed
    sleep 5
    
    # 5. Remove CRDs (this will cascade delete all custom resources)
    echo -e "${BLUE}Removing Custom Resource Definitions...${NC}"
    make uninstall || true
    
    # Force remove KubeVirt/CDI CRDs with finalizer removal
    echo -e "${BLUE}Force removing KubeVirt/CDI CRDs...${NC}"
    kubectl get crd --no-headers | grep -E "(kubevirt|cdi)" | awk '{print $1}' | while read crd; do
        echo "  Force removing CRD: $crd"
        kubectl patch crd $crd --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete crd $crd --force --grace-period=0 2>/dev/null || true
    done
    
    # 6. Delete all project namespaces (aggressive approach)
    echo -e "${BLUE}Deleting project namespaces...${NC}"
    
    # First, try normal deletion without waiting
    for ns in kubebuilderproject-system kubevirt cdi monitoring docker-registry guacamole; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            echo "  Initiating deletion of namespace: $ns"
            kubectl delete namespace $ns --ignore-not-found=true --timeout=10s >/dev/null 2>&1 &
        fi
    done
    
    # Wait briefly for deletion attempts to start
    sleep 5
    
    # 7. Force cleanup any stuck namespaces immediately
    echo -e "${BLUE}Force cleaning stuck namespaces (aggressive cleanup)...${NC}"
    
    # Remove finalizers from all target namespaces
    for ns in kubebuilderproject-system kubevirt cdi monitoring docker-registry guacamole; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            echo "  Force cleaning namespace: $ns"
            # Remove finalizers
            kubectl get namespace $ns -o json 2>/dev/null | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
            
            # Also try patching directly
            kubectl patch namespace $ns --type='merge' -p='{"spec":{"finalizers":[]}}' 2>/dev/null || true
            
            # Force delete any remaining resources in the namespace
            kubectl delete all --all -n $ns --force --grace-period=0 2>/dev/null || true
        fi
    done
    
    # Additional aggressive cleanup for stuck resources
    echo -e "${BLUE}Additional aggressive cleanup...${NC}"
    
    # Kill any webhook configurations that might be blocking
    kubectl delete validatingwebhookconfiguration --all --ignore-not-found=true 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration --all --ignore-not-found=true 2>/dev/null || true
    
    # Remove any remaining CDI/KubeVirt operators
    kubectl delete deployment --all-namespaces --selector="app=cdi-operator" --force --grace-period=0 2>/dev/null || true
    kubectl delete deployment --all-namespaces --selector="kubevirt.io=virt-operator" --force --grace-period=0 2>/dev/null || true
    
    # 8. Clean up persistent volumes and storage
    echo -e "${BLUE}Cleaning up persistent storage...${NC}"
    
    # Delete all PVCs aggressively 
    kubectl get pvc --all-namespaces --no-headers 2>/dev/null | awk '{print $2 " -n " $1}' | xargs -r -I {} kubectl delete pvc {} --force --grace-period=0 2>/dev/null || true
    
    # Delete PVs and remove their finalizers if stuck
    kubectl get pv --no-headers 2>/dev/null | awk '{print $1}' | while read pv; do
        kubectl patch pv $pv --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete pv $pv --force --grace-period=0 2>/dev/null || true
    done
    
    # 9. Clean up any remaining pods
    echo -e "${BLUE}Force removing any remaining pods...${NC}"
    for ns in kubebuilderproject-system kubevirt cdi monitoring docker-registry guacamole; do
        kubectl delete pods --all -n $ns --force --grace-period=0 2>/dev/null || true
    done
    
    # 10. Clean up Docker containers and images
    echo -e "${BLUE}Cleaning up Docker resources...${NC}"
    
    # Stop and remove registry containers  
    docker ps -a | grep -E "(registry|vm-watcher|controller)" | awk '{print $1}' | xargs -r docker rm -f || true
    
    # Remove project-related images
    docker images | grep -E "(vm-watcher|controller|registry)" | awk '{print $3}' | xargs -r docker rmi -f || true
    
    # Clean up dangling images and volumes
    docker system prune -f || true
    docker volume prune -f || true
    
    # 11. Clean up any remaining cluster resources
    echo -e "${BLUE}Cleaning up remaining cluster resources...${NC}"
    
    # Remove any stuck finalizers on nodes
    kubectl get nodes -o name | xargs -r -I {} kubectl patch {} --type='merge' -p='{"metadata":{"finalizers":[]}}' || true
    
    # 12. Final verification and wait
    echo -e "${BLUE}Final cleanup verification...${NC}"
    
    # Wait a bit longer for everything to settle
    sleep 10
    
    # Force cleanup any remaining stuck namespaces one more time
    for ns in kubebuilderproject-system kubevirt cdi monitoring docker-registry guacamole; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            echo "  Final cleanup attempt for namespace: $ns"
            kubectl patch namespace $ns --type='merge' -p='{"spec":{"finalizers":[]}}' 2>/dev/null || true
        fi
    done
    
    sleep 5
    
    # 13. Verify cleanup
    print_header "CLEANUP VERIFICATION"
    
    echo -e "${BLUE}Remaining namespaces:${NC}"
    kubectl get namespaces | grep -E "(kubebuilder|kubevirt|cdi|monitoring|docker-registry|guacamole)" || echo "✅ No project namespaces found"
    
    echo -e "${BLUE}Remaining PVs:${NC}"
    kubectl get pv 2>/dev/null || echo "No persistent volumes found"
    
    echo -e "${BLUE}Remaining project CRDs:${NC}"
    kubectl get crd | grep -E "(kubevirt|virtualmachine|guacamole)" || echo "No project CRDs found"
    
    echo -e "${BLUE}Docker containers:${NC}"
    docker ps | grep -E "(registry|vm-watcher|controller)" || echo "No project containers running"
    
    print_success "Complete cluster cleanup finished!"
    print_success "Your cluster is now reset to a clean slate"
    echo -e "${GREEN}You can now run: ${BLUE}./workflow.sh full-setup${GREEN} to deploy everything fresh${NC}"
}

show_status() {
    print_header "SYSTEM STATUS"
    
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
    echo ""
    
    echo -e "${BLUE}Monitoring Status:${NC}"
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        echo "Monitoring namespace exists"
        kubectl get pods -n monitoring || echo "No monitoring pods found"
        echo ""
        echo "Access URLs:"
        echo "  Prometheus: http://localhost:30090"
        echo "  Grafana: http://localhost:30091 (admin/admin)"
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

case "${1:-help}" in
    setup-registry)
        setup_registry
        ;;
    build)
        build_operator
        ;;
    build-custom-vm)
        build_custom_vm_image
        ;;
    push)
        build_operator
        push_operator
        ;;
    deploy)
        make deploy
        ;;
    monitoring)
        deploy_monitoring
        ;;
    cleanup)
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
        print_header "🚀 COMPLETE SETUP WORKFLOW"
        setup_registry
        sleep 5  # Give Registry time to start
        build_operator
        push_operator
        make deploy
        deploy_monitoring
        print_header "🎉 SETUP COMPLETE!"
        show_status
        ;;
    help|*)
        show_help
        ;;
esac
