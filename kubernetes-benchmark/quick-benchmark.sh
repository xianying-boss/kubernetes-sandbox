#!/bin/bash
# Quick Performance Benchmark - Faster version
# Measures startup time and basic resource usage only

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="quick-benchmark"
ITERATIONS=3

echo "╔════════════════════════════════════════════════════╗"
echo "║   Quick Sandbox Runtime Benchmark                 ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

kubectl create namespace $NAMESPACE 2>/dev/null || true

# Function to measure startup time (average of N runs)
quick_startup_test() {
    local runtime=$1
    local total_time=0
    
    echo -e "${YELLOW}Testing ${runtime:-runc} startup time (${ITERATIONS} iterations)...${NC}"
    
    for i in $(seq 1 $ITERATIONS); do
        local pod_name="startup-test-$i"
        
        cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
spec:
  ${runtime:+runtimeClassName: $runtime}
  containers:
  - name: test
    image: alpine:latest
    command: ["sh", "-c", "echo ready && sleep 10"]
  restartPolicy: Never
EOF
        
        local start=$(date +%s.%N)
        kubectl wait --for=condition=Ready pod/${pod_name} -n ${NAMESPACE} --timeout=120s > /dev/null 2>&1
        local end=$(date +%s.%N)
        
        local duration=$(echo "$end - $start" | bc)
        total_time=$(echo "$total_time + $duration" | bc)
        
        kubectl delete pod ${pod_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1
        sleep 1
    done
    
    local avg_time=$(echo "scale=3; $total_time / $ITERATIONS" | bc)
    echo -e "${GREEN}✅ Average startup: ${avg_time}s${NC}"
    echo "${runtime:-runc},$avg_time"
}

# Function to measure memory overhead
quick_memory_test() {
    local runtime=$1
    local pod_name="memory-test"
    
    echo -e "${YELLOW}Testing ${runtime:-runc} memory overhead...${NC}"
    
    cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
spec:
  ${runtime:+runtimeClassName: $runtime}
  containers:
  - name: test
    image: alpine:latest
    command: ["sh", "-c", "sleep 60"]
    resources:
      requests:
        memory: "64Mi"
      limits:
        memory: "64Mi"
  restartPolicy: Never
EOF
    
    kubectl wait --for=condition=Ready pod/${pod_name} -n ${NAMESPACE} --timeout=120s > /dev/null 2>&1
    sleep 10
    
    local mem=$(kubectl top pod ${pod_name} -n ${NAMESPACE} --no-headers 2>/dev/null | awk '{print $3}' || echo "N/A")
    echo -e "${GREEN}✅ Memory usage: ${mem}${NC}"
    
    kubectl delete pod ${pod_name} -n ${NAMESPACE} --force --grace-period=0 > /dev/null 2>&1
    echo "${runtime:-runc},$mem"
}

# Check available runtimes
RUNTIMES=("" "gvisor" "kata")
AVAILABLE_RUNTIMES=()

for rt in "${RUNTIMES[@]}"; do
    if [ -z "$rt" ]; then
        AVAILABLE_RUNTIMES+=("")
    elif kubectl get runtimeclass $rt &> /dev/null || kubectl get runtimeclass ${rt}-unrestricted &> /dev/null; then
        AVAILABLE_RUNTIMES+=("$rt")
    fi
done

echo "Testing runtimes: ${AVAILABLE_RUNTIMES[@]:-runc}"
echo ""

# Results
RESULTS_FILE="/tmp/quick-benchmark-$(date +%s).csv"
echo "Runtime,Startup(s),Memory" > $RESULTS_FILE

for runtime in "${AVAILABLE_RUNTIMES[@]}"; do
    runtime_name=${runtime:-runc}
    echo ""
    echo -e "${BLUE}━━━ Testing: ${runtime_name} ━━━${NC}"
    
    startup_result=$(quick_startup_test "$runtime")
    sleep 2
    memory_result=$(quick_memory_test "$runtime")
    
    startup_time=$(echo $startup_result | cut -d',' -f2)
    mem_usage=$(echo $memory_result | cut -d',' -f2)
    
    echo "${runtime_name},${startup_time},${mem_usage}" >> $RESULTS_FILE
done

kubectl delete namespace $NAMESPACE --force --grace-period=0 > /dev/null 2>&1

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results:"
cat $RESULTS_FILE
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Saved to: $RESULTS_FILE"
