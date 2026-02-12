#!/bin/bash
# Install gVisor task driver for Nomad
# Run this on Nomad client nodes

set -e

echo "=== Installing gVisor Task Driver for Nomad ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Step 1: Installing runsc (gVisor runtime) ===${NC}"

# Add gVisor repository
curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | \
  sudo tee /etc/apt/sources.list.d/gvisor.list

# Install runsc
sudo apt-get update
sudo apt-get install -y runsc

# Verify
runsc --version

echo -e "${GREEN}✅ runsc installed${NC}"

echo -e "${YELLOW}=== Step 2: Configuring Docker for gVisor ===${NC}"

# Configure Docker to use runsc
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "runtimes": {
    "runsc": {
      "path": "/usr/bin/runsc",
      "runtimeArgs": [
        "--platform=systrap"
      ]
    }
  }
}
EOF

# Restart Docker
sudo systemctl restart docker

# Verify Docker runtime
docker info | grep -A 10 "Runtimes:"

echo -e "${GREEN}✅ Docker configured for gVisor${NC}"

echo -e "${YELLOW}=== Step 3: Configuring Nomad Client ===${NC}"

# Add gVisor configuration to Nomad
cat <<EOF | sudo tee /etc/nomad.d/gvisor.hcl
# gVisor plugin configuration
plugin "docker" {
  config {
    allow_privileged = false
    
    allow_runtimes = ["runc", "runsc"]
    
    volumes {
      enabled = true
    }
  }
}
EOF

# Restart Nomad
sudo systemctl restart nomad

echo -e "${GREEN}✅ Nomad configured for gVisor${NC}"

echo -e "${YELLOW}=== Step 4: Verification ===${NC}"

sleep 5

# Test gVisor with Docker
echo "Testing gVisor with Docker..."
docker run --rm --runtime=runsc alpine uname -a

# Check Nomad node drivers
echo ""
echo "Nomad node drivers:"
nomad node status -self | grep -A 20 "Drivers"

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "gVisor is now available in Nomad!"
echo ""
echo "To use gVisor in a Nomad job, add to your task:"
echo '  config {'
echo '    runtime = "runsc"'
echo '  }'
echo ""
echo "Example job available in: example-nomad-gvisor.nomad"
