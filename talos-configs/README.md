# Talos Configuration Examples

This directory contains example Talos configurations for common use cases, including NVIDIA GPU support.

## Overview

Talos Linux configuration can be customized through:
- **System Extensions**: Pre-built packages that extend Talos functionality
- **Machine Config Patches**: YAML patches applied to machine configuration
- **Cluster Templates**: Omni configurations that apply patches to all nodes

## GPU Support (NVIDIA)

### Understanding Extensions in Talos

**Important Context** (from Sidero Labs team):

> Extensions are part of the Talos image when you install the system. They're not installed as a secondary process - if Talos is installed, the extension should already be there. The system won't become healthy until you apply a patch to **load** the system extensions.

There are two approaches to using extensions:

#### Approach 1: Boot Generic Talos + Template Extensions (Recommended)
- Boot all nodes from generic Talos image
- Specify extensions in the cluster template in Omni
- Extensions are downloaded and activated during installation
- No custom ISO creation required

#### Approach 2: Bake Extensions into Custom ISO
- Create custom Talos ISO with extensions pre-baked
- Boot from this custom ISO
- Extensions are already part of the image

**Note**: Some users report issues with Approach 1 where extension installation hangs. If you experience this, use Approach 2 or check Proxmox console settings.

### Required Extensions for NVIDIA GPU

Two extensions are required:
1. **nonfree-kmod-nvidia** - NVIDIA kernel modules (proprietary drivers)
2. **nvidia-container-toolkit** - NVIDIA container runtime support

⚠️ **Critical**: Both extensions must use **matching driver versions**.

### Setup Instructions

#### Option A: Via Omni Cluster Template (Easiest)

1. **Create Cluster** in Omni UI
2. **Configure Extensions** in cluster template:
   - Add `nonfree-kmod-nvidia`
   - Add `nvidia-container-toolkit`
   - Select matching versions

3. **Apply GPU Worker Patch**:
   - In Omni, navigate to your cluster
   - Go to **Config Patches**
   - Create new patch for worker nodes
   - Use the patch from `gpu-worker-patch.yaml` (see below)

4. **Deploy Nodes**:
   - Nodes will boot from generic Talos
   - Extensions auto-downloaded during installation
   - Patch loads NVIDIA modules

#### Option B: Custom ISO with Extensions

If the template approach doesn't work, create a custom ISO:

```bash
# Generate custom ISO with GPU extensions
# Replace versions with latest compatible versions
docker run --rm -i \
  ghcr.io/siderolabs/imager:v1.11.0 \
  iso \
  --system-extension-image ghcr.io/siderolabs/nonfree-kmod-nvidia:550.127.05-v1.11.0 \
  --system-extension-image ghcr.io/siderolabs/nvidia-container-toolkit:550.127.05-v1.11.0-v1.16.2
```

Then:
1. Upload ISO to Proxmox
2. Boot nodes from this ISO
3. Still apply the GPU worker patch in Omni

### GPU Worker Machine Config Patch

Create a config patch in Omni for GPU worker nodes:

```yaml
machine:
  kernel:
    modules:
      - name: nvidia
      - name: nvidia_uvm
      - name: nvidia_drm
      - name: nvidia_modeset
  sysctls:
    net.core.bpf_jit_harden: 1
```

This patch:
- Loads required NVIDIA kernel modules
- Configures system parameters for GPU operation
- Applied during node bootstrap

See [gpu-worker-patch.yaml](gpu-worker-patch.yaml) for the complete patch file.

### Verification

After nodes are deployed and running:

#### 1. Check Loaded Modules

```bash
talosctl -n <node-ip> read /proc/modules | grep nvidia
```

Expected output:
```
nvidia_drm
nvidia_modeset
nvidia_uvm
nvidia
```

#### 2. Check Installed Extensions

```bash
talosctl -n <node-ip> get extensions
```

Should show both NVIDIA extensions installed.

#### 3. Check Driver Version

```bash
talosctl -n <node-ip> read /proc/driver/nvidia/version
```

Should show NVIDIA driver information.

#### 4. Test GPU Access in Kubernetes

Deploy the NVIDIA device plugin:

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update

helm install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --set runtimeClassName=nvidia
```

Create test pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  runtimeClassName: nvidia
  containers:
  - name: cuda
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
```

```bash
kubectl apply -f gpu-test.yaml
kubectl logs gpu-test
```

Should show `nvidia-smi` output with GPU information.

## Proxmox GPU Passthrough Prerequisites

Before Talos can use GPUs, Proxmox must be configured for GPU passthrough:

### 1. Enable IOMMU

Edit `/etc/default/grub`:

**For Intel CPUs**:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

**For AMD CPUs**:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
```

Update GRUB:
```bash
update-grub
reboot
```

### 2. Load VFIO Modules

Edit `/etc/modules`:
```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

Update initramfs:
```bash
update-initramfs -u -k all
reboot
```

### 3. Identify GPU PCI ID

```bash
lspci -nn | grep -i nvidia
```

Example output:
```
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2080] [10de:1e87]
01:00.1 Audio device [0403]: NVIDIA Corporation TU104 HD Audio Controller [10de:10f8]
```

Note the PCI IDs: `10de:1e87` and `10de:10f8`

### 4. Bind GPU to VFIO

Edit `/etc/modprobe.d/vfio.conf`:
```
options vfio-pci ids=10de:1e87,10de:10f8
```

Blacklist nouveau driver in `/etc/modprobe.d/blacklist.conf`:
```
blacklist nouveau
blacklist nvidiafb
```

Update initramfs:
```bash
update-initramfs -u -k all
reboot
```

### 5. Add GPU to VM

In Proxmox UI or CLI:
```bash
qm set <vmid> -hostpci0 01:00,pcie=1,rombar=0
```

Or via UI:
1. Select VM → Hardware
2. Add → PCI Device
3. Select GPU
4. Enable "All Functions"
5. Set "PCI-Express" to on

## Common Issues

### Extensions Not Installing

**Symptom**: Cluster stuck on "Installing" in Omni, no progress logs

**Possible Causes**:
1. Network connectivity issues (cannot download extensions)
2. Proxmox console/tty configuration issues
3. Extension version compatibility

**Solutions**:
- Check Proxmox console logs for errors
- Try custom ISO approach (Option B)
- Verify extension versions are compatible
- Check that Talos version matches extension version

### Modules Not Loading

**Symptom**: Extensions installed but modules not showing in `/proc/modules`

**Solution**: Ensure you applied the machine config patch to **load** the modules. Extensions being present doesn't automatically load them.

### GPU Not Visible in Kubernetes

**Symptom**: `nvidia-smi` works in Talos but pods can't access GPU

**Solutions**:
1. Deploy NVIDIA device plugin
2. Create RuntimeClass named "nvidia"
3. Specify `runtimeClassName: nvidia` in pod spec
4. Request GPU in pod resources: `nvidia.com/gpu: 1`

### Wrong Driver Version

**Symptom**: Version mismatch errors between extensions

**Solution**: Ensure `nonfree-kmod-nvidia` and `nvidia-container-toolkit` have matching driver versions (e.g., both 550.127.05).

## Extension Version Compatibility

**Talos v1.11.x**:
- nonfree-kmod-nvidia: `550.127.05-v1.11.0`
- nvidia-container-toolkit: `550.127.05-v1.11.0-v1.16.2`

**Talos v1.10.x**:
- nonfree-kmod-nvidia: `550.127.05-v1.10.0`
- nvidia-container-toolkit: `550.127.05-v1.10.0-v1.16.2`

Check [Talos Extension Catalog](https://github.com/siderolabs/extensions) for latest versions.

## Best Practices

1. **Use matching extension versions** - Mismatched versions cause failures
2. **Test with generic Talos first** - Try template approach before custom ISO
3. **Verify Proxmox passthrough** - GPU must work at host level first
4. **Monitor cluster template application** - Watch Omni logs during installation
5. **Keep extensions updated** - Newer drivers often fix issues

## Resources

- [Talos GPU Documentation](https://docs.siderolabs.com/talos/v1.11/configure-your-talos-cluster/hardware-and-drivers/nvidia-gpu-proprietary/)
- [Talos Extensions Catalog](https://github.com/siderolabs/extensions)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [Proxmox GPU Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough)

## Next Steps

- Test GPU workloads with actual ML/AI applications
- Set up node affinity for GPU pods
- Configure resource quotas for GPU resources
- Monitor GPU utilization with Prometheus
