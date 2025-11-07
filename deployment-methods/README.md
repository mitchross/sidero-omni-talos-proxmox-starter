# Talos Cluster Deployment Methods

This repository supports **four different approaches** to deploy Talos Linux clusters on Proxmox. Choose the method that best fits your needs and skill level.

## Quick Comparison

| Method | Difficulty | Automation | Flexibility | Best For |
|--------|-----------|------------|-------------|----------|
| [**Omni Provider**](#1-omni-infrastructure-provider-easiest) | ⭐ Easy | 🤖 Fully Automated | ⚙️ Medium | **Recommended for most users** |
| [**ISO Templates**](#2-iso-templates-simple) | ⭐⭐ Simple | 👆 Manual Cloning | ⚙️⚙️ Medium | Proxmox UI comfort, small clusters |
| [**Terraform**](#3-terraform-advanced) | ⭐⭐⭐ Advanced | 🤖 Fully Automated | ⚙️⚙️⚙️ Very High | IaC experts, large deployments |
| [**PXE Boot**](#4-pxe-boot-booter-specialized) | ⭐⭐⭐⭐ Expert | 🤖 Network Boot | ⚙️⚙️ Medium | Bare metal, PXE infrastructure |

---

## 1. Omni Infrastructure Provider (EASIEST) ✨

**NEW in 2025!** Official Siderolabs tool that auto-provisions VMs directly from Omni UI.

### How It Works
```
You → Omni UI → Define Machine Class → Click "Scale Up" → VMs Created Automatically!
         ↓
   Proxmox Provider ← Talks to Proxmox API
         ↓
   New VMs appear in Proxmox (fully configured)
```

### Pros
- ✅ **Easiest method** - Everything in Omni UI
- ✅ **No Terraform/HCL knowledge** required
- ✅ **Auto-scaling** - Add/remove nodes with a click
- ✅ **Official Siderolabs** support
- ✅ **GPU support** via machine class extensions

### Cons
- ⚠️ Requires self-hosted Omni (already part of this repo)
- ⚠️ Less granular control than Terraform
- ⚠️ Network configuration via Omni, not DHCP reservations

### When to Use
- ✅ You already have Omni running (Phase 1 of this guide)
- ✅ You want the simplest deployment
- ✅ You're okay with Omni managing the infrastructure

### Quick Start
```bash
cd deployment-methods/omni-provider
./setup-provider.sh
# Follow prompts, then use Omni UI to create machines
```

**📁 Directory**: [`omni-provider/`](omni-provider/)

---

## 2. ISO Templates (SIMPLE) 📀

Create custom Talos ISOs with pre-baked NVIDIA drivers, then clone VM templates in Proxmox UI.

### How It Works
```
1. Generate 3 custom ISOs via Talos Image Factory
   - Control Plane ISO
   - Worker ISO
   - GPU Worker ISO (with NVIDIA drivers pre-installed)

2. Create Proxmox VM templates from ISOs

3. Clone templates in Proxmox UI (right-click → Clone)

4. Run bash script to configure machines via omnictl
```

### Pros
- ✅ **No Terraform** - Pure Proxmox UI
- ✅ **GPU drivers pre-installed** in ISO
- ✅ **Simple bash scripts** instead of HCL
- ✅ **Fast cloning** from templates
- ✅ **Visual** - See VMs in Proxmox UI

### Cons
- ⚠️ Manual VM creation (clone each VM)
- ⚠️ Less reproducible than code
- ⚠️ Need to maintain custom ISOs

### When to Use
- ✅ You prefer Proxmox UI over code
- ✅ Small clusters (< 10 VMs)
- ✅ You have GPU workers (drivers pre-baked)
- ✅ You're comfortable with bash

### Quick Start
```bash
cd deployment-methods/iso-templates
./generate-isos.sh          # Creates custom ISOs
./create-templates.sh       # Creates Proxmox templates
# Clone VMs in Proxmox UI
./configure-cluster.sh      # Applies configs via omnictl
```

**📁 Directory**: [`iso-templates/`](iso-templates/)

---

## 3. Terraform (ADVANCED) 🏗️

Full Infrastructure as Code with Terraform HCL.

### How It Works
```
terraform.tfvars → Terraform → Proxmox API → VMs Created
                      ↓
              State tracked in .tfstate
                      ↓
            Scripts configure via omnictl
```

### Pros
- ✅ **Full IaC** - Everything in code
- ✅ **Highly reproducible** - Same config = same result
- ✅ **Version controlled** - Git tracks all changes
- ✅ **Advanced features** - Conditionals, loops, modules
- ✅ **Multi-environment** - Dev/Staging/Prod workspaces

### Cons
- ⚠️ **Steepest learning curve** - Must know Terraform/HCL
- ⚠️ **State management** - Need to track .tfstate file
- ⚠️ **Over-engineering** for small deployments

### When to Use
- ✅ You already know Terraform
- ✅ Large deployments (10+ VMs)
- ✅ Need reproducibility and GitOps
- ✅ Managing multiple environments
- ✅ Want full automation

### Quick Start
```bash
cd terraform
./recommend-cluster.sh      # Auto-generates config
terraform init
terraform apply
cd ../scripts
./discover-machines.sh      # Configure via omnictl
./generate-machine-configs.sh
./apply-machine-configs.sh
```

**📁 Directory**: [`../terraform/`](../terraform/)

---

## 4. PXE Boot (Booter) - SPECIALIZED 🌐

Network boot Talos machines using Siderolabs Booter.

### How It Works
```
1. Run Booter container on network
2. Configure VMs to PXE boot
3. Power on VMs → Auto-download Talos → Boot
4. Machines register with Omni automatically
```

### Pros
- ✅ **No ISO management** - Everything over network
- ✅ **Fast provisioning** - Boot from network
- ✅ **Diskless boot** possible
- ✅ **Bare metal ready** - Works on physical servers

### Cons
- ⚠️ **Requires PXE infrastructure** - DHCP, TFTP, etc.
- ⚠️ **Network dependent** - Must be on same subnet
- ⚠️ **Complexity** - More moving parts

### When to Use
- ✅ You have existing PXE infrastructure
- ✅ Deploying bare metal servers
- ✅ Need rapid provisioning
- ✅ Diskless or thin client deployments

### Quick Start
```bash
cd deployment-methods/pxe-boot
./setup-booter.sh
# Configure VMs to PXE boot, power on
```

**📁 Directory**: [`pxe-boot/`](pxe-boot/)

---

## Decision Tree

```
Start Here
    │
    ├─ Do you have Omni running?
    │  ├─ YES → Use Omni Infrastructure Provider ✨
    │  └─ NO  → Do you want the simplest deployment?
    │           ├─ YES → Use ISO Templates 📀
    │           └─ NO  → Continue...
    │
    ├─ Do you know Terraform?
    │  ├─ YES → Are you deploying > 10 VMs?
    │  │        ├─ YES → Use Terraform 🏗️
    │  │        └─ NO  → Use ISO Templates or Omni Provider
    │  └─ NO  → Use ISO Templates 📀
    │
    └─ Do you have PXE infrastructure?
       ├─ YES → Use PXE Boot (Booter) 🌐
       └─ NO  → Use one of the above methods
```

## Recommended Path for New Users

1. **Start with Omni Infrastructure Provider** if you have Omni
2. **Fall back to ISO Templates** if you want simplicity without Omni provider
3. **Use Terraform** if you're scaling or need IaC
4. **Use PXE/Booter** only if you have specific PXE requirements

## Feature Matrix

| Feature | Omni Provider | ISO Templates | Terraform | PXE Boot |
|---------|--------------|---------------|-----------|----------|
| Auto-scaling | ✅ Yes | ❌ No | ⚙️ Manual | ❌ No |
| GPU pre-configured | ✅ Via extensions | ✅ In ISO | ⚠️ Post-install | ✅ Via extensions |
| Multi-server | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| DHCP reservations | ⚠️ Not needed | ✅ Yes | ✅ Yes | ⚠️ Not needed |
| GitOps ready | ⚙️ Partial | ❌ No | ✅ Yes | ❌ No |
| Requires code | ❌ No | ⚠️ Bash only | ✅ HCL | ⚠️ Minimal |
| State management | ✅ Omni handles | ❌ None | ⚠️ .tfstate | ❌ None |

## Next Steps

Choose your deployment method above and follow the guide in its respective directory:

- **[omni-provider/](omni-provider/)** - Omni Infrastructure Provider setup
- **[iso-templates/](iso-templates/)** - Custom ISO creation and templates
- **[../terraform/](../terraform/)** - Terraform configuration (existing)
- **[pxe-boot/](pxe-boot/)** - PXE boot with Booter

## Support & Resources

- [Omni Infrastructure Provider Docs](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [Talos Image Factory](https://factory.talos.dev)
- [Siderolabs Booter](https://github.com/siderolabs/booter)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)

## Questions?

See [../README.md](../README.md) for the main project documentation, or open an issue on GitHub.
