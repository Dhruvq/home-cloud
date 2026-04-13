# Users Guide: Deploying a Project to the Home Cloud

How to take a project that works on your laptop and get it running on the home cloud cluster.

## Prerequisites

- Docker Desktop installed on your Mac
- Your Mac is connected to the Tailscale network
- The `NOMAD_ADDR` environment variable is set in your shell:
  ```bash
  # Should already be in ~/.zshrc
  export NOMAD_ADDR="http://100.NODE1_IP:4646"
  ```
- The private registry (`100.NODE1_IP:5000`) is listed in Docker Desktop's **insecure-registries** (Settings → Docker Engine)

## Step 1: Containerize Your Project

Create a `Dockerfile` in your project root. Example for a Python project:

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

CMD ["python", "main.py"]
```

If your project needs a GPU, use an NVIDIA base image instead:

```dockerfile
FROM nvidia/cuda:12.4.1-base-ubuntu22.04

# Install Python, dependencies, etc.
RUN apt-get update && apt-get install -y python3 python3-pip
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

CMD ["python3", "main.py"]
```

Test it locally first:

```bash
docker build -t my-project .
docker run my-project
```

## Step 2: Push to the Private Registry

Build and tag the image for the cluster's private registry, then push:

```bash
docker build -t 100.NODE1_IP:5000/my-project:latest .
docker push 100.NODE1_IP:5000/my-project:latest
```

The image is now available to all nodes in the cluster.

## Step 3: Write a Nomad Job File

Create a `.nomad` file (e.g., `my-project.nomad`) on your Mac.

### For a standard service (no GPU):

```hcl
job "my-project" {
  datacenters = ["dc1"]
  type        = "service"

  group "app" {
    count = 1

    network {
      port "http" {
        static = 8080
        to     = 8080
      }
    }

    restart {
      attempts = 5
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }

    task "app" {
      driver = "docker"

      config {
        image = "100.NODE1_IP:5000/my-project:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
```

### For a GPU workload:

Add the `device` block inside `resources` and optionally constrain by VRAM:

```hcl
resources {
  cpu    = 500
  memory = 512

  device "nvidia/gpu" {
    count = 1

    # Optional: skip the GTX 1060 (3GB) for heavy models
    constraint {
      attribute = "${device.attr.memory}"
      operator  = ">="
      value     = "4 GiB"
    }
  }
}
```

Also update the Docker config to allow GPU access:

```hcl
config {
  image      = "100.NODE1_IP:5000/my-project:latest"
  ports      = ["http"]
  privileged = true
}
```

### For persistent data:

If your project needs data to survive restarts (databases, model weights, etc.):

1. Create the volume directory on the target node(s):
   ```bash
   ssh ubuntu@100.NODE_IP
   sudo mkdir -p /opt/nomad/volumes/my-project
   sudo chmod -R 777 /opt/nomad/volumes/my-project
   ```

2. Mount it in the job file:
   ```hcl
   config {
     image   = "100.NODE1_IP:5000/my-project:latest"
     volumes = ["/opt/nomad/volumes/my-project:/app/data"]
   }
   ```

3. Pin the job to a specific node so data doesn't get orphaned:
   ```hcl
   constraint {
     attribute = "${node.unique.id}"
     value     = "<target-node-id>"
   }
   ```
   Find node IDs with: `nomad node status`

## Step 4: Deploy

```bash
nomad job run my-project.nomad
```

## Step 5: Verify & Monitor

```bash
# Check job status
nomad job status my-project

# View logs (grab the alloc ID from the status output)
nomad alloc logs <alloc-id>

# Follow logs in real time
nomad alloc logs -f <alloc-id>
```

Access your service at `http://100.NODE_IP:8080` (the Tailscale IP of whichever node Nomad placed it on — shown in the job status output).

## Updating a Deployment

When you make changes to your project:

```bash
# Rebuild and push
docker build -t 100.NODE1_IP:5000/my-project:latest .
docker push 100.NODE1_IP:5000/my-project:latest

# Redeploy
nomad job run my-project.nomad
```

Nomad will pull the updated image and restart the task.

## Stopping a Deployment

```bash
nomad job stop my-project
```

## Quick Reference

| Action | Command |
|---|---|
| Build & push image | `docker build -t 100.NODE1_IP:5000/my-project:latest . && docker push 100.NODE1_IP:5000/my-project:latest` |
| Deploy | `nomad job run my-project.nomad` |
| Check status | `nomad job status my-project` |
| View logs | `nomad alloc logs <alloc-id>` |
| Stop | `nomad job stop my-project` |
| List all jobs | `nomad job status` |
| List nodes | `nomad node status` |

## Job Types

| Type | Use Case | Behavior |
|---|---|---|
| `service` | Web servers, APIs, inference endpoints | Stays running. Nomad restarts it if it crashes. |
| `batch` | One-off scripts, training runs, data processing | Runs once and exits. `dead` with exit code 0 = success. |

## My Cluster Details:

| Node | GPU | Best For |
|---|---|---|
| Node 1 (ASUS Laptop) | RTX 3050 Mobile | Lightweight GPU tasks, orchestration |
| Node 2 (Desktop) | GTX 1060 3GB | CPU workloads, dev/test (limited VRAM) |
| Node 3 (Desktop) | RTX 3080 | Heavy inference, training, batch processing |