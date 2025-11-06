# Sidero Omni + Talos + Proxmox Starter Kit

A production-ready starter kit for deploying self-hosted Sidero Omni with fully automated Talos Linux cluster provisioning on Proxmox VE infrastructure.

## Overview

This repository provides a complete end-to-end solution for deploying and managing Talos Linux clusters:

1. **Self-Hosted Sidero Omni** - Production-ready Docker deployment with Auth0/SAML authentication
2. **Multi-Proxmox Terraform** - Automated VM provisioning across multiple Proxmox servers
3. **Omni Integration Scripts** - Automated machine discovery, configuration, and deployment via omnictl
4. **GPU Worker Support** - Complete GPU passthrough guide for GPU-accelerated workloads

### Key Features

- **Multi-Server Support**: Distribute VMs across 2-3+ Proxmox servers with automatic load balancing
- **Flexible Node Types**: Control planes, standard workers, and GPU workers with customizable resources
- **Secondary Disk Support**: Automatic secondary disk provisioning for Longhorn storage
- **MAC-Based IP Assignment**: Automated MAC address generation with DHCP reservation support
- **Static IP Configuration**: Dual-strategy IP assignment via DHCP reservations + Talos patches
- **GPU Passthrough**: Comprehensive guide for NVIDIA GPU passthrough configuration
- **Full Automation**: Complete workflow from infrastructure → VMs → configured Talos machines
- **Production Ready**: Based on official Siderolabs v1.3.0-beta.2+ format with real-world improvements

## Repository Structure

```
.
├── README.md                         # This file
├── sidero-omni/                      # Sidero Omni self-hosted deployment
│   ├── README.md                     # Comprehensive Omni deployment guide
│   ├── docker-compose.yml            # Official Siderolabs v1.3.0-beta.2 format
│   ├── .env.example                  # Environment variables template
│   ├── setup-certificates.sh         # Let's Encrypt + Cloudflare DNS automation
│   ├── generate-gpg-key.sh           # GPG key generation for etcd encryption
│   ├── install-docker.sh             # Docker installation automation
│   ├── check-prerequisites.sh        # Pre-deployment validation
│   └── cleanup-omni.sh               # Complete cleanup for fresh deployments
├── terraform/                        # Multi-Proxmox VM provisioning
│   ├── README.md                     # Terraform deployment guide
│   ├── main.tf                       # Multi-server VM creation with secondary disks
│   ├── variables.tf                  # Flexible per-VM configuration
│   ├── outputs.tf                    # Machine inventory for omnictl integration
│   └── terraform.tfvars.example      # Comprehensive configuration examples
├── scripts/                          # Omni integration automation
│   ├── README.md                     # Complete scripts workflow guide
│   ├── discover-machines.sh          # Match Terraform VMs to Omni-registered machines
│   ├── generate-machine-configs.sh   # Generate Talos Machine YAML configs
│   └── apply-machine-configs.sh      # Apply configurations via omnictl
├── docs/                             # Additional documentation
│   └── gpu-passthrough-guide.md      # Comprehensive GPU passthrough guide
└── bootstrap/                        # Legacy cluster bootstrap (deprecated)
    └── README.md                     # Use scripts/ for current workflow
```

## Quick Start

### Prerequisites

**Infrastructure**:
- 1x Ubuntu/Debian VM or mini PC (for Sidero Omni)
- 2-3x Proxmox VE servers (version 7.x or later)
- Network with DHCP server (Firewalla, pfSense, or router)

**Software**:
- Docker and Docker Compose (automated installation provided)
- Terraform 1.0+ ([install guide](https://www.terraform.io/downloads))
- omnictl ([install guide](https://www.siderolabs.com/omni/docs/cli/))
- jq (JSON processor): `sudo apt-get install jq`

**Services**:
- Domain name with Cloudflare DNS management
- Auth0 account for authentication (free tier works)
- Proxmox API tokens for Terraform

### Complete Deployment Workflow

This starter kit uses a **three-phase deployment** approach:

```
Phase 1: Deploy Sidero Omni (Management Platform)
    ↓
Phase 2: Provision VMs with Terraform (Infrastructure)
    ↓
Phase 3: Configure Machines with Scripts (Automation)
    ↓
Phase 4: Create Cluster in Omni UI (Cluster Deployment)
```

---

## Phase 1: Deploy Sidero Omni

Deploy the Omni management platform on a dedicated VM or mini PC:

```bash
# Navigate to Omni directory
cd sidero-omni

# Check prerequisites
./check-prerequisites.sh

# Install Docker (if needed)
./install-docker.sh

# Set up SSL certificates (Let's Encrypt + Cloudflare DNS)
sudo ./setup-certificates.sh

# Generate GPG key for etcd encryption
./generate-gpg-key.sh

# Configure environment variables
cp .env.example omni.env
nano omni.env
# Edit: OMNI_ACCOUNT_UUID, NAME, domain, Auth0 credentials

# Deploy Omni
docker compose --env-file omni.env up -d

# Verify deployment
docker logs omni
```

**Validation**:
- Access Omni UI: `https://your-domain.com`
- Login with Auth0
- Verify no errors in logs

See [sidero-omni/README.md](sidero-omni/README.md) for detailed instructions and troubleshooting.

---

## Phase 2: Provision VMs with Terraform

Create Talos VMs across multiple Proxmox servers:

```bash
# Navigate to Terraform directory
cd terraform

# Configure your infrastructure
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# Edit configuration:
# - Proxmox server details (API URLs, tokens, storage)
# - Control plane VMs (recommend 1 per Proxmox server for HA)
# - Worker VMs (distribute across servers)
# - GPU worker VMs (optional, for GPU workloads)
# - Network configuration (subnet, gateway, DNS)

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Create VMs
terraform apply

# Get machine inventory
terraform output machine_inventory
terraform output dhcp_reservations_table
```

**Validation**:
- VMs created in Proxmox
- VMs booted and running Talos Linux
- After 2-5 minutes, machines registered in Omni UI

**Configure DHCP Reservations** (Recommended):
```bash
# Get formatted DHCP reservations
terraform output dhcp_reservations_table

# Add these MAC→IP mappings to your router/DHCP server
# This ensures machines get consistent IPs on boot
```

See [terraform/README.md](terraform/README.md) for detailed configuration options.

---

## Phase 3: Configure Machines with Scripts

Automatically discover machines and apply configurations via omnictl:

```bash
# Navigate to scripts directory
cd ../scripts

# Step 1: Discover and match machines
./discover-machines.sh
# - Queries Omni API for registered machines
# - Matches to Terraform inventory by MAC address
# - Creates machine UUID mapping files

# Step 2: Generate machine configurations
./generate-machine-configs.sh
# - Creates Talos Machine YAML documents
# - Generates network patches (static IPs, hostnames)
# - Adds secondary disk mounts for Longhorn
# - Includes GPU driver extensions for GPU workers

# Step 3: Apply configurations to Omni
./apply-machine-configs.sh
# - Shows configuration preview
# - Applies via 'omnictl cluster template sync'
# - Verifies application

# Verify machines have static IPs and hostnames
omnictl get machines -o wide
```

**Validation**:
- Machines show correct hostnames in Omni UI
- Static IPs applied (check machine network configuration)
- Configuration patches visible in Omni

See [scripts/README.md](scripts/README.md) for detailed workflow and troubleshooting.

---

## Phase 4: GPU Passthrough (GPU Workers Only)

For GPU workers, manually configure GPU passthrough in Proxmox:

```bash
# Get GPU configuration instructions
cd ../terraform
terraform output gpu_configuration_needed

# Follow the comprehensive guide
# See docs/gpu-passthrough-guide.md for step-by-step instructions:
# 1. Enable IOMMU/VT-d in BIOS
# 2. Configure Proxmox host for GPU passthrough
# 3. Identify GPU PCI addresses
# 4. Add GPU to VM configuration
# 5. Verify GPU visibility in Talos
```

See [docs/gpu-passthrough-guide.md](docs/gpu-passthrough-guide.md) for complete GPU passthrough guide.

---

## Phase 5: Create Cluster in Omni

Use the Omni UI to create your Kubernetes cluster:

1. **Navigate to Omni UI**: `https://your-domain.com`
2. **Go to Clusters** → **Create Cluster**
3. **Select Machines**:
   - Control Planes: Select your `talos-cp-*` machines
   - Workers: Select your `talos-worker-*` and `talos-gpu-*` machines
4. **Configure Cluster**:
   - Cluster name: `talos-cluster`
   - Kubernetes version: Latest
   - CNI: Cilium (recommended) or Flannel
5. **Create** and wait for cluster initialization (5-10 minutes)

**Get kubeconfig**:
```bash
omnictl kubeconfig -c talos-cluster > kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

**Optional**: Install NVIDIA GPU Operator (for GPU workers):
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace
```

## Architecture

### Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Your Network (192.168.10.0/24)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐         ┌─────────────────────────────┐  │
│  │  Omni Server     │         │  Proxmox Cluster            │  │
│  │  (Docker)        │         │                             │  │
│  │                  │         │  ┌───────────┐ ┌──────────┐ │  │
│  │  - Omni UI       │◄────────┤  │  PVE 1    │ │  PVE 2   │ │  │
│  │  - Omni API      │         │  │           │ │          │ │  │
│  │  - SideroLink    │         │  │ Talos VMs │ │Talos VMs │ │  │
│  │  - etcd          │         │  │  - CP 1   │ │ - CP 2   │ │  │
│  │                  │         │  │  - Wkr 1  │ │ - Wkr 2  │ │  │
│  └──────────────────┘         │  └───────────┘ └──────────┘ │  │
│         ▲                     │                             │  │
│         │                     │  ┌───────────┐              │  │
│         │                     │  │  PVE 3    │              │  │
│         │                     │  │           │              │  │
│         │                     │  │ Talos VMs │              │  │
│         │                     │  │  - CP 3   │              │  │
│         │                     │  │  - GPU 1  │              │  │
│         │                     │  └───────────┘              │  │
│         │                     └─────────────────────────────┘  │
│         │                              │                        │
│         └──────────────────────────────┘                        │
│              SideroLink (WireGuard)                             │
└─────────────────────────────────────────────────────────────────┘
```

### Components

**1. Sidero Omni (Management Platform)**
- **Location**: Dedicated Ubuntu/Debian VM or mini PC
- **Deployment**: Docker Compose (official Siderolabs v1.3.0-beta.2 format)
- **Components**:
  - Web UI for cluster management (HTTPS on port 443)
  - REST API for automation via omnictl
  - SideroLink (WireGuard VPN on port 50180) for machine communication
  - Embedded etcd with GPG encryption for data storage
  - Auth0/SAML authentication
- **Storage**: Local etcd directory with automated backups

**2. Proxmox VE Cluster (Infrastructure)**
- **Servers**: 2-3+ Proxmox nodes
- **Networking**: Bridge mode (vmbr0) with VLAN support
- **Storage**: Flexible per-server storage pools (local-lvm, NFS, Ceph)
- **Virtualization**: QEMU/KVM with optional GPU passthrough

**3. Talos Linux VMs (Kubernetes Nodes)**
- **OS**: Immutable, API-managed Kubernetes OS
- **Management**: No SSH, controlled via Omni/talosctl only
- **Node Types**:
  - **Control Planes**: 3+ nodes (odd number for etcd quorum)
  - **Workers**: Standard compute nodes
  - **GPU Workers**: NVIDIA GPU passthrough for accelerated workloads
- **Storage**:
  - OS disk: `/dev/sda` (Talos system)
  - Data disk: `/dev/sdb` (Longhorn persistent volumes)

### Workflow Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Terraform  │────▶│   Proxmox    │────▶│ Talos VMs    │
│              │     │              │     │              │
│ - Creates VMs│     │ - Runs VMs   │     │ - Boot Talos │
│ - Sets MACs  │     │ - Provides   │     │ - Register   │
│ - Inventory  │     │   Resources  │     │   to Omni    │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Scripts    │────▶│    Omni      │────▶│  Configured  │
│              │     │              │     │   Machines   │
│ - Discovery  │     │ - Receives   │     │              │
│ - Config Gen │     │   Patches    │     │ - Static IPs │
│ - Apply      │     │ - Applies    │     │ - Hostnames  │
│              │     │   Configs    │     │ - Storage    │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
                                          ┌──────────────┐
                                          │  Kubernetes  │
                                          │   Cluster    │
                                          │              │
                                          │ - Ready for  │
                                          │   Workloads  │
                                          └──────────────┘
```

### Network Configuration Strategy

**Dual-Strategy IP Assignment**:

1. **DHCP Reservations** (Primary, Recommended):
   - Terraform generates unique MAC addresses
   - User configures router/DHCP server with MAC→IP mappings
   - VMs get consistent IPs on boot via DHCP
   - Works with Firewalla, pfSense, UniFi, etc.

2. **Talos Static IP Patches** (Backup):
   - Applied via Omni machine configuration patches
   - Direct static IP configuration in Talos
   - Redundant if DHCP reservations work
   - Ensures IP consistency even if DHCP fails

**DNS Configuration**:
- Configured via Terraform variables
- Applied to machines via Talos patches
- Default: Cloudflare (1.1.1.1) + Google (8.8.8.8)

### Machine Configuration

**Flexible Per-VM Configuration**:
```hcl
control_planes = [
  {
    name              = "talos-cp-1"      # Hostname
    proxmox_server    = "pve1"            # Which Proxmox server
    ip_address        = "192.168.10.100"  # Static IP
    mac_address       = ""                # Auto-generated or custom
    cpu_cores         = 4
    memory_mb         = 8192
    os_disk_size_gb   = 50                # sda: Talos OS
    data_disk_size_gb = 100               # sdb: Longhorn storage
  }
]
```

**Node Distribution Recommendations**:
- **Control Planes**: 1 per Proxmox server (odd total for quorum)
  - 1 server = 1 control plane
  - 2 servers = 3 control planes (2+1 or 1+2)
  - 3 servers = 3 control planes (1+1+1)
  - 5+ servers = 5 control planes
- **Workers**: Distribute based on workload requirements
- **GPU Workers**: Place on servers with available GPUs

## Troubleshooting

### Common Issues

**Issue**: VMs not registering with Omni
- **Check**: VMs have network connectivity
- **Check**: SideroLink port 50180/UDP is open in firewall
- **Check**: Omni container is running: `docker logs omni`
- **Solution**: Wait 2-5 minutes for initial boot and registration

**Issue**: Static IPs not applied
- **Check**: DHCP reservations configured correctly
- **Check**: Machine patches applied: `omnictl get configpatches`
- **Solution**: Reboot machines after applying patches

**Issue**: GPU not visible in VM
- **Check**: IOMMU enabled in BIOS
- **Check**: GPU bound to VFIO driver (not host driver)
- **Check**: VM configuration: `cat /etc/pve/qemu-server/<VMID>.conf`
- **Solution**: See [GPU Passthrough Guide](docs/gpu-passthrough-guide.md)

**Issue**: Terraform apply fails with storage error
- **Check**: Storage pool names match Proxmox configuration
- **Check**: Sufficient space in storage pools
- **Solution**: Verify `storage_os` and `storage_data` in terraform.tfvars

For detailed troubleshooting, see component-specific READMEs:
- [Omni Troubleshooting](sidero-omni/README.md#troubleshooting)
- [Terraform Troubleshooting](terraform/README.md#troubleshooting)
- [Scripts Troubleshooting](scripts/README.md#troubleshooting)

## Advanced Topics

### Multi-Cluster Deployment

This starter kit can be used to deploy multiple isolated clusters:

1. Use different Terraform workspaces for each cluster
2. Assign different IP ranges per cluster
3. Use Omni to manage multiple clusters from single control plane

### High Availability Considerations

- **Control Plane HA**: Always use odd number (3, 5, 7) for etcd quorum
- **Worker HA**: Distribute workers across multiple Proxmox servers
- **Storage HA**: Use Longhorn with replication factor 3
- **Network HA**: Configure bonded network interfaces in Proxmox

### Integration with GitOps

After cluster creation, integrate with GitOps workflows:

```bash
# Install Flux
flux bootstrap github \
  --owner=your-org \
  --repository=fleet-infra \
  --path=clusters/talos-cluster

# Or install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Documentation

### This Repository
- [Sidero Omni Deployment Guide](sidero-omni/README.md) - Complete Omni setup instructions
- [Terraform Configuration Guide](terraform/README.md) - VM provisioning and configuration
- [Scripts Workflow Guide](scripts/README.md) - Machine discovery and configuration
- [GPU Passthrough Guide](docs/gpu-passthrough-guide.md) - GPU configuration for workers
- [Project Notes](PROJECT.md) - Development roadmap and technical decisions

### Official Documentation
- [Sidero Omni Documentation](https://www.siderolabs.com/omni/docs/)
- [Talos Linux Documentation](https://www.talos.dev/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Omni Cluster Templates Reference](https://www.siderolabs.com/omni/docs/reference/cluster-templates/)
- [omnictl CLI Reference](https://www.siderolabs.com/omni/docs/cli/)

## Project Status

### Completed Features
- ✅ Self-hosted Omni deployment with Docker Compose (v1.3.0-beta.2)
- ✅ Multi-Proxmox server support with flexible VM distribution
- ✅ Automated MAC address generation with DHCP reservation support
- ✅ Secondary disk provisioning for Longhorn storage
- ✅ Automated machine discovery and UUID matching
- ✅ Machine configuration generation with Talos patches
- ✅ Static IP and hostname configuration via omnictl
- ✅ GPU worker support with comprehensive passthrough guide
- ✅ Complete automation scripts (discover, generate, apply)

### Roadmap
- 🔄 Talos template VM creation guide
- 🔄 Automated cluster creation via cluster templates
- 🔄 Backup and restore procedures
- 🔄 Monitoring stack integration (Prometheus, Grafana)
- 🔄 Disaster recovery documentation
- 🔄 Multi-cluster federation examples

### Testing Status
- ⚠️ Scripts tested with real-world deployment (v1.3.0-beta.1)
- ⚠️ Terraform tested with 3-server Proxmox cluster
- ⚠️ GPU passthrough validated with NVIDIA RTX GPUs
- 📝 Community testing and feedback welcome

## Contributing

Contributions are welcome! Areas where contributions would be valuable:

- Testing with different Proxmox storage backends (Ceph, NFS)
- Testing with AMD GPUs
- Additional cluster template examples
- Monitoring and logging integrations
- Backup automation scripts

Please feel free to submit issues or pull requests.

## Acknowledgments

- Built on [Siderolabs Omni](https://www.siderolabs.com/omni/) official v1.3.0-beta.2 format
- Incorporates real-world deployment experience and troubleshooting
- Inspired by community discussions on GitHub and Discord

## License

This project is provided as-is for use as a starter template. See component licenses:
- Sidero Omni: [Siderolabs License](https://www.siderolabs.com/)
- Talos Linux: Apache 2.0
- Terraform: MPL 2.0
