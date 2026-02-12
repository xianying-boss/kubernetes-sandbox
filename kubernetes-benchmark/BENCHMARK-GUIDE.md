# Kubernetes Sandbox Runtime Performance Benchmarking Guide

Measure actual performance overhead of gVisor and Kata Containers in your cluster.

## 📊 Available Benchmark Tools

### 1. **Complete Benchmark** (`benchmark-sandbox.sh`)
- **Duration**: ~20-30 minutes
- **Tests**: Startup time, CPU, Memory, Disk I/O, Resource overhead
- **Best for**: Comprehensive performance analysis
- **Output**: Detailed CSV report with comparison table

### 2. **Quick Benchmark** (`quick-benchmark.sh`)
- **Duration**: ~3-5 minutes
- **Tests**: Startup time, Memory overhead (averaged over 3 runs)
- **Best for**: Fast comparison, CI/CD pipelines
- **Output**: Simple CSV with key metrics

### 3. **Continuous Monitoring** (`benchmark-deployments.yaml`)
- **Duration**: Continuous
- **Tests**: CPU and memory benchmarks every minute
- **Best for**: Long-term performance tracking, production monitoring
- **Output**: Pod logs + metrics (view with `analyze-benchmarks.sh`)

---

## 🚀 Quick Start

### Option 1: Run Complete Benchmark (Recommended)

```bash
# Make executable
chmod +x benchmark-sandbox.sh

# Run benchmark
./benchmark-sandbox.sh
```

This will:
1. Detect available runtimes (runc, gVisor, Kata)
2. Run comprehensive tests for each
3. Generate comparison report
4. Save results to `/tmp/k8s-benchmark-results/`

**Sample Output:**
```
╔════════════════════════════════════════════════════════════════╗
║           Performance Comparison Table                        ║
╚════════════════════════════════════════════════════════════════╝

Test           runc                gvisor              kata                
-------------------------------------------------------------------------------
startup        0.892s              1.234s              2.156s              
cpu            1523.45             1089.23             1245.67             
memory         2845.32             2456.78             2123.45             
disk           12543               8765                9234                
overhead       CPU=2m Memory=15Mi  CPU=5m Memory=48Mi  CPU=12m Memory=168Mi
```

### Option 2: Quick Benchmark

```bash
chmod +x quick-benchmark.sh
./quick-benchmark.sh
```

**Sample Output:**
```
Runtime,Startup(s),Memory
runc,0.845,14Mi
gvisor,1.289,45Mi
kata,2.134,162Mi
```

### Option 3: Deploy Continuous Benchmarks

```bash
# Deploy benchmark pods
kubectl apply -f benchmark-deployments.yaml

# Wait for pods to start
kubectl get pods -l app=benchmark

# Analyze results (after a few minutes)
chmod +x analyze-benchmarks.sh
./analyze-benchmarks.sh
```

---

## 📋 Prerequisites

1. **Kubernetes cluster** with kubectl access
2. **RuntimeClasses** configured (gVisor and/or Kata)
3. **Metrics Server** installed (auto-installed by benchmark script)
4. **Python3** (for complete benchmark report generation)
5. **bc** calculator (usually pre-installed)

Install missing dependencies:
```bash
# Ubuntu/Debian
sudo apt-get install -y python3 bc

# RHEL/CentOS
sudo yum install -y python3 bc
```

---

## 🔬 Understanding the Tests

### Startup Time
- **What it measures**: Time from pod creation to Ready state
- **Why it matters**: Indicates scheduling overhead and initialization time
- **Expected overhead**: 
  - gVisor: +100-400ms
  - Kata: +1-2s (VM boot time)

### CPU Performance
- **Tool**: sysbench CPU test (prime number calculation)
- **Metric**: Events per second (higher is better)
- **Why it matters**: Shows computational overhead
- **Expected overhead**:
  - gVisor: 10-30% slower
  - Kata: 5-20% slower

### Memory Performance
- **Tool**: sysbench memory test
- **Metric**: MiB/sec transferred (higher is better)
- **Why it matters**: Memory-intensive workload performance
- **Expected overhead**:
  - gVisor: 10-20% slower
  - Kata: 15-25% slower

### Disk I/O
- **Tool**: fio random write test
- **Metric**: IOPS (higher is better)
- **Why it matters**: Database and storage workload performance
- **Expected overhead**:
  - gVisor: 20-40% slower
  - Kata: 30-50% slower

### Resource Overhead
- **What it measures**: Actual CPU/Memory usage for idle container
- **Why it matters**: Cost of running the sandbox
- **Expected overhead**:
  - gVisor: +30-50Mi memory, +2-5m CPU
  - Kata: +150-200Mi memory, +10-15m CPU

---

## 📊 Interpreting Results

### Reading the Reports

**Startup Time:**
```
runc:   0.8s   ← Baseline
gvisor: 1.2s   ← 50% slower (acceptable for most workloads)
kata:   2.1s   ← 2.6x slower (acceptable for long-running pods)
```

**CPU Benchmark:**
```
runc:   1523 events/sec  ← 100% baseline
gvisor: 1089 events/sec  ← 71% of baseline (29% overhead)
kata:   1246 events/sec  ← 82% of baseline (18% overhead)
```

**Memory Overhead:**
```
runc:   15Mi   ← Minimal overhead
gvisor: 48Mi   ← +33Mi for sandbox
kata:   168Mi  ← +153Mi for VM
```

### When Results Matter

**High CPU overhead is acceptable when:**
- Security is critical
- Workload is I/O bound
- Running untrusted code

**High memory overhead is acceptable when:**
- Running few pods per node
- Strong isolation is required
- Cost of breach > cost of RAM

**High startup time is acceptable when:**
- Pods are long-lived
- Auto-scaling is not time-critical
- Security benefits outweigh latency

---

## 🎯 Benchmark Scenarios

### Scenario 1: Web Application
```bash
# Deploy a realistic web app benchmark
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-benchmark
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      runtimeClassName: gvisor  # Change to test different runtimes
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF

# Monitor performance
kubectl top pods -l app=webapp
```

### Scenario 2: Database Workload
```bash
# Test disk I/O intensive workload
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: db-benchmark
spec:
  runtimeClassName: kata  # Test with different runtimes
  containers:
  - name: postgres
    image: postgres:15-alpine
    env:
    - name: POSTGRES_PASSWORD
      value: benchmark
    resources:
      requests:
        cpu: "1000m"
        memory: "1Gi"
EOF

# Measure startup and resource usage
time kubectl wait --for=condition=Ready pod/db-benchmark --timeout=300s
kubectl top pod db-benchmark
```

### Scenario 3: Batch Processing
```bash
# Test CPU-intensive batch job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: cpu-job
spec:
  template:
    spec:
      runtimeClassName: gvisor
      containers:
      - name: worker
        image: ubuntu:22.04
        command: ["bash", "-c"]
        args:
        - |
          apt-get update && apt-get install -y stress-ng
          stress-ng --cpu 2 --timeout 60s --metrics-brief
      restartPolicy: Never
EOF

# Compare completion time across runtimes
```

---

## 🔍 Advanced Analysis

### Export Results for Visualization

```bash
# Run benchmark and save results
./benchmark-sandbox.sh

# Results are in CSV format, import to:
# - Excel/Google Sheets
# - Grafana
# - Prometheus
# - Custom dashboards
```

### Compare Across Cluster Configurations

```bash
# Test on different node types
kubectl label nodes node1 disktype=ssd
kubectl label nodes node2 disktype=hdd

# Deploy benchmarks with node selectors
# Compare results between SSD and HDD nodes
```

### Continuous Performance Monitoring

```bash
# Deploy long-running benchmarks
kubectl apply -f benchmark-deployments.yaml

# Set up cron job to collect results
crontab -e
# Add: */30 * * * * /path/to/analyze-benchmarks.sh >> /var/log/k8s-bench.log
```

---

## 🐛 Troubleshooting

### Issue: Benchmark pods won't start

```bash
# Check runtime is available
kubectl get runtimeclass

# Check node has runtime installed
kubectl describe node <node-name>

# View pod events
kubectl describe pod <benchmark-pod>
```

### Issue: Metrics Server not working

```bash
# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify installation
kubectl get deployment metrics-server -n kube-system

# Wait for it to be ready
kubectl wait --for=condition=Available deployment/metrics-server -n kube-system --timeout=300s
```

### Issue: Results show "N/A"

```bash
# Check pod logs
kubectl logs <benchmark-pod>

# Ensure benchmark completed
kubectl logs <benchmark-pod> | grep "RESULT"

# Try running benchmark again
```

---

## 📈 Performance Tuning Tips

### For gVisor

1. **Use systrap platform** (default, fastest)
2. **Disable debug mode** in production
3. **Allocate sufficient CPU** for syscall overhead
4. **Use for I/O-light workloads**

### For Kata

1. **Increase VM memory** if needed:
   ```bash
   # Edit /etc/kata-containers/configuration.toml
   default_memory = 4096  # Increase from 2048
   ```

2. **Enable DAX** for better memory performance
3. **Use virtio-fs** for better file I/O
4. **Allocate dedicated cores** for critical VMs

### General Tips

1. **Baseline first**: Always benchmark runc to establish baseline
2. **Multiple runs**: Run tests 3-5 times for accurate averages
3. **Resource limits**: Set appropriate requests/limits based on results
4. **Monitor production**: Use continuous benchmarks to track degradation
5. **Test your workload**: Generic benchmarks may not reflect your app

---

## 📁 Files Reference

```
.
├── benchmark-sandbox.sh          # Complete benchmark (20-30min)
├── quick-benchmark.sh            # Fast benchmark (3-5min)
├── benchmark-deployments.yaml    # Continuous monitoring pods
├── analyze-benchmarks.sh         # Analyze continuous benchmark results
└── BENCHMARK-GUIDE.md           # This file
```

---

## 🎓 Example Workflow

```bash
# 1. Initial assessment
./quick-benchmark.sh

# 2. Detailed analysis
./benchmark-sandbox.sh

# 3. Deploy continuous monitoring
kubectl apply -f benchmark-deployments.yaml

# 4. Check results after 1 hour
./analyze-benchmarks.sh

# 5. Make decisions based on data
# - Adjust resource allocations
# - Choose appropriate runtime for each workload
# - Plan node capacity
```

---

## 📊 Sample Decision Matrix

| Workload Type | Recommended Runtime | Reason |
|---------------|-------------------|---------|
| Public API | gVisor | Balance of security and performance |
| User code execution | gVisor | Strong isolation, acceptable overhead |
| Batch processing | runc or Kata | CPU-intensive, choose based on security needs |
| Database | runc or Kata | I/O intensive, use Kata if isolation required |
| Microservices | gVisor | Many small containers, lower memory overhead |
| ML inference | runc or Kata | GPU/CPU intensive |
| CI/CD runners | gVisor | Untrusted code, frequent restarts |

---

## 🤝 Contributing

Improve these benchmarks:
- Add new test scenarios
- Optimize test duration
- Add support for other runtimes
- Create visualization tools

---

**Happy Benchmarking! 📊**

Use real data to make informed decisions about sandbox runtime adoption!
