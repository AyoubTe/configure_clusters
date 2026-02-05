# Energy Evaluation of OpenWhisk Functions
## Deployment Scripts for Dual Kubernetes Clusters

This repository contains all scripts needed to deploy and configure two Kubernetes clusters for energy consumption comparison experiments as described in your project: **"Évaluation Énergétique des Fonctions OpenWhisk dans des Environnements Kubernetes"**.

---

## 📚 Project Overview

### Research Question
**In what measure does the underlying infrastructure (MicroVM vs VM + Container) influence energy consumption, both at the function execution level and at the global orchestration stack level?**

### Experimental Setup

You have **10 VMs** that will be split into **2 independent clusters**:

#### **Cluster 1: Traditional Architecture**
- **5 VMs** (1 master + 4 workers)
- **Stack**: VM → Kubernetes → containerd/Docker → OpenWhisk
- **Runtime**: Traditional containers (runc)
- **Purpose**: Baseline measurements

#### **Cluster 2: MicroVM Architecture**
- **5 VMs** (1 master + 4 workers)
- **Stack**: Bare-metal/VM → Kubernetes → Kata Containers → Firecracker → OpenWhisk
- **Runtime**: MicroVMs with hardware isolation
- **Purpose**: Compare against baseline

---

## 📋 Prerequisites Check

Before starting, ensure:

### Hardware
- [ ] **10 VMs available** (Ubuntu 20.04/22.04 LTS)
- [ ] Each VM has **minimum 2 CPU cores, 4GB RAM, 20GB storage**
- [ ] For Cluster 2: **Virtualization enabled** (Intel VT-x or AMD-V)
- [ ] All VMs on **same network** and can communicate

### Access
- [ ] **Root/sudo access** on all VMs
- [ ] **SSH access** configured to all VMs
- [ ] **Internet access** on all VMs

### Verification Commands
```bash
# Check CPU virtualization (critical for Cluster 2!)
grep -E 'vmx|svm' /proc/cpuinfo | wc -l
# Should output > 0

# Check resources
lscpu
free -h
df -h

# Check network
ping 8.8.8.8
```

---

## 🗂️ Repository Structure

```
.
├── 01-k8s-base-setup.sh              # Base K8s setup (run on ALL nodes)
├── 02-cluster1-master-init.sh         # Cluster 1 master initialization
├── 02-cluster2-master-init.sh         # Cluster 2 master initialization
├── 03-install-kata.sh                 # Kata Containers installation (Cluster 2 workers)
├── 04-cluster1-install-openwhisk.sh   # OpenWhisk deployment (Cluster 1)
├── 04-cluster2-install-openwhisk.sh   # OpenWhisk deployment (Cluster 2)
├── README.md                          # This file
├── README-CLUSTER1.md                 # Detailed Cluster 1 guide
├── README-CLUSTER2.md                 # Detailed Cluster 2 guide
└── QUICK-START.md                     # Quick deployment reference
```

---

## 🚀 Quick Start Guide

### Step-by-Step Deployment

#### 1️⃣ Prepare All Nodes (Both Clusters)
Run on **all 10 VMs**:
```bash
chmod +x 01-k8s-base-setup.sh
sudo ./01-k8s-base-setup.sh
```
⏱️ ~5-10 minutes per VM

---

#### 2️⃣ Initialize Master Nodes

**Cluster 1 Master:**
```bash
chmod +x 02-cluster1-master-init.sh
./02-cluster1-master-init.sh
# SAVE the join command output!
```

**Cluster 2 Master:**
```bash
chmod +x 02-cluster2-master-init.sh
./02-cluster2-master-init.sh
# SAVE the join command output!
```

⏱️ ~3-5 minutes per master

---

#### 3️⃣ Join Worker Nodes

**Cluster 1 Workers (4 VMs):**
```bash
# Run the join command from Cluster 1 master output
sudo kubeadm join <cluster1-master-ip>:6443 --token ... --discovery-token-ca-cert-hash ...
```

**Cluster 2 Workers (4 VMs):**
```bash
# Run the join command from Cluster 2 master output
sudo kubeadm join <cluster2-master-ip>:6443 --token ... --discovery-token-ca-cert-hash ...
```

⏱️ ~1-2 minutes per worker

---

#### 4️⃣ Install Kata Containers (Cluster 2 Only)

On **each of the 4 Cluster 2 workers**:
```bash
chmod +x 03-install-kata.sh
sudo ./03-install-kata.sh
```

Then on **Cluster 2 master**, label the nodes:
```bash
for node in $(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node $node katacontainers.io/kata-runtime=true
done
```

⏱️ ~5-10 minutes per worker

---

#### 5️⃣ Deploy OpenWhisk

**Cluster 1 Master:**
```bash
chmod +x 04-cluster1-install-openwhisk.sh
./04-cluster1-install-openwhisk.sh
```

**Cluster 2 Master:**
```bash
chmod +x 04-cluster2-install-openwhisk.sh
./04-cluster2-install-openwhisk.sh
```

⏱️ ~10-20 minutes per cluster

---

#### 6️⃣ Verify Deployments

**Cluster 1:**
```bash
kubectl get nodes
kubectl get pods -n openwhisk
wsk -i action invoke hello --result
```

**Cluster 2:**
```bash
kubectl get nodes
kubectl get pods -n openwhisk
wsk -i action invoke hello-kata --result
```

---

## 📊 Cluster Comparison Table

| Aspect              | Cluster 1 (Containers) | Cluster 2 (MicroVM) |
|---------------------|------------------------|---------------------|
| **Isolation**       | Kernel namespaces      | Hardware (KVM)      |
| **Runtime**         | containerd/runc        | Kata + Firecracker  |
| **Cold Start**      | ~200-500ms             | ~500-2000ms         |
| **Memory Overhead** | ~10-20Mi               | ~160Mi              |
| **Security**        | Process-level          | VM-level            |
| **Density**         | High                   | Medium              |
| **API Port**        | 31001                  | 31002               |
| **Pod CIDR**        | 10.244.0.0/16          | 10.245.0.0/16       |

---

## 🔬 Experimental Scenarios

Based on your methodology (Chapter 6), implement these scenarios:

### Scenario 1: Idle Baseline
```bash
# Cluster 1
kubectl get pods -n openwhisk
# Let cluster run idle for 1 hour, measure energy

# Cluster 2
kubectl get pods -n openwhisk
# Let cluster run idle for 1 hour, measure energy
```

### Scenario 2: Cold Start Measurement
```bash
# Create test functions of different sizes
wsk -i action create small-py small.py    # ~10MB
wsk -i action create medium-node medium.js # ~50MB
wsk -i action create large-java large.jar  # ~200MB

# Measure cold start energy (100 invocations each)
for i in {1..100}; do
    wsk -i action invoke small-py --result
    # Wait for container to be destroyed (keep-alive=0)
    sleep 15
done
```

### Scenario 3: Warm Execution
```bash
# Keep-alive = 10 minutes
# Invoke continuously to measure warm performance
for i in {1..1000}; do
    wsk -i action invoke small-py --result
    sleep 1
done
```

### Scenario 4: Mixed Load
```bash
# Use wrk or hey to generate Poisson traffic
# Rates: 10, 50, 100, 500, 1000 inv/min
# Duration: 30 min per rate
```

### Scenario 5: Keep-Alive Sensitivity
Test different timeouts: 0s, 10s, 60s, 600s

---

## 📈 Energy Measurement Integration

### Installing Kepler (both clusters)
```bash
kubectl apply -f https://raw.githubusercontent.com/sustainable-computing-io/kepler/main/manifests/kubernetes/deployment.yaml

# Verify
kubectl get pods -n kepler
```

### Accessing Metrics
```bash
# Kepler exposes metrics at:
kubectl port-forward -n kepler svc/kepler 9102:9102

# Query metrics:
curl http://localhost:9102/metrics | grep kepler_container_joules_total
```

### Calculate sPUE
According to your methodology (Section 5.3.2):

```
sPUE = E_total / E_functions

Where:
E_total = E_hardware_idle + E_K8s + E_OpenWhisk + E_runtime + E_function
```

---

## 🎯 Expected Outcomes

Based on your hypotheses (Section 6.1):

### H1: Idle Consumption
- **Prediction**: MicroVM 30-50% lower idle consumption
- **Reason**: No Guest OS overhead

### H2: Cold Start Energy
- **Prediction**: MicroVM 40-60% lower cold start energy
- **Reason**: Faster boot (125ms vs 10-60s)

### H3: Warm Execution
- **Prediction**: Comparable (±10%)
- **Reason**: Similar runtime overhead

### H4: Infrastructure Overhead
- **Prediction**: Control plane contribution identical
- **Reason**: Same Kubernetes control plane

### H5: Scalability
- **Prediction**: MicroVM efficiency may degrade at high concurrency
- **Reason**: CPU overhead from virtualization

---

## 🛠️ Troubleshooting

### Common Issues

#### 1. Cluster 2: Virtualization not supported
```bash
# Check: grep -E 'vmx|svm' /proc/cpuinfo
# Fix: Enable VT-x/AMD-V in BIOS or hypervisor
```

#### 2. Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n openwhisk
# Check: Insufficient resources, node selectors, taints
```

#### 3. OpenWhisk controller not starting
```bash
kubectl logs -n openwhisk -l name=controller
# Common: CouchDB not ready (wait longer)
```

#### 4. wsk CLI connection refused
```bash
# Verify service
kubectl get svc -n openwhisk owdev-nginx
# Check NodePort and reconfigure wsk
```

### Getting Help

1. Check detailed READMEs:
   - `README-CLUSTER1.md` for Cluster 1 issues
   - `README-CLUSTER2.md` for Cluster 2 issues

2. Check logs:
```bash
# Kubernetes logs
kubectl logs <pod-name> -n openwhisk
kubectl describe pod <pod-name> -n openwhisk

# System logs
sudo journalctl -u kubelet -f
sudo journalctl -u containerd -f
```

---

## 📖 Documentation References

### Your Project Documents
- **State of the Art**: `etat_art_projet_long.pdf`
- **Project Description**: `teabe-2.pdf`

### Technology Documentation
- **Kubernetes**: https://kubernetes.io/docs/
- **OpenWhisk**: https://openwhisk.apache.org/documentation.html
- **Kata Containers**: https://katacontainers.io/docs/
- **Firecracker**: https://firecracker-microvm.github.io/
- **Kepler**: https://sustainable-computing.io/

---

## 📞 Project Context

**Course**: Projet Long - ENSEEIHT  
**Team**: Sami Ayoub, Bahou Ayman, Berrada Yassine, Mekkaoui Ossama Moussa, Benkia Mohamed Amine, Hassain Ayoub  
**Supervisor**: Boris Teabe
**Date**: January 2026

---

## ✅ Deployment Checklist

Use this to track your progress:

### Pre-deployment
- [ ] 10 VMs allocated and accessible
- [ ] Virtualization verified on Cluster 2 VMs
- [ ] All scripts downloaded to appropriate nodes
- [ ] Network connectivity verified

### Cluster 1
- [ ] Base setup on 5 nodes
- [ ] Master initialized
- [ ] 4 workers joined
- [ ] All nodes Ready
- [ ] OpenWhisk deployed
- [ ] Test action working

### Cluster 2
- [ ] Base setup on 5 nodes
- [ ] Master initialized
- [ ] 4 workers joined
- [ ] Kata installed on workers
- [ ] RuntimeClass created
- [ ] Nodes labeled for Kata
- [ ] OpenWhisk deployed with Kata
- [ ] Test action working with MicroVM

### Instrumentation
- [ ] Kepler installed on both clusters
- [ ] Metrics accessible
- [ ] Baseline measurements collected

### Experiments
- [ ] Idle baseline measured
- [ ] Cold start experiments run
- [ ] Warm execution measured
- [ ] Mixed load tested
- [ ] Keep-alive sensitivity analyzed

---

## 🎉 Success Criteria

Your deployment is successful when:

1. ✅ Both clusters have all nodes Ready
2. ✅ OpenWhisk operational on both clusters
3. ✅ Test functions execute successfully
4. ✅ Cluster 1 uses standard containers
5. ✅ Cluster 2 uses Kata Containers with Firecracker
6. ✅ Energy metrics are collectible
7. ✅ Both clusters can handle your workload scenarios

---

## 📧 Support

For issues specific to:
- **Scripts**: Review detailed READMEs for each cluster
- **Project**: Contact supervisor Boris Teabe
- **Technology**: Refer to official documentation links above

---

**Good luck with your energy evaluation experiments! 🚀⚡**

*Remember: The goal is to quantify the energy trade-offs between isolation (security) and efficiency (performance). Your measurements will provide valuable insights for sustainable serverless computing!*
