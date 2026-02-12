#!/bin/bash
# HashiCorp Nomad Installation Script
# Run this on all Nomad nodes (servers and clients)

set -e

echo "=== HashiCorp Nomad Installation ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NOMAD_VERSION="1.7.5"  # Latest stable version
CONSUL_VERSION="1.18.0"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

echo "Detected OS: $OS"
echo "Nomad version: $NOMAD_VERSION"
echo ""

read -p "Install as [server/client/both]: " NODE_TYPE
NODE_TYPE=${NODE_TYPE:-both}

echo -e "${YELLOW}=== Step 1: Installing Prerequisites ===${NC}"

# Install required packages
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y \
        wget \
        curl \
        unzip \
        gpg \
        coreutils \
        jq
elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
    sudo yum install -y \
        wget \
        curl \
        unzip \
        gpg \
        coreutils \
        jq
fi

echo -e "${GREEN}✅ Prerequisites installed${NC}"

echo -e "${YELLOW}=== Step 2: Installing Docker ===${NC}"

# Install Docker (required for Nomad client)
if ! command -v docker &> /dev/null; then
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
        sudo yum install -y docker
    fi
    
    sudo systemctl enable docker
    sudo systemctl start docker
    echo -e "${GREEN}✅ Docker installed${NC}"
else
    echo -e "${GREEN}✅ Docker already installed${NC}"
fi

echo -e "${YELLOW}=== Step 3: Installing Nomad ===${NC}"

# Download Nomad
cd /tmp
wget "https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip"

# Verify checksum (optional but recommended)
wget "https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS"
sha256sum --ignore-missing -c nomad_${NOMAD_VERSION}_SHA256SUMS

# Install Nomad
unzip nomad_${NOMAD_VERSION}_linux_amd64.zip
sudo mv nomad /usr/local/bin/
sudo chmod +x /usr/local/bin/nomad

# Verify installation
nomad version

echo -e "${GREEN}✅ Nomad installed${NC}"

echo -e "${YELLOW}=== Step 4: Installing Consul (optional, recommended) ===${NC}"

if ask_yes_no "Install Consul for service discovery?"; then
    cd /tmp
    wget "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"
    unzip consul_${CONSUL_VERSION}_linux_amd64.zip
    sudo mv consul /usr/local/bin/
    sudo chmod +x /usr/local/bin/consul
    
    consul version
    echo -e "${GREEN}✅ Consul installed${NC}"
fi

echo -e "${YELLOW}=== Step 5: Configuring Nomad ===${NC}"

# Create directories
sudo mkdir -p /etc/nomad.d
sudo mkdir -p /opt/nomad/data

# Create common configuration
cat <<EOF | sudo tee /etc/nomad.d/nomad.hcl
# Common configuration
datacenter = "dc1"
data_dir = "/opt/nomad/data"
bind_addr = "0.0.0.0"

# Enable UI
ui {
  enabled = true
}
EOF

# Create server configuration
if [ "$NODE_TYPE" = "server" ] || [ "$NODE_TYPE" = "both" ]; then
    cat <<EOF | sudo tee /etc/nomad.d/server.hcl
# Server configuration
server {
  enabled = true
  bootstrap_expect = 1  # Change for multi-server setup
}
EOF
    echo -e "${GREEN}✅ Server configuration created${NC}"
fi

# Create client configuration
if [ "$NODE_TYPE" = "client" ] || [ "$NODE_TYPE" = "both" ]; then
    cat <<EOF | sudo tee /etc/nomad.d/client.hcl
# Client configuration
client {
  enabled = true
  
  # Resource allocation
  # Adjust based on your node capacity
  reserved {
    cpu            = 500
    memory         = 512
    disk           = 1024
  }
}

# Enable Docker driver
plugin "docker" {
  config {
    allow_privileged = false
    volumes {
      enabled = true
    }
  }
}
EOF
    echo -e "${GREEN}✅ Client configuration created${NC}"
fi

echo -e "${YELLOW}=== Step 6: Creating systemd service ===${NC}"

cat <<'EOF' | sudo tee /etc/systemd/system/nomad.service
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs/
Wants=network-online.target
After=network-online.target

[Service]
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
KillMode=process
KillSignal=SIGINT
LimitNOFILE=65536
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
TasksMax=infinity
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Nomad
sudo systemctl daemon-reload
sudo systemctl enable nomad
sudo systemctl start nomad

echo -e "${GREEN}✅ Nomad service started${NC}"

echo -e "${YELLOW}=== Step 7: Verification ===${NC}"

sleep 5

# Check status
sudo systemctl status nomad --no-pager

# Check node status
if [ "$NODE_TYPE" = "server" ] || [ "$NODE_TYPE" = "both" ]; then
    echo ""
    echo "Server members:"
    nomad server members
fi

if [ "$NODE_TYPE" = "client" ] || [ "$NODE_TYPE" = "both" ]; then
    echo ""
    echo "Client nodes:"
    nomad node status
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "Nomad UI available at: http://$(hostname -I | awk '{print $1}'):4646"
echo ""
echo "Useful commands:"
echo "  nomad node status                 # List nodes"
echo "  nomad job status                  # List jobs"
echo "  nomad server members              # List servers"
echo "  sudo systemctl status nomad       # Check service"
echo "  sudo journalctl -u nomad -f       # View logs"
echo ""
echo "Next steps:"
echo "  1. For multi-server setup, join additional servers"
echo "  2. Install sandbox runtimes: ./install-nomad-gvisor.sh or ./install-nomad-kata.sh"
echo "  3. Deploy jobs: nomad job run example.nomad"

# Helper function
ask_yes_no() {
    local question=$1
    read -p "$question [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}
