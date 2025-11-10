# Omni Integration Scripts

This directory contains automation scripts for integrating Terraform-created VMs with Sidero Omni.

## Overview

These scripts bridge the gap between Terraform (VM creation) and Omni (cluster management) by:
1. Discovering Talos machines registered in Omni
2. Matching them to Terraform inventory by MAC address
3. Generating Talos machine configurations with static IPs and hostnames
4. Applying configurations via omnictl

## Prerequisites

### Required Tools

```bash
# Install jq (JSON processor)
sudo apt-get install jq

# Install omnictl
# Download from: https://www.siderolabs.com/omni/docs/cli/
# Or use the Omni UI to get installation instructions
```

### Required Steps Before Running Scripts

1. **Sidero Omni must be deployed**
   - See `../sidero-omni/README.md` for deployment instructions

2. **Terraform must have created VMs**
   ```bash
   cd ../terraform
   terraform apply
   ```

3. **VMs must be booted and registered with Omni**
   - Wait 2-5 minutes after `terraform apply`
   - Check Omni UI: `https://your-omni-url/machines`

4. **omnictl must be configured**
   ```bash
   omnictl config new
   # Follow prompts to configure Omni connection
   ```

5. **DHCP reservations should be configured** (recommended)
   - Get reservation table: `cd ../terraform && terraform output dhcp_reservations_table`
   - Add to your router/DHCP server (Firewalla, pfSense, etc.)

## Scripts

### 1. discover-machines.sh

**Purpose**: Match Terraform VMs to Omni-registered machines

**What it does**:
- Reads Terraform machine inventory
- Queries Omni API for registered Talos machines
- Matches them by MAC address
- Creates machine UUID mapping files

**Usage**:
```bash
./discover-machines.sh
```

**Output Files**:
- `machine-data/matched-machines.json` - Complete matched inventory
- `machine-data/machine-uuids.txt` - Hostname to UUID mapping
- `machine-data/mac-to-uuid.txt` - MAC to UUID mapping
- `machine-data/ip-to-uuid.txt` - IP to UUID mapping

**Example Output**:
```
✓ Found 8 machines in Terraform inventory
✓ Found 8 machines registered in Omni

✓ Matched: talos-cp-1 (BC:24:11:01:00:00) -> Omni UUID: abc123...
✓ Matched: talos-cp-2 (BC:24:11:01:00:01) -> Omni UUID: def456...
...

Matched: 8
Unmatched: 0
```

**Troubleshooting**:

| Issue | Solution |
|-------|----------|
| "No machines registered in Omni" | Wait for VMs to boot (2-5 min) |
| "Cannot connect to Omni" | Run `omnictl config new` |
| "Terraform state not found" | Run `terraform apply` first |
| MAC address mismatch | Check Proxmox VM network settings |

### 2. generate-machine-configs.sh

**Purpose**: Generate Talos machine configuration patches

**What it does**:
- Reads matched machines from discover-machines.sh
- Creates Talos Machine YAML documents for each VM
- Generates patches for:
  - Hostname and node labels (management-ip, node-role, zone)
  - Role-specific configurations (hostDNS, kubePrism, sysctls)
  - Containerd runtime configs
  - Optional Longhorn mounts (for workers with data disks)
  - NVIDIA GPU support (for GPU workers)
- Creates combined cluster template with ControlPlane untaint patch

**Usage**:
```bash
./generate-machine-configs.sh
```

**Output Files**:
- `machine-configs/<hostname>.yaml` - Individual machine configs
- `machine-configs/cluster-template.yaml` - Combined cluster template

**Example Output**:
```
Processing: talos-cp-1 (abc123...)
Processing: talos-cp-2 (def456...)
...

✓ Generated 8 machine configurations

Control Planes: 3
Workers:        3
GPU Workers:    2
Total:          8
```

**Generated Config Example**:
```yaml
---
kind: Machine
name: abc123-def-456-...  # Machine UUID from Omni
patches:
  - idOverride: 400-cm-abc123-set-hostname-talos-control-1
    annotations:
      name: set-hostname-talos-control-1
    inline:
      machine:
        network:
          hostname: talos-control-1
        nodeLabels:
          management-ip: 192.168.10.120
          node-role: control-plane
          topology.kubernetes.io/zone: proxmox
          topology.proxmox.io/node: pve1
  - idOverride: 401-cm-abc123-control-plane-config
    annotations:
      name: control-plane-config
    inline:
      cluster:
        proxy:
          disabled: true
      machine:
        features:
          hostDNS:
            enabled: true
            forwardKubeDNSToHost: true
          kubePrism:
            enabled: true
            port: 7445
        kernel:
          modules:
            - name: br_netfilter
              parameters:
                - nf_conntrack_max=131072
```

### 3. apply-machine-configs.sh

**Purpose**: Apply machine configurations to Omni with intelligent cluster state handling

**What it does**:
- Detects if cluster exists
- **Scenario 1 - New cluster**: Creates cluster with all machines
- **Scenario 2 - Existing cluster**: Adds new machines and updates patches
- **Scenario 3 - Update only**: Updates patches on existing machines
- Shows configuration preview based on scenario
- Applies via omnictl with dry-run validation

**Usage**:
```bash
./apply-machine-configs.sh
```

**Scenario 1: Creating New Cluster**
```
Detecting Cluster State:
• Cluster 'talos-prod-cluster' does not exist

Configuration Preview:
Action: Create new cluster with machines

This will:
  ✓ Create cluster 'talos-prod-cluster'
  ✓ Assign 3 control plane machines
  ✓ Assign 5 worker machines
  ✓ Assign 1 GPU worker machines
  ✓ Apply all machine patches (hostnames, labels, configs)

Create cluster 'talos-prod-cluster' with 9 machines? (yes/no): yes

✓ Cluster created successfully
```

**Scenario 2: Adding Machines to Existing Cluster**
```
Detecting Cluster State:
✓ Cluster 'talos-prod-cluster' already exists

Analyzing Existing Cluster:
  Existing machines in cluster: 9
  New machines to add: 3

New machines:
  - talos-worker-6 (abc123...)
  - talos-worker-7 (def456...)
  - talos-worker-8 (ghi789...)

Add 3 new machines and update existing patches? (yes/no): yes

✓ Cluster updated successfully
```

**Scenario 3: Updating Existing Patches**
```
Detecting Cluster State:
✓ Cluster 'talos-prod-cluster' already exists

Analyzing Existing Cluster:
  Existing machines in cluster: 9
  New machines to add: 0

Update patches on 9 existing machines? (yes/no): yes

✓ Patches updated successfully
```

**What Happens**:
1. Script detects cluster state via `omnictl get cluster`
2. If cluster exists, fetches existing machines
3. Compares with template to identify new machines
4. Runs dry-run validation first
5. Applies cluster template (Omni handles merging)
6. Machine patches are created/updated
7. Talos machines receive configurations
8. Hostnames, node labels, and configs are applied

**Verification**:
```bash
# Check cluster status
omnictl get cluster talos-prod-cluster

# Check machine status
omnictl get machines

# Verify hostnames and labels
omnictl get machines -o json | jq '.items[] | {uuid: .metadata.id, hostname: .spec.network.hostname}'

# Check patches
omnictl get configpatches
```

**Re-running the Script**:
The script is idempotent and can be run multiple times:
- After adding machines in Terraform: Adds new machines to cluster
- After editing generate-machine-configs.sh: Updates patches on all machines
- After any config changes: Safely applies updates

## Complete Workflow

### Step-by-Step Guide

```bash
# 1. Deploy Sidero Omni (if not done)
cd ../sidero-omni
./check-prerequisites.sh
./install-docker.sh           # If needed
sudo ./setup-certificates.sh  # If needed
./generate-gpg-key.sh
cp .env.example omni.env
# Edit omni.env with your values
docker compose --env-file omni.env up -d

# 2. Create VMs with Terraform
cd ../terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox servers and VM configs
terraform init
terraform plan
terraform apply

# 3. Configure DHCP reservations (recommended)
terraform output dhcp_reservations_table
# Add these to your router

# 4. Wait for VMs to register (2-5 minutes)
# Check Omni UI or run: omnictl get machines

# 5. Discover and match machines
cd ../scripts
./discover-machines.sh

# 6. Generate machine configs
./generate-machine-configs.sh

# 7. Apply configs to Omni (creates cluster automatically)
./apply-machine-configs.sh

# 8. Monitor cluster creation
omnictl get cluster talos-prod-cluster
omnictl get machines --watch

# 9. For GPU workers, configure GPU passthrough manually
cd ../terraform
terraform output gpu_configuration_needed
# Follow instructions for each GPU worker
```

## Network Configuration

### IP Assignment via DHCP

The scripts use DHCP for IP assignment with PXE boot:

1. **DHCP Reservations** (Recommended)
   - MAC addresses assigned by Terraform
   - DHCP server maps MAC → IP for consistency
   - Get reservation table: `terraform output dhcp_reservations_table`
   - Add to your router/DHCP server (Firewalla, pfSense, etc.)

2. **Dynamic DHCP** (Fallback)
   - Machines get IPs from DHCP pool
   - IPs may change on reboot
   - Not recommended for production

**No static IP patches are applied** - machines use DHCP via PXE boot. Hostnames and node labels (including management-ip) are set via machine patches for identification in Kubernetes.

### DNS Configuration

DNS is handled by your DHCP server. Talos machines use the DNS servers provided by DHCP during network boot.

## GPU Worker Configuration

### Automated (via scripts)

The scripts automatically add GPU configuration patches for GPU workers:
- NVIDIA container toolkit
- NVIDIA kernel modules
- GPU device plugin support

### Manual Steps Required

**After** running the scripts, GPU passthrough must be configured manually:

```bash
# 1. Get GPU configuration instructions
cd ../terraform
terraform output gpu_configuration_needed

# Example output:
# {
#   hostname = "talos-gpu-1"
#   server = "pve2"
#   node = "pve2"
#   gpu_pci_id = "01:00"
#   instructions = "1. SSH to pve2, 2. Run: qm set <VM_ID> -hostpci0 01:00,pcie=1"
# }

# 2. SSH to the Proxmox server
ssh root@pve2

# 3. Find the VM ID
qm list | grep talos-gpu-1

# 4. Configure GPU passthrough
qm set <VM_ID> -hostpci0 01:00,pcie=1

# 5. Reboot the VM
qm reboot <VM_ID>
```

## Troubleshooting

### Discovery Issues

**Problem**: "No machines registered in Omni"

**Solutions**:
1. Check VMs are running: `cd ../terraform && terraform output cluster_summary`
2. Wait 2-5 minutes for Talos to boot
3. Check SideroLink connectivity in Omni UI
4. Verify firewall allows port 50180/UDP

**Problem**: "MAC address mismatch"

**Solutions**:
1. Check Proxmox VM network config
2. Verify MAC in `terraform output mac_to_ip_mapping`
3. Check VM actually has the assigned MAC

### Configuration Issues

**Problem**: "Machines not getting expected IPs"

**Solutions**:
1. Verify DHCP reservations configured in your router/DHCP server
2. Check MAC addresses match: `terraform output dhcp_reservations_table`
3. Reboot machines to get IP from DHCP reservation
4. Check DHCP server logs for MAC address lease requests

**Problem**: "Hostnames not set"

**Solutions**:
1. Wait a few minutes for patches to apply
2. Check patch status: `omnictl get configpatches`
3. Verify no conflicting patches

**Problem**: "Secondary disk not mounted"

**Solutions**:
1. Verify disk exists: `omnictl get machines -o json | jq '.items[].spec.hardware.blockdevices'`
2. Check Terraform created data disk
3. Check Talos logs for mount errors

### omnictl Issues

**Problem**: "Cannot connect to Omni"

**Solutions**:
```bash
# Reconfigure omnictl
omnictl config new

# Check config
omnictl config list

# Test connection
omnictl get machines
```

**Problem**: "Permission denied"

**Solutions**:
- Verify Auth0/SAML authentication
- Check user has permissions in Omni UI → Users
- Use correct omnictl context

## Advanced Usage

### Adding Machines to Existing Cluster

To add machines to an existing cluster:

```bash
# 1. Update terraform.tfvars with new machines
cd ../terraform
nano terraform.tfvars
# Add new control planes or workers

# 2. Apply Terraform changes
terraform apply

# 3. Wait for new VMs to boot and register (2-5 min)

# 4. Rediscover machines (includes new ones)
cd ../scripts
./discover-machines.sh

# 5. Regenerate configs (includes new machines)
./generate-machine-configs.sh

# 6. Apply (script detects new machines and adds them)
./apply-machine-configs.sh
# Script will detect existing cluster and only add new machines
```

### Updating Machine Configurations

To update patches on existing machines:

```bash
# 1. Edit the generation script with your changes
nano generate-machine-configs.sh

# 2. Regenerate configs
./generate-machine-configs.sh

# 3. Apply updates
./apply-machine-configs.sh
# Script will detect existing cluster and update patches
```

### Manual Config Edits

You can edit generated configs before applying:

```bash
# Generate configs
./generate-machine-configs.sh

# Edit specific machine
nano machine-configs/talos-cp-1.yaml

# Apply manually
omnictl cluster template sync -f machine-configs/talos-cp-1.yaml

# Or apply all
./apply-machine-configs.sh
```

### Selective Application

Apply configs to specific machines:

```bash
# Apply only control planes
for f in machine-configs/talos-cp-*.yaml; do
  omnictl cluster template sync -f "$f"
done

# Apply only workers
for f in machine-configs/talos-worker-*.yaml; do
  omnictl cluster template sync -f "$f"
done
```

## File Structure

```
scripts/
├── README.md                           # This file
├── discover-machines.sh                # Step 1: Match Terraform to Omni
├── generate-machine-configs.sh         # Step 2: Generate configs
├── apply-machine-configs.sh            # Step 3: Apply to Omni
├── machine-data/                       # Created by discover-machines.sh
│   ├── matched-machines.json           # Matched inventory
│   ├── machine-uuids.txt               # Hostname → UUID
│   ├── mac-to-uuid.txt                 # MAC → UUID
│   └── ip-to-uuid.txt                  # IP → UUID
└── machine-configs/                    # Created by generate-machine-configs.sh
    ├── cluster-template.yaml           # Combined template
    ├── talos-cp-1.yaml                 # Individual machine configs
    ├── talos-cp-2.yaml
    └── ...
```

## References

- [Omni Cluster Templates Documentation](https://www.siderolabs.com/omni/docs/reference/cluster-templates/)
- [Talos Machine Configuration](https://www.talos.dev/latest/reference/configuration/)
- [omnictl CLI Reference](https://www.siderolabs.com/omni/docs/cli/)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
