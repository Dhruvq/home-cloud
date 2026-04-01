# Bringing Fire to the Home Cloud

A step-by-step execution plan and comprehensive context document to deploy the "Wildfire Spread Forecaster" onto your 3-Node Proxmox Home Cloud and seamlessly expose it to the internet at `fire.dhruvq.com` using Cloudflare Tunnels.

**Deployment Target Context:**
We are deliberately targeting **Node 2 (`pve-node2` / `gpu-node-2` with the GTX 1060)** rather than Node 3. 
*Why?* The `Fire` application—consisting of a Next.js frontend and a FastAPI backend running a Cellular Automata spread algorithm—is computationally lightweight and has been artificially capped at 8-hour simulations to prevent recursive load spikes. It does not require extreme inference speed. Allocating it to the GTX 1060 efficiently utilizes the cluster while preserving the heavyweight Node 3 (RTX 3080) for bleeding-edge LLM workloads in the future.

---

## Phase 1: Namecheap to Cloudflare DNS Migration (Zero Downtime)
Since `dhruvq.com` is registered on Namecheap, transfer the DNS management to Cloudflare so its Tunneling capabilities can safely intercept traffic to `fire.dhruvq.com`. *Started this phase*

1. **Sign up / Log in to Cloudflare.** Add `dhruvq.com` and select the **Free** tier.
2. **Review DNS Records:** Cloudflare will automatically import existing records.
3. **Update Nameservers in Namecheap:**
   - Go to Domain List > Manage `dhruvq.com` > Nameservers > "Custom DNS".
   - Paste the two Cloudflare nameservers provided (e.g., `halvey.ns.cloudflare.com`).
4. **Wait for Propagation:** Cloudflare will verify and email you when active.

---

## Phase 2: Dockerizing the Fire Application
Once DNS propagation is complete, the next step is containerization.

1. **`backend/Dockerfile`**: A Python 3.10+ image.
   * *Tasks:* Install `requirements.txt`, setup FastAPI / Uvicorn, and expose port `8000`.
2. **`frontend/Dockerfile`**: A Node 20+ image.
   * *Tasks:* Run `npm install`, `npm run build`, and `npm start` on port `3000`. Next.js API rewrites will automatically proxy `/api/*` directly to the backend container over the local Docker network.
3. **`docker-compose.yml`**: The root orchestrator.
   * *Tasks:* Define the `backend` and `frontend` services, attaching them to a shared bridge network, and passing `.env` variables safely.

---

## Phase 3: Pushing and Deploying to Node 2 (GTX 1060)
With the codebase containerized, ship it to your designated Proxmox VM.

1. **SSH into the Node:** Use Tailscale (`100.x.x.x`) to SSH securely into the Ubuntu VM hosted on Node 2.
2. **Code Transfer:** Use `rsync` to push the `@Fire` repository onto `gpu-node-2`.
3. **Launch the Stack:** Run `docker compose up -d --build`.
4. **Validation:** Use `curl localhost:3000` inside the VM to silently confirm the Next.js app resolves successfully.

---

## Phase 4: Cloudflare Tunnel Integration (The "Dark" Connection)
The core component that bypasses router port-forwarding and keeps your network secure.

1. **Create the Tunnel:** 
   - Navigate to **Cloudflare Zero Trust** Dashboard > **Networks** > **Tunnels**.
   - Click "Create a tunnel" and name it `home-cloud-fire`.
2. **Install the Connector (`cloudflared`):** 
   - Cloudflare provides a specific installer script/token. 
   - SSH into the `gpu-node-2` VM and run the provided command. This establishes the outbound-only tunnel directly to Cloudflare's edge.
3. **Configure Public Hostname Routing:** 
   - **Subdomain:** `fire`
   - **Domain:** `dhruvq.com`
   - **Service / URL:** `http://localhost:3000` (Pointing Cloudflare directly to the exposed port of the Next.js Docker container).
4. **Final Test:** Navigate to `https://fire.dhruvq.com` from your phone or Mac. Cloudflare handles the SSL cert automatically, and your Fire project is now live!

---

## Phase 5: Pushing Updates Without Breaking Production

A repeatable, safe workflow for deploying changes from your local Mac to the live cluster.

### The Update Workflow

1. **Test Locally First:**
   Before touching production, always validate your changes on your Mac.
   ```bash
   cd ~/Fire
   docker compose up --build -d
   # Verify at http://localhost:3000
   docker compose down
   ```

2. **Sync Changes to the VM:**
   From your Mac, push only the source files to `gpu-node-2`. This intentionally excludes heavy generated directories — Docker rebuilds them on the VM.
   ```bash
   rsync -avz --delete \
     --exclude 'node_modules' \
     --exclude 'venv' \
     --exclude '.git' \
     --exclude '.next' \
     --exclude '__pycache__' \
     ~/Fire/ ubuntu@100.x.x.x:~/Fire/
   ```
   > **Note:** The `--delete` flag ensures removed files on your Mac are also removed on the VM, keeping both in perfect sync.

3. **Rebuild & Restart with Zero Downtime:**
   SSH into the VM and rebuild. Docker Compose will only recreate containers whose images actually changed.
   ```bash
   ssh ubuntu@100.x.x.x
   cd ~/Fire
   docker compose up -d --build
   ```
   > **Why this is safe:** Docker Compose keeps the old containers running until the new ones are built and ready. Traffic continues to be served during the build phase. The cutover only happens at the very end when it swaps the container, resulting in at most ~1-2 seconds of downtime.

4. **Validate on Production:**
   ```bash
   # From inside the VM:
   curl http://localhost:3000/api/health
   # Expected: {"status":"ok"}

   # From your Mac or phone:
   # Navigate to https://fire.dhruvq.com and verify the changes.
   ```

5. **Rollback if Something Breaks:**
   If the new build has issues, you can instantly revert to the previous working images:
   ```bash
   # On the VM — stop the broken containers:
   docker compose down

   # Re-sync the last known good version from your Mac (e.g., revert your local changes first via git):
   # On Mac:
   git checkout main
   rsync -avz --delete \
     --exclude 'node_modules' --exclude 'venv' --exclude '.git' --exclude '.next' --exclude '__pycache__' \
     ~/Fire/ ubuntu@100.x.x.x:~/Fire/

   # On VM — rebuild from the reverted source:
   docker compose up -d --build
   ```

### Quick Reference (Copy-Paste Cheatsheet)

```bash
# === FULL DEPLOY FROM MAC (4 commands) ===

# 1. Sync
rsync -avz --delete --exclude 'node_modules' --exclude 'venv' --exclude '.git' --exclude '.next' --exclude '__pycache__' ~/Fire/ ubuntu@100.x.x.x:~/Fire/

# 2. SSH in
ssh ubuntu@100.x.x.x

# 3. Rebuild
cd ~/Fire && docker compose up -d --build

# 4. Validate
curl http://localhost:3000/api/health
```
