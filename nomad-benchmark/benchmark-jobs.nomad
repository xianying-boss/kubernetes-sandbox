# Nomad Benchmark Jobs
# Deploy these to test different runtimes

# ==============================================
# Benchmark Job - Default Docker (runc)
# ==============================================
job "benchmark-runc" {
  datacenters = ["dc1"]
  type        = "batch"

  group "benchmark" {
    count = 1

    task "cpu-test" {
      driver = "docker"

      config {
        image = "ubuntu:22.04"
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y sysbench bc
echo "=== CPU Benchmark (runc) ==="
sysbench cpu --cpu-max-prime=20000 --threads=1 run
echo "=== Memory Benchmark (runc) ==="
sysbench memory --memory-block-size=1M --memory-total-size=5G run
sleep 10
EOF
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}

# ==============================================
# Benchmark Job - gVisor (runsc)
# ==============================================
job "benchmark-gvisor" {
  datacenters = ["dc1"]
  type        = "batch"

  group "benchmark" {
    count = 1

    task "cpu-test" {
      driver = "docker"

      config {
        image   = "ubuntu:22.04"
        runtime = "runsc"  # Use gVisor
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y sysbench bc
echo "=== CPU Benchmark (gVisor) ==="
sysbench cpu --cpu-max-prime=20000 --threads=1 run
echo "=== Memory Benchmark (gVisor) ==="
sysbench memory --memory-block-size=1M --memory-total-size=5G run
sleep 10
EOF
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}

# ==============================================
# Benchmark Job - Kata Containers
# ==============================================
job "benchmark-kata" {
  datacenters = ["dc1"]
  type        = "batch"

  group "benchmark" {
    count = 1

    task "cpu-test" {
      driver = "docker"

      config {
        image   = "ubuntu:22.04"
        runtime = "kata-runtime"  # Use Kata
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y sysbench bc
echo "=== CPU Benchmark (Kata) ==="
sysbench cpu --cpu-max-prime=20000 --threads=1 run
echo "=== Memory Benchmark (Kata) ==="
sysbench memory --memory-block-size=1M --memory-total-size=5G run
sleep 10
EOF
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}

# ==============================================
# Disk I/O Benchmark - Default
# ==============================================
job "benchmark-disk-runc" {
  datacenters = ["dc1"]
  type        = "batch"

  group "benchmark" {
    count = 1

    task "disk-test" {
      driver = "docker"

      config {
        image = "ubuntu:22.04"
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y fio
echo "=== Disk I/O Benchmark (runc) ==="
fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite \
    --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=30 --group_reporting
EOF
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}

# ==============================================
# Continuous Benchmark - Service Type
# ==============================================
job "benchmark-continuous-runc" {
  datacenters = ["dc1"]
  type        = "service"

  group "benchmark" {
    count = 1

    task "continuous-test" {
      driver = "docker"

      config {
        image = "ubuntu:22.04"
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y sysbench stress-ng
while true; do
  echo "=== $(date) ==="
  echo "CPU Test:"
  sysbench cpu --cpu-max-prime=20000 --threads=1 run
  echo "Memory Test:"
  sysbench memory --memory-block-size=1M --memory-total-size=1G run
  echo "Sleeping 60s..."
  sleep 60
done
EOF
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}

job "benchmark-continuous-gvisor" {
  datacenters = ["dc1"]
  type        = "service"

  group "benchmark" {
    count = 1

    task "continuous-test" {
      driver = "docker"

      config {
        image   = "ubuntu:22.04"
        runtime = "runsc"
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y sysbench stress-ng
while true; do
  echo "=== $(date) ==="
  echo "CPU Test:"
  sysbench cpu --cpu-max-prime=20000 --threads=1 run
  echo "Memory Test:"
  sysbench memory --memory-block-size=1M --memory-total-size=1G run
  echo "Sleeping 60s..."
  sleep 60
done
EOF
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}

job "benchmark-continuous-kata" {
  datacenters = ["dc1"]
  type        = "service"

  group "benchmark" {
    count = 1

    task "continuous-test" {
      driver = "docker"

      config {
        image   = "ubuntu:22.04"
        runtime = "kata-runtime"
        
        command = "/bin/bash"
        args = [
          "-c",
          <<EOF
apt-get update && apt-get install -y sysbench stress-ng
while true; do
  echo "=== $(date) ==="
  echo "CPU Test:"
  sysbench cpu --cpu-max-prime=20000 --threads=1 run
  echo "Memory Test:"
  sysbench memory --memory-block-size=1M --memory-total-size=1G run
  echo "Sleeping 60s..."
  sleep 60
done
EOF
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
