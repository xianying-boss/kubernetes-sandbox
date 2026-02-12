#!/bin/bash
# Label Kubernetes nodes based on installed runtimes
# Run this after installing gVisor or Kata on your nodes

set -e

if [ $# -eq 0 ]; then
  echo "Usage: $0 <node-name> <runtime-type>"
  echo ""
  echo "Runtime types:"
  echo "  gvisor  - Label node for gVisor runtime"
  echo "  kata    - Label node for Kata Containers runtime"
  echo "  both    - Label node for both runtimes"
  echo ""
  echo "Example:"
  echo "  $0 worker-node-1 gvisor"
  echo "  $0 worker-node-2 kata"
  echo "  $0 worker-node-3 both"
  exit 1
fi

NODE_NAME=$1
RUNTIME_TYPE=$2

echo "=== Labeling node: ${NODE_NAME} for ${RUNTIME_TYPE} runtime ==="

case $RUNTIME_TYPE in
  gvisor)
    kubectl label nodes ${NODE_NAME} runtime=gvisor --overwrite
    kubectl label nodes ${NODE_NAME} gvisor.io/runtime=true --overwrite
    echo "✅ Node labeled for gVisor"
    ;;
    
  kata)
    kubectl label nodes ${NODE_NAME} runtime=kata --overwrite
    kubectl label nodes ${NODE_NAME} katacontainers.io/kata-runtime=true --overwrite
    echo "✅ Node labeled for Kata Containers"
    ;;
    
  both)
    kubectl label nodes ${NODE_NAME} runtime=hybrid --overwrite
    kubectl label nodes ${NODE_NAME} gvisor.io/runtime=true --overwrite
    kubectl label nodes ${NODE_NAME} katacontainers.io/kata-runtime=true --overwrite
    echo "✅ Node labeled for both gVisor and Kata"
    ;;
    
  *)
    echo "❌ Unknown runtime type: ${RUNTIME_TYPE}"
    echo "Valid options: gvisor, kata, both"
    exit 1
    ;;
esac

echo ""
echo "Current labels for ${NODE_NAME}:"
kubectl get node ${NODE_NAME} --show-labels | grep -o 'runtime.*'

echo ""
echo "To verify RuntimeClasses are configured:"
echo "  kubectl get runtimeclass"
