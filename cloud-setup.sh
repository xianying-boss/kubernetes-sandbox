#!/bin/bash
# Cloud-Specific Kubernetes Configuration
# Use this for managed Kubernetes services or cloud VMs

set -e

echo "=== Cloud Provider Configuration for Kubernetes ==="
echo ""
echo "Select your cloud provider:"
echo "1) AWS (EKS or EC2)"
echo "2) GCP (GKE or GCE)"
echo "3) Azure (AKS or VMs)"
echo "4) DigitalOcean"
echo "5) Generic Cloud/On-Premise"
read -p "Choice [1-5]: " CLOUD_CHOICE

case $CLOUD_CHOICE in
    1)
        echo "=== AWS Configuration ==="
        read -p "Are you using EKS (managed) or EC2 (self-managed)? [eks/ec2]: " AWS_TYPE
        
        if [ "$AWS_TYPE" == "eks" ]; then
            echo ""
            echo "For EKS, use eksctl or AWS Console to create cluster."
            echo "Then configure kubectl:"
            echo ""
            echo "  # Install AWS CLI"
            echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
            echo "  unzip awscliv2.zip"
            echo "  sudo ./aws/install"
            echo ""
            echo "  # Configure kubectl"
            echo "  aws eks update-kubeconfig --region <region> --name <cluster-name>"
            echo ""
            echo "For sandbox runtimes on EKS:"
            echo "  - gVisor: Supported via node groups"
            echo "  - Kata: Requires Fargate or bare metal instances"
            echo ""
        else
            echo ""
            echo "For EC2 self-managed Kubernetes:"
            echo ""
            echo "1. Configure security groups:"
            echo "   - Control plane: 6443, 2379-2380, 10250-10252"
            echo "   - Workers: 10250, 30000-32767"
            echo ""
            echo "2. Use elastic IPs for control plane"
            echo "3. Consider ELB for control plane HA"
            echo ""
            echo "Run standard installation scripts:"
            echo "  ./install-k8s-prerequisites.sh"
            echo "  ./install-k8s-master.sh (on control plane)"
            echo "  ./install-k8s-worker.sh (on workers)"
            echo ""
            
            # AWS-specific configurations
            cat <<'EOF' > /tmp/aws-cloud-provider.yaml
# AWS Cloud Provider Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloud-config
  namespace: kube-system
data:
  cloud.conf: |
    [Global]
    Zone=us-east-1a
    VPC=vpc-xxxxx
    SubnetID=subnet-xxxxx
    RouteTableID=rtb-xxxxx
EOF
            echo "AWS cloud provider config template created: /tmp/aws-cloud-provider.yaml"
        fi
        ;;
        
    2)
        echo "=== GCP Configuration ==="
        read -p "Are you using GKE (managed) or GCE (self-managed)? [gke/gce]: " GCP_TYPE
        
        if [ "$GCP_TYPE" == "gke" ]; then
            echo ""
            echo "For GKE, use gcloud CLI or Console to create cluster."
            echo "Then configure kubectl:"
            echo ""
            echo "  # Install gcloud CLI"
            echo "  curl https://sdk.cloud.google.com | bash"
            echo "  exec -l \$SHELL"
            echo ""
            echo "  # Configure kubectl"
            echo "  gcloud container clusters get-credentials <cluster-name> --region <region>"
            echo ""
            echo "For sandbox runtimes on GKE:"
            echo "  - gVisor: Use GKE Sandbox (--enable-sandbox flag)"
            echo "  - Kata: Not directly supported"
            echo ""
        else
            echo ""
            echo "For GCE self-managed Kubernetes:"
            echo ""
            echo "1. Configure firewall rules:"
            echo "   gcloud compute firewall-rules create k8s-control-plane \\"
            echo "     --allow tcp:6443,tcp:2379-2380,tcp:10250-10252"
            echo ""
            echo "2. Create instances with appropriate machine types"
            echo "3. Use internal load balancer for control plane HA"
            echo ""
            echo "Run standard installation scripts:"
            echo "  ./install-k8s-prerequisites.sh"
            echo "  ./install-k8s-master.sh"
            echo "  ./install-k8s-worker.sh"
            echo ""
        fi
        ;;
        
    3)
        echo "=== Azure Configuration ==="
        read -p "Are you using AKS (managed) or VMs (self-managed)? [aks/vms]: " AZURE_TYPE
        
        if [ "$AZURE_TYPE" == "aks" ]; then
            echo ""
            echo "For AKS, use Azure CLI or Portal to create cluster."
            echo "Then configure kubectl:"
            echo ""
            echo "  # Install Azure CLI"
            echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
            echo ""
            echo "  # Configure kubectl"
            echo "  az aks get-credentials --resource-group <rg> --name <cluster-name>"
            echo ""
            echo "For sandbox runtimes on AKS:"
            echo "  - gVisor: Not natively supported"
            echo "  - Kata: Supported via Kata node pools"
            echo ""
        else
            echo ""
            echo "For Azure VMs self-managed Kubernetes:"
            echo ""
            echo "1. Configure NSG rules for required ports"
            echo "2. Use Azure Load Balancer for control plane"
            echo "3. Consider using managed disks for etcd"
            echo ""
            echo "Run standard installation scripts:"
            echo "  ./install-k8s-prerequisites.sh"
            echo "  ./install-k8s-master.sh"
            echo "  ./install-k8s-worker.sh"
            echo ""
        fi
        ;;
        
    4)
        echo "=== DigitalOcean Configuration ==="
        read -p "Are you using DOKS (managed) or Droplets (self-managed)? [doks/droplets]: " DO_TYPE
        
        if [ "$DO_TYPE" == "doks" ]; then
            echo ""
            echo "For DOKS, use doctl CLI or Console to create cluster."
            echo "Then configure kubectl:"
            echo ""
            echo "  # Install doctl"
            echo "  cd ~"
            echo "  wget https://github.com/digitalocean/doctl/releases/download/v1.98.1/doctl-1.98.1-linux-amd64.tar.gz"
            echo "  tar xf doctl-1.98.1-linux-amd64.tar.gz"
            echo "  sudo mv doctl /usr/local/bin"
            echo ""
            echo "  # Configure kubectl"
            echo "  doctl kubernetes cluster kubeconfig save <cluster-name>"
            echo ""
        else
            echo ""
            echo "For Droplets self-managed Kubernetes:"
            echo ""
            echo "1. Configure firewall for required ports"
            echo "2. Use private networking for cluster communication"
            echo "3. Consider using DigitalOcean Load Balancer"
            echo ""
            echo "Run standard installation scripts:"
            echo "  ./install-k8s-prerequisites.sh"
            echo "  ./install-k8s-master.sh"
            echo "  ./install-k8s-worker.sh"
            echo ""
        fi
        ;;
        
    5)
        echo "=== Generic/On-Premise Configuration ==="
        echo ""
        echo "For generic cloud or on-premise deployment:"
        echo ""
        echo "1. Ensure network connectivity between nodes"
        echo "2. Configure firewall/security groups for required ports"
        echo "3. Set up external load balancer for HA (if needed)"
        echo ""
        echo "Run standard installation scripts:"
        echo "  ./install-k8s-prerequisites.sh"
        echo "  ./install-k8s-master.sh"
        echo "  ./install-k8s-worker.sh"
        echo ""
        ;;
esac

echo ""
echo "=== Cloud-Specific Recommendations ==="
echo ""
echo "Storage Classes:"
echo "  - AWS: EBS CSI driver (gp3 volumes recommended)"
echo "  - GCP: GCE PD CSI driver"
echo "  - Azure: Azure Disk CSI driver"
echo "  - DO: DigitalOcean Block Storage"
echo ""
echo "Load Balancers:"
echo "  - AWS: AWS Load Balancer Controller"
echo "  - GCP: GCE Ingress Controller"
echo "  - Azure: Azure Load Balancer"
echo "  - DO: DigitalOcean Load Balancer"
echo ""
echo "For sandbox runtimes (gVisor/Kata):"
echo "  - Ensure instance types support nested virtualization (for Kata)"
echo "  - Use latest generation instances for best performance"
echo "  - gVisor works on all instance types"
echo ""
