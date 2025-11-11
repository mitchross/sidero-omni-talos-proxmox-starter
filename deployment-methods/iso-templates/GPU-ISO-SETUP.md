# GPU Worker ISO Setup Guide

This guide explains how to generate and use a custom Talos ISO with NVIDIA drivers for GPU workers.

## Why a Separate GPU ISO?

- **PXE limitation**: Your standard PXE booter can't have NVIDIA extensions because they would cause non-GPU VMs to fail boot
- **Solution**: GPU workers boot from a custom ISO that includes NVIDIA drivers pre-installed
- **Workflow**: Regular workers use PXE, GPU workers use ISO

## Step 1: Generate the GPU ISO

### 1.1 Generate Schematic ID

From the repository root:

```bash
cd deployment-methods/iso-templates/schematics

curl -X POST --data-binary @gpu-worker.yaml https://factory.talos.dev/schematics
```

You'll get a response like:

```json
{
  "id": "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
}
```

**Save this schematic ID** - you'll need it for downloads and updates.

### 1.2 Download the GPU ISO

Replace `{SCHEMATIC_ID}` with your actual ID and `v1.11.5` with your Talos version:

```bash
# Download ISO (about 150-200 MB)
wget https://factory.talos.dev/image/{SCHEMATIC_ID}/v1.11.5/metal-amd64.iso \
  -O talos-gpu-v1.11.5.iso
```

Or use the web interface:
- Go to: `https://factory.talos.dev/image/{SCHEMATIC_ID}/v1.11.5/metal-amd64.iso`
- Download and rename to `talos-gpu-v1.11.5.iso`

## Step 2: Upload ISO to Proxmox

### Option A: Via Web UI

1. Open Proxmox web interface
2. Navigate to: **Datacenter** → **hp-server-1** → **local** → **ISO Images**
3. Click **Upload**
4. Select your `talos-gpu-v1.11.5.iso` file
5. Wait for upload to complete

### Option B: Via SCP (Faster for large files)

```bash
# From your local machine
scp talos-gpu-v1.11.5.iso root@192.168.10.160:/var/lib/vz/template/iso/
```

## Step 3: Verify Terraform Configuration

Check your `terraform/terraform.tfvars`:

```hcl
# Boot method for regular workers
boot_method = "pxe"

# GPU ISO location (adjust if using different storage)
talos_gpu_iso = "local:iso/talos-gpu-v1.11.5.iso"
```

## Step 4: Deploy Workflow

### Regular Workers (PXE Boot)
1. `terraform apply` creates VMs
2. VMs PXE boot from Sidero Booter
3. Get base extensions: iscsi-tools, nfsd, qemu-guest-agent, util-linux-tools
4. Apply machine configs via Omni

### GPU Workers (ISO Boot)  
1. `terraform apply` creates GPU VMs
2. VMs boot from GPU ISO (includes NVIDIA drivers)
3. **Manually add GPU PCI device** in Proxmox UI
4. Apply machine configs via Omni (with NVIDIA kernel module declarations)

## Step 5: Manual GPU Passthrough Configuration

After Terraform creates the GPU worker VM:

1. In Proxmox, select VM 120 (talos-worker-gpu-1)
2. Go to **Hardware**
3. Click **Add** → **PCI Device**
4. Select your NVIDIA GPU (usually shows as VGA device)
5. Enable:
   - ✅ **All Functions** (includes GPU audio)
   - ✅ **Primary GPU** (if using for display)
   - ✅ **PCI-Express**
6. Click **Add**
7. **Start the VM**

## Updating to New Talos Version

When upgrading Talos:

1. Generate new schematic with updated version:
   ```bash
   # Same schematic YAML, new version
   wget https://factory.talos.dev/image/{SCHEMATIC_ID}/v1.12.0/metal-amd64.iso \
     -O talos-gpu-v1.12.0.iso
   ```

2. Upload new ISO to Proxmox

3. Update `terraform.tfvars`:
   ```hcl
   talos_version = "v1.12.0"
   talos_gpu_iso = "local:iso/talos-gpu-v1.12.0.iso"
   ```

4. Recreate or update VMs

## Verifying NVIDIA Extensions

After VM boots with the GPU ISO, check extensions are present:

```bash
# SSH to GPU worker
talosctl -n 192.168.10.115 get extensions

# Should show:
# - nonfree-kmod-nvidia-production
# - nvidia-container-toolkit-production
```

## Troubleshooting

### GPU ISO not found
- Check ISO uploaded to correct storage: `local` storage
- Verify filename matches: `talos-gpu-v1.11.5.iso`
- Check Proxmox ISO list: Datacenter → local → ISO Images

### Extensions not installing
- This is expected! With the factory ISO, extensions are **pre-installed**
- No need to wait for installation - they're baked into the ISO
- Apply your machine configs immediately after boot

### NVIDIA modules failing to load
- Ensure GPU PCI device is added in Proxmox Hardware tab
- Check machine config has kernel module declarations (nvidia, nvidia_uvm, etc.)
- Verify containerd runtime config is applied

## Quick Reference

| Component | Regular Workers | GPU Workers |
|-----------|----------------|-------------|
| Boot Method | PXE (Sidero Booter) | ISO (Factory Image) |
| Extensions | Base only | Base + NVIDIA |
| Terraform Resource | `proxmox_vm_qemu.worker` | `proxmox_vm_qemu.gpu_worker` |
| Manual Steps | None | Add GPU PCI device |
| ISO Location | N/A | `local:iso/talos-gpu-v1.11.5.iso` |

## Related Documentation

- [GPU Passthrough Guide](../../docs/gpu-passthrough-guide.md)
- [Talos Image Factory](https://factory.talos.dev)
- [NVIDIA GPU Docs](https://docs.siderolabs.com/talos/v1.11/configure-your-talos-cluster/hardware-and-drivers/nvidia-gpu-proprietary/)
