# Terraform Configuration for Proxmox VMs

This directory contains Terraform Infrastructure as Code (IaC) to provision virtual machines across multiple Proxmox VE servers for use with Sidero Omni and Talos Linux.

## Prerequisites

- **Proxmox VE**: 7.x or later (2-3+ servers recommended)
- **Terraform**: 1.0 or later ([install guide](https://www.terraform.io/downloads))
- **Proxmox API Tokens**: One per Proxmox server (see setup guide below)
- **Talos Template VM**: Must exist on all Proxmox servers (same name on each)

## Files

- `main.tf` - Main Terraform configuration
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `terraform.tfvars.example` - Example variables file

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

## Usage

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

After generation, review and customize `terraform.tfvars` as needed, then proceed to [Step 2](#2-initialize-terraform).

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

**Configure your VMs:**

```hcl
control_planes = [
  {
    name              = "talos-cp-1"
    proxmox_server    = "pve1"  # Must match a key from proxmox_servers
    ip_address        = "192.168.10.100"
    mac_address       = ""  # Leave empty for auto-generation
    cpu_cores         = 4
    memory_mb         = 8192
    os_disk_size_gb   = 50
    data_disk_size_gb = 100
  },
  # Add more control planes...
]

workers = [
  {
    name              = "talos-worker-1"
    proxmox_server    = "pve2"  # Distribute across servers
    ip_address        = "192.168.10.110"
    mac_address       = ""
    cpu_cores         = 8
    memory_mb         = 16384
    os_disk_size_gb   = 100
    data_disk_size_gb = 0  # No data disk for this worker
  },
  # Add more workers...
]

# gpu_workers = [...]  # Optional
```

See `terraform.tfvars.example` for complete examples.

### 2. Initialize Terraform

```bash
terraform init
```

This downloads the Proxmox provider and initializes the working directory.

### 3. Validate Configuration

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

### 4. Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted. Terraform will:
1. Connect to each Proxmox server via API
2. Clone the Talos template VM
3. Configure VMs with specified resources
4. Set MAC addresses for network interfaces
5. Create secondary disks (if configured)
6. Start the VMs

**Deployment time**: ~5-10 minutes depending on number of VMs and servers.

### 5. Verify Deployment

```bash
# View created VMs
terraform output machine_inventory

# Get DHCP reservations to configure
terraform output dhcp_reservations_table

# Check control plane endpoints
terraform output control_plane_endpoints

# View GPU workers (if any)
terraform output gpu_configuration_needed
```

## VM Configuration

This configuration will create:
- 3 control plane VMs (4 vCPU, 8GB RAM, 50GB disk)
- 3 regular worker VMs (8 vCPU, 16GB RAM, 100GB disk)
- 2 GPU worker VMs (16 vCPU, 32GB RAM, 200GB disk)

All VMs will be configured with the Talos Linux ISO and ready for bootstrapping via Sidero Omni.
