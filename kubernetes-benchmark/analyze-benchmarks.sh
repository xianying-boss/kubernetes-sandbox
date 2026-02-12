#!/bin/bash
# Analyze and compare performance from running benchmark pods

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Benchmark Results Analyzer                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if benchmark pods are running
RUNTIMES=()
if kubectl get pod -l app=benchmark,runtime=runc &> /dev/null; then
    RUNTIMES+=("runc")
fi
if kubectl get pod -l app=benchmark,runtime=gvisor &> /dev/null; then
    RUNTIMES+=("gvisor")
fi
if kubectl get pod -l app=benchmark,runtime=kata &> /dev/null; then
    RUNTIMES+=("kata")
fi

if [ ${#RUNTIMES[@]} -eq 0 ]; then
    echo "No benchmark pods found. Deploy them first:"
    echo "  kubectl apply -f benchmark-deployments.yaml"
    exit 1
fi

echo "Found benchmark pods for: ${RUNTIMES[@]}"
echo ""

# Function to get pod metrics
get_pod_metrics() {
    local runtime=$1
    local pod=$(kubectl get pod -l app=benchmark,runtime=$runtime -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod" ]; then
        echo "N/A,N/A"
        return
    fi
    
    local metrics=$(kubectl top pod $pod --no-headers 2>/dev/null || echo "N/A N/A N/A")
    local cpu=$(echo $metrics | awk '{print $2}')
    local mem=$(echo $metrics | awk '{print $3}')
    
    echo "$cpu,$mem"
}

# Function to extract benchmark results from logs
get_benchmark_results() {
    local runtime=$1
    local pod=$(kubectl get pod -l app=benchmark,runtime=$runtime -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod" ]; then
        echo "N/A,N/A"
        return
    fi
    
    # Get last CPU test result
    local cpu_result=$(kubectl logs $pod --tail=200 2>/dev/null | grep "events per second:" | tail -1 | awk '{print $4}' || echo "N/A")
    
    # Get last memory test result
    local mem_result=$(kubectl logs $pod --tail=200 2>/dev/null | grep "transferred" | tail -1 | awk '{print $4}' | sed 's/[()]//g' || echo "N/A")
    
    echo "$cpu_result,$mem_result"
}

# Collect results
RESULTS_FILE="/tmp/benchmark-analysis-$(date +%Y%m%d-%H%M%S).txt"

echo "Collecting metrics and benchmark results..."
echo ""

{
    echo "Benchmark Analysis Report"
    echo "========================="
    echo "Date: $(date)"
    echo "Cluster: $(kubectl config current-context)"
    echo ""
    echo "Runtime Performance Comparison"
    echo "------------------------------"
    echo ""
    printf "%-10s %-15s %-15s %-20s %-20s\n" "Runtime" "CPU Usage" "Memory Usage" "CPU Benchmark" "Memory Benchmark"
    printf "%-10s %-15s %-15s %-20s %-20s\n" "-------" "---------" "------------" "-------------" "----------------"
} | tee $RESULTS_FILE

for runtime in "${RUNTIMES[@]}"; do
    metrics=$(get_pod_metrics $runtime)
    cpu_usage=$(echo $metrics | cut -d',' -f1)
    mem_usage=$(echo $metrics | cut -d',' -f2)
    
    bench_results=$(get_benchmark_results $runtime)
    cpu_bench=$(echo $bench_results | cut -d',' -f1)
    mem_bench=$(echo $bench_results | cut -d',' -f2)
    
    printf "%-10s %-15s %-15s %-20s %-20s\n" "$runtime" "$cpu_usage" "$mem_usage" "$cpu_bench" "$mem_bench" | tee -a $RESULTS_FILE
done

echo "" | tee -a $RESULTS_FILE
echo "Notes:" | tee -a $RESULTS_FILE
echo "  - CPU Usage: Current CPU consumption" | tee -a $RESULTS_FILE
echo "  - Memory Usage: Current memory consumption" | tee -a $RESULTS_FILE
echo "  - CPU Benchmark: Events per second (higher is better)" | tee -a $RESULTS_FILE
echo "  - Memory Benchmark: MiB/sec (higher is better)" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE

# Calculate percentages if runc is available
if [[ " ${RUNTIMES[@]} " =~ " runc " ]]; then
    echo "Performance vs runc baseline:" | tee -a $RESULTS_FILE
    echo "-----------------------------" | tee -a $RESULTS_FILE
    
    runc_bench=$(get_benchmark_results runc)
    runc_cpu=$(echo $runc_bench | cut -d',' -f1)
    
    for runtime in "${RUNTIMES[@]}"; do
        if [ "$runtime" != "runc" ]; then
            bench=$(get_benchmark_results $runtime)
            runtime_cpu=$(echo $bench | cut -d',' -f1)
            
            if [[ "$runc_cpu" != "N/A" && "$runtime_cpu" != "N/A" ]]; then
                percentage=$(echo "scale=2; ($runtime_cpu / $runc_cpu) * 100" | bc 2>/dev/null || echo "N/A")
                echo "  $runtime CPU: ${percentage}% of runc performance" | tee -a $RESULTS_FILE
            fi
        fi
    done
fi

echo "" | tee -a $RESULTS_FILE
echo "Results saved to: $RESULTS_FILE"
echo ""
echo "To see live logs from a benchmark pod:"
echo "  kubectl logs -f -l app=benchmark,runtime=runc"
echo "  kubectl logs -f -l app=benchmark,runtime=gvisor"
echo "  kubectl logs -f -l app=benchmark,runtime=kata"
