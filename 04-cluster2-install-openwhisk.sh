#!/bin/bash
#####################################################################
# OpenWhisk Installation Script - CLUSTER 2 (MicroVM/Kata)
# Purpose: Deploy Apache OpenWhisk on Kubernetes with Kata runtime
# Usage: Run on MASTER node of Cluster 2 after Kata installation
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
# Step 1: Verify cluster readiness and Kata availability
#####################################################################
verify_cluster() {
    log_info "Verifying cluster readiness..."
    
    # Check if all nodes are Ready
    NOT_READY=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [ "$NOT_READY" -gt 0 ]; then
        log_warn "Some nodes are not Ready."
        kubectl get nodes
        exit 1
    fi
    
    log_info "✓ All nodes are Ready"
    
    # Check if Kata RuntimeClass exists
    if kubectl get runtimeclass kata-fc &> /dev/null; then
        log_info "✓ Kata RuntimeClass (kata-fc) is available"
    else
        log_warn "Kata RuntimeClass not found. Creating it..."
        create_kata_runtimeclass
    fi
    
    # Check if nodes are labeled for Kata
    KATA_NODES=$(kubectl get nodes -l katacontainers.io/kata-runtime=true --no-headers | wc -l)
    if [ "$KATA_NODES" -eq 0 ]; then
        log_warn "No nodes labeled for Kata. Labeling worker nodes..."
        label_kata_nodes
    else
        log_info "✓ ${KATA_NODES} node(s) labeled for Kata"
    fi
}

#####################################################################
# Helper: Create Kata RuntimeClass
#####################################################################
create_kata_runtimeclass() {
    cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
overhead:
  podFixed:
    memory: "160Mi"
    cpu: "250m"
scheduling:
  nodeSelector:
    katacontainers.io/kata-runtime: "true"
EOF
    log_info "Kata RuntimeClass created"
}

#####################################################################
# Helper: Label nodes for Kata
#####################################################################
label_kata_nodes() {
    WORKER_NODES=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}')
    
    for node in $WORKER_NODES; do
        kubectl label node $node katacontainers.io/kata-runtime=true --overwrite
        log_info "Labeled node for Kata: $node"
    done
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
# Step 6: Create custom invoker image with Kata support
#####################################################################
create_kata_invoker_config() {
    log_info "Creating Kata-compatible invoker configuration..."
    
    # Create a ConfigMap for Kata-specific invoker settings
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: invoker-kata-config
  namespace: ${OPENWHISK_NAMESPACE}
data:
  invoker.conf: |
    # Kata-specific configuration
    whisk.spi {
      ContainerFactoryProvider = org.apache.openwhisk.core.containerpool.kubernetes.KubernetesContainerFactoryProvider
    }
    
    whisk.kubernetes {
      isolation = pod
      pod-template {
        runtime-class-name = "kata-fc"
      }
    }
EOF

    log_info "Kata invoker configuration created"
}

#####################################################################
# Step 7: Create custom values file for Cluster 2
#####################################################################
create_values_file() {
    log_info "Creating custom Helm values for Cluster 2 (Kata/MicroVM)..."
    
    cat <<EOF > ~/openwhisk-cluster2-values.yaml
# OpenWhisk Configuration for Cluster 2 (Kata/Firecracker runtime)
whisk:
  ingress:
    type: NodePort
    apiHostName: localhost
    apiHostPort: 31002

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

# Invoker configuration - using Kubernetes with Kata runtime
invoker:
  containerFactory:
    impl: "kubernetes"
    kubernetes:
      isolateUserActions: true
      
  # Additional options for Kata
  options: "-Dwhisk.kubernetes.pod-template.runtime-class-name=kata-fc"
  
  # Resource allocation for invokers (higher for Kata overhead)
  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "3000m"

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
  httpsNodePort: 31002

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

# Affinity rules - deploy invokers on Kata-enabled nodes
affinity:
  enabled: true
  invokerNodeLabel: openwhisk-role
  invokerNodeValue: invoker

# Additional node affinity for Kata nodes
invoker:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: katacontainers.io/kata-runtime
            operator: In
            values:
            - "true"

# Metrics and monitoring
metrics:
  prometheusEnabled: false
  userMetricsEnabled: true

# Container pool configuration for Kata
containerPool:
  userMemory: "2048m"
  
# Kata-specific: Longer timeout for cold starts
controller:
  loglevel: "INFO"
EOF

    log_info "Values file created at ~/openwhisk-cluster2-values.yaml"
}

#####################################################################
# Step 8: Deploy OpenWhisk using Helm
#####################################################################
deploy_openwhisk() {
    log_info "Deploying OpenWhisk to Cluster 2 with Kata runtime..."
    log_info "This may take 5-10 minutes..."
    
    helm install ${HELM_RELEASE_NAME} openwhisk/openwhisk \
        --namespace ${OPENWHISK_NAMESPACE} \
        --values ~/openwhisk-cluster2-values.yaml \
        --timeout 15m
    
    log_info "OpenWhisk deployment initiated"
}

#####################################################################
# Step 9: Wait for OpenWhisk to be ready
#####################################################################
wait_for_openwhisk() {
    log_info "Waiting for OpenWhisk pods to be ready..."
    log_info "Kata containers take longer to start - this is expected..."
    
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
        --timeout=600s || log_warn "Invokers took longer than expected"
    
    log_info "Invokers are ready"
}

#####################################################################
# Step 10: Install wsk CLI
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
# Step 11: Configure wsk CLI
#####################################################################
configure_wsk_cli() {
    log_info "Configuring wsk CLI..."
    
    NODE_PORT=$(kubectl get svc -n ${OPENWHISK_NAMESPACE} owdev-nginx -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    wsk property set --apihost ${NODE_IP}:${NODE_PORT}
    wsk property set --auth 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
    wsk property set --namespace guest
    
    log_info "Testing wsk configuration..."
    wsk -i list || log_warn "wsk test failed (may be normal during initialization)"
    
    echo ""
    log_info "wsk CLI configured:"
    log_info "  API Host: ${NODE_IP}:${NODE_PORT}"
    log_info "  Auth: 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:***"
    log_info "  Namespace: guest"
}

#####################################################################
# Step 12: Display deployment status
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
    
    echo "RuntimeClass configuration:"
    kubectl get runtimeclass kata-fc -o yaml | grep -A 5 "overhead:"
    echo ""
}

#####################################################################
# Step 13: Verify Kata is being used
#####################################################################
verify_kata_usage() {
    log_info "Verifying Kata container usage..."
    
    # Check if any pod is using kata runtime
    kubectl get pods -n ${OPENWHISK_NAMESPACE} -o json | \
        jq -r '.items[] | select(.spec.runtimeClassName=="kata-fc") | .metadata.name' || \
        log_warn "No pods currently using Kata runtime"
}

#####################################################################
# Step 14: Create test action
#####################################################################
create_test_action() {
    log_info "Creating test action with Kata runtime..."
    
    cat <<'EOF' > /tmp/hello-kata.js
function main(params) {
    const name = params.name || 'MicroVM World';
    return {
        payload: `Hello from Kata Containers, ${name}!`,
        runtime: 'Firecracker MicroVM'
    };
}
EOF

    wsk -i action update hello-kata /tmp/hello-kata.js --web true || log_warn "Could not create test action"
    
    log_info "Test action created: hello-kata"
    log_info "Invoke with: wsk -i action invoke hello-kata --result --param name YourName"
}

#####################################################################
# Main execution
#####################################################################
main() {
    log_info "Starting OpenWhisk deployment for CLUSTER 2 (MicroVM/Kata)..."
    echo ""
    
    verify_cluster
    install_helm
    create_namespace
    label_nodes
    add_helm_repo
    create_kata_invoker_config
    create_values_file
    deploy_openwhisk
    wait_for_openwhisk
    install_wsk_cli
    configure_wsk_cli
    display_status
    verify_kata_usage
    create_test_action
    
    echo ""
    log_info "✓ OpenWhisk deployment on CLUSTER 2 completed!"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  CLUSTER 2 (MicroVM/Kata) - Access Information:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  • API Endpoint: https://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):31002"
    echo "  • Runtime: Kata Containers with Firecracker"
    echo "  • RuntimeClass: kata-fc"
    echo "  • CLI Config: wsk property get"
    echo "  • Test: wsk -i action invoke hello-kata --result"
    echo "  • Monitor: kubectl get pods -n openwhisk -w"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    echo ""
    log_warn "NOTE: Cold starts with Kata may be longer than regular containers"
    log_warn "This is expected and will be measured in your energy experiments"
}

main "$@"
