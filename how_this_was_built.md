# How This Was Built

A detailed technical log of building a self-hosted home cloud cluster using three spare computers, Proxmox VE, and Tailscale.

---

## Table of Contents

1. [Motivation](#motivation)
2. [Core Architecture](#core-architecture)
3. [Remote Location Golden Rules](#remote-location-golden-rules)
4. [Installation Strategy](#installation-strategy)
5. [Rollout Strategy](#rollout-strategy)
6. [Phase 1 — Node 1: Proxmox & Tailscale Setup](#phase-1--node-1-proxmox--tailscale-setup)
7. [Phase 2 — Node 1: GPU VM Deployment](#phase-2--node-1-gpu-vm-deployment)
8. [Phase 3 — Node 1: Container Runtime & GPU Workload Verification](#phase-3--node-1-container-runtime--gpu-workload-verification)
9. [Phase 3.5 — VM Template Creation & Physical Node Prep](#phase-35--vm-template-creation--physical-node-prep)
10. [Phase 4 — Node 2: Deployment & Cluster Formation](#phase-4--node-2-deployment--cluster-formation)
11. [Phase 5 — Node 2: GPU Deployment](#phase-5--node-2-gpu-deployment)
12. [Phase 6 — Node 3: Deployment](#phase-6--node-3-deployment)
13. [Phase 7 — Node 3: GPU Integration & Cluster Finalization](#phase-7--node-3-gpu-integration--cluster-finalization)
14. [Part 2 — Workload Orchestration with Nomad](#part-2--workload-orchestration-with-nomad)
15. [Part 3 — Advanced Configuration & Local Registry](#part-3--advanced-configuration--local-registry)
    - [Proxmox Reliability: VM Autostart](#proxmox-reliability-vm-autostart)
    - [High Availability Nomad Cluster](#high-availability-nomad-cluster)
    - [Advanced Nomad Job Management](#advanced-nomad-job-management)
    - [Persistent Storage: Local Volumes & Node Affinity](#persistent-storage-local-volumes--node-affinity)
    - [Local Image Management: Private Docker Registry](#local-image-management-private-docker-registry)
16. [Current Cluster Architecture](#current-cluster-architecture)
17. [Node Setup Checklist](#node-setup-checklist)

---

## Motivation

The goal was to create a home 'cloud' service using spare hardware rather than paying for commercial cloud hosting.

**Key drivers:**
- Privacy-first project hosting with no third-party data exposure
- No monthly recurring costs

**Process overview:**
- Used an ASUS laptop as the first machine (Node 1)
- Three spare machines total, to be used as a cluster
- Proxmox Virtual Environment (VE) as the hypervisor on each machine
- Tailscale on the Mac to securely connect to all three nodes from anywhere

---

## Core Architecture

The existing Windows installations were replaced with a professional-grade server OS to avoid forced reboots and maximize hardware utilization.

| Layer | Technology | Role |
|---|---|---|
| Hypervisor (OS) | Proxmox VE | Type-1 hypervisor running bare-metal on each PC |
| Network | Tailscale | Encrypted WireGuard tunnel providing secure remote access without port forwarding |
| Workloads | LXC Containers / KVM VMs | Isolated environments for running projects (e.g., OpenClaw) |

---

## Remote Location Golden Rules

Since the machines live at a remote location, the following rules must be followed before moving any node.

| Rule | Requirement |
|---|---|
| **"Same Roof" Rule** | All three PCs must be physically plugged into the same local network (router/switch) so they can communicate without internet lag |
| **Power Outage Proofing** | Go into each PC's BIOS and set **"Restore on AC Power Loss"** to **"Power On"** so nodes self-recover after a power outage |

---

## Installation Strategy

Proxmox is installed using a portable flash drive as a temporary "delivery truck."

> **CRITICAL WIPE WARNINGS:**
> 1. Flashing the installer will **completely wipe everything** on the portable flash drive.
> 2. Installing Proxmox will **completely wipe Windows** and all files on the PC's internal drive.

### The 4-Step Flash Drive Process

| Step | Action |
|---|---|
| 1 | Use a Mac and **BalenaEtcher** to flash the Proxmox ISO onto a portable SSD/USB |
| 2 | Plug the USB into the Windows PC and boot from it via BIOS settings |
| 3 | Follow the graphical wizard to install Proxmox onto the PC's **internal drive** |
| 4 | Unplug the USB, let the PC reboot — the USB can be reformatted afterward |

---

## Rollout Strategy

The cluster was not set up for the first time at the remote location. A phased rollout was used to validate at each step before committing.

| Phase | Description |
|---|---|
| **Phase 1** | Wipe *one* PC at home next to the Mac. Install Proxmox, set up Tailscale, and confirm the dashboard loads via the Mac's browser. |
| **Phase 2** | Move that one working PC to the remote location and verify it comes back online via Tailscale. |
| **Phase 3** | Wipe the other two PCs, move them to the remote location, and join them to the first to form the "Supermachine" cluster. |

---

## Phase 1 — Node 1: Proxmox & Tailscale Setup

### Step 1: Installation Media Prep (Mac)

- Downloaded the Proxmox VE ISO and BalenaEtcher.
- Flashed the OS image onto an 8GB USB drive, successfully ignoring macOS "unreadable disk" format warnings (this is expected and safe).

### Step 2: Hardware & BIOS Configuration (ASUS Laptop / Node 1)

| Action | Detail |
|---|---|
| Connected to power | Hardwired the laptop to a Wi-Fi relay to satisfy Proxmox's wired-network requirement |
| Disabled Secure Boot | Accessed BIOS and set USB drive as the primary boot priority |
| Lid management | Committed to keeping the laptop lid open to bypass sleep-state issues |

### Step 3: Proxmox OS Installation

- Booted into the Proxmox Graphical Installer via the USB drive.
- Targeted the laptop's internal drive (wiping the existing Windows OS).
- Configured localization, set the master `root` password, and allowed the system to auto-assign a local IP via the Wi-Fi relay.
- Ejected the USB drive and rebooted into the headless terminal.

### Step 4: Initial Access & Repository Configuration (from Mac)

- Accessed the Proxmox web GUI at `https://[LOCAL_IP]:8006`, bypassing the browser's self-signed SSL warning.
- Resolved `401 Unauthorized` update errors by navigating to:
  `Datacenter → [Node Name] → Updates → Repositories`
- Disabled the default `enterprise.proxmox.com` repository and added the free **No-Subscription** repository.
- Opened the Proxmox Shell and ran `apt update` to sync the new package sources.

### Step 5: Tailscale Network Tunnel Setup

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Start the service and generate an authentication link
tailscale up
```

- Authenticated the Proxmox node via the Mac's browser to join it to the private Tailscale network.
- Retrieved the node's permanent Tailscale IP (`100.x.x.x`) from the Mac's Tailscale app.

### Step 6: Remote Connectivity Verification

- Successfully loaded the Proxmox dashboard from the Mac using the Tailscale IP:
  `https://100.x.x.x:8006`
- This confirmed the secure remote architecture was fully functional independently of the local network.

---

## Phase 2 — Node 1: GPU VM Deployment

### Step 7: Virtual Machine Creation (Ubuntu GPU Node)

Created a dedicated Ubuntu Server VM within Proxmox to host GPU workloads.

| Setting | Value |
|---|---|
| VM Name | `gpu-node-1` |
| VM ID | `100` |
| OS | Ubuntu 22.04 Server |
| BIOS | OVMF (UEFI) |
| Machine Type | `q35` |
| CPU Type | `host` |
| CPU Allocation | 12 cores |
| Memory | 12 GB |
| Disk | 100 GB (local-lvm) |
| Network | VirtIO via `vmbr0` |

The Ubuntu Server ISO (`ubuntu-22.04.5-live-server-amd64.iso`) was uploaded to Proxmox storage and attached to the VM for installation.

### Step 8: PCI Passthrough Configuration (GPU)

PCI passthrough was configured on the Proxmox host to give the VM direct access to the physical GPU.

#### Enable IOMMU

Edited `/etc/default/grub`:

```diff
# Before
GRUB_CMDLINE_LINUX_DEFAULT="quiet"

# After
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

Applied and rebooted:

```bash
update-grub
reboot
```

Verified IOMMU was active:

```bash
dmesg | grep -e DMAR -e IOMMU
# Confirmed: DMAR: IOMMU enabled
```

#### Bind GPU to VFIO

Identified GPU PCI IDs:

```bash
lspci -nn | grep -i nvidia
```

| Device | PCI ID |
|---|---|
| RTX 3050 (GPU) | `10de:25a2` |
| RTX 3050 (Audio) | `10de:2291` |

Created VFIO configuration at `/etc/modprobe.d/vfio.conf`:

```
options vfio-pci ids=10de:25a2,10de:2291
```

Enabled VFIO kernel modules by adding the following to `/etc/modules`:

```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

Rebuilt initramfs and rebooted:

```bash
update-initramfs -u -k all
reboot
```

Verified both GPU devices were using the correct driver:

```bash
lspci -nnk -d 10de:
# Kernel driver in use: vfio-pci  ✓
```

### Step 9: GPU Attachment to the VM

The GPU was attached to VM 100 via manual configuration (the Proxmox GUI was not used here — see Pain Points below).

Edited `/etc/pve/qemu-server/100.conf` and added:

```
hostpci0: 0000:01:00.0,pcie=1
hostpci1: 0000:01:00.1,pcie=1
```

This exposed both the RTX 3050 GPU and its audio controller to the VM.

### Step 10: Ubuntu Installation

Booted the VM and installed Ubuntu Server. Key installer selections:

| Installer Step | Choice |
|---|---|
| Network | DHCP |
| Storage | Use entire disk with LVM |
| SSH | Install OpenSSH server |
| Featured Snaps | None |

Installation completed successfully and the system rebooted into the new OS.

### Step 11: GPU Visibility Verification

Logged into the Ubuntu VM and verified the GPU was visible at the PCI level:

```bash
lspci | grep -i nvidia
# Output: NVIDIA GA107M [GeForce RTX 3050 Mobile]  ✓
```

### Step 12: NVIDIA Driver Installation

```bash
# Install the recommended driver automatically
sudo ubuntu-drivers autoinstall
sudo reboot

# After reboot, verify CUDA functionality
nvidia-smi
# RTX 3050 detected with CUDA support  ✓
```

### Pain Points Encountered in Phase 2

| Issue | Cause | Resolution |
|---|---|---|
| GPU not appearing in Proxmox "Add PCI Device" dropdown | GPU was still bound to the host kernel driver instead of the VFIO passthrough driver | Bound GPU to `vfio-pci` via `/etc/modprobe.d/vfio.conf` and rebuilt initramfs |
| `Error: Failed to run vncproxy` when opening VM console | The `x-vga=1` option caused the GPU to fully replace the VM display device, breaking Proxmox's VNC console | Removed the `x-vga=1` parameter from the VM configuration |
| Empty PCI device dropdown even after enabling IOMMU | Proxmox UI occasionally hides devices already bound to VFIO | Manually added the GPU to the VM configuration file (`100.conf`) |
| Ubuntu installer hanging at `subiquity/Late/run` | Installer was completing background configuration tasks — it was not actually frozen | Rebooted safely using the installer's reboot option; installation had already completed successfully |

---

## Phase 3 — Node 1: Container Runtime & GPU Workload Verification

### Step 13: Docker Installation

Installed Docker inside the Ubuntu VM to run containerized workloads:

```bash
sudo apt install -y docker.io

# Verify installation
docker run hello-world
# Container executed successfully  ✓
```

### Step 14: Docker Permission Configuration

Running Docker initially produced `connect: permission denied`.

**Cause:** Docker socket (`/var/run/docker.sock`) is restricted to the `docker` group.

**Resolution:**

```bash
sudo usermod -aG docker $USER
# Log out and log back in to apply group permissions
```

Docker commands were then executable without `sudo`.

### Step 15: NVIDIA Container Toolkit Installation

Added the NVIDIA container runtime repository and installed the toolkit:

```bash
# Add NVIDIA GPG key
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Add repository
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure Docker runtime and restart
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Step 16: GPU Container Validation

Ran a CUDA container to verify end-to-end GPU access inside Docker:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

Docker automatically pulled the CUDA base image and executed `nvidia-smi`.

**Output confirmed:**
- RTX 3050 detected
- NVIDIA driver loaded
- CUDA runtime accessible from inside the container

This validated the complete GPU stack:

```
GPU Hardware → VFIO Passthrough → Ubuntu VM → NVIDIA Driver → CUDA → Docker → NVIDIA Container Runtime → GPU-enabled containers
```

### Pain Points Encountered in Phase 3

| Issue | Cause | Resolution |
|---|---|---|
| `connect: permission denied` when running Docker | User not in the `docker` group | `sudo usermod -aG docker $USER` and re-authenticated session |
| `E: Unable to locate package nvidia-container-toolkit` | NVIDIA package repository was not configured | Added NVIDIA repository manually, then installed toolkit successfully |
| `Unable to find image locally` for CUDA container | Docker had not yet downloaded the CUDA image | Docker automatically pulled the image from Docker Hub on the first run |

---

## Phase 3.5 — VM Template Creation & Physical Node Prep

With the Node 1 GPU stack fully validated end-to-end, the configured VM was converted into a reusable Proxmox template before any other nodes were set up. This avoided repeating the entire VM creation, OS installation, GPU driver setup, and Docker configuration for every subsequent node.

### Step 16.5: Convert Configured VM to a Proxmox Template

In the Proxmox dashboard:

1. Right-click on the fully configured VM (`gpu-node-1`, ID 100).
2. Select **"Convert to Template"**.

The VM is now a golden image — it can no longer be started directly but can be cloned any number of times. Each clone inherits the full Ubuntu install, NVIDIA drivers, CUDA, Docker, and the NVIDIA Container Toolkit.

To deploy a new GPU node from the template:

1. Right-click the template → **Clone**.
2. Select **Full Clone** (not linked clone, to ensure independence).
3. Assign the new VM a name and ID, then start it.

> **Note:** Proxmox cannot directly clone a template to a different node when the template lives on local (non-shared) storage. See Phase 5 for how this was handled.

### Step 16.6: Physical Prep — Attach Remaining Nodes to Network Switch

The two remaining desktop PCs (Node 2 and Node 3) were physically connected to the network switch at the remote location before Proxmox was installed on them. This ensured all three nodes shared the same local network, satisfying the "Same Roof" rule.

---

## Phase 4 — Node 2: Deployment & Cluster Formation

### Step 17: Node-2 Proxmox Installation

Installed Proxmox VE on the second machine (a desktop PC) using the same USB installer used for Node 1 (reflashed).

Key installation choices:

| Setting | Value |
|---|---|
| Hostname | `pve-node2` |
| Disk | Internal system disk (Windows wiped) |
| Network | DHCP |
| Management Interface | `nic0` |

Installation completed successfully and the system rebooted into the Proxmox host.

### Step 18: Initial Node-2 Access

Accessed the Node-2 Proxmox dashboard from the Mac's browser:

```
https://<node2_local_ip>:8006
```

Logged in with `root` and the same root password used for Node 1. Verified connectivity and opened the Proxmox shell.

### Step 19: Repository Configuration (Node-2)

Disabled enterprise repositories and enabled the free community repository.

Navigation path: `Datacenter → pve-node2 → Updates → Repositories`

| Action | Detail |
|---|---|
| Disabled | `enterprise.proxmox.com` |
| Added | No-Subscription repository |

```bash
apt update
```

### Step 20: Tailscale Installation (Node-2)

Installed Tailscale identically to Node 1:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
# Authenticated through the browser
tailscale status
```

Node 2 received a new `100.x.x.x` address and appeared in the Tailscale network.

### Step 21: Hostname Conflict Resolution

When attempting to join the cluster, an error occurred:

```
can't add existing node 'pve'
```

**Cause:** Both machines shared the default hostname `pve` from their Proxmox installations.

**Resolution:** Renamed Node 2:

```bash
hostnamectl set-hostname pve-node2
# Also updated /etc/hosts to reflect the new hostname
reboot
```

After reboot, the node appeared correctly as `pve-node2`.

### Step 22: Cluster Creation (Node-1)

Created a Proxmox cluster from Node 1.

Navigation: `Datacenter → Cluster`

| Setting | Value |
|---|---|
| Cluster Name | `home-cluster` |

Cluster initialization completed successfully.

### Step 23: Node-2 Cluster Join

Obtained the cluster join information from Node 1:

`Datacenter → Cluster → Join Information`

Then on Node 2:

`Datacenter → Cluster → Join Cluster`

Pasted the join information and entered the root password for Node 1. Node 2 successfully joined the cluster. The cluster view now displayed:

```
Datacenter
├ pve (Node 1)
└ pve-node2
```

### Pain Points Encountered in Phase 4

| Issue | Cause | Resolution |
|---|---|---|
| `can't add existing node 'pve'` when joining cluster | Both machines shared the default Proxmox hostname `pve` | Renamed Node 2 with `hostnamectl set-hostname pve-node2`, updated `/etc/hosts`, and rebooted |
| `/etc/pve/nodes/pve-node2/pve-ssl.pem does not exist` after joining | The cluster filesystem had not yet generated SSL certificates for the new node | Ran `pvecm updatecerts --force` and `systemctl restart pveproxy`; error cleared after dashboard refresh |

---

## Phase 5 — Node 2: GPU Deployment

### Step 25: GPU Detection

Verified the GPU on Node 2 from the Proxmox host shell:

```bash
lspci | grep -i nvidia
# Detected: NVIDIA GeForce GTX 1060 3GB
```

### Step 26: GPU Passthrough Configuration

Enabled IOMMU in GRUB on the Node 2 host:

```bash
nano /etc/default/grub
# Set: GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
update-grub
reboot
```

### Step 27: VFIO Binding

Identified GPU PCI IDs on Node 2:

```bash
lspci -nn | grep -i nvidia
```

Created VFIO configuration:

```bash
nano /etc/modprobe.d/vfio.conf
# Add: options vfio-pci ids=<GPU_ID>,<AUDIO_ID>
```

Enabled VFIO modules in `/etc/modules`:

```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

Rebuilt initramfs and rebooted:

```bash
update-initramfs -u -k all
reboot
```

Verified:

```bash
lspci -nnk -d 10de:
# Kernel driver in use: vfio-pci  ✓
```

### Step 28: Template Deployment to Node-2

Direct cloning of the Node 1 template to Node 2 failed because the template resided on local storage (not shared storage).

**Resolution — two-step migration:**

1. Cloned the template locally on Node 1 first:
   - Right-click VM 100 (template) → **Clone**
   - Target Node: `pve-node1`, Mode: **Full Clone**

2. Removed the Node 1 GPU passthrough entries from the cloned VM's config (required for migration):
   - Removed `hostpci0` and `hostpci1` lines from `/etc/pve/qemu-server/<VMID>.conf`

3. Migrated the VM from Node 1 to Node 2 via the Proxmox dashboard.

### Step 29: Node-2 GPU Attachment

After migration, edited the VM configuration on Node 2 to attach the GTX 1060:

```bash
nano /etc/pve/qemu-server/102.conf
```

Added:

```
hostpci0: 0000:01:00.0,pcie=1
hostpci1: 0000:01:00.1,pcie=1
```

Started the VM and verified GPU availability inside the guest:

```bash
nvidia-smi
# Output: GeForce GTX 1060  ✓
```

### Step 30: Runtime Verification

Confirmed containerized GPU workload capability:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
# GTX 1060 detected successfully — full CUDA runtime confirmed  ✓
```

### Pain Points Encountered in Phase 5

| Issue | Cause | Resolution |
|---|---|---|
| `Cannot migrate VM with local resources: hostpci0, hostpci1` | Proxmox cannot live-migrate a VM that has PCI passthrough devices attached | Removed the `hostpci` entries from the VM config before migration, then re-added them on Node 2 after migration completed |
| Cannot clone template directly to Node 2 | Template lived on local (non-shared) storage — Proxmox requires shared storage for cross-node cloning | Cloned locally on Node 1 first, then migrated the cloned VM to Node 2 |

---

## Phase 6 — Node 3: Deployment

### Step 31: Proxmox Installation (Node-3)

Attempted to install Proxmox VE on the third machine. During the installer boot, the system hung before launching the graphical installer.

**Resolution — `nomodeset` boot parameter:**

1. At the "Welcome to Proxmox" boot screen, pressed `e` to edit boot parameters.
2. Modified the kernel boot line:

```diff
# Before
linux /boot/linux26 ro quiet splash=silent

# After
linux /boot/linux26 ro quiet splash=silent nomodeset
```

The `nomodeset` flag disables GPU framebuffer initialization during boot, allowing the installer to launch on machines where the GPU interferes with the early boot process. Installation then proceeded normally.

### Step 32: Hostname Configuration Issue

During installation the hostname was set to `pve-node3`, but after installation the node appeared as `pve` in the Proxmox environment.

**Cause:** The hostname was not correctly propagated to system configuration files during the installation.

**Resolution:** Corrected manually before joining the cluster:

```bash
hostnamectl set-hostname pve-node3

# Update hosts file
nano /etc/hosts
# Change: 192.168.xxx.xxx pve
# To:     192.168.xxx.xxx pve-node3

reboot
```

### Step 33: Tailscale Installation (Node-3)

Installed Tailscale identically to the previous nodes:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
# Authenticated through the browser
```

Node 3 received a `100.x.x.x` address and appeared in the Tailscale admin console.

### Step 34: Node-3 Cluster Join

Added `pve-node3` to the cluster using the same join process as Node 2:

`Datacenter → Cluster → Join Information` (on Node 1) → `Datacenter → Cluster → Join Cluster` (on Node 3)

Node 3 appeared correctly in the Tailscale network and on the Proxmox cluster dashboard.

### Pain Points Encountered in Phase 6

| Issue | Cause | Resolution |
|---|---|---|
| System hung during Proxmox installer boot | GPU framebuffer initialization during boot conflicted with the installer's display output | Added `nomodeset` to the kernel boot line at the Proxmox boot screen (`e` to edit) |
| Node appeared as `pve` instead of `pve-node3` after install | Hostname was not correctly written to system config files during installation | Corrected with `hostnamectl set-hostname pve-node3` and updated `/etc/hosts` before joining the cluster |

---

## Phase 7 — Node 3: GPU Integration & Cluster Finalization

### Step 35: GPU Hardware Initialization (Node-3 Host)

Prepared the Node 3 Proxmox host for GPU passthrough using the same process as previous nodes:

| Action | Command / File |
|---|---|
| Enable IOMMU | Edit `/etc/default/grub` → add `intel_iommu=on iommu=pt` |
| Apply GRUB changes | `update-grub && reboot` |
| Identify GPU PCI IDs | `lspci -nn \| grep -i nvidia` |
| Bind to VFIO | `/etc/modprobe.d/vfio.conf` → `options vfio-pci ids=<GPU_ID>,<AUDIO_ID>` |
| Enable VFIO modules | Add `vfio`, `vfio_iommu_type1`, `vfio_pci`, `vfio_virqfd` to `/etc/modules` |
| Rebuild initramfs | `update-initramfs -u -k all && reboot` |

### Step 36: Template Deployment & Cloning to Node-3

To maintain environment parity across the cluster, the master GPU VM template from Node 1 was deployed to Node 3 using the same two-step migration process used for Node 2:

1. Cloned the template locally on Node 1 (Full Clone).
2. Removed `hostpci0` and `hostpci1` entries from the cloned VM config.
3. Migrated the cloned VM to Node 3 via the Proxmox dashboard.
4. Edited the VM config on Node 3 (`/etc/pve/qemu-server/[VM_ID].conf`) to map Node 3's specific GPU PCI addresses (`0000:01:00.0` and `0000:01:00.1`).

### Step 37: Guest OS Identity Correction

Because the VM was cloned from the Node 1 template, the internal OS identity still referenced `gpu-node-1`. This was corrected inside the running VM:

```bash
# Update hostname inside the VM
sudo hostnamectl set-hostname gpu-node-3

# Update /etc/hosts
sudo nano /etc/hosts
# Change: gpu-node-1 → gpu-node-3
```

The VM name was also updated in the Proxmox **Options** tab to keep the GUI sidebar consistent with the terminal prompt.

### Step 38: Cluster-Wide GPU Verification

Verified the complete GPU stack on Node 3:

```bash
# Confirm driver recognized the GPU
nvidia-smi
# RTX 3080 with CUDA available  ✓

# Confirm GPU accessible inside Docker
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
# Successful execution  ✓
```

All three nodes confirmed operational. The cluster was fully complete.

### Pain Points Encountered in Phase 7

| Issue | Cause | Resolution |
|---|---|---|
| Cloned VM had wrong hostname and `/etc/hosts` entries | VM was cloned from Node 1 template which retained Node 1's identity | Updated hostname with `hostnamectl` and corrected `/etc/hosts` and the Proxmox Options tab VM name |

---

## Part 2 — Workload Orchestration with Nomad

### Prerequisite: SSH Access to VMs via Tailscale

Each Ubuntu VM must be individually authenticated with Tailscale to obtain a `100.x.x.x` IP, enabling SSH access from outside the local network.

#### Step 1: Verify Tailscale Status

Open the VM console in Proxmox and run:

```bash
tailscale status
# If not connected, the node will show as logged out or inactive
```

#### Step 2: Authenticate the VM with Tailscale

```bash
sudo tailscale up
# Outputs a login URL: https://login.tailscale.com/a/XXXXXXXX
```

Open the URL in a browser and authenticate with the same Tailscale account. After authentication the VM joins the Tailnet.

#### Step 3: Confirm Tailscale IP

```bash
tailscale ip
# Returns: 100.x.x.x
```

#### Step 4: Enable SSH Password Authentication

```bash
sudo nano /etc/ssh/sshd_config
# Ensure: PasswordAuthentication yes

sudo systemctl restart ssh
```

#### Step 5: Connect via SSH

```bash
ssh ubuntu@100.x.x.x
# Enter the Ubuntu user password when prompted
```

#### Step 6: Enable Tailscale on Boot

```bash
sudo systemctl enable tailscaled
```

#### Step 7: Repeat for All Nodes

Each VM (Node 1, Node 2, Node 3) must authenticate separately. After completing this on all nodes, all VMs will appear in the Tailscale admin console and can securely communicate with each other.

---

### HashiCorp Nomad

Nomad is a simpler, more flexible alternative to Kubernetes, well-suited for a small home lab. It is a single binary that runs on all nodes, handles job scheduling, and natively understands NVIDIA GPUs.

> **Difficulty:** 6/10 — easier to set up than Kubernetes, more robust than a custom Python script.

#### Step 1: Install Nomad on All 3 Nodes

Run the following on the Proxmox Shell of each node:

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install
sudo apt update && sudo apt install nomad -y
```

#### Step 2: Configure Node 1 as Server + Client (The Leader)

Node 1 manages the schedule. It does not run heavy AI jobs itself; it tells the other nodes what to do.

Edit `/etc/nomad.d/nomad.hcl` and replace the contents:

```hcl
data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 3  # Updated for HA (was 1)
}

client {
  enabled = true
}

plugin "docker" {
  config {
    allow_privileged = true
    allow_caps       = ["ALL"]
  }
}

client {
  network_interface = "tailscale0"
}

advertise {
  http = "100.NODE_1_IP"
  rpc  = "100.NODE_1_IP"
  serf = "100.NODE_1_IP"
}
```

```bash
sudo systemctl enable nomad
sudo systemctl start nomad
```

#### Step 3: Configure Nodes 2 & 3 as Clients (The Muscle)

Edit `/etc/nomad.d/nomad.hcl` on Node 2 and Node 3:

```hcl
data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

client {
  enabled           = true
  servers           = ["100.NODE_1_IP:4647"]
  network_interface = "tailscale0"
}

plugin "docker" {
  config {
    allow_privileged = true
    allow_caps       = ["ALL"]
  }
}

advertise {
  http = "100.CURRENT_NODE_IP"
  rpc  = "100.CURRENT_NODE_IP"
  serf = "100.CURRENT_NODE_IP"
}
```

```bash
sudo systemctl enable nomad && sudo systemctl start nomad
```

#### Step 4: Verify All Nodes Are Registered

From the Mac:

```bash
nomad node status -address=http://100.NODE_1_IP:4646
```

All three nodes should appear with status `ready`.

To make the Nomad address permanent on the Mac:

```bash
nano ~/.zshrc
# Add: export NOMAD_ADDR="http://100.NODE1_IP:4646"
source ~/.zshrc
```

#### Step 5: Install the NVIDIA Device Plugin

Nomad does not detect GPUs automatically. A separate plugin binary must be installed on every node.

Run on all 3 nodes:

```bash
# Create plugin directory
sudo mkdir -p /opt/nomad/plugins

# Download and install plugin
wget https://releases.hashicorp.com/nomad-device-nvidia/1.1.0/nomad-device-nvidia_1.1.0_linux_amd64.zip
unzip nomad-device-nvidia_1.1.0_linux_amd64.zip
sudo mv nomad-device-nvidia /opt/nomad/plugins/
sudo chmod +x /opt/nomad/plugins/nomad-device-nvidia
rm nomad-device-nvidia_1.1.0_linux_amd64.zip
```

Add the following blocks to `/etc/nomad.d/nomad.hcl` on each node:

```hcl
plugin_dir = "/opt/nomad/plugins"

plugin "nomad-device-nvidia" {
  config {
    enabled            = true
    fingerprint_period = "1m"
  }
}
```

Restart Nomad after saving:

```bash
sudo systemctl restart nomad
```

Verify the plugin loaded:

```bash
sudo journalctl -u nomad | grep -i nvidia
# Expected: agent: detected plugin: name=nvidia-gpu type=device plugin_version=1.1.0
```

Verify GPU registration from the Mac (run for each node ID):

```bash
nomad node status -verbose <node-id>
```

Look for the **Device Group Capacities** section:

```
Device Group Capacities
Device Group                          Count  Healthy  Unhealthy
nvidia/gpu/NVIDIA GeForce RTX 3080    1      1        0
```

All three nodes should report their respective GPUs. At this point, Nomad's scheduler is fully GPU-aware and will only place GPU jobs on nodes with an available device.

#### Step 6: Run Your First GPU Job

Create a file called `gpu-test.nomad` on the Mac:

```hcl
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
```

Run the job:

```bash
nomad job run gpu-test.nomad

# Check the result
nomad alloc logs <alloc-id>
```

A successful run prints the full `nvidia-smi` output. The task will show as `dead` with `Exit Code: 0` — this is correct for batch jobs. `dead` means finished, not failed.

> **Important distinctions:**
> - `type = "batch"` — one-shot tasks. Goes `dead` on successful completion.
> - `type = "service"` — long-running workloads (e.g., inference servers). Stays running.
> - Never use `device_requests` inside the Docker `config` block — that is a raw Docker API field that Nomad ignores. Always use the `device` stanza inside `resources`.

---

## Part 3 — Advanced Configuration & Local Registry

Following the initial cluster deployment, several critical internal optimizations were performed to ensure high availability, data persistence, and a streamlined development-to-deployment workflow.

### Proxmox Reliability: VM Autostart

By default, Proxmox does not automatically start VMs after a host reboot. Following a power outage, the Proxmox hosts will reboot (due to the BIOS "Restore on AC Power Loss" rule), but the Ubuntu VMs will sit idle.

**To enable VM autostart, run the following on each Proxmox host shell:**

```bash
# Replace 100 with your specific VM ID
qm set 100 --onboot 1

# Verify the setting
qm config 100 | grep onboot
# Expected output: onboot: 1
```

---

### High Availability Nomad Cluster

The initial setup relied on a single Nomad server (Node 1). If Node 1 went offline, the entire cluster would go leaderless. To fix this, Node 2 and Node 3 were also configured as servers.

**Updated Configuration for Node 2 & Node 3 (`/etc/nomad.d/nomad.hcl`):**

Add the `server` block to the existing configuration:

```hcl
server {
  enabled          = true
  bootstrap_expect = 3
}
```

After updating the config, restart Nomad on all nodes:
```bash
sudo systemctl restart nomad
```

Now the cluster can survive the loss of any single node without interruption.

---

### Advanced Nomad Job Management

To make workloads more resilient and aware of hardware limitations, additional stanzas are required in every `.nomad` job file.

#### 1. Restart and Reschedule Policies
Current Nomad jobs will stay dead if they crash. Adding these blocks ensures Nomad attempts to recover the job locally or move it to a healthy node.

```hcl
group "your-group" {
  restart {
    attempts = 5
    interval = "5m"
    delay    = "15s"
    mode     = "delay"   # keep retrying, don't give up
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "10m"
    unlimited      = true   # relocate to another node if current node fails
  }

  task "your-task" { ... }
}
```

#### 2. Service Health Checks
Health checks allow Nomad to determine if your service is actually functional, not just "running."

```hcl
service {
  name = "your-service-name"

  check {
    type     = "script"
    command  = "/bin/sh"
    args     = ["-c", "pgrep -f your_process_name || exit 2"]
    interval = "30s"
    timeout  = "5s"
  }
}
# For HTTP services, use type = "http" with a /health endpoint.
```

#### 3. Hardware Constraints (Node 2 Support)
The GTX 1060 in Node 2 only has 3GB of VRAM, which is insufficient for most modern AI inference. To prevent Large Language Models (LLMs) from landing on Node 2 and failing silently, add a memory constraint:

```hcl
resources {
  device "nvidia/gpu" {
    count = 1
    constraint {
      attribute = "${device.attr.memory}"
      operator  = ">="
      value     = "4 GiB"
    }
  }
}
```
This forces GPU jobs to utilize only the RTX 3050 (Node 1) or RTX 3080 (Node 3).

---

### Persistent Storage: Local Volumes & Node Affinity

Data stored inside a container is volatile. For AI models or databases (like Apollo-AI), persistent storage is required.

#### Step 1: Prepare the Host Nodes
Create the volume directory on **all three nodes** to ensure Nomad can place the task anywhere.

```bash
sudo mkdir -p /opt/nomad/volumes/apollo
sudo chmod -R 777 /opt/nomad/volumes/apollo
```

#### Step 2: Configure the Job File
Define the volume in the task block:

```hcl
task "apollo-task" {
  driver = "docker"
  config {
    image = "..."
    volumes = [
      "/opt/nomad/volumes/apollo:/app/data" # host_path : container_path
    ]
  }
}
```

> [!IMPORTANT]
> **Data Locality Catch:** Local volumes do not move between nodes. If a job moves from Node 2 to Node 3, it will see an empty folder on Node 3.
> **Solution:** Use hard `constraints` in the job file to pin the task to the specific node where the data resides.

---

### Local Image Management: Private Docker Registry

A private registry allows you to build custom Docker images on your Mac and push them to the cluster without using a public hub.

#### 1. Setup on Node 1 (Registry Host)
Create storage and deploy the registry service:

```bash
sudo mkdir -p /opt/registry/data
sudo chown -R 1000:1000 /opt/registry/data
```

**registry.nomad:**
```hcl
job "registry" {
  datacenters = ["dc1"]
  type        = "service"

  group "registry" {
    constraint {
      attribute = "${node.unique.id}"
      value     = "5bcd9b82-365b-aebd-538a-b54c5035967f" # Fixed to gpu-node-1
    }

    network {
      port "registry" {
        static = 5000
        to     = 5000
      }
    }

    task "registry" {
      driver = "docker"
      config {
        image   = "registry:2"
        ports   = ["registry"]
        volumes = ["/opt/registry/data:/var/lib/registry"]
      }
    }
  }
}
```

#### 2. Configure Clients (Mac & Nodes)
Since the registry uses HTTP over Tailscale, it must be added to the `insecure-registries` list in Docker settings:

```json
{
  "insecure-registries": ["100.NODE1_IP:5000"]
}
```
*On Mac: Docker Desktop → Settings → Docker Engine.*
*On Nodes: Edit `/etc/docker/daemon.json` and restart Docker.*

#### 3. Development Workflow

```bash
# On your Mac
docker build -t 100.NODE1_IP:5000/your-project:latest .
docker push 100.NODE1_IP:5000/your-project:latest

# Reference in your .nomad file
config {
  image = "100.NODE1_IP:5000/your-project:latest"
}
```

---

## My Current Cluster Architecture

All three nodes are fully operational, remotely accessible via Tailscale, and running identical Ubuntu 22.04 VM environments with Docker, CUDA, and the NVIDIA Container Toolkit pre-installed.

| Node | Hardware | Proxmox Hostname | GPU | Role |
|---|---|---|---|---|
| Node 1 | ASUS Laptop | `pve` | RTX 3050 Mobile | UI, FastAPI Orchestrator, Nomad Server + Client, Quorum Vote |
| Node 2 | Desktop PC | `pve-node2` | GTX 1060 3GB | Model Inference, Dev Environment, Nomad Server + Client |
| Node 3 | Desktop PC | `pve-node3` | RTX 3080 | Heavy Training Engine, Batch Processing, Nomad Server + Client |

**Operational status:**

| Capability | Status |
|---|---|
| Remote management | 100% accessible via Tailscale (`100.x.x.x`) from Mac |
| Cluster orchestration | All 3 nodes joined to `home-cluster` — single-pane-of-glass Proxmox dashboard |
| VM environment | Identical Ubuntu 22.04 VMs cloned from master template on all nodes |
| GPU workloads | Docker + NVIDIA Container Runtime operational on all 3 nodes |
| Job scheduling | Nomad cluster live with **High Availability (3 servers)** and GPU-aware scheduling |
| Image Registry | Private Docker Registry active on Node 1 |

---

## Node Setup Checklist

A condensed reference for setting up any additional node from scratch.

### Host (Proxmox)

```bash
# 1. Install Proxmox VE (wipe existing OS)
# 2. Access dashboard: https://[LOCAL_IP]:8006
# 3. Disable enterprise repo, enable no-subscription repo
#    Datacenter → [Node Name] → Updates → Repositories
# 4. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
# 5. Enable VM Autostart
qm set <VMID> --onboot 1
# 6. Verify remote access: https://100.x.x.x:8006
```

### Enable GPU Passthrough

```bash
# 6. Enable IOMMU
nano /etc/default/grub
# Set: GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
update-grub && reboot

# 7. Identify GPU PCI IDs
lspci -nn | grep -i nvidia

# 8. Bind GPU to VFIO
nano /etc/modprobe.d/vfio.conf
# options vfio-pci ids=<GPU_ID>,<AUDIO_ID>

# 9. Enable VFIO modules
nano /etc/modules
# Add: vfio, vfio_iommu_type1, vfio_pci, vfio_virqfd

# 10. Apply and reboot
update-initramfs -u -k all && reboot
```

### Deploy GPU VM from Template

```bash
# 11. On Node 1: Clone the master template (Full Clone, target = Node 1)
# 12. Remove hostpci entries from the cloned VM config
# 13. Migrate the cloned VM to the target node
# 14/15. On the target node: re-add GPU hostpci entries
nano /etc/pve/qemu-server/<VMID>.conf
# hostpci0: 0000:01:00.0,pcie=1
# hostpci1: 0000:01:00.1,pcie=1

# 16. Configure Nomad Client (Tailscale Interface)
# Edit /etc/nomad.d/nomad.hcl:
# client { network_interface = "tailscale0" }

# 17. Configure Nomad Server (for HA)
# Add to /etc/nomad.d/nomad.hcl:
# server { enabled = true, bootstrap_expect = 3 }

# 18. Configure Docker (Insecure Registry)
# Edit /etc/docker/daemon.json:
# { "insecure-registries": ["100.NODE1_IP:5000"] }

# 19. Start VM, update hostname inside guest OS
```

### GPU Driver Verification

```bash
# 16. Verify GPU presence in VM
lspci | grep -i nvidia

# 17. Drivers are pre-installed from template — verify
nvidia-smi

# 18. Verify Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
# If successful, the node is ready for GPU workloads
```
