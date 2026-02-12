# Complete Kubernetes + Sandbox Runtime Setup Guide

This package provides complete automation for setting up Kubernetes with gVisor and Kata Containers sandbox runtimes.

## 📦 What's Included

### Kubernetes Installation Scripts
- `install-k8s-prerequisites.sh` - Install containerd, kubeadm, kubelet, kubectl (run on ALL nodes)
- `install-k8s-master.sh` - Initialize control plane with CNI (run on control plane)
- `install-k8s-worker.sh` - Join worker nodes to cluster
- `complete-setup.sh` - **All-in-one automated setup** (recommended for beginners)
- `cloud-setup.sh` - Cloud provider specific guidance

### Sandbox Runtime Installation Scripts
- `install-gvisor.sh` - Install gVisor (systrap) for non-KVM environments
- `install-kata.sh` - Install Kata Containers (KVM) for hardware virtualization

### Kubernetes Configurations
- `gvisor-runtimeclass.yaml` - RuntimeClass for gVisor
- `kata-runtimeclass.yaml` - RuntimeClass for Kata Containers
- `example-workloads.yaml` - Sample pods, deployments, jobs, and services

### Helper Scripts
- `label-nodes.sh` - Label nodes based on installed runtimes
- `deploy.sh` - Interactive deployment assistant

### Documentation
- `KUBERNETES-INSTALL.md` - Detailed Kubernetes installation guide
- `README.md` - This file (overview)
- `sandbox-verification-guide.md` - How to verify sandbox runtimes

---

## 🚀 Quick Start

### Option 1: Complete Automated Setup (Easiest)

For a fully automated installation:

```bash
# Make executable
chmod +x complete-setup.sh

# Run as root
sudo ./complete-setup.sh
```

This interactive script will:
1. Install Kubernetes (if needed)
2. Set up control plane or join as worker
3. Install gVisor and/or Kata Containers
4. Apply RuntimeClasses
5. Optionally deploy example workloads

### Option 2: Step-by-Step Manual Setup

#### Step 1: Install Kubernetes

On **ALL nodes** (control plane and workers):
```bash
chmod +x install-k8s-prerequisites.sh
sudo ./install-k8s-prerequisites.sh
```

On **control plane node**:
```bash
chmod +x install-k8s-master.sh
sudo ./install-k8s-master.sh
```

On **worker nodes**:
```bash
chmod +x install-k8s-worker.sh
sudo ./install-k8s-worker.sh
# Paste the join command from control plane when prompted
```

#### Step 2: Install Sandbox Runtimes

On nodes where you want **gVisor**:
```bash
chmod +x install-gvisor.sh
sudo ./install-gvisor.sh
```

On nodes where you want **Kata Containers**:
```bash
# Verify KVM support first
egrep -c '(vmx|svm)' /proc/cpuinfo  # Should be > 0

chmod +x install-kata.sh
sudo ./install-kata.sh
```

#### Step 3: Apply RuntimeClasses

On the control plane:
```bash
kubectl apply -f gvisor-runtimeclass.yaml
kubectl apply -f kata-runtimeclass.yaml
kubectl get runtimeclass
```

#### Step 4: Test the Setup

```bash
# Test gVisor
kubectl run test-gvisor --image=nginx --restart=Never \
  --overrides='{"spec":{"runtimeClassName":"gvisor"}}'

# Verify
kubectl exec test-gvisor -- uname -a
# Should show old kernel version with gVisor

# Test Kata
kubectl run test-kata --image=nginx --restart=Never \
  --overrides='{"spec":{"runtimeClassName":"kata"}}'

# Verify
kubectl exec test-kata -- dmesg | grep -i qemu
# Should show QEMU/KVM messages
```

---

## 📋 Prerequisites

### Hardware Requirements

| Component | Control Plane | Worker Node |
|-----------|--------------|-------------|
| CPU | 2+ cores | 2+ cores |
| RAM | 4GB+ | 2GB+ |
| Disk | 20GB+ | 20GB+ |

**For Kata Containers (KVM):**
- Hardware virtualization (Intel VT-x or AMD-V)
- `/dev/kvm` device available
- Bare metal or nested virtualization enabled

**For gVisor:**
- Any Linux environment (works on cloud VMs)
- No special hardware requirements

### Operating System

- Ubuntu 22.04 LTS (recommended)
- Ubuntu 20.04 LTS
- Debian 11+
- CentOS 8+
- RHEL 8+

### Network Requirements

**Firewall Ports:**

Control Plane:
- 6443 (API server)
- 2379-2380 (etcd)
- 10250 (Kubelet)
- 10259 (kube-scheduler)
- 10257 (kube-controller-manager)

Worker Nodes:
- 10250 (Kubelet)
- 30000-32767 (NodePort services)

---

## 🎯 Common Use Cases

### Use Case 1: Single-Node Test Cluster with gVisor

```bash
# On one machine
sudo ./complete-setup.sh
# Select: 1) Complete new cluster
# Install gVisor: Yes
# Install Kata: No

# Deploy test app
kubectl create deployment test --image=nginx --replicas=3
kubectl patch deployment test -p '{"spec":{"template":{"spec":{"runtimeClassName":"gvisor"}}}}'
```

### Use Case 2: Multi-Node Production Cluster

```bash
# On control plane
sudo ./install-k8s-prerequisites.sh
sudo ./install-k8s-master.sh

# On each worker
sudo ./install-k8s-prerequisites.sh
sudo ./install-k8s-worker.sh
# Paste join command

# Install sandboxes on specific workers
sudo ./install-gvisor.sh  # On all workers
sudo ./install-kata.sh     # Only on bare metal workers
```

### Use Case 3: Cloud Environment (AWS/GCP/Azure)

```bash
# Get cloud-specific guidance
./cloud-setup.sh

# For managed Kubernetes (EKS/GKE/AKS)
# Follow cloud provider instructions to create cluster
# Then install sandboxes on node groups:
ssh node-1
sudo ./install-gvisor.sh
```

---

## 🔧 Configuration Options

### Kubernetes Configuration

During control plane setup, you can configure:
- **Pod CIDR**: Default `10.244.0.0/16`
- **Service CIDR**: Default `10.96.0.0/12`
- **CNI Plugin**: Calico (recommended), Flannel, or Cilium
- **Control Plane Endpoint**: For HA setups

### Sandbox Runtime Options

**gVisor:**
- Platform: `systrap` (default, works everywhere)
- Platform: `ptrace` (alternative, slower but more compatible)
- Platform: `kvm` (requires KVM, rarely used with gVisor)

**Kata Containers:**
- Hypervisor: QEMU/KVM (default)
- Memory: 2048MB (default, configurable)
- vCPUs: 1 (default, configurable)

Edit `/etc/kata-containers/configuration.toml` to adjust.

---

## 📊 Using Sandbox Runtimes

### In Pod Specifications

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  runtimeClassName: gvisor  # or kata
  containers:
  - name: app
    image: nginx:alpine
```

### In Deployments

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure
  template:
    metadata:
      labels:
        app: secure
    spec:
      runtimeClassName: kata  # or gvisor
      containers:
      - name: app
        image: python:3.11-slim
```

### With kubectl run

```bash
# gVisor
kubectl run myapp --image=nginx \
  --overrides='{"spec":{"runtimeClassName":"gvisor"}}'

# Kata
kubectl run myapp --image=nginx \
  --overrides='{"spec":{"runtimeClassName":"kata"}}'
```

---

## ✅ Verification

### Verify Kubernetes Installation

```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Verify Sandbox Runtimes

```bash
# Check RuntimeClasses
kubectl get runtimeclass

# Check from inside pod
kubectl exec <pod-name> -- uname -a
kubectl exec <pod-name> -- cat /proc/version

# gVisor should show old kernel (4.4.0)
# Kata should show virtualization indicators
```

See `sandbox-verification-guide.md` for detailed verification steps.

---

## 🐛 Troubleshooting

### Common Issues

**1. "kubeadm: command not found"**
```bash
# Run prerequisites script
sudo ./install-k8s-prerequisites.sh
```

**2. "Kubelet not starting"**
```bash
# Check swap is disabled
sudo swapoff -a
sudo systemctl restart kubelet
```

**3. "Pods stuck in Pending"**
```bash
# Check CNI is installed
kubectl get pods -n kube-system | grep -E 'calico|flannel|cilium'
```

**4. "gVisor pod won't start"**
```bash
# Verify runsc is installed
which runsc
runsc --version

# Check containerd config
sudo cat /etc/containerd/config.toml | grep gvisor
```

**5. "Kata pod won't start"**
```bash
# Check KVM support
egrep -c '(vmx|svm)' /proc/cpuinfo
ls -l /dev/kvm

# Verify kata-runtime
sudo /opt/kata/bin/kata-runtime kata-check
```

### Getting Help

1. Check logs:
   ```bash
   sudo journalctl -u kubelet -n 50
   sudo journalctl -u containerd -n 50
   ```

2. Describe resources:
   ```bash
   kubectl describe node <node-name>
   kubectl describe pod <pod-name>
   ```

3. Check events:
   ```bash
   kubectl get events --sort-by='.lastTimestamp'
   ```

---

## 🎓 Learning Resources

### Included Documentation
- `KUBERNETES-INSTALL.md` - Comprehensive Kubernetes installation guide
- `sandbox-verification-guide.md` - How to verify sandbox runtimes are working

### External Resources
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [gVisor Documentation](https://gvisor.dev/docs/)
- [Kata Containers Documentation](https://github.com/kata-containers/kata-containers/tree/main/docs)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)

---

## 📁 File Reference

```
.
├── complete-setup.sh                  # All-in-one automated installer
├── KUBERNETES-INSTALL.md              # Detailed K8s installation guide
├── README.md                          # This file
│
├── Kubernetes Installation/
│   ├── install-k8s-prerequisites.sh   # Install K8s components
│   ├── install-k8s-master.sh          # Initialize control plane
│   ├── install-k8s-worker.sh          # Join worker nodes
│   └── cloud-setup.sh                 # Cloud provider guidance
│
├── Sandbox Runtimes/
│   ├── install-gvisor.sh              # Install gVisor
│   ├── install-kata.sh                # Install Kata Containers
│   ├── gvisor-runtimeclass.yaml       # gVisor RuntimeClass
│   └── kata-runtimeclass.yaml         # Kata RuntimeClass
│
├── Utilities/
│   ├── deploy.sh                      # Interactive deployment tool
│   ├── label-nodes.sh                 # Label nodes by runtime
│   ├── example-workloads.yaml         # Sample deployments
│   └── sandbox-verification-guide.md  # Verification guide
```

---

## 🔐 Security Considerations

### When to Use gVisor
- Multi-tenant environments
- Running untrusted code
- Lightweight isolation needs
- Cloud environments without KVM

### When to Use Kata Containers
- Maximum security requirements
- Compliance-sensitive workloads
- Kernel-level isolation needed
- Bare metal or KVM-enabled environments

### Best Practices
1. Always use sandbox runtimes for untrusted workloads
2. Set appropriate resource limits
3. Use network policies with sandboxed pods
4. Regularly update sandbox runtime versions
5. Monitor performance impact

---

## 📈 Performance Considerations

| Metric | runc (default) | gVisor | Kata |
|--------|----------------|--------|------|
| CPU Overhead | ~5% | 10-30% | 30-50% |
| Memory Overhead | ~10MB | 30-50MB | 150-200MB |
| Startup Time | 100ms | 200-500ms | 1-2s |
| I/O Performance | Baseline | 70-90% | 60-80% |

**Recommendations:**
- Use gVisor for I/O light workloads
- Use Kata for CPU-intensive workloads
- Benchmark your specific applications
- Add overhead to resource requests

---

## 🤝 Contributing

Found an issue? Have a suggestion?
- Open an issue on GitHub
- Submit a pull request
- Share your feedback

---

## 📄 License

These scripts are provided as-is for educational and production use.

---

## 🙏 Acknowledgments

- Kubernetes SIG Node
- gVisor Team (Google)
- Kata Containers Community
- CNCF Sandbox Projects

---

**Happy Clustering! 🎉**

For questions or support, refer to the documentation files or community resources linked above.
