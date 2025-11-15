# Machine Classes

Machine classes define the VM specifications for nodes provisioned by the Proxmox infrastructure provider.

## Available Machine Classes

### 1. Control Plane (`control-plane.yaml`)
**Purpose**: Kubernetes control plane nodes (manage the cluster)

**Specs**:
- CPU: 4 cores
- RAM: 8GB
- Disk: 50GB
- Storage: `ssd512`

**Usage**:
```bash
omnictl apply -f machine-classes/control-plane.yaml
```

### 2. Worker (`worker.yaml`)
**Purpose**: Standard worker nodes (run application workloads)

**Specs**:
- CPU: 4 cores
- RAM: 8GB
- Disk: 100GB
- Storage: `local-lvm`

**Usage**:
```bash
omnictl apply -f machine-classes/worker.yaml
```

### 3. GPU Worker (`gpu-worker.yaml`)
**Purpose**: GPU-enabled worker nodes (AI/ML workloads)

**Specs**:
- CPU: 8 cores
- RAM: 32GB
- Disk: 200GB
- Storage: `local-lvm`

**Special Configuration**:
GPU passthrough must be configured manually in Proxmox after VM creation. See comments in the YAML file for instructions.

**Usage**:
```bash
omnictl apply -f machine-classes/gpu-worker.yaml
```

## Prerequisites

Before applying machine classes:

1. **Authenticate omnictl**:
   ```bash
   omnictl get machineclass
   # Follow the authentication URL if prompted
   ```

2. **Verify Proxmox provider is running**:
   ```bash
   cd ../proxmox-provider
   docker compose ps
   ```

3. **Check provider is connected in Omni UI**:
   - Settings → Infrastructure Providers
   - Should show "proxmox" provider as "Connected"

## Applying All Machine Classes

Apply all at once:

```bash
omnictl apply -f machine-classes/control-plane.yaml
omnictl apply -f machine-classes/worker.yaml
omnictl apply -f machine-classes/gpu-worker.yaml
```

Or use a loop:

```bash
for f in machine-classes/*.yaml; do
  omnictl apply -f "$f"
done
```

## Storage Selectors

The `storageSelector` field uses CEL (Common Expression Language) to select Proxmox storage pools.

**Examples**:

```yaml
# Select by name
storageSelector: 'name == "ssd512"'

# Select by type
storageSelector: 'type == "lvmthin" && enabled && active'

# Select first available ZFS pool
storageSelector: 'type == "zfspool" && enabled && active'

# Select storage with most free space
storageSelector: 'enabled && active'  # Provider will choose best match
```

**Common storage types in Proxmox**:
- `lvmthin` - LVM-Thin (most common)
- `zfspool` - ZFS pool
- `dir` - Directory
- `nfs` - NFS mount
- `rbd` - Ceph RBD

To see your Proxmox storage pools:
```bash
pvesm status
```

## Customizing Machine Classes

Edit the YAML files to match your needs:

### Change CPU/Memory/Disk
```yaml
config:
  cpu: 8        # Change to 8 cores
  memory: 16384 # Change to 16GB
  diskSize: 200 # Change to 200GB
```

### Change Storage
```yaml
storageSelector: 'name == "your-storage-name"'
```

### Change Machine Class Name
```yaml
metadata:
  name: my-custom-class-name
```

## Verifying Machine Classes

After applying, verify they were created:

```bash
# List all machine classes
omnictl get machineclass

# Get specific machine class details
omnictl get machineclass homelab-control-plane -o yaml
```

## Using Machine Classes in Clusters

Once created, reference machine classes when creating a cluster in Omni UI:

1. **Create Cluster** → Configure cluster
2. **Control Plane**:
   - Machine Class: `homelab-control-plane`
   - Replicas: `1` (or `3` for HA)
3. **Workers**:
   - Machine Class: `homelab-worker`
   - Replicas: `2` (or more)
4. **(Optional) GPU Workers**:
   - Machine Class: `homelab-gpu-worker`
   - Replicas: `1` (or more)

## Troubleshooting

### Machine class not appearing in Omni UI

1. Check if applied successfully:
   ```bash
   omnictl get machineclass
   ```

2. Check provider logs:
   ```bash
   cd ../proxmox-provider
   docker compose logs -f
   ```

3. Verify provider is connected in Omni UI (Settings → Infrastructure Providers)

### VMs not being created

1. Check machine class storage selector matches your Proxmox storage:
   ```bash
   pvesm status  # On Proxmox host
   ```

2. Update `storageSelector` in YAML to match actual storage name

3. Check provider has permissions to create VMs in Proxmox

### Storage selector errors

If you get errors about storage not found:

1. List available storage in Proxmox:
   ```bash
   pvesm status
   ```

2. Update the `storageSelector` to match an actual storage pool:
   ```yaml
   storageSelector: 'name == "actual-storage-name"'
   ```

## Next Steps

After applying machine classes:

1. **Create a cluster** in Omni UI
2. **Select machine classes** for control plane and workers
3. **Watch the magic happen** - VMs will be auto-created in Proxmox
4. **Download kubeconfig** once cluster is ready
5. **Deploy workloads** with `kubectl`

For complete examples, see:
- [Simple Homelab](../examples/simple-homelab/README.md)
- [GPU ML Cluster](../examples/gpu-ml-cluster/README.md)
- [Production HA](../examples/production-ha/README.md)
