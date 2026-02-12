#!/bin/bash
# gVisor (systrap) Setup Script for Kubernetes Nodes
# Run this on each worker node where you want gVisor support

set -e

echo "=== Installing gVisor (runsc) ==="

# Add gVisor repository
curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | \
  sudo tee /etc/apt/sources.list.d/gvisor.list > /dev/null

# Install runsc
sudo apt-get update
sudo apt-get install -y runsc

# Verify installation
runsc --version

echo "=== Configuring containerd for gVisor ==="

# Backup existing config
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-$(date +%s)

# Check if gvisor runtime already exists
if grep -q "plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.gvisor" /etc/containerd/config.toml; then
  echo "gVisor runtime config already exists, skipping..."
else
  # Add gVisor runtime configuration
  cat <<EOF | sudo tee -a /etc/containerd/config.toml

# gVisor runtime configuration (systrap platform)
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.gvisor]
  runtime_type = "io.containerd.runsc.v1"
  
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.gvisor.options]
  TypeUrl = "io.containerd.runsc.v1.options"
  ConfigPath = "/etc/containerd/runsc.toml"
EOF

  echo "gVisor runtime config added to containerd"
fi

echo "=== Creating runsc configuration ==="

# Create runsc config with systrap platform
sudo mkdir -p /etc/containerd
cat <<EOF | sudo tee /etc/containerd/runsc.toml
# runsc configuration for systrap (non-KVM) mode
platform = "systrap"
network = "sandbox"
file-access = "exclusive"

# Disable features that require KVM
host-uds = "none"
host-fifo = "none"

# Logging (optional)
debug = false
debug-log = "/tmp/runsc/"
strace = false
EOF

echo "=== Restarting containerd ==="
sudo systemctl restart containerd
sudo systemctl status containerd --no-pager

echo "=== Verifying gVisor installation ==="
if sudo crictl info | grep -q gvisor; then
  echo "✅ gVisor runtime successfully configured in containerd"
else
  echo "⚠️  gVisor runtime not found in containerd info, checking config..."
  sudo crictl info | grep -A 20 runtimes
fi

echo "=== Installation complete ==="
echo "Next steps:"
echo "1. Apply the RuntimeClass: kubectl apply -f gvisor-runtimeclass.yaml"
echo "2. Deploy pods with: runtimeClassName: gvisor"
