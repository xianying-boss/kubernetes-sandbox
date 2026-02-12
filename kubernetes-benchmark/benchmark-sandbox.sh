#!/bin/bash
# Kubernetes Sandbox Runtime Performance Benchmark
# This script runs comprehensive performance tests comparing runc, gVisor, and Kata

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="benchmark-sandbox"
RESULTS_DIR="/tmp/k8s-benchmark-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Kubernetes Sandbox Runtime Performance Benchmark        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi

# Create namespace
echo "Creating benchmark namespace..."
kubectl create namespace $NAMESPACE 2>/dev/null || true

# Create results directory
mkdir -p $RESULTS_DIR
REPORT_FILE="$RESULTS_DIR/benchmark-report-${TIMESTAMP}.txt"

# Function to log results
log_result() {
    echo "$1" | tee -a $REPORT_FILE
}

# Function to measure pod startup time
benchmark_startup() {
    local runtime=$1
    local test_name="startup-${runtime}"
    
    echo -e "${YELLOW}Testing startup time for: ${runtime}${NC}"
    
    # Create pod spec
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${test_name}
  namespace: ${NAMESPACE}
spec:
  runtimeClassName: ${runtime}
  containers:
  - name: test
    image: alpine:latest
    command: ["sh", "-c", "echo 'Started' && sleep 3600"]
  restartPolicy: Never
EOF
    
    # Measure time to Running
    local start_time=$(date +%s.%N)
    
    # Wait for pod to be running
    timeout 300 kubectl wait --for=condition=Ready \
        pod/${test_name} -n ${NAMESPACE} --timeout=300s > /dev/null 2>&1 || {
        echo -e "${RED}❌ Pod ${test_name} failed to start${NC}"
        kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
        return 1
    }
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo -e "${GREEN}✅ ${runtime}: ${duration}s${NC}"
    log_result "${runtime},startup,${duration}"
    
    # Cleanup
    kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
    sleep 2
}

# Function to measure CPU performance
benchmark_cpu() {
    local runtime=$1
    local test_name="cpu-${runtime}"
    
    echo -e "${YELLOW}Testing CPU performance for: ${runtime}${NC}"
    
    # Create pod with CPU stress test
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${test_name}
  namespace: ${NAMESPACE}
spec:
  runtimeClassName: ${runtime}
  containers:
  - name: test
    image: ubuntu:22.04
    command: 
    - /bin/bash
    - -c
    - |
      apt-get update > /dev/null 2>&1
      apt-get install -y sysbench bc > /dev/null 2>&1
      # CPU benchmark - calculate prime numbers
      result=\$(sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>&1 | grep "events per second" | awk '{print \$4}')
      echo "CPU_RESULT:\$result"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "512Mi"
      limits:
        cpu: "1000m"
        memory: "512Mi"
  restartPolicy: Never
EOF
    
    # Wait for pod to be running
    kubectl wait --for=condition=Ready pod/${test_name} -n ${NAMESPACE} --timeout=300s > /dev/null 2>&1 || {
        echo -e "${RED}❌ Pod ${test_name} failed to start${NC}"
        kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
        return 1
    }
    
    # Wait for benchmark to complete and get result
    local result=""
    for i in {1..60}; do
        result=$(kubectl logs ${test_name} -n ${NAMESPACE} 2>/dev/null | grep "CPU_RESULT:" | cut -d: -f2)
        if [ -n "$result" ]; then
            break
        fi
        sleep 5
    done
    
    if [ -n "$result" ]; then
        echo -e "${GREEN}✅ ${runtime}: ${result} events/sec${NC}"
        log_result "${runtime},cpu,${result}"
    else
        echo -e "${RED}❌ ${runtime}: No result${NC}"
        log_result "${runtime},cpu,failed"
    fi
    
    # Cleanup
    kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
    sleep 2
}

# Function to measure memory performance
benchmark_memory() {
    local runtime=$1
    local test_name="memory-${runtime}"
    
    echo -e "${YELLOW}Testing memory performance for: ${runtime}${NC}"
    
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${test_name}
  namespace: ${NAMESPACE}
spec:
  runtimeClassName: ${runtime}
  containers:
  - name: test
    image: ubuntu:22.04
    command:
    - /bin/bash
    - -c
    - |
      apt-get update > /dev/null 2>&1
      apt-get install -y sysbench > /dev/null 2>&1
      result=\$(sysbench memory --memory-block-size=1M --memory-total-size=10G run 2>&1 | grep "transferred" | awk '{print \$4}')
      echo "MEMORY_RESULT:\$result"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "1Gi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
  restartPolicy: Never
EOF
    
    kubectl wait --for=condition=Ready pod/${test_name} -n ${NAMESPACE} --timeout=300s > /dev/null 2>&1 || {
        echo -e "${RED}❌ Pod ${test_name} failed to start${NC}"
        kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
        return 1
    }
    
    local result=""
    for i in {1..60}; do
        result=$(kubectl logs ${test_name} -n ${NAMESPACE} 2>/dev/null | grep "MEMORY_RESULT:" | cut -d: -f2)
        if [ -n "$result" ]; then
            break
        fi
        sleep 5
    done
    
    if [ -n "$result" ]; then
        echo -e "${GREEN}✅ ${runtime}: ${result} MiB/sec${NC}"
        log_result "${runtime},memory,${result}"
    else
        echo -e "${RED}❌ ${runtime}: No result${NC}"
        log_result "${runtime},memory,failed"
    fi
    
    kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
    sleep 2
}

# Function to measure disk I/O
benchmark_disk() {
    local runtime=$1
    local test_name="disk-${runtime}"
    
    echo -e "${YELLOW}Testing disk I/O for: ${runtime}${NC}"
    
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${test_name}
  namespace: ${NAMESPACE}
spec:
  runtimeClassName: ${runtime}
  containers:
  - name: test
    image: ubuntu:22.04
    command:
    - /bin/bash
    - -c
    - |
      apt-get update > /dev/null 2>&1
      apt-get install -y fio > /dev/null 2>&1
      result=\$(fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=30 --group_reporting 2>&1 | grep "write: IOPS=" | awk -F'IOPS=' '{print \$2}' | awk -F',' '{print \$1}')
      echo "DISK_RESULT:\$result"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "1Gi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
  restartPolicy: Never
EOF
    
    kubectl wait --for=condition=Ready pod/${test_name} -n ${NAMESPACE} --timeout=300s > /dev/null 2>&1 || {
        echo -e "${RED}❌ Pod ${test_name} failed to start${NC}"
        kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
        return 1
    }
    
    local result=""
    for i in {1..90}; do
        result=$(kubectl logs ${test_name} -n ${NAMESPACE} 2>/dev/null | grep "DISK_RESULT:" | cut -d: -f2)
        if [ -n "$result" ]; then
            break
        fi
        sleep 5
    done
    
    if [ -n "$result" ]; then
        echo -e "${GREEN}✅ ${runtime}: ${result} IOPS${NC}"
        log_result "${runtime},disk,${result}"
    else
        echo -e "${RED}❌ ${runtime}: No result${NC}"
        log_result "${runtime},disk,failed"
    fi
    
    kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
    sleep 2
}

# Function to measure resource overhead
benchmark_overhead() {
    local runtime=$1
    local test_name="overhead-${runtime}"
    
    echo -e "${YELLOW}Measuring resource overhead for: ${runtime}${NC}"
    
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${test_name}
  namespace: ${NAMESPACE}
spec:
  runtimeClassName: ${runtime}
  containers:
  - name: test
    image: alpine:latest
    command: ["sh", "-c", "sleep 3600"]
    resources:
      requests:
        cpu: "100m"
        memory: "64Mi"
      limits:
        cpu: "100m"
        memory: "64Mi"
  restartPolicy: Never
EOF
    
    kubectl wait --for=condition=Ready pod/${test_name} -n ${NAMESPACE} --timeout=300s > /dev/null 2>&1 || {
        echo -e "${RED}❌ Pod ${test_name} failed to start${NC}"
        kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
        return 1
    }
    
    sleep 10
    
    # Get actual resource usage
    local metrics=$(kubectl top pod ${test_name} -n ${NAMESPACE} --no-headers 2>/dev/null || echo "N/A N/A N/A")
    local cpu=$(echo $metrics | awk '{print $2}')
    local mem=$(echo $metrics | awk '{print $3}')
    
    echo -e "${GREEN}✅ ${runtime}: CPU=${cpu}, Memory=${mem}${NC}"
    log_result "${runtime},overhead,CPU=${cpu} Memory=${mem}"
    
    kubectl delete pod ${test_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1 || true
    sleep 2
}

# Initialize report
log_result "Kubernetes Sandbox Runtime Performance Benchmark"
log_result "================================================"
log_result "Date: $(date)"
log_result "Cluster: $(kubectl config current-context)"
log_result ""
log_result "Runtime,Test,Result"
log_result "-------------------"

# Determine available runtimes
RUNTIMES=()

# Check for default runc
RUNTIMES+=("null")  # null means default runtime (runc)

# Check for gVisor
if kubectl get runtimeclass gvisor &> /dev/null || kubectl get runtimeclass gvisor-unrestricted &> /dev/null; then
    RUNTIMES+=("gvisor")
fi

# Check for Kata
if kubectl get runtimeclass kata &> /dev/null || kubectl get runtimeclass kata-unrestricted &> /dev/null; then
    RUNTIMES+=("kata")
fi

echo "Detected runtimes: ${RUNTIMES[@]}"
echo ""

# Install metrics server if not present
if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    echo -e "${YELLOW}Installing metrics-server for resource measurements...${NC}"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    sleep 20
fi

# Run benchmarks
echo ""
echo "=== Starting Benchmarks ==="
echo ""

# Test each runtime
for runtime in "${RUNTIMES[@]}"; do
    runtime_label=${runtime}
    [ "$runtime" == "null" ] && runtime_label="runc (default)"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing Runtime: ${runtime_label}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Replace null with empty string for pod spec
    runtime_spec=${runtime}
    [ "$runtime" == "null" ] && runtime_spec=""
    
    benchmark_startup "$runtime_spec"
    sleep 3
    
    benchmark_cpu "$runtime_spec"
    sleep 3
    
    benchmark_memory "$runtime_spec"
    sleep 3
    
    benchmark_disk "$runtime_spec"
    sleep 3
    
    benchmark_overhead "$runtime_spec"
    sleep 3
done

# Cleanup
echo ""
echo -e "${YELLOW}Cleaning up benchmark namespace...${NC}"
kubectl delete namespace $NAMESPACE --force --grace-period=0 > /dev/null 2>&1 || true

# Generate summary report
echo ""
echo "=== Benchmark Complete ==="
echo ""
echo "Results saved to: $REPORT_FILE"
echo ""
echo "Summary:"
cat $REPORT_FILE
echo ""

# Create comparison table
echo ""
echo "Creating comparison table..."

python3 - <<PYTHON_SCRIPT
import csv
import sys

results = {}
with open('$REPORT_FILE', 'r') as f:
    for line in f:
        if ',' in line and line.strip() and not line.startswith('Runtime'):
            parts = line.strip().split(',')
            if len(parts) >= 3:
                runtime = parts[0]
                test = parts[1]
                result = parts[2]
                
                if runtime not in results:
                    results[runtime] = {}
                results[runtime][test] = result

print("\n╔════════════════════════════════════════════════════════════════╗")
print("║           Performance Comparison Table                        ║")
print("╚════════════════════════════════════════════════════════════════╝\n")

# Print table
runtimes = list(results.keys())
tests = ['startup', 'cpu', 'memory', 'disk', 'overhead']

print(f"{'Test':<15}", end='')
for rt in runtimes:
    print(f"{rt:<20}", end='')
print()
print("-" * (15 + 20 * len(runtimes)))

for test in tests:
    print(f"{test:<15}", end='')
    for rt in runtimes:
        value = results.get(rt, {}).get(test, 'N/A')
        print(f"{value:<20}", end='')
    print()

PYTHON_SCRIPT

echo ""
echo -e "${GREEN}✅ Benchmark complete!${NC}"
echo ""
echo "Next steps:"
echo "  - Review results in: $REPORT_FILE"
echo "  - Compare performance across runtimes"
echo "  - Adjust resource allocation based on findings"
