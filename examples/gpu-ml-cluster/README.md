# GPU ML Cluster

A Kubernetes cluster optimized for AI/ML workloads with NVIDIA GPU support.

## Overview

This example provides a GPU-enabled cluster for machine learning:
- **1 control plane node** - Manages the cluster
- **1 regular worker** - General workloads
- **2 GPU workers** - AI/ML workloads with NVIDIA GPUs
- **NVIDIA GPU support** - Proprietary drivers and container toolkit
- **ML frameworks ready** - TensorFlow, PyTorch, CUDA

## Resource Requirements

### Per Node

**Control Plane**:
- CPU: 4 cores
- RAM: 8GB
- Disk: 50GB
- GPU: None

**Regular Worker**:
- CPU: 4 cores
- RAM: 16GB
- Disk: 100GB
- GPU: None
- Purpose: Non-GPU workloads (databases, APIs, etc.)

**GPU Workers** (x2):
- CPU: 8 cores
- RAM: 32GB
- Disk: 200GB
- GPU: NVIDIA GPU (RTX 2080, 3090, 4090, A100, etc.)
- Purpose: ML training, inference, GPU compute

**Total Resources**:
- CPU: 24 cores
- RAM: 88GB
- Disk: 550GB
- GPUs: 2x NVIDIA

## Prerequisites

Before starting, you must configure GPU passthrough in Proxmox. See:
- [Talos GPU Configuration Guide](../../talos-configs/README.md#proxmox-gpu-passthrough-prerequisites)
- [Proxmox GPU Passthrough Documentation](https://pve.proxmox.com/wiki/PCI_Passthrough)

### Quick Proxmox GPU Setup

**1. Enable IOMMU** (in Proxmox host):

```bash
# For Intel CPUs
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"' | sudo tee -a /etc/default/grub

# For AMD CPUs
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"' | sudo tee -a /etc/default/grub

sudo update-grub
sudo reboot
```

**2. Load VFIO modules**:

```bash
cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF

update-initramfs -u -k all
reboot
```

**3. Bind GPU to VFIO**:

```bash
# Find your GPU PCI ID
lspci -nn | grep -i nvidia
# Example output: 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation [10de:1e87]

# Add to vfio.conf (replace with your IDs)
echo "options vfio-pci ids=10de:1e87,10de:10f8" > /etc/modprobe.d/vfio.conf

# Blacklist nouveau
cat >> /etc/modprobe.d/blacklist.conf << EOF
blacklist nouveau
blacklist nvidiafb
EOF

update-initramfs -u -k all
reboot
```

**4. Attach GPU to VM** (after VM is created):

```bash
# Via Proxmox UI: VM → Hardware → Add → PCI Device → Select GPU
# Or via CLI:
qm set <vmid> -hostpci0 01:00,pcie=1,rombar=0
```

## Machine Classes

### Control Plane Machine Class

Create in Omni UI → Settings → Machine Classes:

```yaml
name: ml-control-plane
provider: your-proxmox-provider
cpu: 4
memory: 8192
disk: 50
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

### Regular Worker Machine Class

```yaml
name: ml-worker-regular
provider: your-proxmox-provider
cpu: 4
memory: 16384  # 16GB
disk: 100
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

### GPU Worker Machine Class

```yaml
name: ml-worker-gpu
provider: your-proxmox-provider
cpu: 8
memory: 32768  # 32GB
disk: 200
storage: |
  storage.filter(s, s.type == "zfspool" && s.enabled && s.active)[0].storage
```

**Note**: GPU passthrough must be configured **manually** in Proxmox after VMs are created. The provider cannot automatically attach GPUs (current limitation).

## Talos GPU Configuration

### Option A: Cluster Template with Extensions (Recommended)

When creating the cluster in Omni, specify these extensions in the cluster template:

**Required Extensions**:
- `nonfree-kmod-nvidia:550.127.05-v1.11.0` (NVIDIA drivers)
- `nvidia-container-toolkit:550.127.05-v1.11.0-v1.16.2` (Container runtime)

**Version Compatibility**:
- Talos v1.11.x: Use extensions with `-v1.11.0` suffix
- Talos v1.10.x: Use extensions with `-v1.10.0` suffix
- Always match driver versions (e.g., both 550.127.05)

Check [Talos Extensions Catalog](https://github.com/siderolabs/extensions) for latest versions.

### GPU Worker Config Patch

Apply this patch to GPU worker nodes in Omni:

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
- Loads NVIDIA kernel modules on boot
- Required even if extensions are in the image
- Apply in Omni UI: Cluster → Config Patches → Add Patch → Target GPU workers

See the complete patch file: [gpu-worker-patch.yaml](../../talos-configs/gpu-worker-patch.yaml)

## Deployment Steps

### 1. Create Machine Classes

1. Log into Omni UI
2. Navigate to **Settings** → **Machine Classes**
3. Create all three machine classes (control plane, regular worker, GPU worker)

### 2. Create Cluster with Extensions

1. Click **Create Cluster**
2. Cluster configuration:
   - **Name**: `ml-cluster`
   - **Kubernetes Version**: v1.30.0 (or latest)
   - **Talos Version**: v1.11.0
   - **Extensions**: Add both NVIDIA extensions
     - `nonfree-kmod-nvidia:550.127.05-v1.11.0`
     - `nvidia-container-toolkit:550.127.05-v1.11.0-v1.16.2`
   - **Control Plane**:
     - Machine Class: `ml-control-plane`
     - Replicas: `1`
   - **Workers**:
     - Machine Class: `ml-worker-regular`
     - Replicas: `1`
     - Machine Class: `ml-worker-gpu`
     - Replicas: `2`
3. Click **Create**

### 3. Apply GPU Config Patch

1. Wait for cluster to start provisioning
2. In Omni UI, go to your cluster
3. Navigate to **Config Patches**
4. Click **Add Patch**
5. Configure:
   - **Name**: `gpu-worker-modules`
   - **Target**: Machine Class = `ml-worker-gpu`
   - **Patch**: Copy from `gpu-worker-patch.yaml`
6. Save patch

### 4. Attach GPUs in Proxmox

**Important**: After GPU worker VMs are created, manually attach GPUs:

1. In Proxmox UI, find your GPU worker VMs
2. For each GPU worker:
   - Select VM → **Hardware**
   - Click **Add** → **PCI Device**
   - Select your NVIDIA GPU
   - Enable **All Functions**
   - Set **PCI-Express** to ON
   - Click **Add**
3. Restart VMs:
   ```bash
   qm stop <vmid> && qm start <vmid>
   ```

Or via CLI:
```bash
# Find VM IDs for GPU workers
qm list | grep ml-worker-gpu

# Attach GPU (adjust PCI address and VM ID)
qm set 100 -hostpci0 01:00,pcie=1,rombar=0
qm set 101 -hostpci0 02:00,pcie=1,rombar=0

# Reboot VMs
qm reboot 100
qm reboot 101
```

### 5. Verify GPU Detection

Once nodes are ready:

```bash
# Check GPU nodes are ready
kubectl get nodes -l gpu=nvidia

# Check loaded kernel modules
talosctl -n <gpu-worker-ip> read /proc/modules | grep nvidia

# Expected output:
# nvidia
# nvidia_uvm
# nvidia_drm
# nvidia_modeset

# Check NVIDIA driver version
talosctl -n <gpu-worker-ip> read /proc/driver/nvidia/version

# Check system extensions installed
talosctl -n <gpu-worker-ip> get extensions
```

### 6. Deploy NVIDIA Device Plugin

Required for Kubernetes to schedule GPU workloads:

```bash
# Add Helm repo
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update

# Install device plugin
helm install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --set runtimeClassName=nvidia
```

Verify:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin

# Check GPU resources
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'
```

### 7. Create RuntimeClass

Required for GPU pods:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
```

## Testing GPU Access

### Simple GPU Test

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  containers:
  - name: cuda
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
```

Deploy and check output:
```bash
kubectl apply -f gpu-test.yaml
kubectl logs gpu-test

# Should show nvidia-smi output with GPU info
```

### TensorFlow GPU Test

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tensorflow-gpu-test
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  containers:
  - name: tensorflow
    image: tensorflow/tensorflow:latest-gpu
    command:
      - python
      - -c
      - |
        import tensorflow as tf
        print("TensorFlow version:", tf.__version__)
        print("GPUs available:", len(tf.config.list_physical_devices('GPU')))
        print("GPU devices:", tf.config.list_physical_devices('GPU'))
    resources:
      limits:
        nvidia.com/gpu: 1
```

Deploy:
```bash
kubectl apply -f tensorflow-test.yaml
kubectl logs tensorflow-gpu-test

# Should show:
# TensorFlow version: 2.x.x
# GPUs available: 1
# GPU devices: [PhysicalDevice(name='/physical_device:GPU:0', device_type='GPU')]
```

### PyTorch GPU Test

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-gpu-test
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  containers:
  - name: pytorch
    image: pytorch/pytorch:latest
    command:
      - python
      - -c
      - |
        import torch
        print("PyTorch version:", torch.__version__)
        print("CUDA available:", torch.cuda.is_available())
        print("CUDA version:", torch.version.cuda)
        print("GPU count:", torch.cuda.device_count())
        if torch.cuda.is_available():
            print("GPU name:", torch.cuda.get_device_name(0))
    resources:
      limits:
        nvidia.com/gpu: 1
```

## ML Workload Examples

### Jupyter Notebook with GPU

Deploy JupyterLab with GPU access:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: jupyter-gpu
  labels:
    app: jupyter
spec:
  runtimeClassName: nvidia
  containers:
  - name: jupyter
    image: jupyter/tensorflow-notebook:latest
    ports:
    - containerPort: 8888
    env:
    - name: JUPYTER_ENABLE_LAB
      value: "yes"
    resources:
      limits:
        nvidia.com/gpu: 1
        memory: 16Gi
      requests:
        memory: 8Gi
---
apiVersion: v1
kind: Service
metadata:
  name: jupyter-gpu
spec:
  type: NodePort
  selector:
    app: jupyter
  ports:
  - port: 8888
    targetPort: 8888
    nodePort: 30888
```

Access:
```bash
kubectl apply -f jupyter-gpu.yaml

# Get token
kubectl logs jupyter-gpu | grep token

# Access at: http://<node-ip>:30888
```

### Stable Diffusion WebUI

Run Stable Diffusion for AI image generation:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stable-diffusion
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stable-diffusion
  template:
    metadata:
      labels:
        app: stable-diffusion
    spec:
      runtimeClassName: nvidia
      containers:
      - name: webui
        image: ghcr.io/abetlen/llama-cpp-python:latest
        ports:
        - containerPort: 7860
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: 24Gi
          requests:
            memory: 16Gi
        volumeMounts:
        - name: models
          mountPath: /models
      volumes:
      - name: models
        persistentVolumeClaim:
          claimName: stable-diffusion-models
---
apiVersion: v1
kind: Service
metadata:
  name: stable-diffusion
spec:
  type: NodePort
  selector:
    app: stable-diffusion
  ports:
  - port: 7860
    nodePort: 30786
```

### LLM Inference Server

Deploy a Large Language Model inference server:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llm-inference
  template:
    metadata:
      labels:
        app: llm-inference
    spec:
      runtimeClassName: nvidia
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        args:
          - --model
          - meta-llama/Llama-2-7b-chat-hf
          - --gpu-memory-utilization
          - "0.9"
        ports:
        - containerPort: 8000
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: 24Gi
          requests:
            memory: 16Gi
        env:
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token
              key: token
```

## Storage for ML Workloads

ML workloads need fast storage for datasets and models.

### Option 1: Local NVMe Storage

Best performance for training:

```bash
# Install local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Create storage class for GPU nodes
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-gpu-storage
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
- matchLabelExpressions:
  - key: kubernetes.io/hostname
    values:
    - gpu-worker-1
    - gpu-worker-2
EOF
```

### Option 2: Network Storage (NFS)

For shared datasets across GPU nodes:

```bash
# Create PVC for shared ML datasets
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-datasets
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 500Gi
EOF
```

### Option 3: S3-compatible (MinIO)

For model storage and versioning:

```bash
# Deploy MinIO
helm repo add minio https://charts.min.io/
helm install minio minio/minio \
  --namespace minio \
  --create-namespace \
  --set replicas=1 \
  --set persistence.size=500Gi \
  --set resources.requests.memory=4Gi
```

## MLOps Tools

### KubeFlow

Complete ML platform:

```bash
# Install kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash

# Install Kubeflow
kustomize build github.com/kubeflow/manifests/example | kubectl apply -f -

# Access Kubeflow UI
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
```

### MLflow

Experiment tracking:

```bash
helm repo add mlflow https://larribas.me/helm-charts
helm install mlflow mlflow/mlflow \
  --namespace mlflow \
  --create-namespace \
  --set backendStore.postgres.enabled=true
```

### Ray Cluster

Distributed computing for ML:

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install raycluster kuberay/ray-cluster \
  --namespace ray \
  --create-namespace \
  --set worker.replicas=2 \
  --set worker.resources.limits."nvidia\.com/gpu"=1
```

## Monitoring GPU Usage

### NVIDIA DCGM Exporter

Export GPU metrics to Prometheus:

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace kube-system \
  --set serviceMonitor.enabled=true
```

### Grafana Dashboard

Import GPU monitoring dashboard:
1. Install Grafana (see homelab example)
2. Import dashboard ID: 12239 (NVIDIA DCGM Exporter)
3. View real-time GPU metrics

## Node Affinity and Taints

Schedule GPU workloads on GPU nodes only:

### Label GPU Nodes

```bash
# Label GPU worker nodes
kubectl label nodes <gpu-worker-1> gpu=nvidia
kubectl label nodes <gpu-worker-2> gpu=nvidia
```

### Use Node Affinity in Pods

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: gpu
            operator: In
            values:
            - nvidia
```

### Taint GPU Nodes (Optional)

Prevent non-GPU workloads from using GPU nodes:

```bash
# Taint GPU nodes
kubectl taint nodes <gpu-worker-1> nvidia.com/gpu=present:NoSchedule
kubectl taint nodes <gpu-worker-2> nvidia.com/gpu=present:NoSchedule
```

Add toleration to GPU pods:
```yaml
spec:
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

## Cost Optimization

### Multi-Instance GPU (MIG)

For NVIDIA A100/A30, partition GPU:

```bash
# Enable MIG mode (Talos node)
talosctl -n <gpu-node> apply-config -p @gpu-mig.yaml

# Create instances (example: 3x A100 slices)
nvidia-smi mig -cgi 19,19,19 -C
```

### GPU Time Slicing

Share GPUs across multiple pods:

```bash
# Update device plugin config
kubectl patch daemonset nvidia-device-plugin \
  -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "NVIDIA_MIG_MONITOR_DEVICES", "value": "all"}}]'
```

## Troubleshooting

### GPU Not Detected

```bash
# Check GPU passthrough in Proxmox
qm config <vmid> | grep hostpci

# Check PCI devices in VM
talosctl -n <gpu-node> ls /sys/bus/pci/devices/

# Check NVIDIA modules loaded
talosctl -n <gpu-node> read /proc/modules | grep nvidia
```

### "nvidia-smi not found"

The nvidia-smi command runs **inside containers**, not on Talos host:

```bash
# Correct way:
kubectl run test --rm -it --restart=Never \
  --image=nvidia/cuda:12.0.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","containers":[{"name":"test","image":"nvidia/cuda:12.0.0-base-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}' \
  -- nvidia-smi
```

### Pods Not Getting GPU

1. Check RuntimeClass exists: `kubectl get runtimeclass nvidia`
2. Check device plugin running: `kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin`
3. Check GPU resources: `kubectl describe node <gpu-node> | grep nvidia.com/gpu`
4. Verify pod spec includes `runtimeClassName: nvidia`

## Best Practices

1. **Always use RuntimeClass** - Required for GPU access
2. **Set resource limits** - Prevent OOM on GPU nodes
3. **Use node affinity** - Keep GPU workloads on GPU nodes
4. **Monitor GPU utilization** - Use DCGM exporter
5. **Version control models** - Use MLflow or DVC
6. **Implement autoscaling** - Based on GPU metrics
7. **Regular driver updates** - Keep extensions up to date

## Next Steps

- Deploy your first ML model for inference
- Set up MLflow for experiment tracking
- Configure GPU node autoscaling
- Integrate with CI/CD for model deployment
- Explore Kubeflow for end-to-end MLOps

## Resources

- [Talos GPU Guide](../../talos-configs/README.md)
- [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [KubeFlow Documentation](https://www.kubeflow.org/docs/)
- [Ray Documentation](https://docs.ray.io/)
