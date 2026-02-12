#!/bin/bash
# Kubernetes Prerequisites Setup
# Run this on ALL nodes (control plane and workers)

set -e

echo "=== Kubernetes Prerequisites Installation ==="
echo "This script will:"
echo "  1. Disable swap"
echo "  2. Configure kernel modules"
echo "  3. Install container runtime (containerd)"
echo "  4. Install Kubernetes packages"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
K8S_VERSION="1.29"  # Kubernetes version
CONTAINERD_VERSION="1.7.13"

echo -e "${YELLOW}=== Step 1: System Configuration ===${NC}"

# Disable swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
echo -e "${GREEN}✅ Swap disabled${NC}"

# Load kernel modules
echo "Loading required kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
echo -e "${GREEN}✅ Kernel modules loaded${NC}"

# Set sysctl parameters
echo "Configuring sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system > /dev/null
echo -e "${GREEN}✅ Sysctl configured${NC}"

echo -e "${YELLOW}=== Step 2: Installing containerd ===${NC}"

# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's GPG key and repository (for containerd)
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd.io

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
echo -e "${GREEN}✅ containerd installed and configured${NC}"

echo -e "${YELLOW}=== Step 3: Installing Kubernetes Components ===${NC}"

# Add Kubernetes repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable --now kubelet
echo -e "${GREEN}✅ Kubernetes components installed${NC}"

echo -e "${YELLOW}=== Step 4: Installing additional tools ===${NC}"

# Install crictl (container runtime CLI)
CRICTL_VERSION="v1.29.0"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
sudo tar zxvf crictl-${CRICTL_VERSION}-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-${CRICTL_VERSION}-linux-amd64.tar.gz

# Configure crictl
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

echo -e "${GREEN}✅ Additional tools installed${NC}"

echo ""
echo -e "${GREEN}=== Prerequisites Installation Complete ===${NC}"
echo ""
echo "Installed versions:"
kubeadm version
kubelet --version
kubectl version --client
containerd --version
crictl --version
echo ""
echo "Next steps:"
echo "  - If this is a CONTROL PLANE node: Run ./install-k8s-master.sh"
echo "  - If this is a WORKER node: Wait for join command from control plane"
