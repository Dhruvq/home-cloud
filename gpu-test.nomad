job "gpu-test" {
  datacenters = ["dc1"]
  type        = "batch"

  group "gpu-group" {
    task "cuda-check" {
      driver = "docker"

      config {
        image   = "nvidia/cuda:12.4.1-base-ubuntu22.04"
        command = "nvidia-smi"
      }

      resources {
        cpu    = 500
        memory = 512

        device "nvidia/gpu" {
          count = 1
        }
      }
    }
  }
}
