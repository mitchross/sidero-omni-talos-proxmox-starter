# Emergency Debugging: Cluster Stuck in Configuring/Booting

## Current Status
- **Cluster:** talos-prod-cluster
- **State:** 0/7 machines healthy, stuck in "Configuring" or "Booting"
- **Duration:** All day (indicates network/config issue)

---

## Immediate Diagnostics

### Step 1: Check Omni Events (Critical!)

```bash
# View cluster events - will show errors
omnictl get events -c talos-prod-cluster

# Look for errors like:
# - "failed to apply config"
# - "network unreachable"
# - "failed to install"
```

### Step 2: Check One Machine's Console in Proxmox

In Proxmox UI:
1. Click on VM: **talos-control-1** (VMID 100)
2. Click **Console**
3. Look for errors in boot messages

**What to look for:**
- ❌ "Failed to configure interface"
- ❌ "No route to host"
- ❌ "Failed to reach Omni"
- ❌ Stuck at "Waiting for network..."
- ✅ Should see: "Connected to Omni" and configuration applying

### Step 3: Check if Machines Can Reach Network

Try to access one machine via talosctl (using Omni's connection):

```bash
# Get talosconfig
omnictl talosconfig -c talos-prod-cluster

# Try to access control-1
talosctl -n e8ebd88b-ff6b-4f77-b775-cf9e14f57472 version

# If this fails, machines can't be reached
```

### Step 4: Check Machine Status in Omni

```bash
# Get detailed machine status
omnictl get machinestatus -o yaml | grep -A 20 "e8ebd88b"

# Look for:
# - ready: false
# - conditions with errors
# - network status
```

---

## Most Likely Issues

### Issue 1: DHCP is Overriding Static IPs ⚠️

**Symptom:** Machines boot but can't connect with static config

**Why:** Even though we set `dhcp: false`, if VMs are getting DHCP addresses from your router/Firewalla, they might be using those instead of static IPs.

**Check:**
```bash
# From Proxmox console of a VM, see what IP it has
# (won't work if machine is stuck, but try)
talosctl -n 192.168.10.100 get addresses

# Or check your router/Firewalla DHCP leases
# Do you see these MACs getting DHCP leases?
# BC:24:11:01:00:00 (control-1)
# BC:24:11:02:00:00 (worker-1)
```

**Fix:**
- Option A: Add DHCP reservations in Firewalla for these MACs (quick fix)
- Option B: Disable DHCP entirely on that VLAN (permanent fix)

### Issue 2: Network Gateway Unreachable

**Symptom:** Static IPs configured but can't reach gateway (192.168.10.1)

**Check:**
```bash
# From Proxmox host, verify gateway is reachable
ssh root@192.168.10.160
ping 192.168.10.1  # Should work

# Check if Proxmox bridge is working
brctl show vmbr0
```

**Fix:** Verify vmbr0 bridge is configured correctly in Proxmox

### Issue 3: ISOs Missing Extensions

**Symptom:** Machines boot but can't connect to Omni

**Check:** Did you generate ISOs from **your Omni instance** with embedded join token?

**Fix:** Regenerate ISOs:
1. Omni UI → Settings → Download Installation Media
2. Select Talos v1.11.5
3. Add extensions:
   - qemu-guest-agent
   - nfsd
   - iscsi-tools
   - util-linux-tools
4. Generate → Download
5. Re-upload to Proxmox
6. Restart VMs

### Issue 4: Conflicting Configuration

**Symptom:** Old cluster configs interfering

**Check:**
```bash
# List all clusters
omnictl get clusters

# If you see old clusters, they might be interfering
```

**Fix:** Delete old cluster if exists:
```bash
omnictl delete cluster talos-prod-cluster
# Wait 2 minutes
# Re-apply cluster template
omnictl cluster template sync -f scripts/machine-configs/cluster-template.yaml
```

---

## Quick Fix: Try DHCP First

If stuck all day, fastest way to verify setup works:

### Option 1: Enable DHCP Temporarily

Edit cluster template to use DHCP:

```bash
cd scripts/machine-configs

# Backup current template
cp cluster-template.yaml cluster-template.yaml.backup

# Edit all machine patches to enable DHCP
# Change:
#   dhcp: false
# To:
#   dhcp: true

# Re-apply
omnictl delete cluster talos-prod-cluster
sleep 30
omnictl cluster template sync -f cluster-template.yaml
```

If cluster forms with DHCP, we know:
- ✅ VMs are working
- ✅ ISOs are correct
- ✅ Omni connection works
- ❌ Static IP config is the problem

Then we can focus on fixing static IPs.

---

## Step-by-Step Debugging Plan

Run these commands and share the output:

```bash
# 1. Check Omni events
omnictl get events -c talos-prod-cluster | tail -50

# 2. Check machine status
omnictl get machines -o wide

# 3. Try to access a machine
omnictl talosconfig -c talos-prod-cluster
talosctl -n e8ebd88b-ff6b-4f77-b775-cf9e14f57472 version

# 4. Check cluster status
omnictl get cluster talos-prod-cluster -o yaml

# 5. Check if machines have IPs
omnictl get machinestatus -o json | jq -r '.[] | select(.metadata.namespace=="talos-prod-cluster") | {hostname: .metadata.labels["omni.sidero.dev/hostname"], addresses: .spec.network.addresses}'
```

---

## What to Share

Please run the commands above and share:
1. Omni events output (last 50 lines)
2. Proxmox console screenshot of one stuck VM
3. Machine status output
4. Any errors you see

This will help me pinpoint the exact issue!

---

## Fastest Recovery

If you need the cluster up ASAP:

1. **Delete cluster:** `omnictl delete cluster talos-prod-cluster`
2. **Create DHCP reservations in Firewalla** for all 7 MACs → their static IPs
3. **Enable DHCP in cluster template** (dhcp: true)
4. **Re-apply cluster template**
5. **Cluster should form in 5-10 minutes**

Then we can work on proper static IPs once cluster is running.

Let me know what the diagnostics show!
