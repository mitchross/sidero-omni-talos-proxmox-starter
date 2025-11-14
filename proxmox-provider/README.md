# Omni Infrastructure Provider for Proxmox

This guide walks through setting up the Proxmox infrastructure provider that automatically provisions Talos VMs in your Proxmox cluster based on Omni machine classes.

## Overview

The Proxmox provider is a bridge between Omni and your Proxmox cluster:
- Watches Omni API for machine requests
- Automatically creates VMs in Proxmox matching machine class specifications
- Manages VM lifecycle (creation, updates, deletion)
- Reports VM status back to Omni

## Prerequisites

Before starting:
- [Omni deployed](../omni/README.md) and accessible
- Proxmox VE cluster running and accessible
- Infrastructure Provider Key generated in Omni UI

### Generate Infrastructure Provider Key

1. Log into your Omni instance
2. Navigate to **Settings** → **Infrastructure Providers**
3. Click **Create Infrastructure Provider**
4. Select **Proxmox** as the provider type
5. Give it a name (e.g., "proxmox-homelab")
6. Copy the generated **Infrastructure Provider Key**

⚠️ **Important**: This is an **Infrastructure Provider Key**, NOT a service account key.

## Setup Steps

### 1. Configure Provider Settings

Copy the example files:

```bash
cd proxmox-provider/
cp .env.example .env
cp config.yaml.example config.yaml
```

### 2. Edit Environment File

Edit `.env` and add your infrastructure provider key:

```bash
# Omni Infrastructure Provider Key (from Omni UI)
OMNI_INFRA_PROVIDER_KEY=your-key-here
```

### 3. Configure Proxmox Connection

Edit `config.yaml` with your Proxmox details:

```yaml
proxmox:
  # Proxmox API credentials
  # Using root@pam is recommended for full permissions
  username: "root@pam"
  password: "your-proxmox-password"

  # Proxmox API endpoint
  # Format: https://proxmox-host:8006/api2/json
  url: "https://192.168.1.100:8006/api2/json"

  # Skip SSL verification (useful for self-signed certs)
  # Set to false in production with valid certificates
  insecureSkipVerify: true
```

**Security Note**: For production, consider creating a dedicated Proxmox user with limited permissions instead of using root.

### 4. Deploy the Provider

Start the provider container:

```bash
docker compose up -d
```

Check logs to verify connection:

```bash
docker compose logs -f omni-infra-provider-proxmox
```

Look for successful connection messages to both Omni and Proxmox APIs.

### 5. Configure Machine Classes in Omni

Machine classes define the VM specifications for different node types.

#### Via Omni UI (Recommended)

1. Log into Omni
2. Navigate to **Settings** → **Machine Classes**
3. Click **Create Machine Class**
4. Select your Proxmox provider
5. Configure specifications:
   - **Name**: e.g., "proxmox-worker-small"
   - **CPU**: Number of cores (e.g., 4)
   - **Memory**: RAM in MB (e.g., 8192)
   - **Disk**: Size in GB (e.g., 100)
   - **Storage**: CEL expression to select storage (see below)

#### Example Machine Class Configurations

**Small Worker Node**:
```yaml
cpu: 4
memory: 8192  # 8GB
disk: 100     # 100GB
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

**Large Worker Node**:
```yaml
cpu: 8
memory: 16384  # 16GB
disk: 200      # 200GB
storage: |
  storage.filter(s, s.type == "zfspool" && s.enabled && s.active)[0].storage
```

**Control Plane Node**:
```yaml
cpu: 4
memory: 8192
disk: 50
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

### 6. Storage Selection (CEL Expressions)

The provider uses CEL (Common Expression Language) to select Proxmox storage dynamically.

**Common Storage Selection Patterns**:

Select first available LVM-Thin storage:
```cel
storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

Select specific storage by name:
```cel
storage.filter(s, s.storage == "local-lvm")[0].storage
```

Select ZFS pool:
```cel
storage.filter(s, s.type == "zfspool" && s.enabled && s.active)[0].storage
```

Select storage with most free space:
```cel
storage.filter(s, s.enabled && s.active).max(s, s.avail).storage
```

**Available Storage Fields**:
- `s.storage` - Storage name
- `s.type` - Storage type (dir, lvmthin, zfspool, nfs, etc.)
- `s.enabled` - Storage is enabled
- `s.active` - Storage is active
- `s.avail` - Available space in bytes
- `s.total` - Total space in bytes

## Creating Your First Cluster

Once the provider is running and machine classes are configured:

1. In Omni UI, click **Create Cluster**
2. Name your cluster
3. Select Kubernetes version
4. Select your machine class for control plane nodes
5. Select your machine class for worker nodes
6. Specify number of nodes
7. Click **Create**

The provider will automatically:
- Detect the cluster creation request
- Create VMs in Proxmox based on machine class specs
- Download and install Talos Linux
- Bootstrap the cluster
- Report status back to Omni

## Troubleshooting

### Provider Won't Start

Check logs for connection errors:
```bash
docker compose logs omni-infra-provider-proxmox
```

Common issues:
- Incorrect Omni API endpoint
- Invalid infrastructure provider key
- Proxmox API unreachable
- Incorrect Proxmox credentials

### VMs Not Being Created

1. **Verify provider is running**: `docker compose ps`
2. **Check provider logs**: `docker compose logs -f`
3. **Verify machine class exists**: Check Omni UI → Settings → Machine Classes
4. **Check Proxmox storage**: Ensure selected storage has space
5. **Verify network configuration**: VMs need network access to Omni

### Storage Selection Fails

Test your CEL expression:
- Check Proxmox storage is enabled and active
- Verify storage type matches your filter
- Ensure storage has available space
- Check provider logs for CEL evaluation errors

### Authentication Errors

If you see Proxmox authentication errors:
- Verify username format: `root@pam` (not just `root`)
- Check password is correct
- Ensure Proxmox API is accessible from provider host
- Verify certificate trust settings match your setup

## Known Limitations (Beta)

⚠️ The Proxmox provider is currently in **beta**. Known limitations:

- **Single disk per VM**: Cannot provision VMs with multiple disks
  - Workaround: Over-provision single disk and use Talos VolumeConfig
- **Limited network config**: Basic networking only
- **No GPU passthrough**: GPU configuration must be done manually

See [GitHub Issues](https://github.com/siderolabs/omni-infra-provider-proxmox/issues) for current status.

### Feature Request: Multiple Disks

If you need multiple disks per VM (e.g., nvme for OS, ZFS for storage), this is a potential enhancement. Consider contributing to the upstream project!

## Advanced Configuration

### Dedicated Proxmox User

Instead of using `root@pam`, create a dedicated user:

1. In Proxmox, create user: `omni@pve`
2. Grant permissions:
   - VM.Allocate
   - VM.Config.Disk
   - VM.Config.CPU
   - VM.Config.Memory
   - VM.Config.Network
   - Datastore.AllocateSpace
3. Update `config.yaml` with new credentials

### High Availability

Run multiple provider instances for redundancy:
- Deploy on separate hosts
- Use same configuration
- Providers coordinate through Omni API
- Automatic failover if one instance fails

### Custom Network Configuration

By default, VMs use Proxmox's default bridge. To customize:
- Configure network settings in Proxmox
- Talos will use DHCP by default
- Use Talos machine config patches for static IPs

## Monitoring

Check provider status:
```bash
# View logs
docker compose logs -f

# Check process
docker compose ps

# Restart if needed
docker compose restart
```

Monitor in Omni:
- Infrastructure Providers section shows connection status
- Machine Classes show available configurations
- Cluster creation will show VM provisioning progress

## Updating the Provider

To update to a new version:

```bash
# Pull latest image
docker compose pull

# Restart with new image
docker compose up -d

# Verify new version
docker compose logs -f
```

## Security Best Practices

- **Use dedicated Proxmox user** instead of root
- **Use valid SSL certificates** for Proxmox API (set `insecureSkipVerify: false`)
- **Restrict network access** to provider container
- **Secure .env file**: `chmod 600 .env`
- **Don't commit secrets** to version control

## Contributing

Found a bug or want to add a feature?
- Report issues: [GitHub Issues](https://github.com/siderolabs/omni-infra-provider-proxmox/issues)
- Submit PRs: [GitHub Pull Requests](https://github.com/siderolabs/omni-infra-provider-proxmox/pulls)

## Next Steps

With the provider running:
1. [Configure GPU support](../talos-configs/README.md) (optional)
2. Create additional machine classes for different workload types
3. Experiment with cluster creation and scaling
4. Set up monitoring and alerting
