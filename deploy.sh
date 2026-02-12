#!/bin/bash
# Automated Kubernetes Sandbox Runtime Deployment
# This script helps deploy gVisor or Kata to your cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Kubernetes Sandbox Runtime Deployment                   ║"
echo "║   gVisor (systrap) & Kata Containers (KVM)                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
kubectl cluster-info | head -1
echo

# Function to display menu
show_menu() {
    echo "Select deployment option:"
    echo
    echo "1) Install gVisor (systrap) on specific nodes"
    echo "2) Install Kata Containers (KVM) on specific nodes"
    echo "3) Apply RuntimeClass configurations to cluster"
    echo "4) Deploy example workloads"
    echo "5) Verify installation"
    echo "6) Full setup (steps 1-3 combined)"
    echo "7) Exit"
    echo
}

# Function to install on nodes
install_on_nodes() {
    local runtime=$1
    local script=$2
    
    echo -e "${YELLOW}Available nodes:${NC}"
    kubectl get nodes -o wide
    echo
    
    read -p "Enter node names (space-separated) or 'all' for all nodes: " nodes
    
    if [ "$nodes" == "all" ]; then
        nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    fi
    
    for node in $nodes; do
        echo
        echo -e "${YELLOW}Installing ${runtime} on node: ${node}${NC}"
        
        # Get node IP
        NODE_IP=$(kubectl get node $node -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
        
        echo "Node IP: ${NODE_IP}"
        echo "Please SSH to the node and run: ./${script}"
        echo
        read -p "Press Enter when installation is complete on ${node}..."
        
        # Label the node
        read -p "Label this node for ${runtime}? (y/n): " label_choice
        if [ "$label_choice" == "y" ]; then
            bash "${SCRIPT_DIR}/label-nodes.sh" $node $runtime
        fi
    done
}

# Function to apply RuntimeClasses
apply_runtimeclasses() {
    echo -e "${YELLOW}Applying RuntimeClass configurations...${NC}"
    
    if [ -f "${SCRIPT_DIR}/gvisor-runtimeclass.yaml" ]; then
        echo "Applying gVisor RuntimeClass..."
        kubectl apply -f "${SCRIPT_DIR}/gvisor-runtimeclass.yaml"
    fi
    
    if [ -f "${SCRIPT_DIR}/kata-runtimeclass.yaml" ]; then
        echo "Applying Kata RuntimeClass..."
        kubectl apply -f "${SCRIPT_DIR}/kata-runtimeclass.yaml"
    fi
    
    echo
    echo -e "${GREEN}✅ RuntimeClasses applied${NC}"
    kubectl get runtimeclass
}

# Function to deploy examples
deploy_examples() {
    echo -e "${YELLOW}Available example workloads:${NC}"
    echo "1) gVisor test pod"
    echo "2) Kata test pod"
    echo "3) All examples from example-workloads.yaml"
    echo "4) Custom deployment"
    echo
    
    read -p "Select option: " example_choice
    
    case $example_choice in
        1)
            kubectl run gvisor-test --image=nginx:alpine --restart=Never \
                --overrides='{"spec":{"runtimeClassName":"gvisor"}}'
            echo -e "${GREEN}✅ gVisor test pod deployed${NC}"
            ;;
        2)
            kubectl run kata-test --image=nginx:alpine --restart=Never \
                --overrides='{"spec":{"runtimeClassName":"kata"}}'
            echo -e "${GREEN}✅ Kata test pod deployed${NC}"
            ;;
        3)
            if [ -f "${SCRIPT_DIR}/example-workloads.yaml" ]; then
                kubectl apply -f "${SCRIPT_DIR}/example-workloads.yaml"
                echo -e "${GREEN}✅ All examples deployed${NC}"
            else
                echo -e "${RED}❌ example-workloads.yaml not found${NC}"
            fi
            ;;
        4)
            read -p "Enter path to your YAML file: " yaml_file
            kubectl apply -f "$yaml_file"
            ;;
    esac
}

# Function to verify installation
verify_installation() {
    echo -e "${YELLOW}Verifying installation...${NC}"
    echo
    
    echo "=== RuntimeClasses ==="
    kubectl get runtimeclass
    echo
    
    echo "=== Nodes with runtime labels ==="
    kubectl get nodes --show-labels | grep -E 'runtime=|gvisor|kata' || echo "No labeled nodes found"
    echo
    
    echo "=== Pods using sandbox runtimes ==="
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(.spec.runtimeClassName != null) | 
        "\(.metadata.namespace)/\(.metadata.name) - Runtime: \(.spec.runtimeClassName)"' || \
        echo "No sandbox pods found"
    echo
    
    read -p "Test gVisor pod? (y/n): " test_gvisor
    if [ "$test_gvisor" == "y" ]; then
        echo "Deploying test pod..."
        kubectl run verify-gvisor --image=alpine --restart=Never \
            --overrides='{"spec":{"runtimeClassName":"gvisor"}}' \
            --command -- sleep 3600 2>/dev/null || true
        
        sleep 5
        
        if kubectl get pod verify-gvisor &>/dev/null; then
            echo -e "${GREEN}✅ gVisor pod running${NC}"
            echo "Kernel version:"
            kubectl exec verify-gvisor -- uname -a
            echo
            kubectl delete pod verify-gvisor
        else
            echo -e "${RED}❌ gVisor pod failed${NC}"
        fi
    fi
    
    read -p "Test Kata pod? (y/n): " test_kata
    if [ "$test_kata" == "y" ]; then
        echo "Deploying test pod..."
        kubectl run verify-kata --image=alpine --restart=Never \
            --overrides='{"spec":{"runtimeClassName":"kata"}}' \
            --command -- sleep 3600 2>/dev/null || true
        
        sleep 5
        
        if kubectl get pod verify-kata &>/dev/null; then
            echo -e "${GREEN}✅ Kata pod running${NC}"
            echo "Checking for VM indicators:"
            kubectl exec verify-kata -- dmesg 2>/dev/null | grep -i qemu | head -3 || echo "No QEMU messages (might need more time)"
            echo
            kubectl delete pod verify-kata
        else
            echo -e "${RED}❌ Kata pod failed${NC}"
        fi
    fi
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-7]: " choice
    
    case $choice in
        1)
            echo
            echo -e "${YELLOW}=== gVisor Installation ===${NC}"
            echo "You will need to SSH to each node and run: ./install-gvisor.sh"
            install_on_nodes "gvisor" "install-gvisor.sh"
            ;;
        2)
            echo
            echo -e "${YELLOW}=== Kata Containers Installation ===${NC}"
            echo "⚠️  Ensure KVM is available on these nodes!"
            echo "You will need to SSH to each node and run: ./install-kata.sh"
            install_on_nodes "kata" "install-kata.sh"
            ;;
        3)
            echo
            apply_runtimeclasses
            ;;
        4)
            echo
            deploy_examples
            ;;
        5)
            echo
            verify_installation
            ;;
        6)
            echo
            echo -e "${YELLOW}=== Full Setup ===${NC}"
            echo "This will guide you through:"
            echo "1. Installing runtimes on nodes"
            echo "2. Applying RuntimeClasses"
            echo "3. Verification"
            echo
            read -p "Continue? (y/n): " continue_choice
            if [ "$continue_choice" == "y" ]; then
                read -p "Install gVisor? (y/n): " install_gvisor
                if [ "$install_gvisor" == "y" ]; then
                    install_on_nodes "gvisor" "install-gvisor.sh"
                fi
                
                read -p "Install Kata? (y/n): " install_kata
                if [ "$install_kata" == "y" ]; then
                    install_on_nodes "kata" "install-kata.sh"
                fi
                
                apply_runtimeclasses
                verify_installation
                
                echo
                echo -e "${GREEN}✅ Full setup complete!${NC}"
            fi
            ;;
        7)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac
    
    echo
    read -p "Press Enter to continue..."
    clear
done
