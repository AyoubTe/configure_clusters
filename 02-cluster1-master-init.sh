#!/bin/bash
#####################################################################
# Kubernetes Master Initialization Script - CLUSTER 1
# Purpose: Initialize Kubernetes master node with containerd
# Usage: Run ONLY on the MASTER node of Cluster 1
#####################################################################

set -e

# Color codes
RED='\033[0;31m'
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
# Configuration Variables
#####################################################################
POD_NETWORK_CIDR="10.244.0.0/16"  # Flannel default
SERVICE_CIDR="10.96.0.0/12"       # Kubernetes default
CLUSTER_NAME="cluster1-containers"

#####################################################################
# Step 1: Initialize Kubernetes cluster
#####################################################################
initialize_cluster() {
    log_info "Initializing Kubernetes cluster: ${CLUSTER_NAME}..."
    
    sudo kubeadm init \
        --pod-network-cidr=${POD_NETWORK_CIDR} \
        --service-cidr=${SERVICE_CIDR} \
        --kubernetes-version=1.28.0 \
        --cri-socket=unix:///var/run/containerd/containerd.sock
    
    log_info "Cluster initialized"
}

#####################################################################
# Step 2: Configure kubectl for current user
#####################################################################
configure_kubectl() {
    log_info "Configuring kubectl for current user..."
    
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    log_info "kubectl configured"
}

#####################################################################
# Step 3: Install Flannel CNI network plugin
#####################################################################
install_flannel() {
    log_info "Installing Flannel CNI plugin..."
    
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    
    log_info "Flannel CNI installed"
    log_info "Waiting for CNI pods to be ready (this may take 1-2 minutes)..."
    
    sleep 30
    kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s || true
}

#####################################################################
# Step 4: Generate and save worker join command
#####################################################################
generate_join_command() {
    log_info "Generating worker join command..."
    
    # Create join command file
    JOIN_CMD=$(sudo kubeadm token create --print-join-command)
    echo "${JOIN_CMD}" > ~/cluster1-worker-join.sh
    chmod +x ~/cluster1-worker-join.sh
    
    log_info "Worker join command saved to: ~/cluster1-worker-join.sh"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  WORKER JOIN COMMAND (save this for worker nodes):${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    cat ~/cluster1-worker-join.sh
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

#####################################################################
# Step 5: Verify cluster status
#####################################################################
verify_cluster() {
    log_info "Verifying cluster status..."
    echo ""
    
    echo "Cluster Info:"
    kubectl cluster-info
    echo ""
    
    echo "Node Status:"
    kubectl get nodes -o wide
    echo ""
    
    echo "System Pods:"
    kubectl get pods -n kube-system
    echo ""
}

#####################################################################
# Step 6: Install Metrics Server (for resource monitoring)
#####################################################################
install_metrics_server() {
    log_info "Installing Metrics Server..."
    
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Patch metrics server to work with self-signed certificates (for testing)
    kubectl patch deployment metrics-server -n kube-system --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    
    log_info "Metrics Server installed"
}

#####################################################################
# Step 7: Label master node
#####################################################################
label_master() {
    log_info "Labeling master node..."
    
    MASTER_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl label node ${MASTER_NODE} node-role.kubernetes.io/master= --overwrite || true
    kubectl label node ${MASTER_NODE} cluster=cluster1 --overwrite
    
    log_info "Master node labeled"
}

#####################################################################
# Main execution
#####################################################################
main() {
    log_info "Starting Kubernetes Master initialization for CLUSTER 1 (Containers)..."
    echo ""
    
    initialize_cluster
    configure_kubectl
    install_flannel
    install_metrics_server
    label_master
    generate_join_command
    
    echo ""
    log_info "✓ CLUSTER 1 master initialization completed!"
    echo ""
    log_warn "IMPORTANT NEXT STEPS:"
    log_warn "1. Copy the join command above to your worker nodes"
    log_warn "2. On each worker node, run: sudo <join-command>"
    log_warn "3. Verify workers joined: kubectl get nodes"
    log_warn "4. Wait for all nodes to be Ready before installing OpenWhisk"
}

main "$@"
