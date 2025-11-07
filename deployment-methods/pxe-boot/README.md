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

## Option 1: Deploy Booter via Omni (Recommended)

Sidero Omni can automatically deploy and manage Booter for you.

### Step 1: Enable Booter in Omni

1. **Login to Omni UI**: `https://your-omni-instance`

2. **Navigate to Settings**:
   - Click **Settings** in the left sidebar
   - Go to **Infrastructure Providers** or **Booter** section

3. **Enable Booter**:
   - Toggle **Enable Booter** to ON
   - Omni will automatically deploy Booter as a container

4. **Get Booter IP Address**:
   - Note the IP address where Booter is running
   - This is typically the Omni server's IP or a dedicated service IP
   - Example: `192.168.10.50`

5. **Booter API Endpoint**:
   - HTTP: `http://<booter-ip>:8081` (API and file server)
   - TFTP: `<booter-ip>:69` (PXE boot files)

### Step 2: Configure DHCP Server

Configure your DHCP server (router, Firewalla, pfSense, etc.) to point to Booter.

**Required DHCP Options:**
- **Option 66 (TFTP Server)**: `<booter-ip>` (e.g., `192.168.10.50`)
- **Option 67 (Boot Filename)**:
  - BIOS: `undionly.kpxe`
  - UEFI: `ipxe.efi`
- **Next Server**: `<booter-ip>`

**Example Configurations:**

**Firewalla:**
```bash
# SSH to Firewalla
ssh pi@firewalla.local

# Add DHCP options (requires Firewalla Gold/Purple with advanced settings)
# Go to: Settings → Advanced → DHCP Options
Option 66: 192.168.10.50
Option 67: undionly.kpxe
```

**pfSense/OPNsense:**
```
Services → DHCP Server → LAN
→ Additional BOOTP/DHCP Options:

Option 66 (Text): 192.168.10.50
Option 67 (Text): undionly.kpxe
```

**ISC DHCP Server** (`/etc/dhcp/dhcpd.conf`):
```conf
subnet 192.168.10.0 netmask 255.255.255.0 {
  option routers 192.168.10.1;
  option domain-name-servers 1.1.1.1, 8.8.8.8;

  # PXE Boot Options
  next-server 192.168.10.50;

  # BIOS vs UEFI
  if exists user-class and option user-class = "iPXE" {
    filename "http://192.168.10.50:8081/boot.ipxe";
  } elsif option arch = 00:07 or option arch = 00:09 {
    filename "ipxe.efi";
  } else {
    filename "undionly.kpxe";
  }
}
```

**Dnsmasq** (`/etc/dnsmasq.conf`):
```conf
# Enable DHCP
dhcp-range=192.168.10.100,192.168.10.200,12h

# PXE Boot
dhcp-boot=undionly.kpxe,192.168.10.50,192.168.10.50

# TFTP
enable-tftp
tftp-root=/var/lib/tftpboot
```

### Step 3: Boot VMs

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

### Step 4: Accept Machines in Omni

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

## Option 2: Deploy Booter Manually (Advanced)

If you want to run Booter separately from Omni:

### Step 1: Run Booter Container

```bash
# Create directory for Booter data
mkdir -p /opt/sidero-booter

# Run Booter container
docker run -d \
  --name sidero-booter \
  --restart unless-stopped \
  --network host \
  -v /opt/sidero-booter:/var/lib/sidero \
  -e SIDERO_LINK_API=grpc://your-omni-ip:8090 \
  -e API_ENDPOINT=http://0.0.0.0:8081 \
  ghcr.io/siderolabs/booter:latest
```

**Environment Variables:**
- `SIDERO_LINK_API`: Omni's SideroLink endpoint (e.g., `grpc://192.168.10.50:8090`)
- `API_ENDPOINT`: Booter's HTTP API endpoint
- `TFTP_ADDR`: TFTP server address (default: `:69`)

### Step 2: Download PXE Boot Files

```bash
# Download iPXE bootloaders
cd /opt/sidero-booter

# BIOS
wget -O undionly.kpxe https://boot.ipxe.org/undionly.kpxe

# UEFI
wget -O ipxe.efi https://boot.ipxe.org/ipxe.efi

# Or use Sidero's pre-built images
wget https://github.com/siderolabs/sidero/releases/latest/download/undionly.kpxe
wget https://github.com/siderolabs/sidero/releases/latest/download/ipxe.efi
```

### Step 3: Configure Booter

Create `/opt/sidero-booter/config.yaml`:

```yaml
api:
  endpoint: "http://0.0.0.0:8081"

siderolink:
  api: "grpc://192.168.10.50:8090"  # Omni SideroLink endpoint

tftp:
  addr: ":69"

talos:
  # Booter will automatically fetch Talos images from Omni
  # Or specify custom Talos version:
  version: "v1.10.1"
```

### Step 4: Start Booter with Config

```bash
docker run -d \
  --name sidero-booter \
  --restart unless-stopped \
  --network host \
  -v /opt/sidero-booter:/var/lib/sidero \
  -v /opt/sidero-booter/config.yaml:/etc/sidero/config.yaml \
  ghcr.io/siderolabs/booter:latest \
  --config /etc/sidero/config.yaml
```

## Troubleshooting

### VMs Don't PXE Boot

**Symptoms**: VMs don't boot from network, show "No bootable device" or boot to disk

**Solutions**:
1. **Check Boot Order**:
   - Proxmox VM → Options → Boot Order
   - Ensure `net0` is first in boot order
   - If using Terraform, verify `boot = "order=net0;scsi0"`

2. **Verify DHCP Options**:
   ```bash
   # On VM, check DHCP offer
   tcpdump -i any -n port 67 and port 68

   # Should see DHCP offer with:
   # Option 66 (TFTP Server)
   # Option 67 (Boot Filename)
   ```

3. **Test TFTP Access**:
   ```bash
   # From another machine on same network
   tftp 192.168.10.50
   > get undionly.kpxe
   > quit

   # File should download successfully
   ```

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
