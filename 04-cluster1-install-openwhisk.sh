#!/bin/bash
#####################################################################
# OpenWhisk Installation Script - CLUSTER 1 (Containers)
# Purpose: Deploy Apache OpenWhisk on Kubernetes with Docker runtime
# Usage: Run on MASTER node of Cluster 1 after all workers joined
#####################################################################

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#####################################################################
# Configuration
#####################################################################
OPENWHISK_NAMESPACE="openwhisk"
HELM_RELEASE_NAME="openwhisk"

#####################################################################
# Step 1: Verify cluster readiness
#####################################################################
verify_cluster() {
    log_info "Verifying cluster readiness..."
    
    # Check if all nodes are Ready
    NOT_READY=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [ "$NOT_READY" -gt 0 ]; then
        log_warn "Some nodes are not Ready. Please wait for all nodes to be Ready."
        kubectl get nodes
        exit 1
    fi
    
    log_info "✓ All nodes are Ready"
    
    # Check minimum requirements
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    if [ "$NODE_COUNT" -lt 2 ]; then
        log_warn "Warning: OpenWhisk works better with at least 2 nodes (1 master + 1+ workers)"
    fi
    
    log_info "✓ Cluster has ${NODE_COUNT} nodes"
}

#####################################################################
# Step 2: Install Helm
#####################################################################
install_helm() {
    log_info "Installing Helm..."
    
    if command -v helm &> /dev/null; then
        log_info "Helm is already installed: $(helm version --short)"
        return
    fi
    
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    log_info "Helm installed: $(helm version --short)"
}

#####################################################################
# Step 3: Create OpenWhisk namespace
#####################################################################
create_namespace() {
    log_info "Creating OpenWhisk namespace..."
    
    kubectl create namespace ${OPENWHISK_NAMESPACE} || log_info "Namespace already exists"
    kubectl label namespace ${OPENWHISK_NAMESPACE} name=openwhisk --overwrite
}

#####################################################################
# Step 4: Label worker nodes for OpenWhisk
#####################################################################
label_nodes() {
    log_info "Labeling worker nodes for OpenWhisk invokers..."
    
    # Label all worker nodes (not master) as invoker nodes
    WORKER_NODES=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}')
    
    for node in $WORKER_NODES; do
        kubectl label node $node openwhisk-role=invoker --overwrite
        log_info "Labeled node: $node"
    done
}

#####################################################################
# Step 5: Add OpenWhisk Helm repository
#####################################################################
add_helm_repo() {
    log_info "Adding OpenWhisk Helm repository..."
    
    helm repo add openwhisk https://openwhisk.apache.org/charts
    helm repo update
    
    log_info "OpenWhisk Helm repo added"
}

#####################################################################
# Step 6: Create custom values file for Cluster 1
#####################################################################
create_values_file() {
    log_info "Creating custom Helm values for Cluster 1..."
    
    cat <<EOF > ~/openwhisk-cluster1-values.yaml
# OpenWhisk Configuration for Cluster 1 (Docker/containerd runtime)
whisk:
  ingress:
    type: NodePort
    apiHostName: localhost
    apiHostPort: 31001

  # Resource limits for functions
  limits:
    actionsInvokesPerminute: 60
    actionsInvokesConcurrent: 30
    triggersFiresPerminute: 60
    actionsSequenceMaxlength: 50
    actions:
      time:
        min: 100ms
        max: 5m
        std: 1m
      memory:
        min: 128m
        max: 512m
        std: 256m
      concurrency:
        min: 1
        max: 1
        std: 1
      log:
        min: 0m
        max: 10m
        std: 10m

# Invoker configuration - using Docker/containerd
invoker:
  containerFactory:
    impl: "docker"
    enableConcurrency: false
  options: ""
  
  # Resource allocation for invokers
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "2000m"

# Controller configuration
controller:
  replicaCount: 1
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

# Nginx configuration
nginx:
  httpsNodePort: 31001

# Database configuration (CouchDB)
db:
  wipeAndInit: true
  auth:
    username: whisk_admin
    password: some_passw0rd

# Redis for throttling
redis:
  persistence:
    enabled: false

# Kafka configuration
kafka:
  replicaCount: 1
  persistence:
    enabled: false

# Zookeeper
zookeeper:
  replicaCount: 1
  persistence:
    enabled: false

# Affinity rules - deploy invokers on labeled worker nodes
affinity:
  enabled: true
  invokerNodeLabel: openwhisk-role
  invokerNodeValue: invoker

# Metrics and monitoring
metrics:
  prometheusEnabled: false
  userMetricsEnabled: true

# Enable container pool prewarming
containerPool:
  userMemory: "2048m"
EOF

    log_info "Values file created at ~/openwhisk-cluster1-values.yaml"
}

#####################################################################
# Step 7: Deploy OpenWhisk using Helm
#####################################################################
deploy_openwhisk() {
    log_info "Deploying OpenWhisk to Cluster 1..."
    log_info "This may take 5-10 minutes..."
    
    helm install ${HELM_RELEASE_NAME} openwhisk/openwhisk \
        --namespace ${OPENWHISK_NAMESPACE} \
        --values ~/openwhisk-cluster1-values.yaml \
        --timeout 10m
    
    log_info "OpenWhisk deployment initiated"
}

#####################################################################
# Step 8: Wait for OpenWhisk to be ready
#####################################################################
wait_for_openwhisk() {
    log_info "Waiting for OpenWhisk pods to be ready..."
    log_info "This can take several minutes for all components to start..."
    
    kubectl wait --for=condition=ready pod \
        -l name=couchdb \
        -n ${OPENWHISK_NAMESPACE} \
        --timeout=300s || log_warn "CouchDB took longer than expected"
    
    log_info "Database is ready"
    
    kubectl wait --for=condition=ready pod \
        -l name=controller \
        -n ${OPENWHISK_NAMESPACE} \
        --timeout=300s || log_warn "Controller took longer than expected"
    
    log_info "Controller is ready"
    
    kubectl wait --for=condition=ready pod \
        -l name=invoker \
        -n ${OPENWHISK_NAMESPACE} \
        --timeout=300s || log_warn "Invokers took longer than expected"
    
    log_info "Invokers are ready"
}

#####################################################################
# Step 9: Install wsk CLI
#####################################################################
install_wsk_cli() {
    log_info "Installing wsk CLI..."
    
    if command -v wsk &> /dev/null; then
        log_info "wsk CLI already installed: $(wsk version)"
        return
    fi
    
    WSK_VERSION="1.2.0"
    WSK_ARCH="amd64"
    
    wget -q https://github.com/apache/openwhisk-cli/releases/download/${WSK_VERSION}/OpenWhisk_CLI-${WSK_VERSION}-linux-${WSK_ARCH}.tgz
    tar -xzf OpenWhisk_CLI-${WSK_VERSION}-linux-${WSK_ARCH}.tgz
    sudo mv wsk /usr/local/bin/
    rm OpenWhisk_CLI-${WSK_VERSION}-linux-${WSK_ARCH}.tgz
    
    log_info "wsk CLI installed: $(wsk version)"
}

#####################################################################
# Step 10: Configure wsk CLI
#####################################################################
configure_wsk_cli() {
    log_info "Configuring wsk CLI..."
    
    # Get NodePort
    NODE_PORT=$(kubectl get svc -n ${OPENWHISK_NAMESPACE} owdev-nginx -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    
    # Get any worker node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    # Configure wsk
    wsk property set --apihost ${NODE_IP}:${NODE_PORT}
    wsk property set --auth 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
    wsk property set --namespace guest
    
    # Test configuration
    log_info "Testing wsk configuration..."
    wsk -i list || log_warn "wsk test failed (this may be normal during initialization)"
    
    echo ""
    log_info "wsk CLI configured:"
    log_info "  API Host: ${NODE_IP}:${NODE_PORT}"
    log_info "  Auth: 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:***"
    log_info "  Namespace: guest"
}

#####################################################################
# Step 11: Display deployment status
#####################################################################
display_status() {
    log_info "OpenWhisk deployment status:"
    echo ""
    
    echo "All pods in openwhisk namespace:"
    kubectl get pods -n ${OPENWHISK_NAMESPACE} -o wide
    echo ""
    
    echo "OpenWhisk services:"
    kubectl get svc -n ${OPENWHISK_NAMESPACE}
    echo ""
}

#####################################################################
# Step 12: Create test action
#####################################################################
create_test_action() {
    log_info "Creating test action..."
    
    cat <<'EOF' > /tmp/hello.js
function main(params) {
    const name = params.name || 'World';
    return {payload: `Hello, ${name}!`};
}
EOF

    wsk -i action update hello /tmp/hello.js --web true || log_warn "Could not create test action"
    
    log_info "Test action created: hello"
    log_info "Invoke with: wsk -i action invoke hello --result --param name YourName"
}

#####################################################################
# Main execution
#####################################################################
main() {
    log_info "Starting OpenWhisk deployment for CLUSTER 1 (Containers)..."
    echo ""
    
    verify_cluster
    install_helm
    create_namespace
    label_nodes
    add_helm_repo
    create_values_file
    deploy_openwhisk
    wait_for_openwhisk
    install_wsk_cli
    configure_wsk_cli
    display_status
    create_test_action
    
    echo ""
    log_info "✓ OpenWhisk deployment on CLUSTER 1 completed!"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  CLUSTER 1 (Containers) - Access Information:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  • API Endpoint: https://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):31001"
    echo "  • CLI Config: wsk property get"
    echo "  • Test: wsk -i action invoke hello --result"
    echo "  • Monitor: kubectl get pods -n openwhisk -w"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

main "$@"
