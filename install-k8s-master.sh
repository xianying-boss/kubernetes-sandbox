#!/bin/bash
# Kubernetes Control Plane Setup
# Run this on the FIRST control plane node AFTER running install-k8s-prerequisites.sh

set -e

echo "=== Kubernetes Control Plane Installation ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if prerequisites are installed
if ! command -v kubeadm &> /dev/null; then
    echo -e "${RED}❌ kubeadm not found. Run install-k8s-prerequisites.sh first${NC}"
    exit 1
fi

# Get configuration
echo "Please provide the following information:"
echo ""
read -p "Pod network CIDR (default: 10.244.0.0/16): " POD_CIDR
POD_CIDR=${POD_CIDR:-10.244.0.0/16}

read -p "Service CIDR (default: 10.96.0.0/12): " SERVICE_CIDR
SERVICE_CIDR=${SERVICE_CIDR:-10.96.0.0/12}

read -p "Control plane endpoint (IP or DNS, leave empty for single master): " CONTROL_PLANE_ENDPOINT

read -p "API server advertise address (leave empty for auto-detect): " API_SERVER_ADDRESS

echo ""
echo "Configuration:"
echo "  Pod CIDR: ${POD_CIDR}"
echo "  Service CIDR: ${SERVICE_CIDR}"
echo "  Control Plane Endpoint: ${CONTROL_PLANE_ENDPOINT:-Single node}"
echo "  API Server Address: ${API_SERVER_ADDRESS:-Auto-detect}"
echo ""
read -p "Continue? (y/n): " CONTINUE
if [ "$CONTINUE" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo -e "${YELLOW}=== Initializing Kubernetes Control Plane ===${NC}"

# Build kubeadm init command
INIT_CMD="sudo kubeadm init --pod-network-cidr=${POD_CIDR} --service-cidr=${SERVICE_CIDR}"

if [ -n "$CONTROL_PLANE_ENDPOINT" ]; then
    INIT_CMD="${INIT_CMD} --control-plane-endpoint=${CONTROL_PLANE_ENDPOINT}"
fi

if [ -n "$API_SERVER_ADDRESS" ]; then
    INIT_CMD="${INIT_CMD} --apiserver-advertise-address=${API_SERVER_ADDRESS}"
fi

# Add CRI socket
INIT_CMD="${INIT_CMD} --cri-socket=unix:///run/containerd/containerd.sock"

echo "Running: ${INIT_CMD}"
echo ""

# Initialize cluster
$INIT_CMD | tee /tmp/kubeadm-init.log

echo -e "${GREEN}✅ Control plane initialized${NC}"

echo -e "${YELLOW}=== Setting up kubectl ===${NC}"

# Setup kubectl for root
sudo mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown root:root /root/.kube/config

# Setup kubectl for current user (if not root)
if [ "$USER" != "root" ]; then
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    echo -e "${GREEN}✅ kubectl configured for user: $USER${NC}"
fi

echo -e "${GREEN}✅ kubectl configured${NC}"

echo -e "${YELLOW}=== Installing CNI Plugin ===${NC}"
echo "Select CNI plugin:"
echo "1) Calico (recommended for production)"
echo "2) Flannel (simple, good for testing)"
echo "3) Cilium (advanced features, eBPF)"
echo "4) Skip (install manually later)"
read -p "Choice [1-4]: " CNI_CHOICE

case $CNI_CHOICE in
    1)
        echo "Installing Calico..."
        kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
        sleep 5
        
        # Create custom resources for Calico
        cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF
        echo -e "${GREEN}✅ Calico installed${NC}"
        ;;
    2)
        echo "Installing Flannel..."
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
        echo -e "${GREEN}✅ Flannel installed${NC}"
        ;;
    3)
        echo "Installing Cilium..."
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        CLI_ARCH=amd64
        if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
        sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        
        cilium install --version 1.15.0
        echo -e "${GREEN}✅ Cilium installed${NC}"
        ;;
    4)
        echo -e "${YELLOW}⚠️  Skipping CNI installation. Install manually before cluster is ready.${NC}"
        ;;
esac

echo -e "${YELLOW}=== Waiting for control plane to be ready ===${NC}"
sleep 10

# Wait for nodes to be ready
timeout 300 bash -c 'until kubectl get nodes | grep -q Ready; do sleep 5; done' || true

echo ""
echo -e "${GREEN}=== Control Plane Installation Complete ===${NC}"
echo ""

# Show cluster info
echo "Cluster status:"
kubectl get nodes
echo ""
kubectl get pods -A
echo ""

# Extract join commands
echo -e "${YELLOW}=== Join Commands ===${NC}"
echo ""
echo "To add WORKER nodes to this cluster, run this on each worker:"
echo ""
sudo kubeadm token create --print-join-command
echo ""

if [ -n "$CONTROL_PLANE_ENDPOINT" ]; then
    echo "To add additional CONTROL PLANE nodes, run this on each control plane node:"
    echo ""
    sudo kubeadm token create --print-join-command --certificate-key $(sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
    echo ""
fi

# Save join command to file
sudo kubeadm token create --print-join-command > /tmp/k8s-join-worker.sh
chmod +x /tmp/k8s-join-worker.sh
echo "Worker join command saved to: /tmp/k8s-join-worker.sh"

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify cluster: kubectl get nodes"
echo "  2. Deploy workloads: kubectl apply -f your-app.yaml"
echo "  3. Add worker nodes using the join command above"
echo ""
echo "To access cluster from another machine:"
echo "  1. Copy /etc/kubernetes/admin.conf to ~/.kube/config on your local machine"
echo "  2. Update server address in the config if needed"
