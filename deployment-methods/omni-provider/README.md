# Omni Infrastructure Provider for Proxmox

**✨ Easiest deployment method** - Automatically provision Talos VMs directly from Omni UI!

## Overview

The Omni Infrastructure Provider is an official Siderolabs tool (NEW in 2025) that connects Omni to your Proxmox cluster. Instead of using Terraform or manually cloning VMs, you simply:

1. Run the provider (Docker container)
2. Create "Machine Classes" in Omni UI
3. Click "Scale Up" in Omni
4. **VMs automatically appear in Proxmox!** 🎉

## Prerequisites

- ✅ Omni already deployed (see [../../sidero-omni/README.md](../../sidero-omni/README.md))
- ✅ Proxmox API access (root user or dedicated user)
- ✅ Docker on a server that can reach both Omni and Proxmox

## Architecture

```
┌─────────────┐         ┌──────────────────┐         ┌──────────────┐
│  Omni UI    │────────▶│  Omni Provider   │────────▶│   Proxmox    │
│             │         │  (Docker)        │         │              │
│ Click       │  HTTPS  │                  │   API   │  VMs Created │
│ "Scale Up"  │         │ - Watches Omni   │         │  Automatically│
│             │         │ - Creates VMs    │         │              │
└─────────────┘         └──────────────────┘         └──────────────┘
```

## Setup Guide

### Step 1: Create Omni Service Account

In your Omni UI (https://your-omni-domain.com):

1. Navigate to **Settings** → **Service Accounts**
2. Click **Create Service Account**
3. Name: `proxmox-provider`
4. Role: **Infra Provider** (important!)
5. Click **Create**
6. **Copy the key** - you'll need this for the provider config

### Step 2: Configure Proxmox Credentials

Create a `config.yaml` file:

```yaml
# config.yaml
proxmox:
  # Proxmox server details
  url: "https://192.168.10.160:8006/api2/json"

  # Authentication
  username: "root"              # or dedicated terraform@pve user
  password: "your-password"     # Proxmox password
  realm: "pam"                  # or "pve" if using Proxmox user

  # SSL (use true for self-signed certs)
  insecureSkipVerify: true

  # Optional: Default storage pools
  # storage: "local-lvm"        # Uncomment to set default
```

**Security Note**: Store this file securely! Contains Proxmox password.

### Step 3: Run the Provider

**Option A: Docker Run**

```bash
docker run -d \
  --name omni-proxmox-provider \
  --restart unless-stopped \
  -v $(pwd)/config.yaml:/config.yaml:ro \
  ghcr.io/siderolabs/omni-infra-provider-proxmox:latest \
  --config-file /config.yaml \
  --omni-api-endpoint https://your-omni-domain.com/ \
  --omni-service-account-key <SERVICE_ACCOUNT_KEY_FROM_STEP_1>
```

**Option B: Docker Compose** (Recommended)

Use the provided `docker-compose.yml`:

```bash
# Edit docker-compose.yml with your details
nano docker-compose.yml

# Start the provider
docker compose up -d

# Check logs
docker compose logs -f
```

### Step 4: Verify Provider Connection

```bash
# Check provider logs
docker logs omni-proxmox-provider

# Should see:
# ✓ Connected to Omni
# ✓ Connected to Proxmox
# ✓ Watching for machine requests
```

In Omni UI:
- Go to **Settings** → **Infrastructure Providers**
- You should see **Proxmox** listed as **Connected**

---

## Creating Machine Classes (VM Templates)

Machine Classes define VM specifications. Omni uses these to create VMs automatically.

### Example: Control Plane Machine Class

1. In Omni UI, go to **Machine Classes** → **Create**
2. Fill in details:

```yaml
Name: control-plane
Type: Auto-Provision
Infrastructure Provider: proxmox

Resources:
  CPU: 4 cores
  Memory: 8 GB
  Disk: 50 GB

Proxmox Settings:
  Node: pve1                    # Proxmox node name
  Storage: local-lvm            # Storage pool
  Network Bridge: vmbr0

System Extensions:
  - siderolabs/qemu-guest-agent
```

3. Click **Create**

### Example: Worker Machine Class

```yaml
Name: worker
Type: Auto-Provision
Infrastructure Provider: proxmox

Resources:
  CPU: 8 cores
  Memory: 16 GB
  Disk: 100 GB

Proxmox Settings:
  Node: pve2
  Storage: local-lvm
  Network Bridge: vmbr0

System Extensions:
  - siderolabs/qemu-guest-agent
```

### Example: GPU Worker Machine Class

```yaml
Name: gpu-worker
Type: Auto-Provision
Infrastructure Provider: proxmox

Resources:
  CPU: 16 cores
  Memory: 32 GB
  Disk: 200 GB

Proxmox Settings:
  Node: pve3                    # Server with GPU
  Storage: local-lvm
  Network Bridge: vmbr0

System Extensions:
  - siderolabs/qemu-guest-agent
  - siderolabs/nonfree-kmod-nvidia-production
  - siderolabs/nvidia-container-toolkit-production

# Note: Still need to manually add GPU passthrough in Proxmox
# See: ../../docs/gpu-passthrough-guide.md
```

---

## Deploying Your Cluster

### Method 1: Via Cluster Creation (Recommended)

1. **Create Cluster** in Omni UI
2. **Select Machine Class** for Control Planes
3. **Set Replicas**: 3 (for HA)
4. **Add Worker Pool**
5. **Select Machine Class** for Workers
6. **Set Replicas**: 5 (or desired count)
7. Click **Create Cluster**

**Omni automatically**:
- Creates VMs in Proxmox
- Installs Talos
- Configures networking
- Forms Kubernetes cluster

### Method 2: Via Manual Scaling

1. Go to existing cluster
2. **Control Planes** section → **Edit**
3. Change replicas: `1` → `3`
4. VMs created automatically!

---

## Configuration Examples

### Multi-Server Distribution

Create machine classes pointing to different Proxmox nodes:

```yaml
# Machine Class: control-plane-pve1
Proxmox Node: pve1

# Machine Class: control-plane-pve2
Proxmox Node: pve2

# Machine Class: control-plane-pve3
Proxmox Node: pve3
```

Then mix them in your cluster:
- Control Planes: Use all 3 classes (distributed HA)
- Workers: Use whichever node has capacity

### Storage Pool Selection

Different storage per machine class:

```yaml
# Fast SSDs for control planes
control-plane:
  Storage: ssd-pool

# Slow HDDs for workers
worker:
  Storage: hdd-pool

# NFS for GPU workers (large datasets)
gpu-worker:
  Storage: nfs-storage
```

### Network Configuration

Custom network bridges:

```yaml
# Management network
control-plane:
  Network Bridge: vmbr0

# Workload network (VLAN tagged)
worker:
  Network Bridge: vmbr1
```

---

## GPU Worker Configuration

The provider can create GPU worker VMs, but **GPU passthrough still requires manual configuration** in Proxmox:

1. **Create GPU worker** via machine class (as shown above)
2. **Wait for VM creation** in Proxmox
3. **Manually configure GPU passthrough**:
   ```bash
   # SSH to Proxmox server
   ssh root@pve3

   # Find GPU
   lspci | grep -i nvidia

   # Add to VM (replace VMID)
   qm set <VMID> -hostpci0 01:00,pcie=1

   # Reboot VM
   qm reboot <VMID>
   ```

4. **Verify in Omni** - Machine should show GPU available

See [../../docs/gpu-passthrough-guide.md](../../docs/gpu-passthrough-guide.md) for complete GPU setup.

---

## Advantages Over Other Methods

| Feature | Omni Provider | Terraform | ISO Templates |
|---------|--------------|-----------|---------------|
| **Setup Complexity** | ⭐ Low | ⭐⭐⭐ High | ⭐⭐ Medium |
| **Scaling** | Click button | Edit code, apply | Manual clone |
| **Learning Curve** | Easy (UI) | Steep (HCL) | Medium (Bash) |
| **State Management** | Omni handles | Manual .tfstate | None |
| **Auto-healing** | ✅ Yes | ❌ No | ❌ No |

---

## Troubleshooting

### Provider won't connect to Omni

**Check**:
```bash
docker logs omni-proxmox-provider
```

**Common issues**:
- Wrong service account key
- Incorrect Omni URL (must include `https://`)
- Firewall blocking outbound HTTPS

### Provider won't connect to Proxmox

**Check**:
```bash
# Test Proxmox API manually
curl -k https://192.168.10.160:8006/api2/json/version

# From provider container
docker exec omni-proxmox-provider curl -k https://192.168.10.160:8006/api2/json/version
```

**Common issues**:
- Wrong Proxmox URL
- Wrong username/password
- Proxmox firewall blocking API port 8006

### VMs not being created

**Check in Omni UI**:
- Settings → Infrastructure Providers → Status should be "Connected"
- Machine Classes → Verify they exist and are type "Auto-Provision"

**Check Proxmox**:
- Enough resources (CPU, RAM, storage)?
- Storage pool exists and has space?
- Node name matches exactly?

**Provider logs**:
```bash
docker logs -f omni-proxmox-provider | grep -i error
```

### VMs created but not joining cluster

This is usually a **network issue**:

**Check**:
1. VMs have network connectivity
2. Can reach Omni SideroLink (port 50180)
3. DNS resolution works

**Debug**:
```bash
# In Omni UI, check machine status
# Should show "Connected" after 2-3 minutes
```

---

## Advanced Configuration

### Multiple Proxmox Clusters

Run multiple providers for different Proxmox clusters:

```yaml
# docker-compose.yml
services:
  omni-provider-cluster1:
    image: ghcr.io/siderolabs/omni-infra-provider-proxmox:latest
    volumes:
      - ./config-cluster1.yaml:/config.yaml
    command: ...

  omni-provider-cluster2:
    image: ghcr.io/siderolabs/omni-infra-provider-proxmox:latest
    volumes:
      - ./config-cluster2.yaml:/config.yaml
    command: ...
```

### Custom Talos Versions

Specify Talos version in machine class:

```yaml
# In machine class
Talos Version: v1.10.1
```

### Disk Layout Customization

Currently handled via machine class disk size. For secondary disks, you'll need to:
1. Create VM via provider
2. Manually add second disk in Proxmox
3. Configure mount via Talos patches (see [../../scripts/](../../scripts/))

---

## Comparison with Terraform

**Use Omni Provider if**:
- ✅ You want simplicity
- ✅ You already use Omni
- ✅ You want auto-scaling
- ✅ You're not familiar with Terraform

**Use Terraform if**:
- ✅ You need exact control over every VM parameter
- ✅ You want GitOps workflow
- ✅ You're already using Terraform for other infrastructure
- ✅ You need complex conditional logic

**Can use both!**
- Terraform for initial cluster
- Omni Provider for scaling

---

## Next Steps

1. **✅ Provider running** - Verify logs
2. **Create machine classes** - Start with control-plane
3. **Create cluster** - Omni UI → Clusters → Create
4. **Watch the magic** - VMs appear in Proxmox automatically!
5. **Scale as needed** - Add/remove replicas in Omni

## Resources

- [Official Omni Provider Repo](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [Omni Documentation](https://www.siderolabs.com/omni/docs/)
- [Main README](../../README.md)

---

**Need help?** Open an issue on GitHub or check the main project documentation.
