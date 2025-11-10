# Talos Deployment Methods

This repository supports deploying Talos Linux clusters on Proxmox with different boot methods.

## Primary Method: Terraform + PXE Boot (Recommended)

**This is the tested, documented, and recommended approach for this starter kit.**

### How It Works

```
1. Deploy Omni (management platform)          → cd sidero-omni && docker compose up
2. Deploy Booter (PXE boot server)            → cd deployment-methods/pxe-boot && docker compose up
3. Create VMs with Terraform                  → cd terraform && terraform apply
4. Match & configure with scripts             → cd scripts && ./discover-machines.sh
   ↓
Machines appear in Omni with proper names, IPs, and roles!
```

### Why This Method?

✅ **Simple** - 4 clear steps, well-documented
✅ **Automated** - Scripts handle UUID matching and cluster creation
✅ **No ISO management** - VMs network boot automatically
✅ **Production-ready** - Tested with control planes, workers, and GPU workers
✅ **Reproducible** - Terraform tracks infrastructure as code
✅ **Flexible** - Add machines to existing clusters or update configurations

### Quick Start

```bash
# 1. Deploy Omni (see sidero-omni/README.md)
cd sidero-omni
./check-prerequisites.sh
./install-docker.sh
sudo ./setup-certificates.sh
./generate-gpg-key.sh
cp .env.example omni.env
nano omni.env  # Configure
docker compose --env-file omni.env up -d

# 2. Deploy Booter
cd ../deployment-methods/pxe-boot
nano docker-compose.yml  # Update --api-advertise-address, --dhcp-proxy-iface-or-ip, kernel args
docker compose up -d

# 3. Create VMs
cd ../../terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Configure servers and VMs
terraform init
terraform apply

# 4. Match and configure machines
cd ../scripts
./discover-machines.sh
./generate-machine-configs.sh
./apply-machine-configs.sh

# 5. Cluster is created!
# Monitor cluster creation in Omni UI
# Machines have proper names and labels
```

### Components

- **Omni** - Cluster management UI and API ([setup guide](../sidero-omni/README.md))
- **Booter** - PXE boot server for network booting ([setup guide](pxe-boot/README.md))
- **Terraform** - VM provisioning on Proxmox ([setup guide](../terraform/README.md))
- **Scripts** - Automation for UUID → hostname/IP mapping ([setup guide](../scripts/README.md))

### Supported Features

✅ Multiple Proxmox servers
✅ Control planes, workers, GPU workers
✅ Automatic MAC address assignment
✅ DHCP reservations (recommended)
✅ Longhorn storage mounts
✅ NVIDIA GPU runtime configuration
✅ Production-ready cluster templates

**📁 Main Documentation**: See [root README.md](../README.md) for complete walkthrough

---

## Alternative: ISO Boot

If PXE boot doesn't work in your environment (network restrictions, isolated VLANs, etc.), you can use ISO boot instead.

### How It Works

```
1. Upload Talos ISO to Proxmox storage
2. Terraform creates VMs with ISO mounted
3. VMs boot from ISO instead of network
4. Rest of workflow is the same
```

### When to Use

- ✅ PXE boot not possible (network restrictions)
- ✅ Isolated networks/VLANs
- ✅ Prefer explicit boot media over network boot

### Quick Start

```bash
# 1. Download Talos ISO
wget https://github.com/siderolabs/talos/releases/download/v1.11.5/metal-amd64.iso

# 2. Upload to Proxmox
scp metal-amd64.iso root@pve1:/var/lib/vz/template/iso/talos-amd64.iso

# 3. Configure Terraform for ISO boot
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Set: boot_method = "iso"
# Set: talos_iso = "local:iso/talos-amd64.iso"

# 4. Continue with normal Terraform workflow
terraform init
terraform apply

# 5. Use scripts as usual
cd ../scripts
./discover-machines.sh
./generate-machine-configs.sh
./apply-machine-configs.sh
```

### Differences from PXE Boot

| Feature | PXE Boot | ISO Boot |
|---------|----------|----------|
| Setup | Booter + Terraform | ISO upload + Terraform |
| Network dependency | Required | Not required |
| Boot speed | Fast | Medium |
| ISO management | None | Manual upload/updates |
| Production ready | ✅ Yes | ✅ Yes |

**📁 Documentation**: See [terraform/README.md](../terraform/README.md#alternative-iso-boot-method)

---

## Experimental: Other Deployment Methods

The following methods are documented but may not be fully tested or maintained:

### ISO Templates

Create custom Talos ISOs with pre-baked extensions and clone VM templates.

**Status**: Documented but not the primary workflow
**📁 Directory**: [`iso-templates/`](iso-templates/)

**Use case**: If you prefer Proxmox UI cloning over Terraform

### Omni Infrastructure Provider

Auto-provision VMs directly from Omni UI using the official infrastructure provider.

**Status**: Documented but not the primary workflow
**📁 Directory**: [`omni-provider/`](omni-provider/)

**Use case**: If you want Omni to manage infrastructure provisioning

**Note**: These methods may require additional setup and testing. The primary workflow (Terraform + PXE Boot) is the recommended and most tested approach.

---

## Comparison Matrix

| Feature | Terraform + PXE | Terraform + ISO | ISO Templates | Omni Provider |
|---------|----------------|----------------|---------------|---------------|
| Status | ✅ Primary | ✅ Alternative | ⚠️ Experimental | ⚠️ Experimental |
| Documentation | ✅ Complete | ✅ Complete | ⚠️ Basic | ⚠️ Basic |
| Automation | ✅ Full | ✅ Full | ⚠️ Partial | ⚠️ Full |
| Learning curve | Medium | Medium | Low | Low |
| ISO management | None | Manual | Manual | None |
| GitOps ready | ✅ Yes | ✅ Yes | ❌ No | ⚠️ Partial |
| Multi-server | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| GPU support | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |

## Decision Guide

**Start here:**

1. **Are you following this repo's main guide?**
   → Use **Terraform + PXE Boot** (recommended)

2. **Does PXE boot not work in your network?**
   → Use **Terraform + ISO Boot** (alternative)

3. **Want to try something different?**
   → Explore **ISO Templates** or **Omni Provider** (experimental)

## Getting Started

Most users should follow the main README:

→ **[Root README.md](../README.md)** - Complete walkthrough of Terraform + PXE Boot method

For alternative methods, see their respective directories.

## Support

- **Primary method (PXE + Terraform)**: Fully documented and tested
- **Alternative methods**: Community contributions welcome!
- **Issues**: Open a GitHub issue if you encounter problems

## References

- [Sidero Omni Documentation](https://docs.siderolabs.com/omni/)
- [Talos Linux](https://www.talos.dev)
- [Siderolabs Booter](https://github.com/siderolabs/booter)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
