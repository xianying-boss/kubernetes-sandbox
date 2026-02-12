# Nomad Sandbox Runtime Setup & Benchmarking

Complete setup and benchmarking for HashiCorp Nomad with Docker, gVisor, and Kata Containers.

## 📦 What's Included

### Nomad Installation
- `install-nomad.sh` - Install HashiCorp Nomad (server/client)
- `install-nomad-gvisor.sh` - Install gVisor (runsc) for Nomad
- `install-nomad-kata.sh` - Install Kata Containers for Nomad

### Benchmarking Tools
- `nomad-benchmark.sh` - Complete performance benchmark (15-20 min)
- `nomad-quick-benchmark.sh` - Quick startup benchmark (3-5 min)
- `benchmark-jobs.nomad` - Nomad job specifications for continuous monitoring

### Documentation
- `NOMAD-BENCHMARK-GUIDE.md` - Complete benchmarking guide
- `NOMAD-README.md` - This file

---

## 🚀 Quick Start

### Option 1: All-in-One Setup

```bash
# 1. Install Nomad
chmod +x install-nomad.sh
sudo ./install-nomad.sh
# Choose: server, client, or both

# 2. Install gVisor (optional)
chmod +x install-nomad-gvisor.sh
sudo ./install-nomad-gvisor.sh

# 3. Install Kata (optional, requires KVM)
chmod +x install-nomad-kata.sh
sudo ./install-nomad-kata.sh

# 4. Run quick benchmark
chmod +x nomad-quick-benchmark.sh
./nomad-quick-benchmark.sh
```

### Option 2: Just Benchmark Existing Nomad

```bash
# If you already have Nomad with Docker/gVisor/Kata:
chmod +x nomad-quick-benchmark.sh
./nomad-quick-benchmark.sh
```

---

## ⚡ Quick Benchmark (Fastest)

```bash
chmod +x nomad-quick-benchmark.sh
./nomad-quick-benchmark.sh
```

**Output:**
```csv
Runtime,Startup(s)
docker,0.823
runsc,1.267
kata-runtime,2.145
```

---

## 📊 Complete Benchmark

```bash
chmod +x nomad-benchmark.sh
./nomad-benchmark.sh
```

**Output:**
```
Test        docker    runsc     kata-runtime
-------------------------------------------
startup     0.89s     1.23s     2.16s
cpu         1523      1089      1246
memory      2845      2457      2123
```

---

## 🎯 Using Runtimes in Nomad Jobs

### Default Docker (runc)

```hcl
job "myapp" {
  datacenters = ["dc1"]

  group "web" {
    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:alpine"
        # No runtime = default Docker (runc)
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
```

### gVisor (High Security)

```hcl
job "myapp-secure" {
  datacenters = ["dc1"]

  group "web" {
    task "nginx" {
      driver = "docker"

      config {
        image   = "nginx:alpine"
        runtime = "runsc"  # ← Use gVisor
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
```

### Kata Containers (Maximum Isolation)

```hcl
job "myapp-isolated" {
  datacenters = ["dc1"]

  group "web" {
    task "nginx" {
      driver = "docker"

      config {
        image   = "nginx:alpine"
        runtime = "kata-runtime"  # ← Use Kata
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

## 📋 Prerequisites

### System Requirements

| Component | Requirement |
|-----------|-------------|
| OS | Ubuntu 22.04, Debian 11+, RHEL 8+ |
| Nomad | 1.0+ |
| Docker | 20.10+ |
| CPU (for Kata) | Intel VT-x or AMD-V |
| Memory | 2GB+ (4GB+ recommended) |

### Software Requirements

```bash
# Required
- nomad
- docker
- python3
- bc
- jq

# For gVisor
- runsc

# For Kata (requires KVM)
- kata-runtime
- /dev/kvm device
```

---

## 🔧 Installation Details

### Step 1: Install Nomad

```bash
chmod +x install-nomad.sh
sudo ./install-nomad.sh
```

You'll be asked:
- **Node type**: server, client, or both
- **Install Consul**: Yes/No (recommended for service discovery)

**Verification:**
```bash
nomad version
nomad node status
nomad server members  # If server
```

### Step 2: Install gVisor (Optional)

```bash
chmod +x install-nomad-gvisor.sh
sudo ./install-nomad-gvisor.sh
```

This will:
1. Install runsc
2. Configure Docker with runsc runtime
3. Update Nomad configuration
4. Restart services

**Verification:**
```bash
docker info | grep runsc
docker run --rm --runtime=runsc alpine uname -a
```

### Step 3: Install Kata (Optional)

```bash
# First verify KVM support
egrep -c '(vmx|svm)' /proc/cpuinfo  # Should be > 0
ls -l /dev/kvm                       # Should exist

# Then install
chmod +x install-nomad-kata.sh
sudo ./install-nomad-kata.sh
```

**Verification:**
```bash
docker info | grep kata
docker run --rm --runtime=kata-runtime alpine dmesg | grep -i qemu
sudo /opt/kata/bin/kata-runtime kata-check
```

---

## 📊 Benchmarking Guide

### Quick Test (3-5 minutes)

```bash
./nomad-quick-benchmark.sh
```

Measures:
- Startup time (averaged over 3 runs)

### Complete Test (15-20 minutes)

```bash
./nomad-benchmark.sh
```

Measures:
- Startup time
- CPU performance (sysbench)
- Memory bandwidth
- Generates comparison table

### Continuous Monitoring

```bash
# Deploy benchmark jobs
nomad job run benchmark-jobs.nomad

# View running jobs
nomad job status | grep benchmark

# Stream logs
ALLOC_ID=$(nomad job allocs benchmark-continuous-runc -json | jq -r '.[0].ID')
nomad alloc logs -f $ALLOC_ID
```

---

## 🎓 Example Use Cases

### Use Case 1: Multi-Tenant Platform

```hcl
# Trusted internal services use default Docker
job "internal-api" {
  group "api" {
    task "server" {
      driver = "docker"
      config {
        image = "internal/api:latest"
        # No runtime = fast runc
      }
    }
  }
}

# Customer workloads use gVisor
job "customer-app" {
  group "app" {
    task "worker" {
      driver = "docker"
      config {
        image = "customer/app:latest"
        runtime = "runsc"  # Isolated
      }
    }
  }
}
```

### Use Case 2: PCI Compliance

```hcl
# Payment processing requires maximum isolation
job "payment-processor" {
  group "processor" {
    task "worker" {
      driver = "docker"
      config {
        image = "payments/processor:latest"
        runtime = "kata-runtime"  # VM-level isolation
      }
      resources {
        cpu    = 2000
        memory = 2048
      }
    }
  }
}
```

### Use Case 3: CI/CD Runners

```hcl
# CI jobs run untrusted code
job "ci-runner" {
  type = "batch"
  
  group "runner" {
    task "build" {
      driver = "docker"
      config {
        image = "buildkit:latest"
        runtime = "runsc"  # Sandbox user code
      }
      resources {
        cpu    = 4000
        memory = 4096
      }
    }
  }
}
```

---

## 🔍 Verification & Debugging

### Check Nomad Status

```bash
# Server status
nomad server members

# Client status
nomad node status

# Available drivers
nomad node status -self | grep -A 20 "Drivers"
```

### Verify Docker Runtimes

```bash
# List available runtimes
docker info | grep -A 5 "Runtimes:"

# Test each runtime
docker run --rm alpine echo "Docker default"
docker run --rm --runtime=runsc alpine echo "gVisor"
docker run --rm --runtime=kata-runtime alpine echo "Kata"
```

### Debug Job Failures

```bash
# Check job status
nomad job status <job-name>

# View allocation details
nomad alloc status <alloc-id>

# Read logs
nomad alloc logs <alloc-id>

# Check events
nomad alloc status <alloc-id> | grep -A 20 "Recent Events"
```

---

## 🐛 Common Issues

### Issue: "Runtime not found"

```bash
# Check Docker daemon configuration
cat /etc/docker/daemon.json

# Ensure runtimes are configured
sudo systemctl restart docker
sudo systemctl restart nomad
```

### Issue: Kata won't start

```bash
# Verify KVM
ls -l /dev/kvm
lsmod | grep kvm

# Check Kata
sudo /opt/kata/bin/kata-runtime kata-check
sudo /opt/kata/bin/kata-runtime kata-env
```

### Issue: Job stuck in pending

```bash
# Check allocation
nomad alloc status <alloc-id>

# Look for errors in events
nomad alloc status <alloc-id> | grep "Error"

# Check node capacity
nomad node status -self
```

---

## 📈 Performance Expectations

Based on typical benchmarks:

| Metric | Docker | gVisor | Kata |
|--------|--------|--------|------|
| Startup | 0.8-1.0s | 1.2-1.5s | 2.0-2.5s |
| CPU | 100% | 70-85% | 80-90% |
| Memory | 100% | 80-90% | 70-80% |
| Overhead | ~10MB | ~40MB | ~160MB |

**Run your own benchmarks** to get actual numbers for your workload!

---

## 🔐 Security Best Practices

1. **Default to least privilege**
   - Use gVisor for untrusted workloads
   - Use Kata when VM isolation is required
   - Use Docker only for trusted code

2. **Resource limits**
   - Always set CPU and memory limits
   - Account for runtime overhead
   - Monitor actual usage

3. **Network isolation**
   - Use Consul Connect for service mesh
   - Configure network policies
   - Isolate sensitive workloads

4. **Regular updates**
   - Keep Nomad updated
   - Update Docker regularly
   - Update gVisor/Kata runtimes

---

## 📁 Files Reference

```
.
├── NOMAD-README.md                # This file
├── NOMAD-BENCHMARK-GUIDE.md       # Detailed benchmarking guide
│
├── Installation/
│   ├── install-nomad.sh           # Install Nomad
│   ├── install-nomad-gvisor.sh    # Install gVisor
│   └── install-nomad-kata.sh      # Install Kata
│
├── Benchmarking/
│   ├── nomad-benchmark.sh         # Complete benchmark
│   ├── nomad-quick-benchmark.sh   # Quick benchmark
│   └── benchmark-jobs.nomad       # Job specifications
```

---

## 🆚 Nomad vs Kubernetes

| Feature | Nomad | Kubernetes |
|---------|-------|------------|
| Simplicity | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Learning Curve | Low | High |
| Setup Time | 10 min | 30+ min |
| Configuration | HCL (easy) | YAML (verbose) |
| Runtime Config | Task driver | RuntimeClass |
| Overhead | Low | Higher |

**When to use Nomad:**
- Smaller teams
- Simpler workloads
- Multi-datacenter
- Lower complexity needs

**When to use Kubernetes:**
- Large scale
- Complex orchestration
- Rich ecosystem needed
- Industry standard required

---

## 🤝 Next Steps

After installation and benchmarking:

1. **Deploy production workloads**
   ```bash
   nomad job run myapp.nomad
   ```

2. **Set up monitoring**
   - Use Prometheus for metrics
   - Configure alerting
   - Track performance trends

3. **Optimize based on results**
   - Adjust resource allocations
   - Choose appropriate runtimes
   - Plan capacity

4. **Implement CI/CD**
   - Automate deployments
   - Run benchmarks in CI
   - Track performance regressions

---

## 🎓 Learning Resources

- [Nomad Documentation](https://www.nomadproject.io/docs)
- [Nomad Docker Driver](https://www.nomadproject.io/docs/drivers/docker)
- [gVisor in Production](https://gvisor.dev/docs/)
- [Kata Containers Guide](https://github.com/kata-containers/kata-containers/tree/main/docs)

---

**Happy Orchestrating! 🚀**

Use Nomad's simplicity with the security of sandbox runtimes!
