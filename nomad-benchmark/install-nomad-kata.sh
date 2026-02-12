#!/bin/bash
# Install Kata Containers for Nomad
# Run this on Nomad client nodes with KVM support

set -e

echo "=== Installing Kata Containers for Nomad ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Step 1: Checking KVM Support ===${NC}"

# Check CPU virtualization
if egrep -c '(vmx|svm)' /proc/cpuinfo > /dev/null; then
    CPU_COUNT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
    echo -e "${GREEN}✅ CPU virtualization supported (${CPU_COUNT} cores)${NC}"
else
    echo -e "${RED}❌ ERROR: CPU does not support virtualization${NC}"
    exit 1
fi

# Check KVM modules
if lsmod | grep -q kvm; then
    echo -e "${GREEN}✅ KVM modules loaded${NC}"
else
    echo "Loading KVM modules..."
    sudo modprobe kvm
    sudo modprobe kvm_intel || sudo modprobe kvm_amd || true
fi

# Check /dev/kvm
if [ -e /dev/kvm ]; then
    echo -e "${GREEN}✅ /dev/kvm device exists${NC}"
else
    echo -e "${RED}❌ ERROR: /dev/kvm not found${NC}"
    exit 1
fi

echo -e "${YELLOW}=== Step 2: Installing Kata Containers ===${NC}"

# Download and install Kata
KATA_VERSION="3.2.0"
ARCH=$(uname -m)

cd /tmp
wget "https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${ARCH}.tar.xz"

# Extract
sudo tar -xvf kata-static-${KATA_VERSION}-${ARCH}.tar.xz -C /

# Verify
/opt/kata/bin/kata-runtime --version

echo -e "${GREEN}✅ Kata Containers installed${NC}"

echo -e "${YELLOW}=== Step 3: Configuring Docker for Kata ===${NC}"

# Configure Docker with Kata runtime
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "runtimes": {
    "kata-runtime": {
      "path": "/opt/kata/bin/kata-runtime"
    }
  }
}
EOF

# Restart Docker
sudo systemctl restart docker

# Verify
docker info | grep -A 10 "Runtimes:"

echo -e "${GREEN}✅ Docker configured for Kata${NC}"

echo -e "${YELLOW}=== Step 4: Configuring Kata ===${NC}"

# Create custom configuration
sudo mkdir -p /etc/kata-containers
cat <<EOF | sudo tee /etc/kata-containers/configuration.toml
[hypervisor.qemu]
path = "/opt/kata/bin/qemu-system-x86_64"
kernel = "/opt/kata/share/kata-containers/vmlinuz.container"
image = "/opt/kata/share/kata-containers/kata-containers.img"
machine_type = "q35"
default_vcpus = 1
default_maxvcpus = 2
default_memory = 2048
enable_iommu = false

[runtime]
enable_pprof = false
internetworking_model = "tcfilter"
EOF

# Set permissions
sudo chmod 666 /dev/kvm
sudo usermod -aG kvm root

echo -e "${GREEN}✅ Kata configured${NC}"

echo -e "${YELLOW}=== Step 5: Configuring Nomad Client ===${NC}"

# Add Kata configuration to Nomad
cat <<EOF | sudo tee /etc/nomad.d/kata.hcl
# Kata Containers plugin configuration
plugin "docker" {
  config {
    allow_privileged = false
    
    allow_runtimes = ["runc", "kata-runtime"]
    
    volumes {
      enabled = true
    }
  }
}
EOF

# Restart Nomad
sudo systemctl restart nomad

echo -e "${GREEN}✅ Nomad configured for Kata${NC}"

echo -e "${YELLOW}=== Step 6: Verification ===${NC}"

sleep 5

# Test Kata runtime
echo "Running Kata check..."
sudo /opt/kata/bin/kata-runtime kata-check

# Test with Docker
echo ""
echo "Testing Kata with Docker..."
docker run --rm --runtime=kata-runtime alpine uname -a

# Check Nomad
echo ""
echo "Nomad node drivers:"
nomad node status -self | grep -A 20 "Drivers"

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "Kata Containers is now available in Nomad!"
echo ""
echo "To use Kata in a Nomad job, add to your task:"
echo '  config {'
echo '    runtime = "kata-runtime"'
echo '  }'
echo ""
echo "Example job available in: example-nomad-kata.nomad"
