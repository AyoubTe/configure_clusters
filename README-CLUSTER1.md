# CLUSTER 1 Deployment Guide
## Kubernetes + Containers (Docker/containerd) + OpenWhisk

This cluster uses traditional container runtime (containerd with runc) for OpenWhisk function execution.

---

## 📋 Prerequisites

### Hardware Requirements (per VM)
- **CPU**: 2+ cores (4+ recommended)
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 20GB minimum
- **Network**: All VMs must be on the same network

### Software Requirements
- **OS**: Ubuntu 20.04/22.04 LTS (or Debian-based)
- **Privileges**: Root/sudo access on all nodes
- **Internet**: Access to download packages and container images

### VM Allocation for Cluster 1
- **1 Master Node**: Control plane components
- **4 Worker Nodes**: OpenWhisk invokers and workload execution

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
- ✅ Loads required kernel modules (overlay, br_netfilter)
- ✅ Configures sysctl for networking
- ✅ Installs containerd container runtime
- ✅ Installs Kubernetes components (kubeadm, kubelet, kubectl v1.28)

**Expected Duration:** ~5-10 minutes per node

**Verification:**
```bash
# Check containerd
sudo systemctl status containerd

# Check Kubernetes components
kubelet --version
kubeadm version
```

---

### Phase 2: Initialize Master Node

Run this script **ONLY on the MASTER node**:

```bash
chmod +x 02-cluster1-master-init.sh
./02-cluster1-master-init.sh
```

**What this does:**
- ✅ Initializes Kubernetes control plane
- ✅ Configures kubectl for current user
- ✅ Installs Flannel CNI (pod network)
- ✅ Installs Metrics Server (resource monitoring)
- ✅ Labels master node
- ✅ Generates worker join command

**Expected Duration:** ~3-5 minutes

**Important Output:**
At the end, you'll see a **join command** like:
```bash
kubeadm join 192.168.1.100:6443 --token abc123.xyz789 \
    --discovery-token-ca-cert-hash sha256:abcdef123456...
```

**⚠️ SAVE THIS COMMAND!** You'll need it for the next step.

**Verification:**
```bash
kubectl get nodes
# Should show master as Ready

kubectl get pods -n kube-system
# All system pods should be Running
```

---

### Phase 3: Join Worker Nodes

On **EACH of the 4 WORKER nodes**, run the join command from Phase 2:

```bash
# Example (use YOUR actual command from Phase 2):
sudo kubeadm join 192.168.1.100:6443 \
    --token abc123.xyz789 \
    --discovery-token-ca-cert-hash sha256:abcdef123456...
```

**Expected Duration:** ~1-2 minutes per worker

**Verification (on Master):**
```bash
kubectl get nodes
# Should show all 5 nodes (1 master + 4 workers) as Ready

kubectl get nodes -o wide
# Verify all nodes have STATUS=Ready and correct IPs
```

**Wait until all nodes show "Ready" before proceeding!**

---

### Phase 4: Deploy OpenWhisk

Run this script **ONLY on the MASTER node**:

```bash
chmod +x 04-cluster1-install-openwhisk.sh
./04-cluster1-install-openwhisk.sh
```

**What this does:**
- ✅ Verifies cluster readiness
- ✅ Installs Helm package manager
- ✅ Creates OpenWhisk namespace
- ✅ Labels worker nodes for invokers
- ✅ Deploys OpenWhisk with custom configuration
- ✅ Installs and configures wsk CLI
- ✅ Creates test action

**Expected Duration:** ~10-15 minutes

**Verification:**
```bash
# Check all OpenWhisk pods are running
kubectl get pods -n openwhisk

# Wait for all pods to be Ready (may take a few minutes)
kubectl get pods -n openwhisk -w

# Test wsk CLI
wsk -i list

# Invoke test action
wsk -i action invoke hello --result --param name "Cluster1"
```

**Expected test output:**
```json
{
    "payload": "Hello, Cluster1!"
}
```

---

## 🔍 Verification and Testing

### 1. Cluster Health Check
```bash
# All nodes should be Ready
kubectl get nodes -o wide

# System pods should be Running
kubectl get pods -n kube-system

# Check resource usage
kubectl top nodes
kubectl top pods -n openwhisk
```

### 2. OpenWhisk Health Check
```bash
# All OpenWhisk pods should be Running
kubectl get pods -n openwhisk -o wide

# Key components to verify:
# - controller-0: OpenWhisk controller
# - invoker-0: OpenWhisk invoker(s)
# - owdev-couchdb-0: Database
# - owdev-kafka-0: Message queue
# - owdev-nginx-*: API gateway

# Check OpenWhisk services
kubectl get svc -n openwhisk
```

### 3. Function Execution Test
```bash
# List actions
wsk -i action list

# Invoke test action
wsk -i action invoke hello --result

# Check activation logs
wsk -i activation list
wsk -i activation get <activation-id>
```

### 4. Create Your Own Test Function
```bash
# Create a simple function
cat > /tmp/test.js << 'EOF'
function main(params) {
    return {
        message: "Running on Cluster 1 (Containers)",
        timestamp: new Date().toISOString(),
        input: params
    };
}
EOF

# Deploy it
wsk -i action create test-cluster1 /tmp/test.js

# Invoke it
wsk -i action invoke test-cluster1 --result --param key "value"
```

---

## 📊 Cluster Configuration Summary

| Component              | Configuration        |
|------------------------|----------------------|
| **Cluster Name**       | cluster1-containers  |
| **Container Runtime**  | containerd with runc |
| **CNI Plugin**         | Flannel              |
| **Pod CIDR**           | 10.244.0.0/16        |
| **Service CIDR**       | 10.96.0.0/12         |
| **OpenWhisk NodePort** | 31001                |
| **Kubernetes Version** | 1.28.x               |

### OpenWhisk Configuration
- **Container Factory**: Docker/containerd (native)
- **Invoker Resources**: 512Mi-2Gi RAM, 500m-2000m CPU
- **Function Limits**: 128Mi-512Mi RAM, 100ms-5min timeout
- **Namespace**: guest
- **Default Auth**: 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:***

---

## 🛠️ Troubleshooting

### Issue: Nodes not joining cluster
```bash
# On worker node, check logs
sudo journalctl -u kubelet -f

# Reset and retry (on worker)
sudo kubeadm reset
# Then run join command again
```

### Issue: Pods stuck in Pending
```bash
# Check node resources
kubectl describe node <node-name>

# Check pod details
kubectl describe pod <pod-name> -n openwhisk

# Common fixes:
# - Ensure all nodes are Ready
# - Check CNI pods are running
# - Verify sufficient resources
```

### Issue: OpenWhisk controller/invoker not starting
```bash
# Check logs
kubectl logs -n openwhisk <pod-name>

# Common issues:
# - CouchDB not ready yet (wait longer)
# - Insufficient resources (check node capacity)
# - Configuration errors (check Helm values)
```

### Issue: wsk CLI connection errors
```bash
# Verify service is running
kubectl get svc -n openwhisk owdev-nginx

# Get correct NodePort
kubectl get svc -n openwhisk owdev-nginx -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}'

# Test connectivity
curl -k https://<node-ip>:<nodeport>

# Reconfigure wsk
wsk property set --apihost <node-ip>:<nodeport>
wsk property set --auth 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
```

### Issue: containerd service fails
```bash
# Check logs
sudo journalctl -u containerd -n 50

# Restart containerd
sudo systemctl restart containerd

# Verify configuration
sudo containerd config dump | grep SystemdCgroup
# Should show: SystemdCgroup = true
```

---

## 🔧 Useful Commands

### Cluster Management
```bash
# View cluster info
kubectl cluster-info

# Get all resources
kubectl get all -n openwhisk

# Monitor pod status
kubectl get pods -n openwhisk -w

# Check logs
kubectl logs -f <pod-name> -n openwhisk

# Execute into pod
kubectl exec -it <pod-name> -n openwhisk -- /bin/bash
```

### OpenWhisk Management
```bash
# List all actions
wsk -i action list

# Get action details
wsk -i action get <action-name>

# Update action
wsk -i action update <action-name> <file>

# Delete action
wsk -i action delete <action-name>

# View activations
wsk -i activation list
wsk -i activation logs <activation-id>
```

### Resource Monitoring
```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n openwhisk

# Detailed node info
kubectl describe node <node-name>
```

---

## 📁 File Locations

- **Kubeconfig**: `~/.kube/config`
- **OpenWhisk values**: `~/openwhisk-cluster1-values.yaml`
- **Join command**: `~/cluster1-worker-join.sh`
- **Containerd config**: `/etc/containerd/config.toml`
- **Kubelet config**: `/var/lib/kubelet/config.yaml`

---

## 🎯 Next Steps

After successful deployment:

1. ✅ **Verify baseline energy consumption** (idle state)
2. ✅ **Deploy test workloads** for your experiments
3. ✅ **Install energy monitoring tools** (Kepler, PowerAPI)
4. ✅ **Compare with Cluster 2** (MicroVM) metrics

---

## 📖 References

- Kubernetes Documentation: https://kubernetes.io/docs/
- OpenWhisk Documentation: https://openwhisk.apache.org/documentation.html
- Containerd Documentation: https://containerd.io/docs/
- Your Project State of the Art: `etat_art_projet_long.pdf`

---

**Cluster 1 is now ready for energy evaluation experiments! 🎉**
