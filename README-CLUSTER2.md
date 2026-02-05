# CLUSTER 2 Deployment Guide
## Kubernetes + Kata Containers + Firecracker (MicroVM) + OpenWhisk

This cluster uses Kata Containers with Firecracker as the MicroVM runtime for OpenWhisk function execution, providing hardware-level isolation with lightweight virtualization.

---

## 📋 Prerequisites

### Hardware Requirements (per VM)
- **CPU**: 2+ cores with **virtualization support** (Intel VT-x or AMD-V) ⚠️ **CRITICAL**
- **RAM**: 4GB minimum (8GB+ recommended for MicroVMs)
- **Storage**: 25GB minimum (more for MicroVM images)
- **Network**: All VMs must be on the same network

### Software Requirements
- **OS**: Ubuntu 20.04/22.04 LTS (or Debian-based)
- **Privileges**: Root/sudo access on all nodes
- **Internet**: Access to download packages and images
- **Virtualization**: Must be enabled in BIOS/UEFI

### VM Allocation for Cluster 2
- **1 Master Node**: Control plane components
- **4 Worker Nodes**: OpenWhisk invokers with Kata Containers

---

## ⚠️ IMPORTANT: Virtualization Check

Before starting, verify that your VMs support nested virtualization:

```bash
# Check CPU flags
grep -E 'vmx|svm' /proc/cpuinfo

# If no output → Virtualization NOT supported (cannot proceed)
# If output shows vmx (Intel) or svm (AMD) → Supported ✓

# Check if KVM module can be loaded
sudo modprobe kvm
sudo modprobe kvm_intel  # For Intel
# OR
sudo modprobe kvm_amd    # For AMD

# Verify /dev/kvm exists
ls -l /dev/kvm
```

If virtualization is **not supported**, you cannot use Kata Containers with Firecracker. You may need to:
1. Enable VT-x/AMD-V in your physical machine's BIOS
2. Enable nested virtualization in your hypervisor (if using VMs)
3. Use bare-metal machines instead of VMs

---

## 🚀 Deployment Steps

### Phase 1: Base Setup (ALL Nodes)

Run this script on **ALL 5 nodes** (1 master + 4 workers):

```bash
# Copy script to all nodes
# Then on EACH node:
chmod +x 01-k8s-base-setup.sh
sudo ./01-k8s-base-setup.sh
```

**What this does:**
- ✅ Disables swap (required by Kubernetes)
- ✅ Loads required kernel modules (overlay, br_netfilter, kvm)
- ✅ Configures sysctl for networking
- ✅ Installs containerd container runtime
- ✅ Installs Kubernetes components (kubeadm, kubelet, kubectl v1.28)

**Expected Duration:** ~5-10 minutes per node

**Verification:**
```bash
sudo systemctl status containerd
kubelet --version
```

---

### Phase 2: Initialize Master Node

Run this script **ONLY on the MASTER node**:

```bash
chmod +x 02-cluster2-master-init.sh
./02-cluster2-master-init.sh
```

**What this does:**
- ✅ Verifies hardware virtualization support
- ✅ Initializes Kubernetes control plane
- ✅ Configures kubectl for current user
- ✅ Installs Flannel CNI (with custom CIDR: 10.245.0.0/16)
- ✅ Installs Metrics Server
- ✅ Labels master node
- ✅ Generates worker join command

**Expected Duration:** ~3-5 minutes

**Important Output:**
Save the **join command** displayed at the end:
```bash
kubeadm join 192.168.1.200:6443 --token xyz789.abc123 \
    --discovery-token-ca-cert-hash sha256:fedcba654321...
```

**Verification:**
```bash
kubectl get nodes
kubectl get pods -n kube-system
```

---

### Phase 3: Join Worker Nodes

On **EACH of the 4 WORKER nodes**, run the join command from Phase 2:

```bash
# Example (use YOUR actual command):
sudo kubeadm join 192.168.1.200:6443 \
    --token xyz789.abc123 \
    --discovery-token-ca-cert-hash sha256:fedcba654321...
```

**Expected Duration:** ~1-2 minutes per worker

**Verification (on Master):**
```bash
kubectl get nodes
# Wait for all 5 nodes to show "Ready"
```

---

### Phase 4: Install Kata Containers (WORKER Nodes Only)

Run this script on **EACH of the 4 WORKER nodes** (NOT on master):

```bash
chmod +x 03-install-kata.sh
sudo ./03-install-kata.sh
```

**What this does:**
- ✅ Verifies virtualization prerequisites
- ✅ Installs Kata Containers (v3.2.0)
- ✅ Installs Firecracker (v1.6.0) and jailer
- ✅ Configures Kata to use Firecracker as hypervisor
- ✅ Updates containerd configuration for Kata runtime
- ✅ Creates RuntimeClass definition
- ✅ Verifies installation

**Expected Duration:** ~5-10 minutes per worker

**⚠️ Important:** If the script fails with virtualization errors, your hardware doesn't support nested virtualization.

**Verification:**
```bash
# Check Kata installation
kata-runtime --version
firecracker --version

# Check Kata environment
sudo kata-runtime check

# Verify containerd sees Kata runtime
sudo ctr plugins ls | grep kata
```

---

### Phase 4.5: Apply RuntimeClass and Label Nodes (Master)

After installing Kata on all workers, run these commands **on the MASTER node**:

```bash
# Apply RuntimeClass (if not already applied)
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

# Label all worker nodes for Kata
for node in $(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node $node katacontainers.io/kata-runtime=true --overwrite
    echo "Labeled: $node"
done

# Verify labels
kubectl get nodes -L katacontainers.io/kata-runtime
```

---

### Phase 5: Test Kata Containers (Optional but Recommended)

Before installing OpenWhisk, verify Kata works:

```bash
# Create a test pod with Kata runtime
kubectl run kata-test \
    --image=nginx:alpine \
    --runtime=kata-fc \
    --restart=Never

# Wait for pod to start (may take 30-60s - first MicroVM is slower)
kubectl wait --for=condition=ready pod/kata-test --timeout=120s

# Verify it's using Kata
kubectl get pod kata-test -o jsonpath='{.spec.runtimeClassName}'
# Should output: kata-fc

# Check the pod
kubectl describe pod kata-test

# Clean up
kubectl delete pod kata-test
```

**If this test fails**, troubleshoot before proceeding to OpenWhisk:
```bash
# Check worker node logs
kubectl describe node <worker-node-name>

# Check Kata logs on worker
sudo journalctl -u containerd -n 100 | grep -i kata

# Verify /dev/kvm permissions
ls -l /dev/kvm
```

---

### Phase 6: Deploy OpenWhisk with Kata

Run this script **ONLY on the MASTER node**:

```bash
chmod +x 04-cluster2-install-openwhisk.sh
./04-cluster2-install-openwhisk.sh
```

**What this does:**
- ✅ Verifies cluster and Kata readiness
- ✅ Installs Helm package manager
- ✅ Creates OpenWhisk namespace
- ✅ Labels worker nodes for OpenWhisk invokers
- ✅ Creates Kata-specific invoker configuration
- ✅ Deploys OpenWhisk with Kata runtime
- ✅ Installs and configures wsk CLI
- ✅ Creates test action

**Expected Duration:** ~10-20 minutes (Kata pods take longer to start)

**Important:** The first MicroVM creation can take 1-2 minutes. Be patient!

**Verification:**
```bash
# Check all OpenWhisk pods
kubectl get pods -n openwhisk -o wide

# Wait for all to be Running (use -w to watch)
kubectl get pods -n openwhisk -w

# Verify invoker is using Kata
kubectl get pod -n openwhisk -l name=invoker -o jsonpath='{.items[0].spec.runtimeClassName}'
# Should show: kata-fc (if invoker pods use Kata)

# Test wsk CLI
wsk -i list

# Invoke test action
wsk -i action invoke hello-kata --result
```

**Expected output:**
```json
{
    "payload": "Hello from Kata Containers, MicroVM World!",
    "runtime": "Firecracker MicroVM"
}
```

---

## 🔍 Verification and Testing

### 1. Verify Kata is Running
```bash
# Check RuntimeClass
kubectl get runtimeclass

# Check which pods use Kata
kubectl get pods -n openwhisk -o json | \
    jq -r '.items[] | "\(.metadata.name): \(.spec.runtimeClassName // "default")"'

# On a worker node, check Firecracker processes
ps aux | grep firecracker
```

### 2. Compare Startup Times
```bash
# Create a simple action
cat > /tmp/simple.js << 'EOF'
function main() {
    return {timestamp: Date.now()};
}
EOF

wsk -i action create simple /tmp/simple.js

# Time a cold start (first invocation)
time wsk -i action invoke simple --result

# Time a warm start (immediate second invocation)
time wsk -i action invoke simple --result

# Note: Cold start with Kata will be slower than containers (expected!)
```

### 3. Verify MicroVM Isolation
```bash
# Create a test function
cat > /tmp/isolation-test.js << 'EOF'
function main() {
    const os = require('os');
    return {
        hostname: os.hostname(),
        platform: os.platform(),
        arch: os.arch(),
        cpus: os.cpus().length,
        memory: Math.round(os.totalmem() / 1024 / 1024) + 'MB'
    };
}
EOF

wsk -i action create isolation-test /tmp/isolation-test.js
wsk -i action invoke isolation-test --result

# This shows the MicroVM environment (not the host)
```

---

## 📊 Cluster Configuration Summary

| Component | Configuration |
|-----------|--------------|
| **Cluster Name** | cluster2-microvm |
| **Container Runtime** | containerd + Kata Containers |
| **Hypervisor** | Firecracker v1.6.0 |
| **RuntimeClass** | kata-fc |
| **CNI Plugin** | Flannel |
| **Pod CIDR** | 10.245.0.0/16 |
| **Service CIDR** | 10.97.0.0/12 |
| **OpenWhisk NodePort** | 31002 |
| **Kubernetes Version** | 1.28.x |

### OpenWhisk Configuration
- **Container Factory**: Kubernetes with Kata runtime
- **RuntimeClass**: kata-fc (Firecracker)
- **Invoker Resources**: 1Gi-4Gi RAM, 1000m-3000m CPU (higher for MicroVM overhead)
- **Function Limits**: 128Mi-512Mi RAM, 100ms-5min timeout
- **MicroVM Overhead**: ~160Mi RAM, ~250m CPU per pod

---

## 🛠️ Troubleshooting

### Issue: Kata installation fails - virtualization not supported
```bash
# Verify nested virtualization is enabled
# On physical host (not in VM):
# For KVM/QEMU:
cat /sys/module/kvm_intel/parameters/nested  # Intel
cat /sys/module/kvm_amd/parameters/nested    # AMD
# Should show: Y or 1

# Enable nested virtualization (physical host):
# Intel:
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel nested=1
# AMD:
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd nested=1

# Make permanent:
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf
```

### Issue: Kata pods stuck in ContainerCreating
```bash
# Check events
kubectl describe pod <pod-name> -n openwhisk

# Check containerd logs on worker
sudo journalctl -u containerd -f | grep kata

# Check if /dev/kvm is accessible
ls -l /dev/kvm
sudo chmod 666 /dev/kvm  # If needed

# Verify Kata configuration
sudo kata-runtime env

# Check Firecracker
which firecracker
firecracker --version
```

### Issue: Slow cold starts
This is **expected** with MicroVMs! Cold starts will be 2-5x slower than containers:
- Container cold start: ~200-500ms
- Kata/Firecracker cold start: ~500-2000ms

This is what you're measuring in your experiments!

### Issue: Out of memory errors
MicroVMs have overhead. If pods crash:
```bash
# Increase node resources or
# Reduce number of concurrent MicroVMs

# Check node resources
kubectl top nodes

# Check MicroVM overhead
kubectl describe runtimeclass kata-fc
```

### Issue: Firecracker not found
```bash
# Verify installation
which firecracker
which jailer

# Reinstall if needed
cd /tmp
wget https://github.com/firecracker-microvm/firecracker/releases/download/v1.6.0/firecracker-v1.6.0-x86_64.tgz
tar -xzf firecracker-v1.6.0-x86_64.tgz
sudo mv release-v1.6.0-x86_64/firecracker-v1.6.0-x86_64 /usr/local/bin/firecracker
sudo chmod +x /usr/local/bin/firecracker
```

---

## 🔧 Useful Commands

### Kata-Specific Commands
```bash
# Check Kata runtime version
kata-runtime --version

# Verify Kata environment
sudo kata-runtime check

# List Kata configuration
sudo kata-runtime env

# Check running Firecracker VMs
ps aux | grep firecracker

# Monitor Kata logs
sudo journalctl -u containerd -f | grep kata
```

### MicroVM Debugging
```bash
# Get detailed pod info
kubectl get pod <pod-name> -n openwhisk -o yaml

# Check RuntimeClass usage
kubectl get pods -A -o custom-columns=\
NAME:.metadata.name,\
NAMESPACE:.metadata.namespace,\
RUNTIME:.spec.runtimeClassName

# Monitor MicroVM resource usage
kubectl top pods -n openwhisk --containers
```

---

## 📈 Performance Comparison Notes

When comparing with Cluster 1:

**Expected Differences:**
- ✅ **Cold Start**: 2-5x slower (MicroVM boot overhead)
- ✅ **Warm Execution**: Similar performance (~5-15% overhead)
- ✅ **Memory Overhead**: ~160Mi per MicroVM vs ~10-20Mi per container
- ✅ **Isolation**: Stronger (hardware-level) vs kernel-level
- ✅ **Density**: Lower (more resources per function)
- ✅ **Security**: Better (VM-level isolation)

**Your Experiments Should Measure:**
1. Idle energy consumption difference
2. Cold start energy cost (Kata will be higher)
3. Warm execution efficiency (should be comparable)
4. Infrastructure overhead (control plane contribution)
5. Scale behavior (how does Kata scale vs containers?)

---

## 📁 File Locations

- **Kubeconfig**: `~/.kube/config`
- **OpenWhisk values**: `~/openwhisk-cluster2-values.yaml`
- **Join command**: `~/cluster2-worker-join.sh`
- **Kata config**: `/etc/kata-containers/configuration.toml`
- **Containerd config**: `/etc/containerd/config.toml`
- **Kata binaries**: `/opt/kata/bin/`
- **Firecracker binary**: `/usr/local/bin/firecracker`

---

## 🎯 Next Steps

After successful deployment:

1. ✅ **Compare baseline** with Cluster 1
2. ✅ **Measure cold start energy** (key difference!)
3. ✅ **Test warm execution** efficiency
4. ✅ **Evaluate sPUE metric** for both clusters
5. ✅ **Vary keep-alive timeouts** and measure impact

---

## 📖 References

- Kata Containers: https://katacontainers.io/
- Firecracker: https://firecracker-microvm.github.io/
- OpenWhisk: https://openwhisk.apache.org/
- Your State of the Art: `etat_art_projet_long.pdf` (Chapter 4: MicroVMs)

---

**Cluster 2 is now ready for energy evaluation experiments with MicroVMs! 🎉**

**Key Insight:** This cluster trades some performance (slower cold starts) for better isolation and security. Your experiments will quantify the energy cost of this trade-off!
