# Action Plan: Fix Omni Cluster Network & Configuration

## Problem Summary
Your machines can't connect to Omni because the network configuration isn't applying at boot. The cluster template is missing critical configuration that worked in your old Talos setup.

## Root Causes
1. **No `deviceSelector` with `hardwareAddr`** - Talos doesn't know which NIC to configure
2. **Wrong DNS servers** - Using gateway (192.168.10.1) instead of real DNS (1.1.1.1)
3. **Missing disk configuration** - Longhorn needs `/dev/sdb` mounted
4. **Missing `dhcp: false`** - DHCP might override static config

## The Fix (Step by Step)

### Step 1: Update Terraform API Token
Edit `terraform/terraform.tfvars` and replace `YOUR_TOKEN_HERE` with your actual Proxmox API token.

### Step 2: Destroy Current VMs (they have wrong MACs)
```bash
cd terraform
terraform destroy
```

This will remove your current VMs that have auto-generated MAC addresses.

### Step 3: Create VMs with Your Old Working MAC Addresses
```bash
terraform apply
```

This will create new VMs with:
- Your old MAC addresses (that work with Firewalla)
- Correct IP addresses
- Data disks for Longhorn

### Step 4: Wait for Machines to Appear in Omni
After VMs boot from ISO, they should register with Omni. Check the Omni UI and wait for 7 machines to appear as "Unknown" or "Available".

### Step 5: Discover New Machine UUIDs
```bash
cd ../scripts
./discover-machines.sh
```

This will create `scripts/machine-data/matched-machines.json` with new UUIDs matched to IPs/MACs.

### Step 6: Generate New Cluster Template
```bash
./generate-machine-configs.sh
```

**CRITICAL**: Before running this, update the generate script to include the missing configuration. The script needs to add:

1. **deviceSelector with hardwareAddr** in network interfaces
2. **dhcp: false** on interfaces
3. **DNS servers: 1.1.1.1/1.0.0.1** instead of gateway
4. **disk configuration** for workers/GPU workers

Alternatively, manually edit `scripts/machine-configs/cluster-template.yaml` after generation using the example in `CLUSTER-TEMPLATE-FIX-EXAMPLE.yaml`.

### Step 7: Apply Fixed Cluster Template to Omni
```bash
omnictl cluster template sync -f scripts/machine-configs/cluster-template.yaml
```

Watch in Omni UI - machines should now:
1. Get their network configuration
2. Connect to Omni successfully
3. Apply all patches
4. Join the cluster

## What Changed from Your Old Working Setup

### Old Talos Config (worked)
```yaml
machine:
  network:
    interfaces:
      - deviceSelector:
          hardwareAddr: "AC:24:21:A4:B2:97"  # ✅ Specified MAC
        dhcp: false                           # ✅ Disabled DHCP
        addresses:
          - 192.168.10.100/24
    nameservers:
      - 1.1.1.1                               # ✅ Real DNS
      - 1.0.0.1
  disks:
    - device: /dev/sdb                        # ✅ Extra disk
      partitions:
        - mountpoint: /var/mnt/longhorn_sdb
```

### Current Omni Template (broken)
```yaml
machine:
  network:
    interfaces:
      - interface: eth0                       # ❌ No deviceSelector!
        addresses:
          - 192.168.10.100/24
        # ❌ No dhcp: false
    nameservers:
      - 192.168.10.1                          # ❌ Using gateway as DNS
  # ❌ No disk configuration!
```

## Expected Result After Fix

All 7 machines should:
- ✅ Boot with correct network configuration
- ✅ Connect to Omni successfully
- ✅ Show as "Running" in Omni UI
- ✅ Have static IPs (100, 101, 102, 111, 112, 113)
- ✅ Have correct MAC addresses (for Firewalla)
- ✅ Have `/dev/sdb` mounted for Longhorn
- ✅ Form a healthy Kubernetes cluster

## Verification Commands

After applying cluster template, check machine status:
```bash
# Check if machines are connected
omnictl get machines

# Check machine network status
omnictl get machinestatus

# Watch cluster formation
omnictl get clusters
```

## Troubleshooting

### If machines still show "Unknown":
1. Check VM console in Proxmox - is network configured?
2. Verify MAC addresses match Terraform and cluster template
3. Check Omni logs: `docker logs -f omni`

### If DNS not working:
1. Verify nameservers in cluster template are `1.1.1.1` and `1.0.0.1`
2. Check if `hostDNS` is enabled in machine config

### If Longhorn disk not mounting:
1. Check `/dev/sdb` exists in VM (Proxmox VM → Hardware)
2. Verify `machine.disks` configuration in cluster template
3. Check disk is at least 200GB for workers, 500GB for GPU worker

## Alternative: Manual Fix (if generate script needs update)

If you don't want to update the generate script, after running `./generate-machine-configs.sh`, manually edit each machine in `scripts/machine-configs/cluster-template.yaml` to add:

For each machine's network interface:
```yaml
interfaces:
  - deviceSelector:              # ← ADD THIS
      hardwareAddr: "XX:XX:XX:XX:XX:XX"  # ← ADD MAC ADDRESS
    dhcp: false                  # ← ADD THIS
    addresses:
      - 192.168.10.XXX/24
```

Change nameservers from:
```yaml
nameservers:
  - 192.168.10.1
```

To:
```yaml
nameservers:
  - 1.1.1.1
  - 1.0.0.1
```

For workers/GPU workers, add disk config:
```yaml
machine:
  disks:
    - device: /dev/sdb
      partitions:
        - mountpoint: /var/mnt/longhorn_sdb
```

And update Longhorn mount source:
```yaml
kubelet:
  extraMounts:
    - destination: /var/lib/longhorn
      source: /var/mnt/longhorn_sdb  # ← Change from /var/lib/longhorn
```

## Files Created for You

1. `terraform/terraform.tfvars` - With your old MAC addresses
2. `CLUSTER-TEMPLATE-FIX-EXAMPLE.yaml` - Example showing all required changes
3. This action plan

## Ready to Proceed?

Once you're ready, start with Step 1 and work through sequentially. The cluster should come up cleanly with all the features working:
- ✅ Static IPs
- ✅ DNS resolution
- ✅ Longhorn storage on extra disk
- ✅ GPU passthrough
- ✅ Firewalla MAC address matching
