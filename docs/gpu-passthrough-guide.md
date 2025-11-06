# GPU Passthrough Configuration Guide for Proxmox

This guide covers the manual steps required to configure GPU passthrough for GPU worker nodes in your Talos cluster.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Enable IOMMU in BIOS](#step-1-enable-iommu-in-bios)
- [Step 2: Configure Proxmox Host](#step-2-configure-proxmox-host)
- [Step 3: Identify GPU PCI Address](#step-3-identify-gpu-pci-address)
- [Step 4: Configure GPU Passthrough for VM](#step-4-configure-gpu-passthrough-for-vm)
- [Step 5: Verify GPU in Talos](#step-5-verify-gpu-in-talos)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

## Overview

GPU passthrough allows a Proxmox VM to directly access a physical GPU. This is essential for:
- GPU-accelerated workloads (AI/ML, rendering, transcoding)
- NVIDIA GPU operator in Kubernetes
- CUDA applications
- GPU-based inference servers

**Important**: GPU passthrough configuration cannot be automated via Terraform. After Terraform creates your GPU worker VMs, you must manually configure GPU passthrough in Proxmox.

## Prerequisites

### Hardware Requirements

- **CPU**: Intel VT-d or AMD-Vi support
- **Motherboard**: IOMMU support
- **GPU**: Dedicated GPU for passthrough (cannot be used by Proxmox host)
- **Multiple GPUs** (recommended): One for Proxmox host, one for passthrough

### Software Requirements

- Proxmox VE 7.0 or later
- GPU drivers on Proxmox host (for initial identification)
- Talos VM already created by Terraform

### Check CPU Support

```bash
# For Intel CPUs
egrep -c '(vmx|svm)' /proc/cpuinfo
# Output > 0 means virtualization is supported

# Check IOMMU support
dmesg | grep -e DMAR -e IOMMU
```

## Step 1: Enable IOMMU in BIOS

1. **Reboot Proxmox server** and enter BIOS/UEFI settings (usually F2, F12, or DEL)

2. **Find virtualization settings** (location varies by manufacturer):
   - Intel: Look for **"Intel VT-d"** or **"Intel Virtualization Technology for Directed I/O"**
   - AMD: Look for **"AMD-Vi"** or **"IOMMU"**

3. **Enable the following**:
   - VT-d / AMD-Vi
   - VT-x / AMD-V (CPU virtualization)
   - IOMMU

4. **Save and reboot**

### Common BIOS Locations

| Manufacturer | Menu Path |
|--------------|-----------|
| ASUS | Advanced → CPU Configuration → Intel VT-d |
| Gigabyte | BIOS Features → Intel VT-d |
| MSI | OC → CPU Features → Intel VT-d |
| ASRock | Advanced → CPU Configuration → Intel VT-d |
| Supermicro | Advanced → Chipset Configuration → North Bridge → IIO Configuration → Intel VT-d |

## Step 2: Configure Proxmox Host

### 2.1 Edit GRUB Configuration

```bash
# SSH to Proxmox server
ssh root@your-proxmox-server

# Edit GRUB config
nano /etc/default/grub
```

### 2.2 Update GRUB_CMDLINE_LINUX_DEFAULT

**For Intel CPUs**:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction video=efifb:off"
```

**For AMD CPUs**:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction video=efifb:off"
```

**Parameter Explanations**:
- `intel_iommu=on` / `amd_iommu=on`: Enable IOMMU
- `iommu=pt`: Use passthrough mode (better performance)
- `pcie_acs_override=downstream,multifunction`: Override PCIe ACS (for certain motherboards)
- `video=efifb:off`: Disable EFI framebuffer (prevents host from using GPU)

### 2.3 Update GRUB and Reboot

```bash
# Update GRUB
update-grub

# Reboot Proxmox server
reboot
```

### 2.4 Verify IOMMU is Enabled

```bash
# After reboot, verify IOMMU
dmesg | grep -e DMAR -e IOMMU

# Should see output like:
# [    0.000000] DMAR: IOMMU enabled
```

### 2.5 Load VFIO Modules

```bash
# Edit modules file
nano /etc/modules

# Add these lines:
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

### 2.6 Update initramfs and Reboot

```bash
# Update initramfs
update-initramfs -u -k all

# Reboot
reboot
```

## Step 3: Identify GPU PCI Address

### 3.1 List All PCI Devices

```bash
# List all GPUs
lspci | grep -i vga

# Example output:
# 01:00.0 VGA compatible controller: NVIDIA Corporation GA102 [GeForce RTX 3080] (rev a1)
# 02:00.0 VGA compatible controller: NVIDIA Corporation TU116 [GeForce GTX 1660 Ti] (rev a1)
```

### 3.2 Get Detailed GPU Information

```bash
# Get detailed info for specific GPU (replace 01:00 with your GPU)
lspci -n -s 01:00

# Example output:
# 01:00.0 0300: 10de:2206 (rev a1)
# 01:00.1 0403: 10de:1aef (rev a1)
```

**Important**: Note both the **PCI address** (e.g., `01:00`) and **vendor:device IDs** (e.g., `10de:2206`).

Most GPUs have two functions:
- `01:00.0`: GPU
- `01:00.1`: Audio device

### 3.3 Check IOMMU Groups

```bash
# Check IOMMU grouping
find /sys/kernel/iommu_groups/ -type l

# Or use this helper script:
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done
```

**Ideal**: GPU should be in its own IOMMU group or with only its audio device.

**If not**: You may need `pcie_acs_override` (already added in GRUB config).

## Step 4: Configure GPU Passthrough for VM

### 4.1 Find Your GPU Worker VM ID

```bash
# List all VMs
qm list

# Find your GPU worker (e.g., talos-gpu-1)
# Note the VMID (e.g., 106)
```

### 4.2 Stop the VM

```bash
# Stop the VM (replace 106 with your VMID)
qm stop 106
```

### 4.3 Add GPU to VM Configuration

**Method 1: Using qm command (Recommended)**

```bash
# Add GPU passthrough (replace VMID and PCI address)
qm set 106 -hostpci0 01:00,pcie=1,x-vga=0

# Explanation:
# -hostpci0: First PCI passthrough device (use hostpci1, hostpci2 for multiple)
# 01:00: PCI address (both .0 and .1 are passed through automatically)
# pcie=1: Present as PCIe device (recommended for GPUs)
# x-vga=0: Not primary VGA (Talos doesn't need VGA)
```

**Method 2: Edit VM config file directly**

```bash
# Edit VM config
nano /etc/pve/qemu-server/106.conf

# Add this line:
hostpci0: 0000:01:00,pcie=1,x-vga=0
```

### 4.4 Configure Additional VM Settings

```bash
# Set CPU type to host (better performance)
qm set 106 -cpu host

# Enable PCIe passthrough features
qm set 106 -machine q35

# Disable tablet device (optional, reduces overhead)
qm set 106 -tablet 0
```

### 4.5 Verify Configuration

```bash
# Check VM config
cat /etc/pve/qemu-server/106.conf

# Should see:
# hostpci0: 0000:01:00,pcie=1,x-vga=0
# cpu: host
# machine: q35
```

### 4.6 Start the VM

```bash
# Start the VM
qm start 106

# Monitor console for errors
qm terminal 106
```

## Step 5: Verify GPU in Talos

### 5.1 Get Talos Node IP

```bash
# From your local machine with omnictl configured
omnictl get machines -o wide

# Find the GPU worker IP (e.g., 192.168.10.120)
```

### 5.2 Check GPU via omnictl

```bash
# Get machine hardware info
omnictl get machines -o json | jq '.items[] | select(.metadata.labels.hostname == "talos-gpu-1") | .spec.hardware'

# Look for PCI devices in the output
```

### 5.3 Verify GPU with Kubernetes (After Cluster Creation)

```bash
# After creating the cluster and installing NVIDIA GPU operator

# Check GPU nodes
kubectl get nodes -l nvidia.com/gpu.present=true

# Check GPU resources
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpus: .status.capacity["nvidia.com/gpu"]}'

# List GPUs
kubectl describe node talos-gpu-1 | grep nvidia.com/gpu
```

## Troubleshooting

### Issue: VM won't start after adding GPU

**Error**: `kvm: -device vfio-pci,host=01:00.0,id=hostpci0,bus=ich9-pcie-port-1,addr=0x0: vfio 0000:01:00.0: failed to open /dev/vfio/1: Device or resource busy`

**Solutions**:

1. **Check if GPU is bound to host driver**:
```bash
lspci -k -s 01:00

# If you see "Kernel driver in use: nvidia" or similar, the host is using the GPU
```

2. **Blacklist host GPU drivers**:
```bash
nano /etc/modprobe.d/blacklist-nvidia.conf

# Add:
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nouveau

# Update initramfs and reboot
update-initramfs -u -k all
reboot
```

3. **Bind GPU to VFIO driver**:
```bash
# Get GPU vendor:device IDs (from lspci -n)
# Example: 10de:2206 (NVIDIA RTX 3080)

nano /etc/modprobe.d/vfio.conf

# Add (replace with your IDs):
options vfio-pci ids=10de:2206,10de:1aef

# Update initramfs and reboot
update-initramfs -u -k all
reboot
```

### Issue: GPU not visible in VM

**Solutions**:

1. **Check IOMMU grouping** (see Step 3.3)
2. **Verify VFIO modules loaded**:
```bash
lsmod | grep vfio

# Should see vfio, vfio_pci, vfio_iommu_type1
```

3. **Check VM logs**:
```bash
# Check for errors
journalctl -u pvedaemon | grep -i vfio

# Check VM log
tail -f /var/log/pve/tasks/*
```

### Issue: GPU passthrough works but no CUDA

**Solutions**:

1. **Verify NVIDIA drivers in Talos**:
   - Talos requires GPU driver extensions
   - Applied via machine patches (see scripts/generate-machine-configs.sh)

2. **Check Talos system extensions**:
```bash
# Via omnictl
omnictl get machines -o json | jq '.items[] | select(.metadata.labels.hostname == "talos-gpu-1") | .spec.extensions'
```

3. **Install NVIDIA GPU Operator in Kubernetes**:
```bash
# After cluster creation
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install --wait gpu-operator nvidia/gpu-operator --namespace gpu-operator --create-namespace
```

### Issue: Multiple GPUs, wrong one passed through

**Solution**:

- Carefully note the PCI address of each GPU
- Use specific PCI addresses for each VM
- Consider physical slot positions for clarity

```bash
# Label GPU workers with specific GPU info
omnictl label machine <uuid> gpu-model=rtx3080
omnictl label machine <uuid> gpu-pci-id=01:00
```

## Advanced Configuration

### Multiple GPUs per VM

```bash
# Pass through multiple GPUs to the same VM
qm set 106 -hostpci0 01:00,pcie=1
qm set 106 -hostpci1 02:00,pcie=1

# Verify
cat /etc/pve/qemu-server/106.conf
```

### SR-IOV (Single Root I/O Virtualization)

For supported GPUs (NVIDIA A100, A30, etc.):

```bash
# Enable SR-IOV on GPU
echo 1 > /sys/bus/pci/devices/0000:01:00.0/sriov_numvfs

# List virtual functions
lspci | grep -i nvidia

# Pass through virtual function instead of full GPU
qm set 106 -hostpci0 01:00.1,pcie=1
```

### GPU ROM Extraction (for certain GPUs)

Some GPUs require ROM extraction for passthrough:

```bash
# Extract GPU ROM
cd /sys/bus/pci/devices/0000:01:00.0
echo 1 > rom
cat rom > /root/gpu-rom.bin
echo 0 > rom

# Use ROM in VM config
qm set 106 -hostpci0 01:00,pcie=1,romfile=/root/gpu-rom.bin
```

### CPU Pinning for Better Performance

```bash
# Pin VM CPUs to specific host cores
qm set 106 -cores 16
qm set 106 -cpu host,flags=+pcid
qm set 106 -numa 1

# Edit config manually for specific pinning
nano /etc/pve/qemu-server/106.conf

# Add:
# vcpus: 16
# affinity: 0-7,16-23  # Pin to specific cores
```

## Integration with Terraform Workflow

After Terraform creates your GPU worker VMs:

1. **Get GPU configuration instructions**:
```bash
cd terraform
terraform output gpu_configuration_needed

# Output example:
# {
#   hostname   = "talos-gpu-1"
#   server     = "pve2"
#   node       = "pve2"
#   gpu_pci_id = "01:00"
#   instructions = "1. SSH to pve2, 2. Run: qm set <VM_ID> -hostpci0 01:00,pcie=1"
# }
```

2. **Follow this guide** to manually configure GPU passthrough

3. **Continue with machine configuration**:
```bash
cd ../scripts
./discover-machines.sh
./generate-machine-configs.sh  # Includes GPU driver extensions
./apply-machine-configs.sh
```

4. **Verify GPU availability** after cluster creation

## References

- [Proxmox GPU Passthrough Documentation](https://pve.proxmox.com/wiki/PCI_Passthrough)
- [Talos GPU Support](https://www.talos.dev/latest/talos-guides/configuration/nvidia-gpu/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html)
- [Troubleshooting GPU Passthrough](https://www.reddit.com/r/homelab/wiki/index)

## Quick Reference Card

```bash
# === PROXMOX HOST SETUP ===
# Enable IOMMU in BIOS (Intel VT-d / AMD-Vi)
nano /etc/default/grub
# Add: intel_iommu=on iommu=pt (or amd_iommu=on)
update-grub && reboot

# Load VFIO modules
nano /etc/modules
# Add: vfio, vfio_iommu_type1, vfio_pci, vfio_virqfd
update-initramfs -u -k all && reboot

# === IDENTIFY GPU ===
lspci | grep -i vga
lspci -n -s 01:00  # Replace 01:00 with your GPU

# === CONFIGURE VM ===
qm list  # Find VMID
qm stop <VMID>
qm set <VMID> -hostpci0 01:00,pcie=1,x-vga=0
qm set <VMID> -cpu host
qm set <VMID> -machine q35
qm start <VMID>

# === VERIFY ===
# In Proxmox
lsmod | grep vfio
dmesg | grep -i iommu

# In Kubernetes (after cluster creation)
kubectl get nodes -l nvidia.com/gpu.present=true
kubectl describe node <node-name> | grep nvidia.com/gpu
```
