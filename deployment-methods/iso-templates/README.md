# ISO Templates Deployment Method

**📀 Simple approach** - Create custom Talos ISOs with GPU drivers pre-installed, then clone VM templates in Proxmox UI.

## Overview

Instead of Terraform's complex HCL syntax, this method uses:
1. **Custom ISOs** generated from Talos Image Factory (GPU drivers pre-baked!)
2. **Proxmox VM templates** created once, cloned many times
3. **Simple bash scripts** for configuration (no Terraform knowledge needed)

Perfect for users comfortable with Proxmox UI but not ready for full IaC.

## Prerequisites

- ✅ Proxmox VE 7.x+ with web UI access
- ✅ Internet access (to download ISOs from factory.talos.dev)
- ✅ Omni deployed (see [../../sidero-omni/README.md](../../sidero-omni/README.md))
- ✅ omnictl installed ([install guide](https://www.siderolabs.com/omni/docs/cli/))
- ✅ jq installed: `sudo apt-get install jq`

## Why This Method?

✅ **No Terraform** - Just bash scripts and Proxmox UI
✅ **GPU drivers pre-installed** - In the ISO itself!
✅ **Visual** - See and manage VMs in Proxmox UI
✅ **Fast cloning** - Create new VMs in seconds
✅ **Simpler** - Less moving parts than Terraform

## The Three ISOs

We create 3 custom Talos ISOs, each tailored for a specific node type:

### 1. Control Plane ISO
- Base Talos Linux
- QEMU Guest Agent (for Proxmox integration)
- Minimal footprint

### 2. Worker ISO
- Base Talos Linux
- QEMU Guest Agent
- Standard configuration

### 3. GPU Worker ISO ⭐
- Base Talos Linux
- QEMU Guest Agent
- **NVIDIA drivers (proprietary)**
- **NVIDIA Container Toolkit**
- **Pre-configured for GPU workloads**

This is the **killer feature** - GPU drivers baked into the ISO means no post-install configuration!

---

## Setup Guide

### Step 1: Generate Custom ISOs

Run the automated ISO generation script:

```bash
./scripts/generate-isos.sh
```

This script:
1. Creates schematic YAML files for each node type
2. Uploads them to Talos Image Factory (factory.talos.dev)
3. Downloads custom ISOs with extensions pre-installed
4. Saves ISOs to `./isos/` directory

**Output**:
```
isos/
├── talos-control-plane-v1.10.1.iso
├── talos-worker-v1.10.1.iso
└── talos-gpu-worker-v1.10.1.iso
```

**Note**: ISOs are ~200-300MB each. GPU ISO is slightly larger due to NVIDIA drivers.

### Step 2: Upload ISOs to Proxmox

#### Option A: Via Proxmox UI (Easiest)

1. Open Proxmox web UI: `https://your-proxmox:8006`
2. Select your Proxmox node (e.g., `pve1`)
3. Go to **local** storage → **ISO Images** → **Upload**
4. Upload all 3 ISOs

#### Option B: Via SCP (Faster)

```bash
# Upload to each Proxmox server
scp isos/*.iso root@pve1:/var/lib/vz/template/iso/
scp isos/*.iso root@pve2:/var/lib/vz/template/iso/
scp isos/*.iso root@pve3:/var/lib/vz/template/iso/
```

### Step 3: Create VM Templates

Run the template creation script:

```bash
./scripts/create-templates.sh
```

This creates 3 VM templates in Proxmox:
- `talos-control-plane-template`
- `talos-worker-template`
- `talos-gpu-worker-template`

Each template is pre-configured with:
- CPU, RAM, disk sizes (optimized for role)
- Network configuration (vmbr0)
- Boot from ISO
- QEMU Guest Agent enabled

**Or manually** (if you prefer):

See [MANUAL_TEMPLATE_CREATION.md](./MANUAL_TEMPLATE_CREATION.md) for step-by-step Proxmox UI guide.

### Step 4: Clone VMs from Templates

In Proxmox UI:

1. **Right-click on template** → **Clone**
2. **VM ID**: 100 (or auto-assign)
3. **Name**: `talos-cp-1`
4. **Mode**: Full Clone
5. **Target Storage**: Same as template
6. Click **Clone**

Repeat for all nodes:
- 3x Control Planes: `talos-cp-1`, `talos-cp-2`, `talos-cp-3`
- 5x Workers: `talos-worker-1` through `talos-worker-5`
- 2x GPU Workers: `talos-gpu-1`, `talos-gpu-2`

**Pro Tip**: Distribute across Proxmox servers for HA!

### Step 5: Start VMs

In Proxmox UI:
1. Select each VM
2. Click **Start**
3. VMs boot Talos Linux from ISO
4. After 2-3 minutes, VMs register with Omni automatically

**Verify** in Omni UI:
- Go to **Machines**
- You should see all VMs listed (with random names initially)

### Step 6: Configure Machines

Now that VMs are running and registered, configure them via omnictl:

```bash
./scripts/configure-cluster.sh
```

This script:
1. Queries Omni API for registered machines
2. Prompts you to map VMs to roles (control-plane, worker, gpu-worker)
3. Generates Talos machine configs with:
   - Static IPs
   - Hostnames
   - Secondary disk mounts (if applicable)
   - GPU extensions (already in ISO, but verified here)
4. Applies configs via omnictl

**Interactive prompts**:
```
Found 10 machines in Omni:

  1. 3c:f0:11:8a:2b:c1 (192.168.10.45)
  2. 3c:f0:11:8a:2b:c2 (192.168.10.46)
  ...

Which is talos-cp-1? (enter number): 1
Assign IP for talos-cp-1 (default 192.168.10.100): [press enter]
```

---

## GPU Worker Configuration

The GPU ISO has drivers pre-installed, but you still need to **manually configure GPU passthrough** in Proxmox:

### Step 1: Identify VMs with GPUs

```bash
# After running configure-cluster.sh
cat machine-data/gpu-workers.txt

# Shows:
# talos-gpu-1 → VM ID 105 on pve3
# talos-gpu-2 → VM ID 106 on pve2
```

### Step 2: Configure GPU Passthrough

For each GPU worker:

```bash
# SSH to Proxmox server
ssh root@pve3

# Find GPU PCI ID
lspci | grep -i nvidia
# Output: 01:00.0 VGA compatible controller: NVIDIA ...

# Stop VM
qm stop 105

# Add GPU to VM
qm set 105 -hostpci0 01:00,pcie=1,x-vga=0

# Start VM
qm start 105
```

See [../../docs/gpu-passthrough-guide.md](../../docs/gpu-passthrough-guide.md) for complete GPU setup.

---

## File Structure

```
iso-templates/
├── README.md                   # This file
├── schematics/                 # Talos Image Factory schematics
│   ├── control-plane.yaml
│   ├── worker.yaml
│   └── gpu-worker.yaml
├── scripts/
│   ├── generate-isos.sh        # Downloads custom ISOs
│   ├── create-templates.sh     # Creates Proxmox templates
│   └── configure-cluster.sh    # Configures via omnictl
├── isos/                       # Downloaded ISOs (not in git)
│   ├── talos-control-plane-*.iso
│   ├── talos-worker-*.iso
│   └── talos-gpu-worker-*.iso
└── machine-data/               # Generated during config (not in git)
    ├── machine-mapping.json
    └── gpu-workers.txt
```

---

## Example Schematic (GPU Worker)

```yaml
# schematics/gpu-worker.yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/qemu-guest-agent
      - siderolabs/nonfree-kmod-nvidia-production
      - siderolabs/nvidia-container-toolkit-production
```

This gets uploaded to factory.talos.dev, which builds a custom ISO with all extensions pre-installed.

---

## Advantages Over Terraform

| Feature | ISO Templates | Terraform |
|---------|--------------|-----------|
| **Learning Curve** | ⭐ Low (Proxmox UI) | ⭐⭐⭐ High (HCL) |
| **GPU Drivers** | ✅ Pre-installed in ISO | ⚠️ Applied after |
| **VM Creation** | Manual clone (visual) | Automated (code) |
| **Reproducibility** | ⚙️ Medium | ✅ High |
| **State Management** | None | .tfstate file |
| **Scaling** | Manual clone each VM | `count = 10` |

**Best for**:
- Small clusters (< 10 VMs)
- Users comfortable with Proxmox UI
- GPU workloads (drivers pre-baked)
- One-time deployments

**Not ideal for**:
- Large clusters (> 10 VMs)
- Frequent re-deployments
- GitOps workflows
- Multi-environment (dev/staging/prod)

---

## Workflow Diagram

```
1. Generate ISOs           2. Upload to Proxmox      3. Create Templates
   (factory.talos.dev)        (Web UI or SCP)           (Proxmox UI or script)
         ↓                           ↓                          ↓
   ┌─────────────┐           ┌──────────────┐          ┌──────────────┐
   │ Control ISO │──────────▶│ Proxmox      │─────────▶│ Template     │
   │ Worker ISO  │           │ ISO Storage  │          │ (VM 9000)    │
   │ GPU ISO     │           │              │          │              │
   └─────────────┘           └──────────────┘          └──────────────┘
                                                                ↓
4. Clone VMs               5. Start VMs              6. Configure via omnictl
   (Right-click → Clone)      (Proxmox UI)              (./configure-cluster.sh)
         ↓                           ↓                          ↓
   ┌──────────────┐           ┌──────────────┐          ┌──────────────┐
   │ talos-cp-1   │──────────▶│ VMs Running  │─────────▶│ Configured   │
   │ talos-cp-2   │           │ Talos Linux  │          │ Cluster      │
   │ talos-worker │           │              │          │ Ready!       │
   └──────────────┘           └──────────────┘          └──────────────┘
```

---

## Updating Talos Version

To update to a new Talos version:

```bash
# Edit schematics to specify new version
nano schematics/control-plane.yaml
# Change: version: v1.10.1 → v1.11.0

# Regenerate ISOs
./scripts/generate-isos.sh

# Upload new ISOs to Proxmox
scp isos/*.iso root@pve1:/var/lib/vz/template/iso/

# Update templates (or create new ones)
./scripts/create-templates.sh

# Clone new VMs from updated templates
```

---

## Troubleshooting

### ISOs not downloading

**Check**:
```bash
# Test Image Factory connectivity
curl -I https://factory.talos.dev

# Check schematic upload
cat schematics/control-plane.yaml | curl -X POST --data-binary @- https://factory.talos.dev/schematics
```

### VMs not booting from ISO

**Check in Proxmox UI**:
1. VM → Hardware → CD/DVD Drive
2. Should show: `talos-*.iso`
3. Boot Order: CD-ROM should be first

### VMs not registering with Omni

**Check**:
1. VMs have network connectivity
2. Can reach Omni SideroLink: `telnet your-omni-domain.com 50180`
3. Check Omni logs: `docker logs omni`

### GPU not working after passthrough

See [../../docs/gpu-passthrough-guide.md](../../docs/gpu-passthrough-guide.md) troubleshooting section.

---

## Next Steps

After VMs are configured:

1. **Create cluster** in Omni UI
2. **Select machines** (your configured VMs)
3. **Deploy** - Omni forms Kubernetes cluster
4. **Get kubeconfig**: `omnictl kubeconfig -c talos-cluster > kubeconfig`
5. **Deploy workloads**!

---

## Resources

- [Talos Image Factory](https://factory.talos.dev)
- [Talos System Extensions](https://github.com/siderolabs/extensions)
- [Main README](../../README.md)
- [GPU Passthrough Guide](../../docs/gpu-passthrough-guide.md)

---

**Questions?** See [Comparison Guide](../README.md) or open a GitHub issue.
