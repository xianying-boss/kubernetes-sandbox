#!/bin/bash
# Nomad Sandbox Runtime Performance Benchmark
# Comprehensive performance testing for Docker, gVisor, and Kata

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RESULTS_DIR="/tmp/nomad-benchmark-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$RESULTS_DIR/benchmark-report-${TIMESTAMP}.txt"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Nomad Sandbox Runtime Performance Benchmark             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if nomad is available
if ! command -v nomad &> /dev/null; then
    echo -e "${RED}❌ nomad command not found${NC}"
    exit 1
fi

# Create results directory
mkdir -p $RESULTS_DIR

# Function to log results
log_result() {
    echo "$1" | tee -a $REPORT_FILE
}

# Function to wait for job completion
wait_for_job() {
    local job_name=$1
    local timeout=$2
    
    echo "Waiting for job $job_name to complete..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local status=$(nomad job status $job_name 2>/dev/null | grep "Status" | head -1 | awk '{print $3}' || echo "unknown")
        
        if [ "$status" = "dead" ]; then
            # Job completed, check if successful
            local failed=$(nomad job status $job_name 2>/dev/null | grep "Failed" | awk '{print $3}')
            if [ "$failed" = "0" ]; then
                return 0
            else
                return 1
            fi
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo -e "${RED}Timeout waiting for job${NC}"
    return 1
}

# Function to get job allocation logs
get_job_logs() {
    local job_name=$1
    
    local alloc_id=$(nomad job status $job_name 2>/dev/null | grep "running\|complete" | head -1 | awk '{print $1}')
    
    if [ -z "$alloc_id" ]; then
        # Try to get any allocation
        alloc_id=$(nomad job allocs $job_name 2>/dev/null | grep -v "ID" | head -1 | awk '{print $1}')
    fi
    
    if [ -n "$alloc_id" ]; then
        nomad alloc logs $alloc_id 2>/dev/null || echo "No logs available"
    else
        echo "No allocation found"
    fi
}

# Function to benchmark startup time
benchmark_startup() {
    local runtime=$1
    local job_file="/tmp/startup-${runtime}.nomad"
    local job_name="startup-${runtime}"
    
    echo -e "${YELLOW}Testing startup time for: ${runtime}${NC}"
    
    # Create simple job
    cat > $job_file <<EOF
job "${job_name}" {
  datacenters = ["dc1"]
  type        = "batch"

  group "test" {
    count = 1

    task "startup" {
      driver = "docker"

      config {
        image = "alpine:latest"
        ${runtime:+runtime = \"$runtime\"}
        command = "sh"
        args = ["-c", "echo 'Started' && sleep 5"]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
EOF
    
    # Measure time
    local start_time=$(date +%s.%N)
    
    nomad job run $job_file > /dev/null 2>&1
    
    # Wait for allocation to be running
    local elapsed=0
    while [ $elapsed -lt 60 ]; do
        local status=$(nomad job status $job_name 2>/dev/null | grep "running" | wc -l)
        if [ "$status" -gt 0 ]; then
            break
        fi
        sleep 0.5
        elapsed=$(echo "$elapsed + 0.5" | bc)
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo -e "${GREEN}✅ ${runtime:-docker}: ${duration}s${NC}"
    log_result "${runtime:-docker},startup,${duration}"
    
    # Cleanup
    nomad job stop -purge $job_name > /dev/null 2>&1 || true
    sleep 2
}

# Function to benchmark CPU performance
benchmark_cpu() {
    local runtime=$1
    local job_file="/tmp/cpu-${runtime}.nomad"
    local job_name="cpu-${runtime}"
    
    echo -e "${YELLOW}Testing CPU performance for: ${runtime}${NC}"
    
    cat > $job_file <<EOF
job "${job_name}" {
  datacenters = ["dc1"]
  type        = "batch"

  group "test" {
    count = 1

    task "cpu" {
      driver = "docker"

      config {
        image = "ubuntu:22.04"
        ${runtime:+runtime = \"$runtime\"}
        command = "/bin/bash"
        args = [
          "-c",
          "apt-get update > /dev/null 2>&1 && apt-get install -y sysbench > /dev/null 2>&1 && sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>&1 | grep 'events per second' | awk '{print \$4}'"
        ]
      }

      resources {
        cpu    = 1000
        memory = 512
      }
    }
  }
}
EOF
    
    nomad job run $job_file > /dev/null 2>&1
    
    if wait_for_job $job_name 300; then
        local logs=$(get_job_logs $job_name)
        local result=$(echo "$logs" | grep -oE '[0-9]+\.[0-9]+' | tail -1)
        
        if [ -n "$result" ]; then
            echo -e "${GREEN}✅ ${runtime:-docker}: ${result} events/sec${NC}"
            log_result "${runtime:-docker},cpu,${result}"
        else
            echo -e "${RED}❌ ${runtime:-docker}: No result${NC}"
            log_result "${runtime:-docker},cpu,failed"
        fi
    else
        echo -e "${RED}❌ ${runtime:-docker}: Job failed${NC}"
        log_result "${runtime:-docker},cpu,failed"
    fi
    
    nomad job stop -purge $job_name > /dev/null 2>&1 || true
    sleep 2
}

# Function to benchmark memory performance
benchmark_memory() {
    local runtime=$1
    local job_file="/tmp/memory-${runtime}.nomad"
    local job_name="memory-${runtime}"
    
    echo -e "${YELLOW}Testing memory performance for: ${runtime}${NC}"
    
    cat > $job_file <<EOF
job "${job_name}" {
  datacenters = ["dc1"]
  type        = "batch"

  group "test" {
    count = 1

    task "memory" {
      driver = "docker"

      config {
        image = "ubuntu:22.04"
        ${runtime:+runtime = \"$runtime\"}
        command = "/bin/bash"
        args = [
          "-c",
          "apt-get update > /dev/null 2>&1 && apt-get install -y sysbench > /dev/null 2>&1 && sysbench memory --memory-block-size=1M --memory-total-size=5G run 2>&1 | grep 'transferred' | awk '{print \$4}' | tr -d '()'"
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}
EOF
    
    nomad job run $job_file > /dev/null 2>&1
    
    if wait_for_job $job_name 300; then
        local logs=$(get_job_logs $job_name)
        local result=$(echo "$logs" | grep -oE '[0-9]+\.[0-9]+' | tail -1)
        
        if [ -n "$result" ]; then
            echo -e "${GREEN}✅ ${runtime:-docker}: ${result} MiB/sec${NC}"
            log_result "${runtime:-docker},memory,${result}"
        else
            echo -e "${RED}❌ ${runtime:-docker}: No result${NC}"
            log_result "${runtime:-docker},memory,failed"
        fi
    else
        echo -e "${RED}❌ ${runtime:-docker}: Job failed${NC}"
        log_result "${runtime:-docker},memory,failed"
    fi
    
    nomad job stop -purge $job_name > /dev/null 2>&1 || true
    sleep 2
}

# Initialize report
log_result "Nomad Sandbox Runtime Performance Benchmark"
log_result "============================================"
log_result "Date: $(date)"
log_result "Nomad Address: $(nomad agent-info 2>/dev/null | grep 'server_name' | head -1 || echo 'N/A')"
log_result ""
log_result "Runtime,Test,Result"
log_result "-------------------"

# Determine available runtimes
RUNTIMES=("")  # Default Docker

# Check if gVisor is available
if docker info 2>/dev/null | grep -q "runsc"; then
    RUNTIMES+=("runsc")
fi

# Check if Kata is available
if docker info 2>/dev/null | grep -q "kata-runtime"; then
    RUNTIMES+=("kata-runtime")
fi

echo "Detected runtimes: ${RUNTIMES[@]}"
echo ""

# Run benchmarks
echo ""
echo "=== Starting Benchmarks ==="
echo ""

for runtime in "${RUNTIMES[@]}"; do
    runtime_label=${runtime:-docker}
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing Runtime: ${runtime_label}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    benchmark_startup "$runtime"
    sleep 3
    
    benchmark_cpu "$runtime"
    sleep 3
    
    benchmark_memory "$runtime"
    sleep 3
done

echo ""
echo "=== Benchmark Complete ==="
echo ""
echo "Results saved to: $REPORT_FILE"
echo ""
echo "Summary:"
cat $REPORT_FILE
echo ""

# Generate comparison
echo ""
echo "Generating comparison table..."

python3 - <<PYTHON_SCRIPT
results = {}
with open('$REPORT_FILE', 'r') as f:
    for line in f:
        if ',' in line and not line.startswith('Runtime'):
            parts = line.strip().split(',')
            if len(parts) >= 3:
                runtime = parts[0]
                test = parts[1]
                result = parts[2]
                
                if runtime not in results:
                    results[runtime] = {}
                results[runtime][test] = result

print("\n╔════════════════════════════════════════════════════════╗")
print("║         Performance Comparison Table                  ║")
print("╚════════════════════════════════════════════════════════╝\n")

runtimes = list(results.keys())
tests = ['startup', 'cpu', 'memory']

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
echo "Results saved to: $REPORT_FILE"
