# Terraform Configuration for Proxmox VMs

This directory contains Terraform Infrastructure as Code (IaC) to provision virtual machines across multiple Proxmox VE servers for use with Sidero Omni and Talos Linux.

## Overview

**Default method**: PXE Boot (recommended)

This Terraform configuration creates VMs that PXE boot from Sidero Booter, automatically register with Omni, and become part of your Talos cluster. No ISO management, no templates, no manual configuration.

**What it does**:
- Creates VMs across 1-3+ Proxmox servers
- Assigns static MAC addresses for machine identification
- Configures boot order for PXE network boot
- Outputs machine inventory for automation scripts
- Supports control planes, workers, and GPU workers

## Quick Start (PXE Boot)

```bash
# 1. Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# 2. Edit with your settings
nano terraform.tfvars
# Set boot_method = "pxe" (default)
# Add your Proxmox API credentials
# Configure your VMs

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. VMs will PXE boot and appear in Omni UI
# Continue with scripts/discover-machines.sh
```

That's it! VMs boot from the network via Booter, register with Omni, and you're ready for the next step.

## Prerequisites

### Required

- **Proxmox VE**: 8.x or 9.x (1-3+ servers)
- **Terraform**: 1.0+ ([install guide](https://www.terraform.io/downloads))
- **Proxmox API Tokens**: One per Proxmox server (see [setup guide](#proxmox-api-token-setup) below)
- **Sidero Omni**: Deployed and accessible ([setup guide](../sidero-omni/README.md))
- **Sidero Booter**: Running for PXE boot ([setup guide](../deployment-methods/pxe-boot/README.md))

### Network Setup

For PXE boot, you need:
- DHCP server on your network (router, Firewalla, pfSense, etc.)
- Booter running with `--dhcp-proxy-iface-or-ip=<interface>` flag
- VMs able to reach Booter and Omni

**No manual DHCP configuration needed** - Booter acts as a DHCP proxy and intercepts PXE requests automatically.

## Files

- `main.tf` - Main Terraform configuration
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `terraform.tfvars.example` - Example variables file
- `recommend-cluster.sh` - Automated resource discovery tool

## Proxmox API Token Setup

**You need to create API tokens for EACH Proxmox server.** Follow these steps for every Proxmox node.

### Step 1: Create Terraform User in Proxmox

For each Proxmox server, SSH or use the web console:

```bash
# SSH to your Proxmox server
ssh root@pve1.example.com

# Create a dedicated user for Terraform
pveum user add terraform@pve --comment "Terraform automation user"
```

### Step 2: Create API Token

**Option A: Via Proxmox Web UI (Easiest)**

1. **Login to Proxmox Web UI**: `https://your-proxmox-server:8006`

2. **Navigate to API Tokens**:
   - Click on **Datacenter** (top left)
   - Click on **Permissions** → **API Tokens**
   - Click **Add** button

3. **Create Token**:
   - **User**: Select `terraform@pve`
   - **Token ID**: `terraform` (or any name you prefer)
   - **Privilege Separation**: ✅ **UNCHECK** this box (very important!)
     - This allows the token to use the user's permissions
   - Click **Add**

4. **Save the Secret**:
   - A dialog will show the **Token Secret** (looks like: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
   - **COPY THIS NOW** - it won't be shown again!
   - Save it securely (password manager recommended)

**Option B: Via Command Line**

```bash
# SSH to Proxmox server
ssh root@pve1.example.com

# Create API token
pveum user token add terraform@pve terraform --privsep 0

# Output will show:
# ┌──────────────┬──────────────────────────────────────┐
# │ key          │ value                                │
# ╞══════════════╪══════════════════════════════════════╡
# │ full-tokenid │ terraform@pve!terraform              │
# ├──────────────┼──────────────────────────────────────┤
# │ info         │ {"privsep":0}                        │
# ├──────────────┼──────────────────────────────────────┤
# │ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
# └──────────────┴──────────────────────────────────────┘

# SAVE THE 'value' - this is your API token secret!
```

### Step 3: Grant Permissions to Terraform User

The terraform user needs permissions to create and manage VMs:

```bash
# SSH to Proxmox server
ssh root@pve1.example.com

# Grant VM management permissions
pveum acl modify / --user terraform@pve --role Administrator

# Alternatively, use a more restrictive role (recommended for production):
pveum role add TerraformProv -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit"
pveum acl modify / --user terraform@pve --role TerraformProv
```

**Explanation of Roles**:
- **Administrator**: Full permissions (easiest, less secure)
- **TerraformProv**: Custom role with only VM creation permissions (recommended)

### Step 4: Verify Token Works

Test the API token:

```bash
# Replace with your values
PROXMOX_HOST="192.168.10.160"
API_TOKEN_ID="terraform@pve!terraform"
API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Test API access
curl -k -H "Authorization: PVEAPIToken=${API_TOKEN_ID}=${API_TOKEN_SECRET}" \
  https://${PROXMOX_HOST}:8006/api2/json/version

# Should return JSON with Proxmox version info
```

If you see version information, the token works!

### Step 5: Repeat for All Proxmox Servers

**Important**: Repeat Steps 1-4 for EACH Proxmox server in your cluster.

Example for 3 servers:
```bash
# Server 1 (pve1)
ssh root@pve1
pveum user add terraform@pve
pveum user token add terraform@pve terraform --privsep 0
pveum acl modify / --user terraform@pve --role Administrator

# Server 2 (pve2)
ssh root@pve2
pveum user add terraform@pve
pveum user token add terraform@pve terraform --privsep 0
pveum acl modify / --user terraform@pve --role Administrator

# Server 3 (pve3)
ssh root@pve3
pveum user add terraform@pve
pveum user token add terraform@pve terraform --privsep 0
pveum acl modify / --user terraform@pve --role Administrator
```

### Step 6: Organize Your Credentials

Create a secure note with all your API credentials:

```
# Proxmox API Credentials for Terraform

## PVE1
API URL: https://192.168.10.160:8006/api2/json
Token ID: terraform@pve!terraform
Token Secret: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Node Name: pve1

## PVE2
API URL: https://192.168.10.161:8006/api2/json
Token ID: terraform@pve!terraform
Token Secret: yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
Node Name: pve2

## PVE3
API URL: https://192.168.10.162:8006/api2/json
Token ID: terraform@pve!terraform
Token Secret: zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz
Node Name: pve3
```

**Security Best Practices**:
- Store credentials in a password manager (1Password, Bitwarden, etc.)
- Never commit `terraform.tfvars` to git (it's in `.gitignore`)
- Use environment variables for CI/CD: `TF_VAR_proxmox_servers`
- Rotate tokens periodically

## Configuration

### Option A: Automated Resource Discovery (Recommended)

Use the **automated cluster recommendation tool** to discover your Proxmox resources and generate optimal VM configurations:

```bash
./recommend-cluster.sh
```

**What it does**:
1. **Queries each Proxmox server** - Discovers CPU, RAM, and storage capacity
2. **Calculates usable resources** - Reserves 20% for Proxmox host
3. **Recommends optimal VMs** - Suggests control planes and workers based on capacity
4. **Generates terraform.tfvars** - Creates complete configuration automatically
5. **Shows resource allocation** - Displays how VMs are distributed across servers

**Example**:
```
Server with 8 cores, 32GB RAM, 500GB storage:
  → Recommends: 1 control plane (4 cores, 8GB) + 2 workers (8 cores, 16GB each)
  → Reserves 20% for host

Server with 24 cores, 128GB RAM, 2TB storage:
  → Recommends: 1 control plane (4 cores, 8GB) + 7 workers (8 cores, 16GB each)
  → Prevents over-provisioning
```

After generation, review and customize `terraform.tfvars` as needed, then proceed to [Deployment](#deployment).

---

### Option B: Manual Configuration

Copy the example configuration and edit it manually:

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Configure `proxmox_servers` section with your API credentials:**

```hcl
proxmox_servers = {
  "pve1" = {
    api_url          = "https://192.168.10.160:8006/api2/json"
    api_token_id     = "terraform@pve!terraform"
    api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # From Step 2 above
    node_name        = "pve1"
    tls_insecure     = true  # Set to false if using valid SSL certs
    storage_os       = "local-lvm"  # Your OS disk storage pool
    storage_data     = "local-lvm"  # Your data disk storage pool
    network_bridge   = "vmbr0"
  }
  "pve2" = {
    api_url          = "https://192.168.10.161:8006/api2/json"
    api_token_id     = "terraform@pve!terraform"
    api_token_secret = "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # Different token!
    node_name        = "pve2"
    tls_insecure     = true
    storage_os       = "local-lvm"
    storage_data     = "local-lvm"
    network_bridge   = "vmbr0"
  }
  # Add pve3, pve4, etc. as needed
}
```

**Important Notes**:
- Each Proxmox server needs its own API token secret
- `node_name` must match the Proxmox node name exactly
- `storage_os` and `storage_data` can be different (e.g., `local-lvm` for OS, `nfs-storage` for data)
- Storage pool names must exist on that specific Proxmox server

**Configure boot method (use PXE):**

```hcl
# Use PXE boot (recommended)
boot_method = "pxe"

# Cluster name
cluster_name = "talos-cluster"

# Network configuration
network_config = {
  gateway     = "192.168.10.1"
  dns_servers = ["1.1.1.1", "8.8.8.8"]
}
```

**Configure your VMs:**

```hcl
control_planes = [
  {
    name              = "talos-control-1"
    proxmox_server    = "pve1"  # Must match a key from proxmox_servers
    ip_address        = "192.168.10.120"
    mac_address       = ""  # Leave empty for auto-generation
    cpu_cores         = 4
    memory_mb         = 8192
    os_disk_size_gb   = 50
    data_disk_size_gb = 100
  },
  {
    name              = "talos-control-2"
    proxmox_server    = "pve2"
    ip_address        = "192.168.10.121"
    mac_address       = ""
    cpu_cores         = 4
    memory_mb         = 8192
    os_disk_size_gb   = 50
    data_disk_size_gb = 100
  },
  {
    name              = "talos-control-3"
    proxmox_server    = "pve1"
    ip_address        = "192.168.10.122"
    mac_address       = ""
    cpu_cores         = 4
    memory_mb         = 8192
    os_disk_size_gb   = 50
    data_disk_size_gb = 100
  },
]

workers = [
  {
    name              = "talos-worker-1"
    proxmox_server    = "pve2"
    ip_address        = "192.168.10.130"
    mac_address       = ""
    cpu_cores         = 8
    memory_mb         = 16384
    os_disk_size_gb   = 65
    data_disk_size_gb = 200  # For Longhorn storage
  },
  {
    name              = "talos-worker-2"
    proxmox_server    = "pve1"
    ip_address        = "192.168.10.131"
    mac_address       = ""
    cpu_cores         = 8
    memory_mb         = 16384
    os_disk_size_gb   = 65
    data_disk_size_gb = 200
  },
  # Add more workers...
]

# Optional: GPU workers
gpu_workers = [
  {
    name              = "talos-gpu-1"
    proxmox_server    = "pve2"
    ip_address        = "192.168.10.140"
    mac_address       = ""
    cpu_cores         = 16
    memory_mb         = 32768
    os_disk_size_gb   = 65
    data_disk_size_gb = 500
  },
]
```

See `terraform.tfvars.example` for complete examples.

## Deployment

### 1. Initialize Terraform

```bash
terraform init
```

This downloads the Proxmox provider and initializes the working directory.

### 2. Validate Configuration

```bash
# Check syntax
terraform validate

# Format code
terraform fmt

# Plan deployment (dry-run)
terraform plan
```

Review the plan carefully. It should show:
- VM resources to be created on each Proxmox server
- Correct storage pools being used
- Proper network configuration

### 3. Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted. Terraform will:
1. Connect to each Proxmox server via API
2. Create VMs with empty disks (no ISO for PXE boot)
3. Configure VMs with specified resources (CPU, RAM, disks)
4. Set MAC addresses for network interfaces
5. Configure boot order: Network first, then disk
6. Start the VMs (they will PXE boot)

**Deployment time**: ~5-10 minutes depending on number of VMs and servers.

**What happens next**:
1. VMs PXE boot from network
2. Booter serves Talos image
3. VMs boot into Talos maintenance mode
4. Machines register with Omni (appear in UI as UUIDs)
5. Continue with `scripts/discover-machines.sh` to map UUIDs to hostnames

### 4. Verify Deployment

```bash
# View created VMs with MAC addresses and IPs
terraform output machine_inventory

# Get DHCP reservations to configure (recommended)
terraform output dhcp_reservations_table

# View cluster summary
terraform output cluster_summary

# View GPU workers (if any)
terraform output gpu_configuration_needed
```

## PXE Boot Workflow

When using PXE boot (`boot_method = "pxe"`), VMs are created with:

**VM Configuration**:
- Empty OS disk (scsi0)
- Optional empty data disk (scsi1, if configured)
- No CD-ROM
- Static MAC address (auto-generated or specified)
- Boot order: Network interface first, then disk (`order=net0;scsi0`)

**Boot Process**:
1. **VM starts** → Network boot initiated
2. **DHCP request** → Router provides IP and network info
3. **PXE request** → Booter intercepts as DHCP proxy
4. **Booter serves Talos** → iPXE downloads and boots Talos kernel
5. **Talos boots** → Machine registers with Omni via SideroLink
6. **Omni discovers machine** → Appears in Omni UI (with UUID)
7. **Scripts match UUID** → Map to hostname/IP/role from Terraform
8. **Omni installs to disk** → After cluster creation
9. **VM reboots to disk** → Permanent installation complete

## VM Configuration Details

### Default VM Settings

**Control Planes**:
- 4 vCPU cores
- 8GB RAM
- 50GB OS disk
- 100GB data disk (optional)

**Workers**:
- 8 vCPU cores
- 16GB RAM
- 65GB OS disk
- 200GB data disk (for Longhorn)

**GPU Workers**:
- 16 vCPU cores
- 32GB RAM
- 65GB OS disk
- 500GB data disk
- GPU passthrough (manual configuration required after Terraform)

### Network Configuration

All VMs are configured with:
- Static MAC addresses (for matching with Omni)
- Network bridge (default: vmbr0)
- DHCP initially (for PXE boot)
- Static IPs applied via DHCP reservations or Omni configs

**DHCP Reservations (Recommended)**:
```bash
# Get DHCP reservation table
terraform output dhcp_reservations_table

# Add these to your router/DHCP server
# Example: Firewalla, pfSense, etc.
```

### Storage Configuration

**OS Disk** (scsi0):
- Used for Talos OS installation
- Typical size: 50-65GB
- Storage pool: `storage_os` (e.g., `local-lvm`)

**Data Disk** (scsi1, optional):
- Used for Longhorn persistent storage
- Mounted at `/var/mnt/longhorn`
- Typical size: 100-500GB
- Storage pool: `storage_data` (can differ from OS disk)
- Set `data_disk_size_gb = 0` to skip

### GPU Configuration

For GPU workers, Terraform creates the VM but **GPU passthrough must be configured manually**:

```bash
# 1. Get GPU configuration instructions
terraform output gpu_configuration_needed

# 2. SSH to the Proxmox server
ssh root@pve2

# 3. Find the VM ID
qm list | grep talos-gpu-1

# 4. Find GPU PCI ID
lspci | grep -i nvidia
# Example: 01:00.0 VGA compatible controller: NVIDIA Corporation ...

# 5. Configure GPU passthrough
qm set <VM_ID> -hostpci0 01:00,pcie=1

# 6. Reboot the VM
qm reboot <VM_ID>
```

The machine configuration scripts will automatically add NVIDIA runtime configs for GPU workers.

## Terraform Outputs

### machine_inventory

Complete inventory of all created machines:
```json
{
  "talos-control-1": {
    "hostname": "talos-control-1",
    "ip_address": "192.168.10.120",
    "mac_address": "BC:24:11:01:00:00",
    "role": "control-plane",
    "proxmox_server": "pve1",
    "vmid": 100
  }
}
```

Use this for automation scripts and machine matching.

### dhcp_reservations_table

Formatted table for adding DHCP reservations:
```
MAC Address         IP Address       Hostname
BC:24:11:01:00:00   192.168.10.120   talos-control-1
BC:24:11:01:00:01   192.168.10.121   talos-control-2
```

### cluster_summary

High-level cluster overview:
- Total VMs created
- Control planes, workers, GPU workers
- Distribution across Proxmox servers

## Troubleshooting

### VMs Stuck in PXE Boot Loop

**Symptom**: VMs reboot endlessly at "Configuring (net0)..."

**Solutions**:
1. Check Booter is running: `docker logs sidero-booter`
2. Verify Booter has correct interface: `--dhcp-proxy-iface-or-ip=enp1s0`
3. Check Booter API address matches Omni host: `--api-advertise-address=<ip>`
4. Verify kernel args are correct (copy from Omni UI → Overview)
5. Check network connectivity between VMs and Booter

See: [PXE Boot Troubleshooting](../deployment-methods/pxe-boot/README.md#troubleshooting)

### Terraform API Connection Failures

**Symptom**: `Error: error creating VM: ... 401 Unauthorized`

**Solutions**:
1. Verify API token is correct
2. Check token has proper permissions
3. Test token with curl (see [Step 4](#step-4-verify-token-works))
4. Ensure `privsep=0` when creating token

### Storage Pool Not Found

**Symptom**: `Error: storage 'local-lvm' does not exist`

**Solutions**:
1. List available storage: `pvesm status` (on Proxmox)
2. Update `storage_os` and `storage_data` in terraform.tfvars
3. Common storage names: `local-lvm`, `local-zfs`, `nfs-storage`, `ceph-storage`

### MAC Address Conflicts

**Symptom**: VM fails to start with MAC address conflict

**Solutions**:
1. Let Terraform auto-generate MACs (leave `mac_address = ""`)
2. If specifying manually, ensure uniqueness across ALL Proxmox servers
3. Use format: `BC:24:11:XX:XX:XX` (avoid common vendor prefixes)

## Next Steps

After successful Terraform deployment:

1. **Wait for machines to register** (2-5 minutes)
   - Check Omni UI: Machines should appear with UUIDs

2. **Match machines with scripts**:
   ```bash
   cd ../scripts
   ./discover-machines.sh
   ```

3. **Generate machine configurations**:
   ```bash
   ./generate-machine-configs.sh
   ```

4. **Apply configurations to Omni**:
   ```bash
   ./apply-machine-configs.sh
   ```

5. **Create cluster in Omni UI**:
   - Machines now have friendly names
   - Select control planes and workers
   - Click "Create Cluster"

See: [Scripts README](../scripts/README.md) for detailed workflow.

## Alternative: ISO Boot Method

If PXE boot doesn't work in your environment, you can use ISO boot instead.

### ISO Boot Setup

**Step 1: Download Talos ISO**

```bash
# Download latest stable Talos ISO
wget https://github.com/siderolabs/talos/releases/download/v1.11.5/metal-amd64.iso
```

**Step 2: Upload to Proxmox**

```bash
# Via SCP
scp metal-amd64.iso root@pve1:/var/lib/vz/template/iso/talos-amd64.iso

# Or via Proxmox Web UI:
# Datacenter → Storage → local → ISO Images → Upload
```

**Step 3: Configure Terraform**

In `terraform.tfvars`:
```hcl
boot_method = "iso"
talos_iso   = "local:iso/talos-amd64.iso"
```

**Step 4: Deploy**

```bash
terraform apply
```

VMs will boot from ISO instead of PXE.

### ISO Boot vs PXE Boot

| Feature | PXE Boot | ISO Boot |
|---------|----------|----------|
| Setup complexity | Simple (just Booter) | Medium (ISO upload) |
| Network dependency | Required | Not required |
| ISO management | None | Manual upload/updates |
| Boot speed | Fast | Medium |
| Production ready | ✅ Yes | ✅ Yes |

**Recommendation**: Use PXE boot unless network boot is not possible in your environment.

## References

- [Terraform Proxmox Provider v3](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Talos Linux Downloads](https://github.com/siderolabs/talos/releases)
- [Sidero Booter](https://github.com/siderolabs/booter)
- [Proxmox VE API](https://pve.proxmox.com/wiki/Proxmox_VE_API)
