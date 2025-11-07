# PXE Boot Deployment with Sidero Booter

This deployment method uses **Sidero Booter** to PXE boot machines into Talos Linux, which then automatically register with Sidero Omni.

## Overview

**Sidero Booter** is a lightweight PXE/iPXE server that serves Talos Linux images to machines booting over the network. It integrates seamlessly with Sidero Omni for automated cluster provisioning.

**Workflow:**
1. VMs boot from network (PXE)
2. Booter serves iPXE bootloader
3. iPXE loads Talos kernel and initramfs from Booter
4. Machines boot into Talos maintenance mode
5. Talos connects to Omni via SideroLink
6. Omni discovers machines and provisions the cluster

## Prerequisites

- **Sidero Omni**: Running and accessible (on-prem or SaaS)
- **VMs Created**: VMs with PXE boot enabled (use Terraform with `boot_method = "pxe"`)
- **Network Access**: VMs must reach both Booter and Omni
- **DHCP Server**: To provide PXE boot options (e.g., Firewalla, pfSense, router)

## Deploy Booter with Docker Compose (Recommended)

The easiest way to deploy Booter is using Docker Compose.

### Step 1: Create Service Account in Omni

1. **Login to Omni UI**: `https://your-omni-instance`

2. **Create Service Account**:
   - Go to **Settings** → **Service Accounts**
   - Click **Create Service Account**
   - Name: `booter`
   - **Role: Operator** (important!)
   - Copy the token (starts with `eyJ...`)

### Step 2: Configure Environment

```bash
# Navigate to pxe-boot directory
cd deployment-methods/pxe-boot

# Copy the example environment file
cp .env.example .env

# Edit .env with your values
nano .env
```

Update `.env` with your credentials:
```bash
OMNI_ENDPOINT=https://your-omni-instance.com
OMNI_SERVICE_ACCOUNT_KEY=eyJuYW1lIjoiYm9vdGVyIiwi...  # Your service account key
```

### Step 3: Start Booter

```bash
# Make sure you've exported your environment variables or they're in .env
docker-compose up -d

# Check logs
docker logs -f sidero-booter
```

You should see:
```
Starting Omni Infra Provider (Bare Metal)...
Connected to Omni at https://your-omni-instance.com
Listening on :8081 (HTTP)
Listening on :69 (TFTP)
Listening on :67 (DHCP Proxy)
```

Booter is now acting as a DHCP proxy on your network!

### Step 4: DHCP Configuration (No Changes Needed!)

**Important:** Sidero Booter acts as a **DHCP proxy server**. This means:

✅ **What you DON'T need to do:**
- You do **NOT** need to configure DHCP Option 66 (TFTP Server)
- You do **NOT** need to configure DHCP Option 67 (Boot Filename)
- You do **NOT** need to set "Next Server" options

✅ **What you DO need:**
- Keep your normal DHCP server running (Firewalla, router, etc.) for IP address assignment
- Ensure VMs are on the same network as Booter
- That's it!

**How it works:**
1. VM sends DHCP request for IP address
2. Your DHCP server (Firewalla/router) assigns IP address normally
3. **Booter intercepts the PXE boot request** and automatically provides the correct boot files
4. VM boots Talos from Booter

**⚠️ Important - Remove Conflicting DHCP Options:**

If you previously configured DHCP Options 66/67 for PXE boot, **remove them now**. They will conflict with Booter's DHCP proxy functionality.

For Firewalla users:
- Go to: Settings → Advanced → DHCP Options
- **Remove** Option 66 (TFTP Server) if set
- **Remove** Option 67 (Bootfile) if set
- Leave DHCP server enabled normally

The same applies to pfSense, OPNsense, or any other DHCP server - remove manual PXE boot options.

### Step 5: Boot VMs

1. **Start VMs**:
   ```bash
   # If VMs are stopped, start them in Proxmox
   # They will automatically PXE boot on first start
   ```

2. **Watch Boot Process**:
   - Open Proxmox console for a VM
   - You should see:
     ```
     iPXE (http://ipxe.org) 00:00.0 ...

     net0: 52:54:00:12:34:56 using virtio-net on PCI00:03.0 (open)
     DHCP (net0 52:54:00:12:34:56)...ok

     Booting from PXE...
     Downloading Talos kernel...
     Downloading Talos initramfs...

     Talos Linux starting...
     ```

3. **Verify in Omni**:
   - Go to Omni UI → **Machines**
   - Your VMs should appear as **unallocated** machines
   - Status: **Maintenance mode**

### Step 6: Accept Machines in Omni

1. **View Discovered Machines**:
   - Omni UI → **Machines**
   - You'll see all your PXE-booted VMs

2. **Create Machine Classes** (optional):
   - Define machine classes for control planes vs workers
   - Based on CPU, RAM, or custom labels

3. **Create Cluster**:
   - Omni UI → **Clusters** → **Create Cluster**
   - Select machines for control plane and worker roles
   - Omni will install Talos to disk and configure the cluster

## Alternative: Deploy Booter with Plain Docker

If you prefer not to use Docker Compose:

```bash
# Create directory for Booter data
mkdir -p /opt/sidero-booter

# Run Booter container
docker run -d \
  --name sidero-booter \
  --restart unless-stopped \
  --network host \
  -v /opt/sidero-booter:/var/lib/sidero \
  -e OMNI_ENDPOINT=https://your-omni-instance.com \
  -e OMNI_SERVICE_ACCOUNT_KEY=eyJuYW1lIjoiYm9vdGVyIiwi... \
  ghcr.io/siderolabs/omni-infra-provider-bare-metal:latest \
  --name=booter \
  --omni-api-endpoint=https://your-omni-instance.com

# Check logs
docker logs -f sidero-booter
```

Then follow steps 4-6 above for DHCP configuration and booting VMs.

## Troubleshooting

### VMs Don't PXE Boot

**Symptoms**: VMs don't boot from network, show "No bootable device" or boot to disk

**Solutions**:

1. **⚠️ Check for Conflicting DHCP Options (Most Common Issue)**:
   - If you have DHCP Option 66 or 67 configured in your router/DHCP server, **remove them**
   - Booter acts as a DHCP proxy and will conflict with manual PXE options
   - Firewalla: Settings → Advanced → DHCP Options → Remove Option 66/67
   - pfSense: Services → DHCP Server → Remove BOOTP/DHCP Options
   - After removing, restart Booter: `docker restart sidero-booter`

2. **Check Boot Order**:
   - Proxmox VM → Options → Boot Order
   - Ensure `net0` is first in boot order
   - If using Terraform, verify `boot = "order=net0;scsi0"`

3. **Verify Booter is Running**:
   ```bash
   # Check Booter logs
   docker logs sidero-booter

   # Should see "Listening on :67 (DHCP Proxy)"
   ```

4. **Check Network Connectivity**:
   - Ensure VMs are on the same network as Booter
   - Booter must be reachable on UDP port 67 (DHCP) and 69 (TFTP)
   - Check firewall rules on the machine running Booter

### Machines Don't Appear in Omni

**Symptoms**: VMs boot to Talos but don't show up in Omni

**Solutions**:
1. **Check SideroLink Connectivity**:
   ```bash
   # SSH to Omni server
   docker logs sidero-booter

   # Look for SideroLink connection errors
   ```

2. **Verify Firewall Rules**:
   - Omni SideroLink port: `8090/tcp` (must be reachable from VMs)
   - Booter HTTP port: `8081/tcp`
   - Booter DHCP Proxy port: `67/udp`
   - Booter TFTP port: `69/udp`

3. **Check VM Network**:
   ```bash
   # In VM console (Talos maintenance mode)
   # Press Ctrl+C to get shell

   # Test connectivity to Omni
   ping 192.168.10.50

   # Check if SideroLink endpoint is reachable
   nc -zv 192.168.10.50 8090
   ```

### Wrong Talos Version

**Symptoms**: Booter serves old/wrong Talos version

**Solutions**:
1. **Update Booter Cache**:
   ```bash
   # Delete Booter cache
   docker stop sidero-booter
   rm -rf /opt/sidero-booter/cache
   docker start sidero-booter
   ```

2. **Specify Talos Version**:
   - In Omni UI → Settings → Talos Version
   - Or in Booter config.yaml

### Network Boot Too Slow

**Symptoms**: VMs take 5+ minutes to PXE boot

**Solutions**:
1. **Use Local Booter**: Run Booter on same network as VMs (not over VPN)
2. **Check Network Bandwidth**: TFTP is slow over high-latency links
3. **Consider ISO Boot**: For slow networks, use `boot_method = "iso"` instead

## Next Steps

After VMs boot and appear in Omni:

1. **Organize Machines**:
   - Create machine classes
   - Label machines by role (control-plane, worker, gpu-worker)

2. **Create Cluster**:
   - Omni UI → Clusters → Create Cluster
   - Select machines
   - Configure cluster settings

3. **Monitor Installation**:
   - Watch Omni install Talos to disk
   - VMs will reboot and join the cluster

4. **Access Cluster**:
   ```bash
   # Download kubeconfig from Omni
   kubectl get nodes
   ```

## Architecture Diagram

```
┌─────────────────┐
│   VMs (Proxmox) │
│   PXE Boot      │
└────────┬────────┘
         │ DHCP Request
         ▼
┌─────────────────┐
│  DHCP Server    │◄── Option 66: Booter IP
│  (Firewalla)    │    Option 67: undionly.kpxe
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Sidero Booter  │◄── Serves iPXE, Talos kernel/initramfs
│  :69 (TFTP)     │
│  :8081 (HTTP)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Sidero Omni    │◄── SideroLink (:8090)
│  Cluster Mgmt   │    Machine discovery
└─────────────────┘    Cluster provisioning
```

## References

- [Sidero Omni Documentation](https://www.siderolabs.com/platform/saas-for-kubernetes/)
- [Talos Linux Documentation](https://www.talos.dev)
- [iPXE Documentation](https://ipxe.org)
