#!/bin/bash
# Quick Nomad Benchmark - Fast performance comparison
# Tests startup time only for quick results

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ITERATIONS=3

echo "╔════════════════════════════════════════════════════╗"
echo "║   Quick Nomad Runtime Benchmark                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check if nomad is available
if ! command -v nomad &> /dev/null; then
    echo "❌ nomad command not found"
    exit 1
fi

# Function to measure startup time
quick_startup_test() {
    local runtime=$1
    local total_time=0
    
    echo -e "${YELLOW}Testing ${runtime:-docker} startup time (${ITERATIONS} iterations)...${NC}"
    
    for i in $(seq 1 $ITERATIONS); do
        local job_name="quick-test-$i"
        local job_file="/tmp/${job_name}.nomad"
        
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
        args = ["-c", "echo ready && sleep 5"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF
        
        local start=$(date +%s.%N)
        nomad job run $job_file > /dev/null 2>&1
        
        # Wait for running
        while true; do
            local status=$(nomad job status $job_name 2>/dev/null | grep "running" | wc -l)
            if [ "$status" -gt 0 ]; then
                break
            fi
            sleep 0.2
        done
        
        local end=$(date +%s.%N)
        local duration=$(echo "$end - $start" | bc)
        total_time=$(echo "$total_time + $duration" | bc)
        
        nomad job stop -purge $job_name > /dev/null 2>&1
        sleep 1
    done
    
    local avg_time=$(echo "scale=3; $total_time / $ITERATIONS" | bc)
    echo -e "${GREEN}✅ Average startup: ${avg_time}s${NC}"
    echo "${runtime:-docker},$avg_time"
}

# Detect available runtimes
RUNTIMES=("")
if docker info 2>/dev/null | grep -q "runsc"; then
    RUNTIMES+=("runsc")
fi
if docker info 2>/dev/null | grep -q "kata-runtime"; then
    RUNTIMES+=("kata-runtime")
fi

echo "Testing runtimes: ${RUNTIMES[@]}"
echo ""

# Results
RESULTS_FILE="/tmp/nomad-quick-benchmark-$(date +%s).csv"
echo "Runtime,Startup(s)" > $RESULTS_FILE

for runtime in "${RUNTIMES[@]}"; do
    runtime_name=${runtime:-docker}
    echo ""
    echo -e "${BLUE}━━━ Testing: ${runtime_name} ━━━${NC}"
    
    startup_result=$(quick_startup_test "$runtime")
    startup_time=$(echo $startup_result | cut -d',' -f2)
    
    echo "${runtime_name},${startup_time}" >> $RESULTS_FILE
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results:"
cat $RESULTS_FILE
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Saved to: $RESULTS_FILE"
