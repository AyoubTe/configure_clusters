# Quick Deployment Reference Card

## 🎯 At-a-Glance Deployment Order

### CLUSTER 1 (Traditional Containers)

```
┌─────────────────────────────────────────────────┐
│ PHASE 1: Base Setup (ALL 5 nodes)              │
├─────────────────────────────────────────────────┤
│ Script: 01-k8s-base-setup.sh                    │
│ Time: 5-10 min/node                             │
│ Run on: Master + 4 Workers                      │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 2: Master Init (Master only)             │
├─────────────────────────────────────────────────┤
│ Script: 02-cluster1-master-init.sh              │
│ Time: 3-5 min                                    │
│ Output: JOIN COMMAND (save it!)                 │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 3: Join Workers (4 workers)              │
├─────────────────────────────────────────────────┤
│ Command: sudo kubeadm join <saved-command>      │
│ Time: 1-2 min/worker                             │
│ Verify: kubectl get nodes (on master)           │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 4: Deploy OpenWhisk (Master)             │
├─────────────────────────────────────────────────┤
│ Script: 04-cluster1-install-openwhisk.sh        │
│ Time: 10-15 min                                  │
│ Test: wsk -i action invoke hello --result       │
└─────────────────────────────────────────────────┘
```

---

### CLUSTER 2 (MicroVM/Kata)

```
┌─────────────────────────────────────────────────┐
│ PHASE 1: Base Setup (ALL 5 nodes)              │
├─────────────────────────────────────────────────┤
│ Script: 01-k8s-base-setup.sh                    │
│ Time: 5-10 min/node                             │
│ Run on: Master + 4 Workers                      │
│ ⚠️ VERIFY: grep -E 'vmx|svm' /proc/cpuinfo     │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 2: Master Init (Master only)             │
├─────────────────────────────────────────────────┤
│ Script: 02-cluster2-master-init.sh              │
│ Time: 3-5 min                                    │
│ Output: JOIN COMMAND (save it!)                 │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 3: Join Workers (4 workers)              │
├─────────────────────────────────────────────────┤
│ Command: sudo kubeadm join <saved-command>      │
│ Time: 1-2 min/worker                             │
│ Verify: kubectl get nodes (on master)           │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 4: Install Kata (Workers only)           │
├─────────────────────────────────────────────────┤
│ Script: 03-install-kata.sh                       │
│ Time: 5-10 min/worker                            │
│ Verify: kata-runtime --version                   │
│ Then on Master: Label nodes for Kata            │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ PHASE 5: Deploy OpenWhisk (Master)             │
├─────────────────────────────────────────────────┤
│ Script: 04-cluster2-install-openwhisk.sh        │
│ Time: 10-20 min                                  │
│ Test: wsk -i action invoke hello-kata --result  │
└─────────────────────────────────────────────────┘
```

---

## ⚡ Essential Commands

### Cluster Status
```bash
# Check nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check OpenWhisk
kubectl get pods -n openwhisk
```

### OpenWhisk Testing
```bash
# List actions
wsk -i action list

# Invoke action
wsk -i action invoke <action> --result

# Check logs
wsk -i activation list
wsk -i activation logs <id>
```

### Troubleshooting
```bash
# Pod details
kubectl describe pod <pod> -n openwhisk

# Pod logs
kubectl logs <pod> -n openwhisk

# Node resources
kubectl top nodes
kubectl describe node <node>

# Restart pod
kubectl delete pod <pod> -n openwhisk
```

---

## 🔑 Key Configuration Values

### Cluster 1 (Containers)
| Item | Value |
|------|-------|
| API Port | 31001 |
| Pod CIDR | 10.244.0.0/16 |
| Runtime | containerd/runc |
| Auth | 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:*** |

### Cluster 2 (MicroVM)
| Item | Value |
|------|-------|
| API Port | 31002 |
| Pod CIDR | 10.245.0.0/16 |
| Runtime | Kata + Firecracker |
| RuntimeClass | kata-fc |
| Auth | 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:*** |

---

## ⚠️ Critical Checks

### Before Starting Cluster 2
```bash
# MUST pass these checks:
grep -E 'vmx|svm' /proc/cpuinfo  # Must show output
lsmod | grep kvm                  # KVM modules loaded
ls -l /dev/kvm                    # Device must exist
```

### After Each Phase
```bash
# Phase 1: Base setup
systemctl status containerd
kubelet --version

# Phase 2: Master init
kubectl get nodes
kubectl get pods -n kube-system

# Phase 3: Workers joined
kubectl get nodes
# All should show "Ready"

# Phase 4 (Cluster 2): Kata installed
kata-runtime --version
firecracker --version

# Phase 5: OpenWhisk running
kubectl get pods -n openwhisk
# All should show "Running"
```

---

## 📊 Performance Expectations

### Cold Start Times
- **Cluster 1**: 200-500ms
- **Cluster 2**: 500-2000ms (2-5x slower - expected!)

### Memory Overhead
- **Cluster 1**: ~10-20Mi per container
- **Cluster 2**: ~160Mi per MicroVM

### Warm Execution
- **Both**: Similar (~5-15% difference)

---

## 🚨 Common Errors & Quick Fixes

### Error: "swap is enabled"
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### Error: "connection refused" (wsk)
```bash
# Get correct API endpoint
kubectl get svc -n openwhisk owdev-nginx
# Reconfigure wsk with correct IP:PORT
```

### Error: "virtualization not supported" (Cluster 2)
```bash
# Enable in BIOS/hypervisor
# For nested virt in KVM:
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf
```

### Error: "ContainerCreating" stuck
```bash
kubectl describe pod <pod> -n openwhisk
# Check events at bottom for specific error
```

---

## 📋 Pre-Flight Checklist

Before deployment:
- [ ] 10 VMs allocated (5 per cluster)
- [ ] Each VM: 2+ CPU, 4GB+ RAM, 20GB+ storage
- [ ] Cluster 2 VMs support virtualization
- [ ] All VMs can reach each other
- [ ] All VMs have internet access
- [ ] You have sudo/root on all VMs
- [ ] Scripts copied to appropriate VMs

---

## 🎯 Deployment Time Estimates

### Cluster 1 (Total: ~30-40 minutes)
- Base setup: 5-10 min × 5 nodes = 25-50 min
- Master init: 3-5 min
- Workers join: 1-2 min × 4 = 4-8 min
- OpenWhisk: 10-15 min

### Cluster 2 (Total: ~40-60 minutes)
- Base setup: 5-10 min × 5 nodes = 25-50 min
- Master init: 3-5 min
- Workers join: 1-2 min × 4 = 4-8 min
- Kata install: 5-10 min × 4 = 20-40 min
- OpenWhisk: 10-20 min

**Total for both: 1.5-2.5 hours**

---

## 🔗 Quick Links

- Full deployment guide: `README.md`
- Cluster 1 detailed guide: `README-CLUSTER1.md`
- Cluster 2 detailed guide: `README-CLUSTER2.md`
- Project state of the art: `etat_art_projet_long.pdf`

---

## 📞 Emergency Commands

### Reset a node completely
```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf ~/.kube
sudo systemctl restart containerd
```

### Regenerate join token (on master)
```bash
kubeadm token create --print-join-command
```

### Force delete stuck pod
```bash
kubectl delete pod <pod> -n openwhisk --force --grace-period=0
```

---

## 🎓 For Your Report

Key metrics to measure:
1. Idle energy consumption (both clusters)
2. Cold start energy (time × power)
3. Warm execution energy
4. sPUE = E_total / E_functions
5. Keep-alive optimization

Expected findings:
- MicroVM: Lower idle, higher cold start
- Container: Higher idle, lower cold start
- sPUE will quantify infrastructure overhead

---

**Print this card for quick reference during deployment! 📄**
