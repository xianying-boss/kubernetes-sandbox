#!/bin/bash
# Kata Containers (KVM) Setup Script for Kubernetes Nodes
# Run this on each worker node where you want Kata Containers support
# Requires: Hardware virtualization (KVM) enabled

set -e

echo "=== Checking KVM Support ==="

# Check CPU virtualization support
if egrep -c '(vmx|svm)' /proc/cpuinfo > /dev/null; then
  CPU_COUNT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
  echo "✅ CPU virtualization supported (${CPU_COUNT} cores)"
else
  echo "❌ ERROR: CPU does not support virtualization (no vmx/svm flags)"
  echo "Kata Containers requires hardware virtualization support"
  exit 1
fi

# Check KVM modules
if lsmod | grep -q kvm; then
  echo "✅ KVM modules loaded"
else
  echo "⚠️  KVM modules not loaded, attempting to load..."
  sudo modprobe kvm
  sudo modprobe kvm_intel || sudo modprobe kvm_amd || true
fi

# Verify /dev/kvm exists
if [ -e /dev/kvm ]; then
  echo "✅ /dev/kvm device exists"
else
  echo "❌ ERROR: /dev/kvm not found"
  echo "KVM may not be enabled in BIOS or nested virtualization is not enabled"
  exit 1
fi

echo "=== Installing Kata Containers ==="

# Determine architecture
ARCH=$(uname -m)
KATA_VERSION="3.2.0"  # Latest stable as of early 2025

echo "Installing Kata Containers ${KATA_VERSION} for ${ARCH}..."

# Download and extract Kata static binaries
KATA_URL="https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${ARCH}.tar.xz"

cd /tmp
wget -q --show-progress "${KATA_URL}"

# Extract to root (installs to /opt/kata and /usr/local/bin)
sudo tar -xvf kata-static-${KATA_VERSION}-${ARCH}.tar.xz -C /

# Verify installation
if [ -f /opt/kata/bin/kata-runtime ]; then
  echo "✅ Kata runtime installed"
  /opt/kata/bin/kata-runtime --version
else
  echo "❌ Kata runtime not found after installation"
  exit 1
fi

echo "=== Configuring containerd for Kata ==="

# Backup existing config
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-$(date +%s)

# Check if kata runtime already exists
if grep -q "plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.kata" /etc/containerd/config.toml; then
  echo "Kata runtime config already exists, skipping..."
else
  # Add Kata runtime configuration
  cat <<EOF | sudo tee -a /etc/containerd/config.toml

# Kata Containers runtime configuration (KVM)
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
  runtime_type = "io.containerd.kata.v2"
  privileged_without_host_devices = false
  pod_annotations = ["io.katacontainers.*"]
  
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata.options]
  ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration.toml"
EOF

  echo "Kata runtime config added to containerd"
fi

echo "=== Configuring Kata Containers ==="

# Create custom configuration (optional, for tuning)
sudo mkdir -p /etc/kata-containers
cat <<EOF | sudo tee /etc/kata-containers/configuration.toml
# Kata Containers configuration
# This file overrides defaults from /opt/kata/share/defaults/kata-containers/configuration.toml

[hypervisor.qemu]
# Use KVM acceleration
enable_annotations = [".*"]
enable_iommu = false
enable_mem_prealloc = false
enable_swap = false
hotplug_vfio_on_root_bus = false

# Memory and CPU (adjust based on your needs)
default_memory = 2048
default_vcpus = 1
default_maxvcpus = 2

# VM firmware
firmware = "/opt/kata/share/kata-containers/kata-containers.img"

# Kernel
kernel = "/opt/kata/share/kata-containers/vmlinuz.container"
image = "/opt/kata/share/kata-containers/kata-containers.img"

# Machine type
machine_type = "q35"

[runtime]
enable_pprof = false
internetworking_model = "tcfilter"

[agent.kata]
enable_tracing = false
EOF

echo "=== Setting up KVM permissions ==="

# Add containerd user to kvm group
sudo usermod -aG kvm root
# If using specific user for containerd, add them too
if getent passwd containerd > /dev/null 2>&1; then
  sudo usermod -aG kvm containerd
fi

# Set /dev/kvm permissions
sudo chmod 666 /dev/kvm || true

echo "=== Restarting containerd ==="
sudo systemctl restart containerd
sleep 3
sudo systemctl status containerd --no-pager

echo "=== Verifying Kata installation ==="
if sudo crictl info | grep -q kata; then
  echo "✅ Kata runtime successfully configured in containerd"
else
  echo "⚠️  Kata runtime not found in containerd info, checking config..."
  sudo crictl info | grep -A 20 runtimes
fi

# Test kata-runtime
echo "=== Testing Kata runtime ==="
sudo /opt/kata/bin/kata-runtime kata-check

echo "=== Installation complete ==="
echo "Next steps:"
echo "1. Apply the RuntimeClass: kubectl apply -f kata-runtimeclass.yaml"
echo "2. Deploy pods with: runtimeClassName: kata"
echo ""
echo "To verify KVM is working:"
echo "  sudo /opt/kata/bin/kata-runtime kata-env"
