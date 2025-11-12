# Deployment Workflow: Omni + Talos + Proxmox

Complete step-by-step guide for deploying a Talos Kubernetes cluster using Sidero Omni and Proxmox VE.

## Overview

This workflow will create a production-ready Kubernetes cluster with:
- 3 Control Plane nodes
- 2-3 Worker nodes (with Longhorn storage)
- 0-1 GPU Worker nodes (with Longhorn storage + NVIDIA GPU support)
- Static IPs with MAC-based network interface selection
- Automated VM provisioning via Terraform
- GitOps-based machine configuration via Omni cluster templates

## Prerequisites

Before starting, ensure you have:

### 1. Sidero Omni Instance
- Self-hosted Omni running (e.g., at `192.168.10.15`)
- Omni account and service account token
- `omnictl` CLI installed and configured

### 2. Proxmox VE Server
- Proxmox VE 8.x installed (single node or cluster)
- API token created: `terraform@pve!terraform`
- Storage configured: `local-lvm` (or custom storage)
- Network bridge: `vmbr0`
- ISO storage: `local` (for Talos ISOs)

### 3. Local Workstation
- Terraform >= 1.0 installed
- `omnictl` configured to connect to your Omni instance
- `jq` installed (for JSON parsing)
- Git (to clone this repository)

### 4. Network Planning
- Subnet: `192.168.10.0/24` (or your subnet)
- Gateway: `192.168.10.1`
- DNS: `1.1.1.1`, `1.0.0.1` (Cloudflare)
- IP Ranges:
  - Control Planes: `192.168.10.100-102`
  - Workers: `192.168.10.110-112`
  - GPU Workers: `192.168.10.115+`

---

## Step 1: Generate Talos ISOs in Omni

### 1.1 Generate Standard ISO

In the Omni UI:

1. Navigate to **Settings** → **Download Installation Media**
2. Click **Download Installation Media**
3. Select **Talos Linux v1.11.5**
4. Under **System Extensions**, select:
   - `siderolabs/qemu-guest-agent`
   - `siderolabs/nfsd`
   - `siderolabs/iscsi-tools`
   - `siderolabs/util-linux-tools`
5. Click **Generate Installation Media**
6. Download the ISO
7. Rename it to: `talos-1.11.5.iso`

### 1.2 Generate GPU ISO

In the Omni UI:

1. Navigate to **Settings** → **Download Installation Media**
2. Click **Download Installation Media**
3. Select **Talos Linux v1.11.5**
4. Under **System Extensions**, select:
   - `siderolabs/qemu-guest-agent`
   - `siderolabs/nfsd`
   - `siderolabs/iscsi-tools`
   - `siderolabs/util-linux-tools`
   - `siderolabs/nonfree-kmod-nvidia-production`
   - `siderolabs/nvidia-container-toolkit-production`
5. Click **Generate Installation Media**
6. Download the ISO
7. Rename it to: `talos-1.11.5-gpu.iso`

### 1.3 Upload ISOs to Proxmox

Upload both ISOs to your Proxmox server:

```bash
# Option 1: Via Proxmox Web UI
# Navigate to: Node → local → ISO Images → Upload

# Option 2: Via SCP
scp talos-1.11.5.iso root@192.168.10.160:/var/lib/vz/template/iso/
scp talos-1.11.5-gpu.iso root@192.168.10.160:/var/lib/vz/template/iso/
```

Verify ISOs are uploaded:
```bash
ssh root@192.168.10.160
ls -lh /var/lib/vz/template/iso/talos*.iso
```

---

## Step 2: Configure Terraform

### 2.1 Create Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### 2.2 Edit Terraform Variables

Edit `terraform/terraform.tfvars` and update:

1. **Proxmox API Token**:
   ```hcl
   api_token_secret = "YOUR_ACTUAL_PROXMOX_API_TOKEN"
   ```

2. **MAC Addresses** (if using specific MACs for Firewalla):
   - Update control_planes, workers, and gpu_workers MAC addresses
   - Or leave as-is to use old working MACs from config

3. **VM Resources** (optional):
   - Adjust CPU cores, memory, disk sizes per VM
   - Set `data_disk_size_gb = 0` to disable secondary storage

4. **Storage Overrides** (optional):
   - Set `storage_os_override` or `storage_data_override` to use custom Proxmox storage
   - Leave empty (`""`) to use defaults

### 2.3 Initialize Terraform

```bash
cd terraform
terraform init
```

---

## Step 3: Create VMs with Terraform

### 3.1 Review Terraform Plan

```bash
terraform plan
```

Review:
- Number of VMs to be created (7 total: 3 control planes, 2-3 workers, 0-1 GPU)
- MAC addresses
- IP addresses
- Storage configuration
- ISOs being used

### 3.2 Apply Terraform Configuration

```bash
terraform apply
```

Type `yes` to confirm and create VMs.

**Expected duration**: 2-5 minutes

### 3.3 Verify VMs Created

Check Proxmox UI:
- All VMs should be visible with correct names
- VMs should be starting/running
- Check console to see Talos boot process

View Terraform output:
```bash
terraform output cluster_summary
```

---

## Step 4: Wait for Machines to Register with Omni

After VMs boot with Talos ISOs, they will:
1. Boot Talos Linux
2. Connect to Omni via SideroLink (embedded in ISO)
3. Register as "Unknown" machines in Omni

**Expected duration**: 2-5 minutes after VMs boot

### 4.1 Check Omni UI

Navigate to Omni UI → **Machines**

You should see 6-7 new machines in "Unknown" state with:
- Machine UUIDs
- Status: "Unknown" or "Available"
- Connection status: "Connected"

### 4.2 Verify Network Connectivity

If machines don't appear after 5 minutes, troubleshoot:

**Check VM Console (Proxmox)**:
- Is Talos booting correctly?
- Are there network errors?
- Can the VM reach internet?

**Check Omni Logs**:
```bash
# If running Omni in Docker
docker logs omni | grep -i error

# If running as systemd service
journalctl -u omni -f
```

**Common Issues**:
- Firewall blocking SideroLink (port 443)
- Network misconfiguration in Proxmox
- ISOs not generated with Omni join token

---

## Step 5: Discover and Match Machines

### 5.1 Run Discovery Script

```bash
cd scripts
./discover-machines.sh
```

This script will:
1. Query Omni for all registered machines
2. Match them to Terraform VMs by MAC address
3. Create `machine-data/matched-machines.json`
4. Apply labels to machines in Omni for easy sorting
5. Create quick reference files

**Expected output**:
```
✓ Found 6 machines in Terraform inventory
✓ Found 6 machines registered in Omni
✓ Matched: talos-control-1 (AC:24:21:A4:B2:97) -> Omni UUID: abc123...
✓ Matched: talos-control-2 (BC:24:11:3A:F0:18) -> Omni UUID: def456...
...
Matched: 6
```

### 5.2 Verify Matched Machines

Review matched machines:
```bash
cat scripts/machine-data/matched-machines.json | jq '.[] | {hostname, role, ip_address, mac_address}'
```

Check machine labels in Omni UI:
- Each machine should have labels: `role`, `hostname`, `node-role`, `has-longhorn`

### 5.3 Troubleshooting

**If some machines don't match**:
- Check MAC addresses in Proxmox vs Terraform
- Verify VMs have booted and connected to Omni
- Check Omni UI for machine status

**If no machines match**:
- Verify Terraform was applied successfully
- Check VMs are running in Proxmox
- Ensure ISOs were generated from correct Omni instance

---

## Step 6: Generate Machine Configurations

### 6.1 Run Configuration Generator

```bash
cd scripts
./generate-machine-configs.sh
```

When prompted for cluster name, enter: `talos-prod-cluster` (or press Enter for default)

This script will:
1. Read matched machines from Step 5
2. Generate individual machine YAML configs
3. Create combined `cluster-template.yaml`
4. Include all critical fixes:
   - deviceSelector with hardwareAddr (MAC-based interface selection)
   - dhcp: false (prevent DHCP override)
   - Static IPs and gateway
   - DNS: 1.1.1.1, 1.0.0.1
   - Longhorn disk mounting (for workers/GPU workers)
   - Node labels and role configurations

**Expected output**:
```
✓ Generated 6 machine configurations
✓ Combined cluster template created

Generated configurations:
  Control Planes: 3
  Workers:        2
  GPU Workers:    1
  Total:          6
```

### 6.2 Review Generated Configurations

```bash
# View combined cluster template
cat scripts/machine-configs/cluster-template.yaml | less

# View individual machine config
cat scripts/machine-configs/talos-control-1.yaml
```

**Key sections to verify**:
- Network interfaces use `deviceSelector` with `hardwareAddr`
- `dhcp: false` is set
- Nameservers are `1.1.1.1` and `1.0.0.1`
- Workers have `machine.disks` configuration
- Workers have correct Longhorn mount: `/var/mnt/longhorn_sdb`

---

## Step 7: Apply Cluster Configuration to Omni

### 7.1 Sync Cluster Template

Apply the generated cluster template to Omni:

```bash
cd scripts
omnictl cluster template sync -f machine-configs/cluster-template.yaml
```

This will:
1. Create the cluster in Omni
2. Apply all machine patches (hostname, network, storage, etc.)
3. Assign machines to control plane and worker pools
4. Install NVIDIA extensions on GPU workers

**Expected duration**: 5-10 minutes for full cluster formation

### 7.2 Monitor Cluster Formation

**Watch in Omni UI**:
1. Navigate to **Clusters** → `talos-prod-cluster`
2. Watch machines transition:
   - "Configuring" → "Installing" → "Running"
3. Check machine phases:
   - All control planes should become "Running"
   - All workers should become "Running"

**Watch from CLI**:
```bash
# Check cluster status
omnictl get clusters

# Check machine status
omnictl get machines

# Watch cluster events
omnictl get events -f
```

### 7.3 Verify Cluster Health

Once all nodes are "Running", verify cluster health:

```bash
# Get kubeconfig
omnictl kubeconfig -c talos-prod-cluster > ~/.kube/omni-talos-prod

# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Verify all nodes are Ready
kubectl get nodes
```

**Expected output**:
```
NAME               STATUS   ROLES           AGE   VERSION
talos-control-1    Ready    control-plane   5m    v1.34.1
talos-control-2    Ready    control-plane   5m    v1.34.1
talos-control-3    Ready    control-plane   5m    v1.34.1
talos-worker-1     Ready    worker          4m    v1.34.1
talos-worker-2     Ready    worker          4m    v1.34.1
talos-gpu-worker-1 Ready    worker          4m    v1.34.1
```

---

## Step 8: Verify Static IPs and Network Configuration

### 8.1 Verify Static IPs Applied

Check each node has its expected IP:

```bash
# From control plane
kubectl get nodes -o custom-columns=NAME:.metadata.name,INTERNAL-IP:.status.addresses[0].address

# Or use omnictl
omnictl get machinestatus -o json | jq -r '.[] | select(.metadata.namespace=="default") | "\(.metadata.id): \(.spec.network.addresses)"'
```

### 8.2 Test Network Connectivity

SSH to a control plane via Omni:

```bash
# Get talosconfig
omnictl talosconfig -c talos-prod-cluster

# Check network config
talosctl get links
talosctl get addresses

# Verify DNS resolution
talosctl exec -- nslookup kubernetes.default.svc.cluster.local
talosctl exec -- nslookup google.com
```

### 8.3 Verify No DHCP Leases

Check your router/DHCP server (Firewalla):
- No DHCP leases for Talos machine MACs
- Only static IP assignments visible
- DNS queries work from Talos nodes

---

## Step 9: Verify Longhorn Storage

### 9.1 Check Disk Mounts

For each worker and GPU worker, verify disk is mounted:

```bash
# SSH to worker via omnictl
omnictl talosconfig -c talos-prod-cluster
talosctl -n 192.168.10.111 get disks

# Check mount points
talosctl -n 192.168.10.111 exec -- df -h | grep longhorn

# Expected output:
/dev/sdb1       200G   1.5G  198G   1% /var/mnt/longhorn_sdb
```

### 9.2 Verify Kubelet Mount

Check kubelet can access Longhorn directory:

```bash
talosctl -n 192.168.10.111 exec -- ls -la /var/lib/longhorn

# Should show it's a bind mount to /var/mnt/longhorn_sdb
```

### 9.3 Install Longhorn

Deploy Longhorn to your cluster:

```bash
# Add Longhorn Helm repo
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultDataPath="/var/lib/longhorn"

# Wait for Longhorn to be ready
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get nodes
```

Verify Longhorn detected all worker disks:
```bash
kubectl -n longhorn-system get nodes.longhorn.io -o wide
```

---

## Step 10: Verify GPU Passthrough (GPU Workers Only)

### 10.1 Configure GPU Passthrough in Proxmox

For GPU workers, configure Proxmox mapped resource:

1. Navigate to Proxmox UI → **Datacenter** → **Resource Mappings**
2. Add PCI device mapping: `nvidia-gpu-1`
3. Map to your NVIDIA GPU device (e.g., `01:00.0`)

This should already be configured by Terraform, but verify:

```bash
ssh root@192.168.10.160
qm config <GPU_WORKER_VMID> | grep hostpci
# Should show: hostpci0: mapping=nvidia-gpu-1,pcie=1
```

### 10.2 Verify NVIDIA Drivers Loaded

SSH to GPU worker:

```bash
omnictl talosconfig -c talos-prod-cluster
talosctl -n 192.168.10.115 exec -- nvidia-smi
```

**Expected output**:
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.xx.xx            Driver Version: 535.xx.xx    CUDA Version: |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  NVIDIA GeForce ...  Off  | 00000000:01:00.0 Off |                  N/A |
...
```

### 10.3 Install NVIDIA Device Plugin

Deploy NVIDIA device plugin:

```bash
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Verify plugin is running
kubectl get pods -n kube-system | grep nvidia
```

Check GPU is detected in Kubernetes:

```bash
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpu: .status.capacity."nvidia.com/gpu"}'
```

---

## Step 11: Validate Entire Cluster

### 11.1 Run Cluster Validation Tests

```bash
# All nodes ready
kubectl get nodes
kubectl get nodes -o wide

# All system pods running
kubectl get pods -A

# Check cluster info
kubectl cluster-info

# Check API server health
kubectl get --raw /healthz

# Check component status
kubectl get cs
```

### 11.2 Deploy Test Workload

Deploy a simple nginx test:

```bash
# Create test namespace
kubectl create namespace test

# Deploy nginx
kubectl -n test create deployment nginx --image=nginx:latest --replicas=3

# Expose nginx
kubectl -n test expose deployment nginx --port=80 --type=NodePort

# Check deployment
kubectl -n test get pods -o wide
kubectl -n test get svc nginx

# Test access
NODE_PORT=$(kubectl -n test get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://192.168.10.110:${NODE_PORT}
```

### 11.3 Test GPU Workload (GPU Workers Only)

Deploy GPU test workload:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: test
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    nvidia.com/gpu: "true"
EOF

# Check pod scheduled to GPU worker
kubectl -n test get pod gpu-test -o wide

# Check logs
kubectl -n test logs gpu-test
```

---

## Troubleshooting Guide

### Machines Not Appearing in Omni

**Symptoms**: VMs created but don't register in Omni

**Causes**:
- ISOs not generated from correct Omni instance
- Network connectivity issues
- Firewall blocking SideroLink

**Solutions**:
1. Verify ISOs were generated in Omni UI (not Factory directly)
2. Check VM console - is Talos booting?
3. Check network connectivity: `ping 8.8.8.8` from VM console
4. Verify Omni is reachable from VMs
5. Check firewall rules (allow outbound 443)

### Static IPs Not Applying

**Symptoms**: Machines get DHCP IPs instead of static IPs

**Causes**:
- Missing `deviceSelector` with `hardwareAddr`
- Missing `dhcp: false`
- Configuration not applied via cluster template sync

**Solutions**:
1. Verify cluster template has `deviceSelector` and `dhcp: false`
2. Re-run `./generate-machine-configs.sh`
3. Re-sync cluster template: `omnictl cluster template sync -f ...`
4. Check machine patches applied: `omnictl get machine <uuid> -o yaml`

### Longhorn Disk Not Mounting

**Symptoms**: Longhorn can't find storage, `/var/lib/longhorn` empty

**Causes**:
- Missing `machine.disks` configuration
- Wrong mount path in kubelet extraMounts
- Terraform didn't create secondary disk

**Solutions**:
1. Verify secondary disk exists in Proxmox VM hardware
2. Check mount point: `talosctl exec -- df -h | grep longhorn`
3. Verify cluster template has both `machine.disks` AND `kubelet.extraMounts`
4. Ensure mount source is `/var/mnt/longhorn_sdb` not `/var/mnt/longhorn`
5. Re-generate config: `./generate-machine-configs.sh`

### DNS Resolution Failing

**Symptoms**: Pods can't resolve DNS, `nslookup` fails

**Causes**:
- Wrong nameservers (using gateway instead of DNS)
- hostDNS not enabled
- CoreDNS pods not running

**Solutions**:
1. Verify nameservers in cluster template are `1.1.1.1` and `1.0.0.1`
2. Check hostDNS enabled: `omnictl get machine <uuid> -o yaml | grep hostDNS`
3. Check CoreDNS pods: `kubectl -n kube-system get pods | grep coredns`
4. Test from node: `talosctl exec -- nslookup google.com`

### GPU Not Detected

**Symptoms**: `nvidia-smi` fails, no GPU in Kubernetes

**Causes**:
- GPU passthrough not configured in Proxmox
- NVIDIA extensions not loaded
- GPU device plugin not installed

**Solutions**:
1. Verify Proxmox GPU mapping: `qm config <vmid> | grep hostpci`
2. Check NVIDIA kernel modules: `talosctl exec -- lsmod | grep nvidia`
3. Verify system extensions in Omni UI
4. Re-generate GPU ISO with NVIDIA extensions
5. Install NVIDIA device plugin

### Cluster Not Forming

**Symptoms**: Machines stuck in "Configuring" or "Unknown"

**Causes**:
- Cluster template not synced correctly
- Network connectivity issues between nodes
- Insufficient resources

**Solutions**:
1. Check Omni cluster events: `omnictl get events`
2. Verify machine patches: `omnictl get machine <uuid> -o yaml`
3. Check node connectivity: `ping` between node IPs
4. Verify sufficient CPU/RAM allocated to VMs
5. Check etcd health on control planes

---

## Maintenance Operations

### Update Cluster Template

To update machine configurations:

```bash
# Edit terraform/terraform.tfvars (if needed)
cd terraform && terraform apply

# Re-run discovery and generation
cd ../scripts
./discover-machines.sh
./generate-machine-configs.sh

# Sync updated template
omnictl cluster template sync -f machine-configs/cluster-template.yaml
```

### Add New Worker Node

1. Add worker to `terraform/terraform.tfvars`:
   ```hcl
   workers = [
     # ... existing workers
     {
       name              = "talos-worker-4"
       proxmox_server    = "pve1"
       ip_address        = "192.168.10.113"
       mac_address       = "AC:24:21:4C:99:A4"
       cpu_cores         = 8
       memory_mb         = 16384
       os_disk_size_gb   = 100
       data_disk_size_gb = 200
     }
   ]
   ```

2. Apply Terraform:
   ```bash
   cd terraform && terraform apply
   ```

3. Wait for machine to register, then re-run discovery and config generation:
   ```bash
   cd scripts
   ./discover-machines.sh
   ./generate-machine-configs.sh
   omnictl cluster template sync -f machine-configs/cluster-template.yaml
   ```

### Remove Node

1. Drain node:
   ```bash
   kubectl drain talos-worker-3 --ignore-daemonsets --delete-emptydir-data
   ```

2. Remove from Omni cluster template (edit `cluster-template.yaml`)

3. Sync template:
   ```bash
   omnictl cluster template sync -f machine-configs/cluster-template.yaml
   ```

4. Remove VM from Terraform:
   ```bash
   cd terraform
   # Edit terraform.tfvars to remove worker
   terraform apply
   ```

### Backup Cluster Configuration

```bash
# Backup Terraform state
cd terraform
cp terraform.tfstate terraform.tfstate.backup

# Backup machine discovery data
cd ../scripts
tar -czf machine-data-backup-$(date +%Y%m%d).tar.gz machine-data/

# Backup cluster template
cp machine-configs/cluster-template.yaml cluster-template-backup-$(date +%Y%m%d).yaml

# Backup Kubernetes etcd (via Omni)
omnictl backup create -c talos-prod-cluster
```

---

## Quick Reference

### Important Files

| File | Purpose |
|------|---------|
| `terraform/terraform.tfvars` | VM configuration (IPs, MACs, resources) |
| `scripts/machine-data/matched-machines.json` | UUID-to-VM mapping |
| `scripts/machine-configs/cluster-template.yaml` | Complete cluster configuration for Omni |
| `scripts/discover-machines.sh` | Discover and match machines by MAC |
| `scripts/generate-machine-configs.sh` | Generate Omni cluster template |

### Important Commands

```bash
# Terraform operations
cd terraform
terraform plan           # Preview changes
terraform apply          # Create/update VMs
terraform destroy        # Remove all VMs

# Discovery and configuration
cd scripts
./discover-machines.sh                    # Match machines to VMs
./generate-machine-configs.sh             # Generate cluster template
omnictl cluster template sync -f ...      # Apply configuration

# Cluster operations
omnictl get clusters                      # List clusters
omnictl get machines                      # List machines
omnictl get events                        # View cluster events
omnictl kubeconfig -c <cluster>           # Get kubeconfig
omnictl talosconfig -c <cluster>          # Get talosconfig

# Talos operations
talosctl -n <ip> get links                # View network interfaces
talosctl -n <ip> get addresses            # View IP addresses
talosctl -n <ip> get disks                # View disks
talosctl -n <ip> exec -- <command>        # Run command on node

# Kubernetes operations
kubectl get nodes                         # List nodes
kubectl get pods -A                       # List all pods
kubectl get events -A                     # View events
```

### Network Configuration

| Component | Configuration |
|-----------|---------------|
| Subnet | `192.168.10.0/24` |
| Gateway | `192.168.10.1` |
| DNS | `1.1.1.1`, `1.0.0.1` |
| Control Planes | `192.168.10.100-102` |
| Workers | `192.168.10.110-112` |
| GPU Workers | `192.168.10.115+` |

### Default Resource Allocations

| Node Type | CPU | RAM | OS Disk | Data Disk |
|-----------|-----|-----|---------|-----------|
| Control Plane | 4 cores | 8GB | 70GB | 0GB |
| Worker | 8 cores | 16GB | 70GB | 250GB |
| GPU Worker | 16 cores | 32GB | 70GB | 250GB |

---

## Next Steps After Deployment

1. **Install Essential Add-ons**:
   - Longhorn for storage
   - MetalLB for LoadBalancer services
   - Traefik/Nginx for Ingress
   - Cert-Manager for TLS certificates

2. **Configure Monitoring**:
   - Prometheus + Grafana
   - Talos Dashboard in Omni UI

3. **Set Up GitOps**:
   - ArgoCD or Flux
   - Store cluster template in Git

4. **Harden Security**:
   - Enable Pod Security Standards
   - Configure Network Policies
   - Set up RBAC

5. **Test Disaster Recovery**:
   - Take etcd backups
   - Practice cluster restore
   - Document recovery procedures

---

## Support and Resources

- **Talos Documentation**: https://www.talos.dev/
- **Sidero Omni Documentation**: https://omni.siderolabs.com/docs/
- **Proxmox VE Documentation**: https://pve.proxmox.com/wiki/
- **Longhorn Documentation**: https://longhorn.io/docs/
- **This Repository**: File issues and PRs for improvements

---

**Last Updated**: 2025-01-12
**Talos Version**: v1.11.5
**Kubernetes Version**: v1.34.1
**Omni Version**: Latest
