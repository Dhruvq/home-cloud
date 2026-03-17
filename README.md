# Home-Cloud
Building a Home Cloud setup with three spare computers using proxmox and tailscale. Repo meant to serve as a guide as to how I did it.

### Current Physical Server Setup(Don't mind the mess haha)

<img src="./Server_setup.jpg" width="60%">

## Part 1:

### 1. The Core Architecture

* The OS: Proxmox VE (A Type-1 Hypervisor). It runs "bare metal" on the PCs.  
* The Network: Tailscale. This acts as a magic, secure tunnel connecting your Mac to the remote machines from anywhere in the world, without touching router port forwarding.  
* The Workloads: You will run your projects (like OpenClaw) inside lightweight Linux Containers (LXC) or Virtual Machines (VMs) on Proxmox.  

