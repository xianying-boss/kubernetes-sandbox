# Nomad Sandbox Runtime Benchmarking Guide

Measure actual performance of Docker (runc), gVisor, and Kata Containers in HashiCorp Nomad.

## 📦 What's Different from Kubernetes

Nomad uses **task drivers** instead of RuntimeClasses:
- **Docker driver** - Default, uses runc
- **Docker driver with runtime parameter** - Can use gVisor (runsc) or Kata
- Simpler configuration
- Different monitoring approach

---

## 🚀 Quick Start

### Step 1: Install Nomad and Runtimes

```bash
# Install Nomad
chmod +x install-nomad.sh
sudo ./install-nomad.sh

# Install gVisor (optional)
chmod +x install-nomad-gvisor.sh
sudo ./install-nomad-gvisor.sh

# Install Kata (optional, requires KVM)
chmod +x install-nomad-kata.sh
sudo ./install-nomad-kata.sh
```

### Step 2: Run Quick Benchmark

```bash
chmod +x nomad-quick-benchmark.sh
./nomad-quick-benchmark.sh
```

**Sample Output:**
```csv
Runtime,Startup(s)
docker,0.823
runsc,1.267
kata-runtime,2.145
```

### Step 3: Run Complete Benchmark

```bash
chmod +x nomad-benchmark.sh
./nomad-benchmark.sh
```

**Sample Output:**
```
Test           docker              runsc               kata-runtime        
------------------------------------------------------------------------
startup        0.892s              1.234s              2.156s              
cpu            1523.45             1089.23             1245.67             
memory         2845.32             2456.78             2123.45             
```

---

## 📊 Available Benchmark Tools

### 1. **Quick Benchmark** (`nomad-quick-benchmark.sh`)
- **Duration**: 3-5 minutes
- **Tests**: Startup time only
- **Best for**: Fast comparison
- **Output**: CSV with startup times

### 2. **Complete Benchmark** (`nomad-benchmark.sh`)
- **Duration**: 15-20 minutes
- **Tests**: Startup, CPU, Memory performance
- **Best for**: Comprehensive analysis
- **Output**: Detailed report with comparison table

### 3. **Continuous Monitoring** (`benchmark-jobs.nomad`)
- **Duration**: Continuous
- **Tests**: Long-running performance tests
- **Best for**: Production monitoring
- **Output**: Job logs via `nomad alloc logs`

---

## 🔧 Using Sandbox Runtimes in Nomad

### Default Docker (runc)

```hcl
job "myapp" {
  group "app" {
    task "web" {
      driver = "docker"
      
      config {
        image = "nginx:alpine"
        # No runtime specified = default runc
      }
    }
  }
}
```

### gVisor (runsc)

```hcl
job "myapp-gvisor" {
  group "app" {
    task "web" {
      driver = "docker"
      
      config {
        image   = "nginx:alpine"
        runtime = "runsc"  # Use gVisor
      }
    }
  }
}
```

### Kata Containers

```hcl
job "myapp-kata" {
  group "app" {
    task "web" {
      driver = "docker"
      
      config {
        image   = "nginx:alpine"
        runtime = "kata-runtime"  # Use Kata
      }
    }
  }
}
```

---

## 📋 Prerequisites

1. **Nomad cluster** (1.0+)
2. **Docker** installed and running
3. **Nomad CLI** configured
4. **Python3** and **bc** for report generation

Verify prerequisites:
```bash
nomad version
docker --version
docker info | grep Runtimes
python3 --version
bc --version
```

---

## 🎯 Running Benchmark Jobs

### Deploy Batch Benchmark Jobs

```bash
# Extract individual jobs from benchmark-jobs.nomad
# Run CPU benchmark for each runtime

# Default Docker
nomad job run -
job "benchmark-runc" {
  # ... (see benchmark-jobs.nomad)
}
^D

# Check status
nomad job status benchmark-runc

# View logs
nomad alloc logs $(nomad job allocs benchmark-runc -json | jq -r '.[0].ID')
```

### Deploy Continuous Benchmarks

```bash
# Deploy long-running benchmark jobs
nomad job run benchmark-jobs.nomad

# View all running benchmarks
nomad job status | grep benchmark

# Stream logs
nomad alloc logs -f <alloc-id>
```

---

## 📊 Analyzing Results

### View Job Logs

```bash
# List allocations for a job
nomad job allocs benchmark-runc

# Get logs from allocation
ALLOC_ID=$(nomad job allocs benchmark-runc -json | jq -r '.[0].ID')
nomad alloc logs $ALLOC_ID
```

### Extract Metrics

```bash
# CPU benchmark result
nomad alloc logs $ALLOC_ID | grep "events per second"

# Memory benchmark result  
nomad alloc logs $ALLOC_ID | grep "transferred"
```

### Compare Across Runtimes

Use the benchmark scripts which automatically:
1. Run jobs for each runtime
2. Extract results from logs
3. Generate comparison tables
4. Save to CSV files

---

## 🔍 Verification

### Check Installed Runtimes

```bash
# List Docker runtimes
docker info | grep -A 10 "Runtimes:"

# Should show:
#   Runtimes: io.containerd.runc.v2 runc runsc kata-runtime
```

### Test Runtime Manually

```bash
# Test gVisor
docker run --rm --runtime=runsc alpine uname -a
# Should show old kernel version

# Test Kata
docker run --rm --runtime=kata-runtime alpine dmesg | grep -i qemu
# Should show QEMU/virtualization messages
```

### Verify in Nomad

```bash
# Check node drivers
nomad node status -self

# Should show Docker driver with multiple runtimes
```

---

## 🎓 Example Workflows

### Workflow 1: Initial Assessment

```bash
# 1. Quick test
./nomad-quick-benchmark.sh

# 2. Full benchmark if needed
./nomad-benchmark.sh

# 3. Deploy production workload with chosen runtime
nomad job run myapp.nomad
```

### Workflow 2: A/B Testing

```bash
# Deploy same app with different runtimes
nomad job run app-docker.nomad
nomad job run app-gvisor.nomad
nomad job run app-kata.nomad

# Compare metrics
nomad alloc status <alloc-id>
```

### Workflow 3: Continuous Monitoring

```bash
# Deploy continuous benchmarks
nomad job run benchmark-jobs.nomad

# Set up monitoring
watch -n 60 "nomad job status | grep benchmark"

# Collect results periodically
crontab -e
# Add: 0 * * * * nomad alloc logs $(nomad job allocs benchmark-continuous-runc -json | jq -r '.[0].ID') >> /var/log/nomad-bench.log
```

---

## 🐛 Troubleshooting

### Issue: Runtime not found

```bash
# Check Docker configuration
cat /etc/docker/daemon.json

# Should include:
# {
#   "runtimes": {
#     "runsc": { "path": "/usr/bin/runsc" },
#     "kata-runtime": { "path": "/opt/kata/bin/kata-runtime" }
#   }
# }

# Restart Docker
sudo systemctl restart docker
```

### Issue: Job fails to start

```bash
# Check allocation status
nomad alloc status <alloc-id>

# View events
nomad alloc status <alloc-id> | grep -A 20 "Recent Events"

# Check logs
nomad alloc logs <alloc-id>
```

### Issue: No benchmark results

```bash
# Ensure job completed
nomad job status benchmark-runc

# Check if allocation succeeded
nomad job allocs benchmark-runc

# View full logs
nomad alloc logs <alloc-id>
```

---

## 📈 Performance Tuning

### For gVisor in Nomad

```hcl
config {
  runtime = "runsc"
  
  # Increase resources for overhead
  resources {
    cpu    = 500  # vs 300 for runc
    memory = 256  # vs 128 for runc
  }
}
```

### For Kata in Nomad

```hcl
config {
  runtime = "kata-runtime"
  
  # Kata needs more resources
  resources {
    cpu    = 1000
    memory = 512
  }
}
```

### Nomad Client Configuration

```hcl
# /etc/nomad.d/docker.hcl
plugin "docker" {
  config {
    # Allow multiple runtimes
    allow_runtimes = ["runc", "runsc", "kata-runtime"]
    
    # Performance tuning
    gc {
      image       = true
      image_delay = "3m"
      container   = true
    }
    
    volumes {
      enabled = true
    }
  }
}
```

---

## 📊 Benchmark Job Templates

### Minimal Test Job

```hcl
job "test-runtime" {
  datacenters = ["dc1"]
  type        = "batch"

  group "test" {
    task "hello" {
      driver = "docker"

      config {
        image   = "alpine:latest"
        runtime = "runsc"  # Change to test different runtimes
        command = "echo"
        args    = ["Hello from gVisor!"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
```

### CPU-Intensive Benchmark

```hcl
job "cpu-benchmark" {
  datacenters = ["dc1"]
  type        = "batch"

  group "bench" {
    task "cpu" {
      driver = "docker"

      config {
        image   = "ubuntu:22.04"
        runtime = "runsc"
        
        command = "/bin/bash"
        args = ["-c", "apt-get update && apt-get install -y sysbench && sysbench cpu --cpu-max-prime=20000 run"]
      }

      resources {
        cpu    = 1000
        memory = 512
      }
    }
  }
}
```

---

## 🔐 Security Considerations

### When to Use Each Runtime in Nomad

| Use Case | Recommended | Reason |
|----------|-------------|---------|
| Multi-tenant workloads | gVisor | Good isolation, lower overhead than Kata |
| Running user code | gVisor | Syscall filtering, untrusted code |
| Maximum isolation | Kata | Full VM isolation |
| General workloads | Docker | Best performance, standard |
| Mixed environment | All three | Use different runtimes per job |

### Runtime Selection in Job Spec

```hcl
job "mixed-workloads" {
  group "trusted" {
    task "app" {
      driver = "docker"
      config {
        image = "myapp:latest"
        # No runtime = default runc (best performance)
      }
    }
  }
  
  group "untrusted" {
    task "user-code" {
      driver = "docker"
      config {
        image = "user-provided:latest"
        runtime = "runsc"  # Isolate untrusted code
      }
    }
  }
  
  group "highly-sensitive" {
    task "pci-compliance" {
      driver = "docker"
      config {
        image = "payment-processor:latest"
        runtime = "kata-runtime"  # Maximum isolation
      }
    }
  }
}
```

---

## 📁 Files Reference

```
.
├── install-nomad.sh              # Install Nomad
├── install-nomad-gvisor.sh       # Install gVisor for Nomad
├── install-nomad-kata.sh         # Install Kata for Nomad
├── nomad-benchmark.sh            # Complete benchmark
├── nomad-quick-benchmark.sh      # Quick benchmark
├── benchmark-jobs.nomad          # Benchmark job specifications
└── NOMAD-BENCHMARK-GUIDE.md      # This file
```

---

## 🆚 Nomad vs Kubernetes Benchmarking

| Aspect | Nomad | Kubernetes |
|--------|-------|------------|
| Configuration | Task driver config | RuntimeClass |
| Deployment | Job spec | Pod spec |
| Monitoring | `nomad alloc logs` | `kubectl logs` |
| Simplicity | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Flexibility | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 🎓 Additional Resources

- [Nomad Docker Driver](https://www.nomadproject.io/docs/drivers/docker)
- [Nomad Task Drivers](https://www.nomadproject.io/docs/drivers)
- [gVisor Documentation](https://gvisor.dev/docs/)
- [Kata Containers](https://katacontainers.io/)

---

**Happy Benchmarking! 📊**

Get real performance data from your Nomad cluster to make informed runtime decisions!
