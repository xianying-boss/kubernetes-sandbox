# Kubernetes Installation Guide

Complete guide for installing Kubernetes from scratch using kubeadm.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation Steps](#installation-steps)
4. [Cluster Setup](#cluster-setup)
5. [Verification](#verification)
6. [Common Issues](#common-issues)

---

## Overview

This guide covers installing Kubernetes 1.29 using kubeadm on Ubuntu 22.04 LTS with containerd as the container runtime.

### Architecture Options

**Single-node cluster (testing):**
- 1 control plane node
- Good for development/testing

**Multi-node cluster (production):**
- 1+ control plane nodes
- 2+ worker nodes
- Recommended for production

---

## Prerequisites

### Hardware Requirements

**Control Plane Node:**
- 2+ CPUs
- 4GB+ RAM
- 20GB+ disk space

**Worker Nodes:**
- 2+ CPUs
- 2GB+ RAM
- 20GB+ disk space

### Network Requirements

**Required Ports:**

Control Plane:
- 6443: Kubernetes API server
- 2379-2380: etcd server client API
- 10250: Kubelet API
- 10259: kube-scheduler
- 10257: kube-controller-manager

Worker Nodes:
- 10250: Kubelet API
- 30000-32767: NodePort Services

**Firewall Configuration:**

```bash
# On control plane
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 10259/tcp
sudo ufw allow 10257/tcp

# On worker nodes
sudo ufw allow 10250/tcp
sudo ufw allow 30000:32767/tcp
```

### Operating System

- Ubuntu 22.04 LTS (recommended)
- Ubuntu 20.04 LTS
- Debian 11+
- CentOS 8+
- RHEL 8+

---

## Installation Steps

### Step 1: Prepare All Nodes

Run `install-k8s-prerequisites.sh` on **EVERY** node (control plane and workers).

```bash
# Make script executable
chmod +x install-k8s-prerequisites.sh

# Run on each node
sudo ./install-k8s-prerequisites.sh
```

This script will:
1. Disable swap
2. Load required kernel modules
3. Configure networking
4. Install containerd
5. Install kubeadm, kubelet, kubectl

**Verification:**

```bash
# Check installations
kubeadm version
kubelet --version
kubectl version --client
containerd --version
crictl --version

# Verify containerd is running
sudo systemctl status containerd

# Verify kernel modules
lsmod | grep br_netfilter
lsmod | grep overlay
```

### Step 2: Initialize Control Plane

Run `install-k8s-master.sh` on the **FIRST control plane node only**.

```bash
chmod +x install-k8s-master.sh
sudo ./install-k8s-master.sh
```

You'll be prompted for:
- **Pod network CIDR**: Default `10.244.0.0/16`
- **Service CIDR**: Default `10.96.0.0/12`
- **Control plane endpoint**: For HA setup (optional)
- **API server address**: Usually auto-detected (optional)
- **CNI plugin**: Choose Calico, Flannel, or Cilium

**What happens:**
1. Initializes Kubernetes control plane
2. Configures kubectl
3. Installs CNI plugin
4. Generates join commands

**Save the join command!** It will be printed at the end and saved to `/tmp/k8s-join-worker.sh`

### Step 3: Join Worker Nodes

Run `install-k8s-worker.sh` on **EACH worker node**.

```bash
chmod +x install-k8s-worker.sh
sudo ./install-k8s-worker.sh
```

When prompted, paste the join command from Step 2.

**Alternative method** (using saved join command):

```bash
# Copy join command from control plane
scp user@control-plane:/tmp/k8s-join-worker.sh .

# Run it
sudo bash k8s-join-worker.sh
```

---

## Cluster Setup

### Verify Cluster

```bash
# On control plane
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

Expected output:
```
NAME            STATUS   ROLES           AGE   VERSION
control-plane   Ready    control-plane   5m    v1.29.0
worker-1        Ready    <none>          2m    v1.29.0
worker-2        Ready    <none>          2m    v1.29.0
```

### Label Worker Nodes

```bash
# Label nodes with worker role
kubectl label node worker-1 node-role.kubernetes.io/worker=worker
kubectl label node worker-2 node-role.kubernetes.io/worker=worker
```

### Test the Cluster

Deploy a test application:

```bash
# Create deployment
kubectl create deployment nginx --image=nginx --replicas=3

# Expose as service
kubectl expose deployment nginx --port=80 --type=NodePort

# Check status
kubectl get pods
kubectl get svc nginx

# Get NodePort
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
echo "Access nginx at: http://<node-ip>:${NODE_PORT}"

# Test
curl http://<any-node-ip>:${NODE_PORT}
```

Clean up:
```bash
kubectl delete svc nginx
kubectl delete deployment nginx
```

---

## CNI Plugin Details

### Calico (Recommended for Production)

```bash
# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Configure Calico
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Verify
kubectl get pods -n calico-system
```

**Features:**
- Network policies
- BGP routing
- IPIP/VXLAN encapsulation
- High performance

### Flannel (Simple, Good for Testing)

```bash
# Install Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Verify
kubectl get pods -n kube-flannel
```

**Features:**
- Simple VXLAN overlay
- Easy to set up
- Good for small clusters

### Cilium (Advanced)

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin

# Install Cilium
cilium install --version 1.15.0

# Verify
cilium status
kubectl get pods -n kube-system -l k8s-app=cilium
```

**Features:**
- eBPF-based networking
- Advanced network policies
- Service mesh capabilities
- Observability

---

## Advanced Configuration

### High Availability (HA) Setup

For production, set up multiple control plane nodes:

1. **Set up load balancer** for control plane endpoint
2. **Initialize first control plane** with `--control-plane-endpoint`
3. **Join additional control planes**:

```bash
# On first control plane after init
sudo kubeadm init phase upload-certs --upload-certs

# This prints a certificate key, use it to join other control planes
# On other control plane nodes:
sudo kubeadm join <lb-endpoint>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>
```

### Storage Configuration

Install storage provisioner for persistent volumes:

**Local Path Provisioner (simple):**

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Set as default
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**NFS Provisioner:**

```bash
# Install NFS CSI driver
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/nfs-subdir-external-provisioner/master/deploy/rbac.yaml
# Configure with your NFS server details
```

### Ingress Controller

Install NGINX Ingress Controller:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml

# Verify
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

---

## Verification

### Complete Cluster Health Check

```bash
# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -A

# Check component health
kubectl get componentstatuses

# Check API server
kubectl cluster-info

# Check etcd
sudo crictl ps | grep etcd

# Check logs
kubectl logs -n kube-system <pod-name>
journalctl -u kubelet -n 50
```

### Resource Usage

```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -A

# Describe node
kubectl describe node <node-name>
```

---

## Common Issues

### Issue 1: Kubelet not starting

```bash
# Check status
sudo systemctl status kubelet

# View logs
sudo journalctl -u kubelet -n 50

# Common causes:
# - Swap not disabled
# - Container runtime not running
# - Port conflicts
```

**Fix:**
```bash
sudo swapoff -a
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

### Issue 2: Pods stuck in Pending

```bash
# Check events
kubectl describe pod <pod-name>

# Common causes:
# - CNI not installed
# - Insufficient resources
# - Node not ready
```

**Fix:**
```bash
# Check CNI
kubectl get pods -n kube-system | grep -E 'calico|flannel|cilium'

# Check node capacity
kubectl describe node <node-name> | grep -A 5 Capacity
```

### Issue 3: Node NotReady

```bash
# Check node
kubectl describe node <node-name>

# Common causes:
# - Kubelet issues
# - Network issues
# - Disk pressure
```

**Fix:**
```bash
# On the node
sudo systemctl restart kubelet
sudo systemctl restart containerd

# Check disk space
df -h

# Check network
ping 8.8.8.8
```

### Issue 4: Cannot pull images

```bash
# Check containerd
sudo systemctl status containerd
sudo crictl images

# Test image pull
sudo crictl pull nginx:alpine
```

**Fix:**
```bash
sudo systemctl restart containerd

# Configure registry mirror if needed
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
```

### Issue 5: Token expired

If worker join fails with "token expired":

```bash
# On control plane, generate new token
sudo kubeadm token create --print-join-command

# Use the new command on worker
```

### Issue 6: Certificate errors

```bash
# Regenerate certificates (on control plane)
sudo kubeadm certs renew all
sudo systemctl restart kubelet
```

---

## Maintenance

### Reset Node

To completely reset a node:

```bash
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
```

### Upgrade Cluster

```bash
# Check current version
kubectl version

# Upgrade control plane
sudo apt-mark unhold kubeadm
sudo apt-get update
sudo apt-get install -y kubeadm=1.29.x-00
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.29.x

# Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get update
sudo apt-get install -y kubelet=1.29.x-00 kubectl=1.29.x-00
sudo apt-mark hold kubelet kubectl
sudo systemctl restart kubelet

# Upgrade workers (one at a time)
kubectl drain <worker-node> --ignore-daemonsets
# SSH to worker and upgrade kubeadm, kubelet, kubectl
sudo kubeadm upgrade node
kubectl uncordon <worker-node>
```

---

## Next Steps

After Kubernetes is installed:

1. **Install sandbox runtimes** (gVisor/Kata)
   - Run `./install-gvisor.sh` or `./install-kata.sh`
   - Apply RuntimeClasses

2. **Set up monitoring**
   - Prometheus + Grafana
   - Metrics Server

3. **Deploy applications**
   - Use kubectl apply -f
   - Use Helm charts

4. **Configure security**
   - RBAC policies
   - Network policies
   - Pod security standards

---

## Quick Reference

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# Deploy app
kubectl create deployment app --image=nginx
kubectl scale deployment app --replicas=3
kubectl expose deployment app --port=80

# Troubleshooting
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- bash

# Node operations
kubectl drain <node> --ignore-daemonsets
kubectl uncordon <node>
kubectl delete node <node>

# Config
kubectl config view
kubectl config get-contexts
kubectl config use-context <context>
```

---

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [containerd Documentation](https://containerd.io/docs/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)
- [Cilium Documentation](https://docs.cilium.io/)
