# Public-Facing Home-Cloud Architecture

## Current State
A private 3-node Proxmox cluster (ASUS Laptop, 2x Desktop PCs) using Tailscale for secure internal remote access. GPUs (RTX 3050, GTX 1060, RTX 3080) are passed through to Ubuntu VMs for ML workloads (e.g., Wildfire Prediction, Network Degradation ML). 

## The Gateway Implementation
The system successfully hosts public-facing web infrastructure on the home cluster without compromising the private security of the existing Tailscale network. 

### Architecture Specifications
- **Public Domain**: `dhruvq.com` (e.g., routing to `fire.dhruvq.com`)
- **Public Entry Point**: Hosted via Cloudflare Tunnels (`cloudflared`). This allows public external traffic to reach specific internal cluster applications securely without opening router ports or exposing the home IP address. All traffic is auto-secured with SSL (HTTPS) via Cloudflare.
- **Distributed Workloads**:
  - Web Front-ends (Next.js/React) and ML Backends (FastAPI) are spun up efficiently in isolated Docker containers (via `docker compose`) on specific VMs (`gpu-node-2`, etc.).
- **Internal Communication**: The Web Front-ends communicate with backend APIs over the internal Proxmox bridge/Docker networks, ensuring low latency and strict isolation.

## Key Advantages
- **Security**: The bare metal nodes and private infrastructure remain "dark" to the internet; only the designated web containers are securely exposed through the outbound Cloudflare tunnel.
- **Performance**: Local gigabit interconnects between Proxmox nodes handle heavy data processing faster than traditional cloud-to-local setups.
- **Cost Efficiency**: $0 for Cloudflare (Free tier covers unlimited bandwidth), completely replacing massive monthly AWS compute scaling fees by utilizing local hardware.

## Completed Setup Steps
- [x] Registered custom domain name (`dhruvq.com`).
- [x] Configured Cloudflare DNS and Zero Trust networking.
- [x] Deployed a `cloudflared` connector inside the Proxmox VM.
- [x] Verified routing infrastructure by successfully deploying and exposing the containerized "Fire" ML application.

## Troubleshooting / Known Issues

### Local DNS Not Resolving After Cloudflare Tunnel Creation
When initially routing a new domain or subdomain through a Cloudflare Tunnel, your Mac/laptop (unlike a mobile phone on cellular data) may aggressively cache the old DNS records or fail to resolve the new route locally while connected to Tailscale.
- **The Fix:** Simply turn off Tailscale on your local machine, refresh the browser to load the site via the public internet directly, and then turn Tailscale back on. This forces the local DNS/network stack to acknowledge the new Cloudflare route.
