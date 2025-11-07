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

### Step 1: Get Kernel Parameters from Omni

1. **Login to Omni UI**: `https://your-omni-instance`

2. **Copy Kernel Parameters**:
   - Go to the **Overview** page (main dashboard)
   - Click **"Copy Kernel Parameters"** button
   - This copies parameters like:
     ```
     siderolink.api=https://omni.example.com:8090/?jointoken=YOUR_TOKEN
     talos.events.sink=[fdae:41e4:649b:9303::1]:8091
     talos.logging.kernel=tcp://[fdae:41e4:649b:9303::1]:8092
     ```

### Step 2: Configure Docker Compose

```bash
# Navigate to pxe-boot directory
cd deployment-methods/pxe-boot

# Edit docker-compose.yml
nano docker-compose.yml
```

Replace `<KERNEL_ARGS>` with the parameters you copied from Omni:

```yaml
services:
  booter:
    image: ghcr.io/siderolabs/booter:latest
    container_name: sidero-booter
    network_mode: host
    restart: unless-stopped
    command:
      - siderolink.api=https://omni.example.com:8090/?jointoken=YOUR_TOKEN
      - talos.events.sink=[fdae:41e4:649b:9303::1]:8091
      - talos.logging.kernel=tcp://[fdae:41e4:649b:9303::1]:8092
```

### Step 3: Start Booter

```bash
# Start Booter
docker-compose up -d

# Check logs
docker logs -f sidero-booter
```

You should see:
```
Listening on :8081 (HTTP)
Listening on :69 (TFTP)
Listening on :67 (DHCP Proxy)
PXE server started
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
# Get kernel parameters from Omni UI -> Overview -> Copy Kernel Parameters
# Then run:

docker run -d \
  --name sidero-booter \
  --restart unless-stopped \
  --network host \
  ghcr.io/siderolabs/booter:latest \
  siderolink.api=https://omni.example.com:8090/?jointoken=YOUR_TOKEN \
  talos.events.sink=[fdae:41e4:649b:9303::1]:8091 \
  talos.logging.kernel=tcp://[fdae:41e4:649b:9303::1]:8092

# Check logs
docker logs -f sidero-booter
```

Replace the kernel arguments with the ones you copied from Omni.

Then follow steps 4-6 above for booting VMs.

## Troubleshooting

### iPXE Stalls at "Configuring" - Can't Get IP Address

**Symptoms**:
- VMs boot to iPXE successfully
- iPXE shows "Configuring (net0 MAC:ADDRESS)......" and stalls
- Eventually times out and reboots
- Booter logs show DHCP proxy responses but NO HTTP/TFTP GET requests

**Root Cause**: Firewalla (or your DHCP server) is not assigning IP addresses to the VMs. Without an IP, iPXE cannot proceed.

**Solutions**:

1. **Check DHCP Server Logs/Leases**:
   ```bash
   # In Firewalla, check if VMs are getting DHCP leases
   # Look for VM MAC addresses (bc:24:11:xx:xx:xx) in DHCP leases
   ```
   - If no leases: DHCP server isn't seeing requests or is blocking them
   - If leases exist but VMs still failing: Network connectivity issue

2. **Verify VMs are on Correct Network**:
   - Check Proxmox VM → Hardware → Network Device
   - Should be on same bridge as Booter server (e.g., vmbr0)
   - Should be on same subnet (e.g., 192.168.10.x/24)
   - **Common issue**: VMs on isolated/different VLAN from Booter

3. **Check DHCP Scope/Pool**:
   - Ensure Firewalla DHCP pool has available IPs
   - DHCP range should cover the VM subnet
   - Check for IP exhaustion

4. **Test with Manual DHCP Reservation**:
   ```bash
   # In Firewalla: Create static DHCP reservation for one test VM
   # MAC: bc:24:11:01:00:00 (or your VM's MAC)
   # IP: 192.168.10.150 (or unused IP in your range)
   ```
   - If this works: Dynamic DHCP has issues
   - If this fails: Network connectivity problem

5. **Check for MAC Filtering**:
   - Some routers/firewalls filter unknown MAC addresses
   - Firewalla: Check if MAC filtering is enabled
   - Add VM MAC addresses to allowed list if needed

6. **Verify Network Connectivity**:
   ```bash
   # From Booter host (192.168.10.15)
   ping 192.168.10.1  # Gateway/Firewalla

   # Check if Booter can reach Proxmox network
   ping <proxmox-host-ip>
   ```

7. **Check Proxmox Network Bridge**:
   ```bash
   # On Proxmox host
   brctl show  # List bridges
   ip addr show vmbr0  # Check bridge config
   ```
   - Ensure vmbr0 (or your bridge) is up and connected to physical network
   - VMs must use same bridge as Booter's network path

**If nothing works**, see "Alternative: Use DHCP Options" section below for fallback method.

### VMs Don't PXE Boot

**Symptoms**: VMs don't boot from network, show "No bootable device" or boot to disk

**Solutions**:

1. **⚠️ Check for Conflicting DHCP Options (Different Issue)**:
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

## Alternative: Use DHCP Options (Fallback Method)

If the DHCP proxy approach isn't working (VMs can't get IP from DHCP server), you can configure your DHCP server to explicitly tell PXE clients where to find the boot server.

**When to use this**:
- DHCP proxy method not working
- VMs stuck at iPXE configuration
- Network isolation issues
- Prefer explicit configuration over proxy auto-discovery

### Configure Firewalla DHCP Options

1. **Login to Firewalla**

2. **Navigate to DHCP Settings**:
   - Settings → Advanced → DHCP Options
   - Or: Network → Your Network → DHCP Settings

3. **Add DHCP Option 66** (TFTP Server):
   ```
   Option Number: 66
   Type: IP Address
   Value: 192.168.10.15  (your Booter host IP)
   ```

4. **Add DHCP Option 67** (Boot Filename):
   ```
   Option Number: 67
   Type: String
   Value: undionly.kpxe
   ```

5. **Save and Restart DHCP Service**

6. **Restart VMs**: They should now PXE boot successfully

### Configure Other DHCP Servers

**pfSense/OPNsense**:
```
Services → DHCP Server → Your Network
→ Additional BOOTP/DHCP Options:

Number: 66
Type: IP Address
Value: 192.168.10.15

Number: 67
Type: String
Value: undionly.kpxe
```

**ISC DHCP (Linux)**:
```
subnet 192.168.10.0 netmask 255.255.255.0 {
  option tftp-server-name "192.168.10.15";
  option bootfile-name "undionly.kpxe";
  next-server 192.168.10.15;
}
```

**Mikrotik**:
```
/ip dhcp-server option
add code=66 name=tftp-server value="'192.168.10.15'"
add code=67 name=boot-file value="'undionly.kpxe'"

/ip dhcp-server network
set [find] dhcp-option=tftp-server,boot-file
```

**Note**: If using this method, you may need to restart or disable Booter's DHCP proxy to avoid conflicts:
```bash
# Edit docker-compose.yml and add environment variable
environment:
  - DISABLE_DHCP_PROXY=true

# Or just rely on your DHCP server options and let Booter serve files
```

## Complete Workflow: Terraform + PXE Boot + Omni

### Step 1: Create VMs with Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - Set boot_method = "pxe"
#   - Configure your Proxmox servers
#   - Define control planes, workers, GPU workers
terraform init
terraform plan
terraform apply
```

**Result**: VMs created in Proxmox, configured for PXE boot, with specific MAC addresses.

### Step 2: Deploy Booter (Already Done ✅)

Your working Booter configuration:
```yaml
services:
  booter:
    image: ghcr.io/siderolabs/booter:v0.3.0
    container_name: sidero-booter
    network_mode: host
    restart: unless-stopped
    command:
      - "--api-advertise-address=192.168.10.15"
      - "--dhcp-proxy-iface-or-ip=enp1s0"
      - "--api-port=50084"
      - "--extra-kernel-args=siderolink.api=https://omni.vanillax.me:8090/?jointoken=... talos.events.sink=[fdae:41e4:649b:9303::1]:8091 talos.logging.kernel=tcp://[fdae:41e4:649b:9303::1]:8092"
```

**Result**: VMs PXE boot into Talos and register with Omni.

### Step 3: Match Machines (Automation Scripts)

At this point, VMs appear in Omni with UUIDs but no identifying information. **Use the automation scripts** to label them:

```bash
cd scripts

# 1. Install prerequisites
sudo apt-get install jq
# Install omnictl from Omni UI or: https://www.siderolabs.com/omni/docs/cli/

# 2. Configure omnictl
omnictl config new
# Follow prompts to connect to your Omni instance

# 3. Discover and match machines by MAC address
./discover-machines.sh
# Matches Terraform inventory → Omni machines by MAC
# Output: machine-data/matched-machines.json with UUID mappings

# 4. Generate machine configurations
./generate-machine-configs.sh
# Creates YAML configs with:
#   - Hostnames (e.g., talos-control-01)
#   - Static IPs
#   - Role labels (control-plane, worker, gpu-worker)
#   - Disk configurations
#   - GPU configurations (for GPU workers)

# 5. Apply configurations to Omni
./apply-machine-configs.sh
# Applies labels, hostnames, and network configs
```

**Result**: Machines now show up in Omni with proper hostnames and labels instead of just UUIDs.

### Step 4: Create Cluster in Omni

**Option A: Via Omni UI (Recommended)**
1. Go to Omni UI → Clusters → Create Cluster
2. Machines now show with names like `talos-control-01` instead of UUIDs
3. Select machines by role (control-plane, worker, gpu-worker)
4. Configure cluster settings
5. Create cluster

**Option B: Via Cluster Template**
```bash
# Use the generated cluster template
omnictl cluster template sync -f scripts/machine-configs/cluster-template.yaml
```

### Step 5: Monitor and Access

```bash
# Watch cluster creation
omnictl get machines --watch

# Download kubeconfig when ready
omnictl kubeconfig > kubeconfig.yaml
export KUBECONFIG=kubeconfig.yaml

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

## Why This Workflow?

**Problem**: When VMs PXE boot into Omni, they appear with auto-generated UUIDs like `c1b495ae-4e67-4292-b78d-9354f6aae431`. You can't tell which UUID is which VM from Terraform.

**Solution**: The automation scripts:
1. Read Terraform outputs (VM names, MACs, IPs, roles)
2. Query Omni API for registered machines
3. **Match by MAC address** (Terraform knows MACs, Omni sees MACs)
4. Apply labels and configurations so machines show up with proper names

**Before Scripts**:
```
UUID                                  | Platform | CPU | RAM
c1b495ae-4e67-4292-b78d-9354f6aae431 | metal    | 8   | 16GB
7bfdca4c-6917-4279-bd38-4d5d7c174904 | metal    | 4   | 8GB
```

**After Scripts**:
```
Hostname            | Role          | IP              | Platform
talos-control-01    | control-plane | 192.168.10.100  | metal
talos-worker-01     | worker        | 192.168.10.110  | metal
talos-worker-gpu-01 | gpu-worker    | 192.168.10.120  | metal
```

## Architecture Diagram

```
┌─────────────────┐
│   VMs (Proxmox) │
│   PXE Boot      │
└────────┬────────┘
         │ DHCP Request (broadcast)
         ▼
┌─────────────────┐         ┌─────────────────┐
│  DHCP Server    │         │  Sidero Booter  │
│  (Firewalla)    │         │  (DHCP Proxy)   │
│  Assigns IP     │         │  Port :67       │
└────────┬────────┘         └────────┬────────┘
         │                           │
         └──────────┬────────────────┘
                    │ VM gets IP + PXE boot info
                    ▼
         ┌─────────────────┐
         │  VM (iPXE)      │
         │  Downloads boot │
         │  files via TFTP │
         └────────┬────────┘
                  │ HTTP/TFTP requests
                  ▼
         ┌─────────────────┐
         │  Sidero Booter  │◄── Serves Talos kernel/initramfs
         │  :69 (TFTP)     │
         │  :8081 (HTTP)   │
         └────────┬────────┘
                  │ Boots into Talos
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
