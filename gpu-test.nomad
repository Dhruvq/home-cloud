job "gpu-test" {
  datacenters = ["dc1"]
  type        = "batch"

  group "gpu-group" {
    task "cuda-check" {
      driver = "docker"

      config {
        image   = "nvidia/cuda:12.4.1-base-ubuntu22.04"
        command = "nvidia-smi"
        # ❌ Remove device_requests entirely — Nomad doesn't use this
      }

      resources {
        cpu    = 500
        memory = 512

        # ✅ This is how Nomad requests a GPU
        device "nvidia/gpu" {
          count = 1
        }
      }
    }
  }
}
