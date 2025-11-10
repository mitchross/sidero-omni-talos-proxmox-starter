# Sidero Omni + Talos + Proxmox Starter Kit

**The simple way to deploy production Talos Linux clusters on Proxmox with Sidero Omni.**

Stop fighting with UUIDs, IP addresses, and manual configuration. This starter kit automates everything from infrastructure provisioning to cluster deployment using PXE boot + Terraform + Omni.

## What This Repo Does

**For**: Experienced devs who want to try Talos Linux with Proxmox
**Problem**: Connecting Terraform VMs → PXE boot → Omni UUIDs → Hostnames/IPs is confusing
**Solution**: Automated scripts that handle all the abstraction layers for you

### The Workflow (4 Simple Steps)

```
1. Deploy Omni (management platform)          → cd sidero-omni && docker-compose up
2. Deploy Booter (PXE boot server)            → cd deployment-methods/pxe-boot && docker-compose up
3. Create VMs with Terraform                  → cd terraform && terraform apply
4. Match & configure with scripts             → cd scripts && ./discover-machines.sh
   ↓
Machines appear in Omni with proper names, IPs, and roles!
```

## Key Features

- ✅ **PXE Boot**: VMs network boot into Talos automatically (no ISO management)
- ✅ **Full Automation**: Terraform → Booter → Omni → Scripts handle everything
- ✅ **MAC Address Matching**: Scripts automatically map Terraform VMs to Omni UUIDs
- ✅ **Production Configs**: Pre-configured with hostDNS, kubePrism, Longhorn, GPU support
- ✅ **Multiple Proxmox Servers**: Distribute VMs across 2-3+ Proxmox hosts
- ✅ **GPU Workers**: Full NVIDIA containerd runtime + kernel modules
- ✅ **Self-Hosted Omni**: Complete Docker Compose setup with Auth0/SAML

## Quick Start

### Prerequisites

**Infrastructure**:
- 1x Linux VM/NUC for Omni + Booter (same machine)
- 1-3x Proxmox VE 8.x or 9.x servers
- Network with DHCP server (Firewalla, pfSense, router)

**Software** (will be installed):
- Docker & Docker Compose
- Terraform 1.0+
- omnictl CLI
- jq (JSON processor)

**Accounts**:
- Domain with Cloudflare DNS (for Let's Encrypt)
- Auth0 account (free tier works)
- Proxmox API tokens ([setup guide](terraform/README.md#proxmox-api-token-setup))

---

## Step 1: Deploy Sidero Omni

Deploy the management platform on a Linux VM or NUC:

```bash
cd sidero-omni

# Check prerequisites
./check-prerequisites.sh

# Install Docker if needed
./install-docker.sh

# Setup SSL certificates (Let's Encrypt + Cloudflare)
sudo ./setup-certificates.sh

# Generate GPG key for etcd encryption
./generate-gpg-key.sh

# Configure environment
cp .env.example omni.env
nano omni.env  # Set your domain, Auth0, etc.

# Start Omni
docker compose --env-file omni.env up -d

# Check logs
docker logs -f omni
```

**Verify**: Open `https://your-domain.com` and login via Auth0.

📖 **Full Guide**: [sidero-omni/README.md](sidero-omni/README.md)

---

## Step 2: Deploy Booter (PXE Server)

On the same machine as Omni, deploy the PXE boot server:

```bash
cd deployment-methods/pxe-boot

# Edit docker-compose.yml
nano docker-compose.yml
```

Update these values:
- `--api-advertise-address=192.168.10.15` (your Omni host IP)
- `--dhcp-proxy-iface-or-ip=enp1s0` (your network interface, find with `ip addr show`)
- Paste kernel args from Omni UI (Overview → Copy Kernel Parameters)

```bash
# Start Booter
docker-compose up -d

# Verify
docker logs -f sidero-booter
ss -ulnp | grep :69  # TFTP should be listening
```

📖 **Full Guide**: [deployment-methods/pxe-boot/README.md](deployment-methods/pxe-boot/README.md)

---

## Step 3: Create VMs with Terraform

Provision VMs on Proxmox with PXE boot:

```bash
cd terraform

# Copy example config
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
nano terraform.tfvars
```

**Key settings**:
```hcl
boot_method = "pxe"  # Use PXE boot (recommended)

proxmox_servers = {
  "pve1" = {
    api_url          = "https://192.168.10.160:8006/api2/json"
    api_token_id     = "terraform@pve!terraform"
    api_token_secret = "your-secret-here"
    node_name        = "pve1"
    storage_os       = "local-lvm"
    storage_data     = "hddpool"
    network_bridge   = "vmbr0"
  }
}

control_planes = [
  {
    name              = "talos-control-1"
    proxmox_server    = "pve1"
    ip_address        = "192.168.10.120"
    mac_address       = ""  # Auto-generated
    cpu_cores         = 4
    memory_mb         = 8192
    os_disk_size_gb   = 50
    data_disk_size_gb = 100
  },
  # Add 2 more for HA (3 total)
]

workers = [
  {
    name              = "talos-worker-1"
    proxmox_server    = "pve1"
    ip_address        = "192.168.10.130"
    mac_address       = ""
    cpu_cores         = 8
    memory_mb         = 16384
    os_disk_size_gb   = 65
    data_disk_size_gb = 200  # For Longhorn
  },
]
```

```bash
# Initialize and apply
terraform init
terraform plan
terraform apply
```

VMs will PXE boot into Talos and appear in Omni UI (with UUIDs, not names yet).

📖 **Full Guide**: [terraform/README.md](terraform/README.md)

---

## Step 4: Match & Configure Machines

The automation scripts connect Terraform data to Omni machines:

```bash
cd scripts

# Install omnictl
# Get download link from Omni UI → Settings → CLI

# Configure omnictl
# Optional if already have configured
omnictl config new
# Enter your Omni URL and authenticate

# 1. Match VMs to Omni machines by MAC address
./discover-machines.sh

# Output:
# ✓ Matched: talos-control-1 (BC:24:11:01:00:00) -> Omni UUID: 7bfdca4c...
# ✓ Matched: talos-control-2 (BC:24:11:01:00:01) -> Omni UUID: 468090e7...
# ✓ Matched: talos-control-3 (BC:24:11:01:00:02) -> Omni UUID: 78c997c5...
# Matched: 6/6

# 2. Generate Omni cluster templates with production configs
./generate-machine-configs.sh

# Output:
# ✓ Generated 6 machine configurations
# Files created:
#   machine-configs/cluster-template.yaml
#   machine-configs/talos-control-1.yaml
#   machine-configs/talos-worker-1.yaml

# 3. Apply configurations to Omni
./apply-machine-configs.sh

# Prompt: Apply this configuration to Omni? (yes/no): yes
# ✓ Cluster template applied successfully
```

**Result**: Machines now show in Omni with proper:
- ✅ Hostnames (talos-control-1, talos-worker-1, etc.)
- ✅ IP addresses (192.168.10.120, etc.)
- ✅ Roles (control-plane, worker, gpu-worker)
- ✅ Production configs (hostDNS, kubePrism, Longhorn mounts, GPU support)

📖 **Full Guide**: [scripts/README.md](scripts/README.md)

---

## Step 5: Create Cluster in Omni

Now create your cluster in the Omni UI:

1. Go to Omni UI → **Clusters** → **Create Cluster**
2. Machines now have friendly names (not UUIDs!)
3. Select machines by role:
   - **Control Planes**: Pick 3 machines (for HA)
   - **Workers**: Pick remaining machines
4. Configure:
   - Kubernetes version: v1.34.1
   - Talos version: v1.11.5
5. Click **Create**

Omni will install Talos to disk, configure everything, and bootstrap Kubernetes.

**Monitor progress**:
```bash
# Watch nodes come online
omnictl get machines --watch

# Once ready, get kubeconfig
omnictl kubeconfig > kubeconfig.yaml
export KUBECONFIG=kubeconfig.yaml

# Verify cluster
kubectl get nodes -o wide
kubectl get pods -A
```

---

## What Each Component Does

| Component | Purpose | Location |
|-----------|---------|----------|
| **Omni** | Cluster management UI + API | `sidero-omni/` |
| **Booter** | PXE boot server (serves Talos images) | `deployment-methods/pxe-boot/` |
| **Terraform** | Creates VMs in Proxmox | `terraform/` |
| **Scripts** | Matches VMs → Omni, generates configs | `scripts/` |

### How They Connect

```
Terraform                Booter                 Omni
   ↓                        ↓                     ↓
Creates VMs  →  VMs PXE boot into Talos  →  Talos registers with Omni
   ↓                                              ↓
Outputs MAC addresses              Scripts match by MAC address
                                             ↓
                                   Apply hostnames, IPs, configs
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Network (192.168.10.0/24)            │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │   Omni Host  │      │  Firewalla   │                     │
│  │ (Omni+Booter)│      │ (DHCP Server)│                     │
│  │ .10.15       │      │ .10.1        │                     │
│  └──────────────┘      └──────────────┘                     │
│         │                      │                             │
│         │ SideroLink          │ DHCP + PXE Proxy            │
│         │                      │                             │
│  ┌──────┴──────────────────────┴─────────┐                 │
│  │                                         │                 │
│  │         Proxmox Server(s)              │                 │
│  │                                         │                 │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐│                 │
│  │  │Control-1│  │Worker-1 │  │GPU      ││                 │
│  │  │.10.120  │  │.10.130  │  │Worker-1 ││                 │
│  │  │PXE Boot │  │PXE Boot │  │.10.140  ││                 │
│  │  └─────────┘  └─────────┘  └─────────┘│                 │
│  └─────────────────────────────────────────                 │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Common Issues

### VMs stuck in PXE boot loop

**Symptom**: VMs reboot endlessly at "Configuring (net0)..."

**Solution**: Check Booter configuration:
```bash
docker logs sidero-booter | grep -i dhcp

# Make sure:
# 1. --api-advertise-address is correct
# 2. --dhcp-proxy-iface-or-ip matches your interface (ip addr show)
# 3. Kernel args are correct (copy from Omni UI)
```

See: [PXE Boot Troubleshooting](deployment-methods/pxe-boot/README.md#troubleshooting)

### Scripts can't match machines

**Symptom**: `discover-machines.sh` shows "Not found in Omni"

**Solution**: Check MAC addresses match:
```bash
# From Terraform
cd terraform && terraform output mac_to_ip_mapping

# From Omni
omnictl get machinestatus -o json | jq '.[] | {uuid: .metadata.id, mac: .spec.network.networklinks[0].hardwareaddress}'
```

### Machines don't show hostnames after applying configs

**Solution**: Wait 2-3 minutes for configs to propagate, then check:
```bash
omnictl get machines -o json | jq '.[] | {uuid: .metadata.id, hostname: .metadata.labels["omni.sidero.dev/hostname"]}'
```

---

## Alternative Deployment Methods

This repo focuses on **Terraform + PXE** as the primary method, but we also document:

- **ISO Boot**: For networks without PXE support ([iso-templates/](deployment-methods/iso-templates/))
- **Omni Infrastructure Provider**: Auto-provision from Omni UI ([omni-provider/](deployment-methods/omni-provider/))

See: [deployment-methods/README.md](deployment-methods/README.md)

---

## GPU Worker Configuration

GPU workers are fully supported with:
- ✅ NVIDIA containerd runtime
- ✅ NVIDIA kernel modules (nvidia, nvidia_uvm, nvidia_drm, nvidia_modeset)
- ✅ GPU scheduling labels
- ✅ Longhorn storage mounts

The `generate-machine-configs.sh` script automatically adds GPU configs for any `gpu-worker` role machines.

**Manual GPU Passthrough** (required after Terraform):
```bash
# 1. SSH to Proxmox host
ssh root@pve1

# 2. Find GPU PCI ID
lspci | grep -i nvidia
# Example: 01:00.0 VGA compatible controller: NVIDIA Corporation ...

# 3. Find VM ID
qm list | grep talos-worker-gpu

# 4. Add GPU passthrough
qm set <VM_ID> -hostpci0 01:00,pcie=1

# 5. Reboot VM
qm reboot <VM_ID>
```

---

## Project Structure

```
.
├── sidero-omni/                      # Omni deployment (Docker Compose)
│   ├── docker-compose.yml            # Official Sidero Labs format
│   ├── setup-certificates.sh         # Let's Encrypt automation
│   └── README.md                     # Complete Omni setup guide
│
├── deployment-methods/
│   └── pxe-boot/                     # PXE boot with Booter
│       ├── docker-compose.yml        # Working Booter configuration
│       └── README.md                 # PXE setup + troubleshooting
│
├── terraform/                        # VM provisioning
│   ├── main.tf                       # Multi-server VM creation
│   ├── variables.tf                  # Flexible configuration
│   ├── terraform.tfvars.example      # Configuration template
│   └── README.md                     # Terraform guide
│
└── scripts/                          # Automation scripts
    ├── discover-machines.sh          # Match Terraform → Omni by MAC
    ├── generate-machine-configs.sh   # Generate cluster templates
    ├── apply-machine-configs.sh      # Apply to Omni
    └── README.md                     # Scripts workflow guide
```

---

## Credits & Links

- **Sidero Labs** - Creators of Talos Linux and Omni ([siderolabs.com](https://www.siderolabs.com))
- **Talos Linux** - Immutable Kubernetes OS ([talos.dev](https://www.talos.dev))
- **Sidero Omni** - Kubernetes cluster management ([omni.siderolabs.com](https://omni.siderolabs.com))
- **Proxmox VE** - Virtualization platform ([proxmox.com](https://www.proxmox.com))

---

## License

MIT License - Use freely, modify as needed, no warranty provided.

---

## Support & Contributions

**Issues**: Open a GitHub issue for bugs or questions
**PRs**: Contributions welcome! Keep the focus on simplicity.

**Philosophy**: This repo prioritizes **simplicity and clarity** over feature completeness. The goal is to help experienced devs get started quickly, not to cover every edge case.
