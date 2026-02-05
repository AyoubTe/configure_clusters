#!/bin/bash
#####################################################################
# Kata Containers Installation Script - CLUSTER 2 WORKERS
# Purpose: Install Kata Containers with Firecracker on worker nodes
# Usage: Run on ALL WORKER nodes of Cluster 2 AFTER joining cluster
#####################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#####################################################################
# Step 1: Verify prerequisites
#####################################################################
verify_prerequisites() {
    log_info "Verifying prerequisites..."
    
    # Check virtualization
    if grep -E 'vmx|svm' /proc/cpuinfo > /dev/null; then
        log_info "✓ Hardware virtualization supported"
    else
        log_error "Hardware virtualization NOT supported!"
        log_error "Kata Containers requires Intel VT-x or AMD-V"
        exit 1
    fi
    
    # Check KVM device
    if [ -e /dev/kvm ]; then
        log_info "✓ /dev/kvm exists"
    else
        log_warn "/dev/kvm not found, loading KVM modules..."
        sudo modprobe kvm
        sudo modprobe kvm_intel || sudo modprobe kvm_amd || true
    fi
    
    # Verify containerd is running
    if systemctl is-active --quiet containerd; then
        log_info "✓ containerd is running"
    else
        log_error "containerd is not running!"
        exit 1
    fi
}

#####################################################################
# Step 2: Install Kata Containers
#####################################################################
install_kata() {
    log_info "Installing Kata Containers..."
    
    # Add Kata Containers repository
    KATA_VERSION="3.2.0"
    ARCH=$(uname -m)
    
    # Download and extract Kata release
    cd /tmp
    log_info "Downloading Kata Containers ${KATA_VERSION}..."
    wget -q https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${ARCH}.tar.xz
    
    log_info "Extracting Kata Containers..."
    sudo tar -xf kata-static-${KATA_VERSION}-${ARCH}.tar.xz -C /
    
    # Create symbolic links
    sudo ln -sf /opt/kata/bin/kata-runtime /usr/local/bin/kata-runtime
    sudo ln -sf /opt/kata/bin/kata-collect-data.sh /usr/local/bin/kata-collect-data.sh
    
    log_info "Kata Containers installed"
}

#####################################################################
# Step 3: Install Firecracker
#####################################################################
install_firecracker() {
    log_info "Installing Firecracker..."
    
    FIRECRACKER_VERSION="v1.6.0"
    ARCH=$(uname -m)
    
    cd /tmp
    log_info "Downloading Firecracker ${FIRECRACKER_VERSION}..."
    
    # Download Firecracker binary
    wget -q https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz
    
    # Extract and install
    tar -xzf firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz
    sudo mv release-${FIRECRACKER_VERSION}-${ARCH}/firecracker-${FIRECRACKER_VERSION}-${ARCH} /usr/local/bin/firecracker
    sudo chmod +x /usr/local/bin/firecracker
    
    # Download jailer (for isolation)
    wget -q https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz
    tar -xzf firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz
    sudo mv release-${FIRECRACKER_VERSION}-${ARCH}/jailer-${FIRECRACKER_VERSION}-${ARCH} /usr/local/bin/jailer
    sudo chmod +x /usr/local/bin/jailer
    
    log_info "Firecracker installed"
}

#####################################################################
# Step 4: Configure Kata to use Firecracker
#####################################################################
configure_kata_firecracker() {
    log_info "Configuring Kata Containers to use Firecracker..."
    
    # Create Kata configuration directory
    sudo mkdir -p /etc/kata-containers
    
    # Copy default Firecracker configuration
    sudo cp /opt/kata/share/defaults/kata-containers/configuration-fc.toml \
        /etc/kata-containers/configuration.toml
    
    # Update configuration for Firecracker
    sudo sed -i 's|^#\?\s*path\s*=.*firecracker.*|path = "/usr/local/bin/firecracker"|' \
        /etc/kata-containers/configuration.toml
    
    sudo sed -i 's|^#\?\s*jailer_path\s*=.*|jailer_path = "/usr/local/bin/jailer"|' \
        /etc/kata-containers/configuration.toml
    
    # Enable debug logging (useful for troubleshooting)
    sudo sed -i 's|^#\?\s*enable_debug\s*=.*|enable_debug = true|' \
        /etc/kata-containers/configuration.toml
    
    log_info "Kata Firecracker configuration created"
}

#####################################################################
# Step 5: Configure containerd for Kata runtime
#####################################################################
configure_containerd_kata() {
    log_info "Configuring containerd for Kata runtime..."
    
    # Backup original config
    sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
    
    # Add Kata runtime configuration to containerd
    cat <<EOF | sudo tee -a /etc/containerd/config.toml

# Kata Containers runtime configuration
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
  runtime_type = "io.containerd.kata.v2"
  privileged_without_host_devices = true
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata.options]
    ConfigPath = "/etc/kata-containers/configuration.toml"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]
  runtime_type = "io.containerd.kata.v2"
  privileged_without_host_devices = true
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc.options]
    ConfigPath = "/etc/kata-containers/configuration.toml"
EOF

    # Restart containerd
    sudo systemctl restart containerd
    
    log_info "containerd configured for Kata runtime"
}

#####################################################################
# Step 6: Create Kata RuntimeClass
#####################################################################
create_runtimeclass() {
    log_info "Creating Kata RuntimeClass..."
    
    cat <<EOF > /tmp/kata-runtimeclass.yaml
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

    # Try to apply (will work after node joins cluster)
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        kubectl apply -f /tmp/kata-runtimeclass.yaml || log_warn "Could not apply RuntimeClass (apply it manually from master)"
    else
        log_warn "kubectl not configured, apply RuntimeClass manually from master node:"
        log_warn "kubectl apply -f /tmp/kata-runtimeclass.yaml"
    fi
}

#####################################################################
# Step 7: Label node for Kata workloads
#####################################################################
label_node() {
    log_info "Node labeling instructions..."
    
    HOSTNAME=$(hostname)
    
    echo ""
    log_warn "After this node joins the cluster, run this on the MASTER node:"
    echo ""
    echo "  kubectl label node ${HOSTNAME} katacontainers.io/kata-runtime=true"
    echo "  kubectl label node ${HOSTNAME} cluster=cluster2"
    echo ""
}

#####################################################################
# Step 8: Verify installation
#####################################################################
verify_installation() {
    log_info "Verifying Kata installation..."
    
    echo ""
    echo "Kata runtime version:"
    kata-runtime --version || log_error "kata-runtime not found"
    
    echo ""
    echo "Firecracker version:"
    firecracker --version || log_error "firecracker not found"
    
    echo ""
    echo "Kata environment check:"
    sudo kata-runtime check || log_warn "Some checks failed (may be expected)"
    
    echo ""
    log_info "Verifying containerd runtime configuration..."
    sudo ctr plugins ls | grep kata || log_warn "Kata plugin not detected"
}

#####################################################################
# Main execution
#####################################################################
main() {
    log_info "Starting Kata Containers installation for CLUSTER 2..."
    echo ""
    
    verify_prerequisites
    install_kata
    install_firecracker
    configure_kata_firecracker
    configure_containerd_kata
    create_runtimeclass
    verify_installation
    label_node
    
    echo ""
    log_info "✓ Kata Containers installation completed!"
    echo ""
    log_warn "IMPORTANT NEXT STEPS:"
    log_warn "1. Ensure this node has joined the Kubernetes cluster"
    log_warn "2. Label the node from master (see instructions above)"
    log_warn "3. Apply RuntimeClass from master node if not already done"
    log_warn "4. Test Kata with: kubectl run test-kata --image=nginx --runtime=kata-fc"
}

main "$@"
