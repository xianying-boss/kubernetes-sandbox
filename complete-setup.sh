#!/bin/bash
# All-in-One Kubernetes + Sandbox Runtime Deployment
# This script automates the complete setup process

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║   Kubernetes + Sandbox Runtime Complete Setup                 ║
║                                                                ║
║   This script will:                                           ║
║   • Install Kubernetes (kubeadm + containerd)                 ║
║   • Set up control plane or worker nodes                      ║
║   • Install gVisor and/or Kata Containers                     ║
║   • Deploy example workloads                                  ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}This script must be run as root (sudo)${NC}"
    exit 1
fi

# Function to print section header
print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to ask yes/no question
ask_yes_no() {
    local question=$1
    local default=${2:-n}
    local response
    
    if [ "$default" == "y" ]; then
        read -p "$question [Y/n]: " response
        response=${response:-y}
    else
        read -p "$question [y/N]: " response
        response=${response:-n}
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# Main menu
print_header "Setup Configuration"

echo "What would you like to set up?"
echo ""
echo "1) Complete new cluster (control plane + Kubernetes + sandboxes)"
echo "2) Join as worker node (to existing cluster)"
echo "3) Install only sandbox runtimes (on existing Kubernetes)"
echo "4) Custom setup (interactive)"
echo ""
read -p "Choice [1-4]: " SETUP_TYPE

case $SETUP_TYPE in
    1)
        SETUP_K8S=true
        NODE_TYPE="control-plane"
        INSTALL_SANDBOXES=true
        ;;
    2)
        SETUP_K8S=true
        NODE_TYPE="worker"
        INSTALL_SANDBOXES=true
        ;;
    3)
        SETUP_K8S=false
        INSTALL_SANDBOXES=true
        ;;
    4)
        ask_yes_no "Install Kubernetes?" && SETUP_K8S=true || SETUP_K8S=false
        
        if [ "$SETUP_K8S" == true ]; then
            echo ""
            echo "Node type:"
            echo "1) Control Plane"
            echo "2) Worker"
            read -p "Choice [1-2]: " NODE_CHOICE
            [ "$NODE_CHOICE" == "1" ] && NODE_TYPE="control-plane" || NODE_TYPE="worker"
        fi
        
        ask_yes_no "Install sandbox runtimes?" && INSTALL_SANDBOXES=true || INSTALL_SANDBOXES=false
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Confirm configuration
print_header "Configuration Summary"
echo "Setup Kubernetes: $SETUP_K8S"
[ "$SETUP_K8S" == true ] && echo "Node Type: $NODE_TYPE"
echo "Install Sandboxes: $INSTALL_SANDBOXES"
echo ""
ask_yes_no "Continue with this configuration?" y || exit 0

#############################################
# STEP 1: Install Kubernetes Prerequisites
#############################################

if [ "$SETUP_K8S" == true ]; then
    print_header "Installing Kubernetes Prerequisites"
    
    # Check if already installed
    if command -v kubeadm &> /dev/null; then
        echo -e "${YELLOW}Kubernetes components already installed${NC}"
        ask_yes_no "Reinstall/reconfigure?" n || skip_k8s_prereq=true
    fi
    
    if [ "$skip_k8s_prereq" != true ]; then
        if [ -f "$SCRIPT_DIR/install-k8s-prerequisites.sh" ]; then
            bash "$SCRIPT_DIR/install-k8s-prerequisites.sh"
        else
            echo -e "${RED}install-k8s-prerequisites.sh not found${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✅ Prerequisites installed${NC}"
fi

#############################################
# STEP 2: Set up Control Plane or Worker
#############################################

if [ "$SETUP_K8S" == true ]; then
    if [ "$NODE_TYPE" == "control-plane" ]; then
        print_header "Setting Up Control Plane"
        
        if [ -f "$SCRIPT_DIR/install-k8s-master.sh" ]; then
            bash "$SCRIPT_DIR/install-k8s-master.sh"
        else
            echo -e "${RED}install-k8s-master.sh not found${NC}"
            exit 1
        fi
        
        # Wait for cluster to be ready
        echo "Waiting for cluster to be ready..."
        sleep 10
        
        # Save kubeconfig for current session
        export KUBECONFIG=/etc/kubernetes/admin.conf
        
        echo -e "${GREEN}✅ Control plane configured${NC}"
        
    else
        print_header "Joining as Worker Node"
        
        if [ -f "$SCRIPT_DIR/install-k8s-worker.sh" ]; then
            bash "$SCRIPT_DIR/install-k8s-worker.sh"
        else
            echo -e "${RED}install-k8s-worker.sh not found${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✅ Worker node joined${NC}"
    fi
fi

#############################################
# STEP 3: Install Sandbox Runtimes
#############################################

if [ "$INSTALL_SANDBOXES" == true ]; then
    print_header "Sandbox Runtime Installation"
    
    echo "Which sandbox runtimes would you like to install?"
    echo ""
    ask_yes_no "Install gVisor (systrap)?" y && INSTALL_GVISOR=true || INSTALL_GVISOR=false
    ask_yes_no "Install Kata Containers (KVM)?" && INSTALL_KATA=true || INSTALL_KATA=false
    
    # Install gVisor
    if [ "$INSTALL_GVISOR" == true ]; then
        print_header "Installing gVisor"
        
        if [ -f "$SCRIPT_DIR/install-gvisor.sh" ]; then
            bash "$SCRIPT_DIR/install-gvisor.sh"
            echo -e "${GREEN}✅ gVisor installed${NC}"
        else
            echo -e "${RED}install-gvisor.sh not found${NC}"
        fi
    fi
    
    # Install Kata
    if [ "$INSTALL_KATA" == true ]; then
        print_header "Installing Kata Containers"
        
        # Check KVM support
        if ! egrep -c '(vmx|svm)' /proc/cpuinfo > /dev/null 2>&1; then
            echo -e "${RED}❌ CPU does not support virtualization${NC}"
            echo "Kata Containers requires hardware virtualization (KVM)"
            ask_yes_no "Continue anyway?" n || INSTALL_KATA=false
        fi
        
        if [ "$INSTALL_KATA" == true ] && [ -f "$SCRIPT_DIR/install-kata.sh" ]; then
            bash "$SCRIPT_DIR/install-kata.sh"
            echo -e "${GREEN}✅ Kata Containers installed${NC}"
        fi
    fi
    
    # Apply RuntimeClasses (only on control plane)
    if [ "$NODE_TYPE" == "control-plane" ] || [ "$SETUP_K8S" == false ]; then
        print_header "Applying RuntimeClasses"
        
        if [ "$INSTALL_GVISOR" == true ] && [ -f "$SCRIPT_DIR/gvisor-runtimeclass.yaml" ]; then
            kubectl apply -f "$SCRIPT_DIR/gvisor-runtimeclass.yaml" 2>/dev/null || \
                echo -e "${YELLOW}Note: RuntimeClass already exists or kubectl not configured${NC}"
        fi
        
        if [ "$INSTALL_KATA" == true ] && [ -f "$SCRIPT_DIR/kata-runtimeclass.yaml" ]; then
            kubectl apply -f "$SCRIPT_DIR/kata-runtimeclass.yaml" 2>/dev/null || \
                echo -e "${YELLOW}Note: RuntimeClass already exists or kubectl not configured${NC}"
        fi
        
        echo -e "${GREEN}✅ RuntimeClasses configured${NC}"
    fi
fi

#############################################
# STEP 4: Deploy Examples (Optional)
#############################################

if [ "$NODE_TYPE" == "control-plane" ] && [ "$SETUP_K8S" == true ]; then
    print_header "Example Workloads"
    
    if ask_yes_no "Deploy example workloads?"; then
        if [ -f "$SCRIPT_DIR/example-workloads.yaml" ]; then
            kubectl apply -f "$SCRIPT_DIR/example-workloads.yaml"
            echo -e "${GREEN}✅ Example workloads deployed${NC}"
        else
            echo -e "${YELLOW}example-workloads.yaml not found${NC}"
        fi
    fi
fi

#############################################
# FINAL: Summary and Next Steps
#############################################

print_header "Installation Complete!"

echo -e "${GREEN}✅ Setup completed successfully!${NC}"
echo ""

if [ "$NODE_TYPE" == "control-plane" ]; then
    echo "Cluster Information:"
    echo "===================="
    kubectl get nodes 2>/dev/null || echo "Run: export KUBECONFIG=/etc/kubernetes/admin.conf"
    echo ""
    kubectl get runtimeclass 2>/dev/null || true
    echo ""
    
    echo "Worker Join Command:"
    echo "===================="
    kubeadm token create --print-join-command 2>/dev/null || \
        echo "Run: sudo kubeadm token create --print-join-command"
    echo ""
fi

echo "Next Steps:"
echo "==========="

if [ "$NODE_TYPE" == "control-plane" ]; then
    echo "1. Add worker nodes using the join command above"
    echo "2. Deploy your applications:"
    echo "   kubectl create deployment app --image=nginx"
    echo "   kubectl expose deployment app --port=80"
    echo ""
    echo "3. Use sandbox runtimes in your pods:"
    echo "   Add 'runtimeClassName: gvisor' or 'runtimeClassName: kata'"
    echo ""
    echo "4. Verify installation:"
    echo "   kubectl get nodes"
    echo "   kubectl get pods -A"
fi

if [ "$INSTALL_GVISOR" == true ]; then
    echo ""
    echo "Test gVisor:"
    echo "  kubectl run test-gvisor --image=nginx --restart=Never --overrides='{\"spec\":{\"runtimeClassName\":\"gvisor\"}}'"
    echo "  kubectl exec test-gvisor -- uname -a"
fi

if [ "$INSTALL_KATA" == true ]; then
    echo ""
    echo "Test Kata:"
    echo "  kubectl run test-kata --image=nginx --restart=Never --overrides='{\"spec\":{\"runtimeClassName\":\"kata\"}}'"
    echo "  kubectl exec test-kata -- dmesg | grep -i qemu"
fi

echo ""
echo "For detailed documentation, see:"
echo "  - KUBERNETES-INSTALL.md"
echo "  - README.md"
echo ""

# Save summary
cat > /tmp/setup-summary.txt <<EOF
Kubernetes + Sandbox Runtime Setup Summary
===========================================

Date: $(date)
Hostname: $(hostname)

Configuration:
- Kubernetes: $SETUP_K8S
- Node Type: ${NODE_TYPE:-N/A}
- gVisor: ${INSTALL_GVISOR:-false}
- Kata Containers: ${INSTALL_KATA:-false}

Installed Versions:
$(command -v kubeadm &>/dev/null && kubeadm version || echo "Kubernetes: Not installed")
$(command -v runsc &>/dev/null && runsc --version || echo "gVisor: Not installed")
$([ -f /opt/kata/bin/kata-runtime ] && /opt/kata/bin/kata-runtime --version || echo "Kata: Not installed")

Next Actions:
$( [ "$NODE_TYPE" == "control-plane" ] && echo "- Join worker nodes to cluster" || echo "- Node ready for workloads" )
$( [ "$INSTALL_GVISOR" == true ] && echo "- Test gVisor workloads" || true )
$( [ "$INSTALL_KATA" == true ] && echo "- Test Kata workloads" || true )
EOF

echo -e "${GREEN}Setup summary saved to: /tmp/setup-summary.txt${NC}"
echo ""
echo -e "${BLUE}Thank you for using this installer!${NC}"
