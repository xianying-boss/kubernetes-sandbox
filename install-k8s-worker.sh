#!/bin/bash
# Kubernetes Worker Node Setup
# Run this on worker nodes AFTER running install-k8s-prerequisites.sh

set -e

echo "=== Kubernetes Worker Node Setup ==="
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

echo "This script will join this node to an existing Kubernetes cluster."
echo ""
echo "You need the join command from the control plane node."
echo "The join command looks like:"
echo "  kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
echo ""

read -p "Do you have the join command? (y/n): " HAS_JOIN
if [ "$HAS_JOIN" != "y" ]; then
    echo ""
    echo "To get the join command, run this on the control plane:"
    echo "  sudo kubeadm token create --print-join-command"
    echo ""
    exit 0
fi

echo ""
echo "Paste the complete join command (starting with 'kubeadm join'):"
read -r JOIN_COMMAND

# Validate join command
if [[ ! $JOIN_COMMAND =~ ^kubeadm\ join ]]; then
    echo -e "${RED}❌ Invalid join command. Must start with 'kubeadm join'${NC}"
    exit 1
fi

echo ""
echo "Join command to execute:"
echo "  sudo ${JOIN_COMMAND}"
echo ""
read -p "Continue? (y/n): " CONTINUE
if [ "$CONTINUE" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo -e "${YELLOW}=== Joining Kubernetes Cluster ===${NC}"

# Execute join command with sudo
sudo ${JOIN_COMMAND}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully joined the cluster${NC}"
    echo ""
    echo "This node is now part of the Kubernetes cluster."
    echo ""
    echo "To verify from the control plane, run:"
    echo "  kubectl get nodes"
    echo ""
    echo "To label this node for specific workloads:"
    echo "  kubectl label nodes $(hostname) node-role.kubernetes.io/worker=worker"
else
    echo -e "${RED}❌ Failed to join the cluster${NC}"
    echo ""
    echo "Common issues:"
    echo "  1. Firewall blocking port 6443"
    echo "  2. Token expired (tokens expire after 24 hours)"
    echo "  3. Network connectivity issues"
    echo "  4. Certificate hash mismatch"
    echo ""
    echo "To generate a new join command on the control plane:"
    echo "  sudo kubeadm token create --print-join-command"
fi
