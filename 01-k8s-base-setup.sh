#!/bin/bash
#####################################################################
# Kubernetes Base Setup Script
# Purpose: Prepare base Kubernetes installation on all nodes
# Usage: Run on ALL nodes (master + workers) before cluster init
#####################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

#####################################################################
# Step 1: Disable swap (required for Kubernetes)
#####################################################################
disable_swap() {
    log_info "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    log_info "Swap disabled"
}

#####################################################################
# Step 2: Load required kernel modules
#####################################################################
load_kernel_modules() {
    log_info "Loading required kernel modules..."
    
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter
    log_info "Kernel modules loaded"
}

#####################################################################
# Step 3: Configure sysctl parameters for Kubernetes networking
#####################################################################
configure_sysctl() {
    log_info "Configuring sysctl parameters..."
    
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sudo sysctl --system
    log_info "Sysctl parameters configured"
}

#####################################################################
# Step 4: Install containerd runtime
#####################################################################
install_containerd() {
    log_info "Installing containerd..."
    
    # Update package index
    sudo apt-get update
    
    # Install dependencies
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    # Install containerd
    sudo apt-get install -y containerd
    
    # Create default configuration
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    
    # Enable SystemdCgroup (required for Kubernetes)
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Restart containerd
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    
    log_info "Containerd installed and configured"
}

#####################################################################
# Step 5: Install Kubernetes components (kubeadm, kubelet, kubectl)
#####################################################################
install_kubernetes() {
    log_info "Installing Kubernetes components..."
    
    # Add Kubernetes GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
        sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # Add Kubernetes repository
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | \
        sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    # Update package index
    sudo apt-get update
    
    # Install Kubernetes components (version 1.28.x for stability)
    sudo apt-get install -y kubelet=1.28.* kubeadm=1.28.* kubectl=1.28.*
    
    # Hold packages to prevent automatic updates
    sudo apt-mark hold kubelet kubeadm kubectl
    
    log_info "Kubernetes components installed (version 1.28.x)"
}

#####################################################################
# Main execution
#####################################################################
main() {
    log_info "Starting Kubernetes base setup..."
    log_info "This script will prepare the node for Kubernetes installation"
    echo ""
    
    disable_swap
    load_kernel_modules
    configure_sysctl
    install_containerd
    install_kubernetes
    
    echo ""
    log_info "✓ Base setup completed successfully!"
    log_info "Next steps:"
    log_info "  - On MASTER node: Run 02-k8s-master-init.sh"
    log_info "  - On WORKER nodes: Wait for master initialization, then run join command"
}

main "$@"
