#!/usr/bin/env bash
set -euo pipefail

# Post-install helper to apply consistent Proxmox VM settings.
# 
# Features:
# - Disk optimization: ssd=1, discard=on, iothread=1, cache=none, aio=io_uring
# - GPU passthrough optimization: cpu=host, machine=q35, NUMA, hugepages
# - Dry-run by default (requires --apply to perform changes)
# - Select VMs by explicit IDs or by name substring
# - Update a single slot (default scsi0) or all scsi* slots
# - Skips running VMs by default (override with --include-running)
#
# Examples:
#   # Apply disk settings to VM IDs 100..106
#   ./post-install-vm-golden-settings.sh --vmids 100-106 --apply
#
#   # Apply to VMs with name containing "talos-"
#   ./post-install-vm-golden-settings.sh --name-contains talos- --apply
#
#   # Apply GPU optimizations for passthrough workloads
#   ./post-install-vm-golden-settings.sh --vmids 200 --gpu --apply
#
#   # Apply to all scsi slots on specific VMs (not just scsi0)
#   ./post-install-vm-golden-settings.sh --vmids 200-205 --all-scsi --apply

if ! command -v qm >/dev/null 2>&1; then
  echo "Error: 'qm' command not found. Run this on a Proxmox node." >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --vmids "LIST"          VM IDs as comma/range list, e.g. "100,101,105-110"
  --name-contains STR      Match VMs whose name contains STR (from 'qm list')
  --slot SLOT              SCSI slot to update (default: scsi0)
  --all-scsi               Update all scsi* slots found for each VM
  --gpu                    Apply GPU passthrough optimizations (cpu=host, q35, NUMA)
  --add-10g-nic            Add second NIC for 10G storage network
  --nic-bridge BRIDGE      Bridge for 10G NIC (default: vmbr1)
  --apply                  Perform changes (default: dry-run)
  --include-running        Include running VMs (default: skip running)
  -h, --help               Show this help

Disk Settings Applied:
  ssd=1, discard=on, iothread=1, cache=none, aio=io_uring

GPU Optimization Settings (--gpu):
  cpu: host              Pass through host CPU features for best performance
  machine: q35           Modern chipset with native PCIe support
  numa: 1                Enable NUMA for better memory locality
  hugepages: 1GB         Use 1GB hugepages for reduced TLB misses
  args: -cpu host,+kvm_pv_unhalt,+kvm_pv_eoi
                         KVM paravirt optimizations for lower latency

Examples:
  $(basename "$0") --vmids 100-106 --apply
  $(basename "$0") --name-contains talos- --all-scsi --apply
  $(basename "$0") --vmids 200 --gpu --apply
  $(basename "$0") --name-contains gpu-worker --gpu --apply
  $(basename "$0") --name-contains talos- --add-10g-nic --apply
EOF
}

VMIDS_INPUT=""
NAME_CONTAINS=""
SLOT="scsi0"
ALL_SCSI=false
DO_APPLY=false
INCLUDE_RUNNING=false
GPU_MODE=false
ADD_10G_NIC=false
NIC_BRIDGE="vmbr1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vmids)
      VMIDS_INPUT=${2:-}
      shift 2
      ;;
    --name-contains)
      NAME_CONTAINS=${2:-}
      shift 2
      ;;
    --slot)
      SLOT=${2:-}
      shift 2
      ;;
    --all-scsi)
      ALL_SCSI=true
      shift
      ;;
    --gpu)
      GPU_MODE=true
      shift
      ;;
    --add-10g-nic)
      ADD_10G_NIC=true
      shift
      ;;
    --nic-bridge)
      NIC_BRIDGE=${2:-}
      shift 2
      ;;
    --apply)
      DO_APPLY=true
      shift
      ;;
    --include-running)
      INCLUDE_RUNNING=true
      shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage; exit 2
      ;;
  esac
done

expand_vmids() {
  local input="$1"
  local IFS=','
  local out=()
  for part in $input; do
    if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
      local start=${part%-*}
      local end=${part#*-}
      for ((i=start; i<=end; i++)); do out+=("$i"); done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      out+=("$part")
    elif [[ -n "$part" ]]; then
      echo "Invalid vmid token: $part" >&2; exit 2
    fi
  done
  printf '%s\n' "${out[@]}"
}

collect_vmids() {
  local arr=()
  if [[ -n "$VMIDS_INPUT" ]]; then
    mapfile -t arr < <(expand_vmids "$VMIDS_INPUT")
  elif [[ -n "$NAME_CONTAINS" ]]; then
    # 'qm list' columns: VMID NAME STATUS ...
    while read -r vmid name _rest; do
      if [[ "$vmid" =~ ^[0-9]+$ ]] && [[ "$name" == *"$NAME_CONTAINS"* ]]; then
        arr+=("$vmid")
      fi
    done < <(qm list | tail -n +2)
  else
    echo "Specify --vmids or --name-contains" >&2
    exit 2
  fi
  printf '%s\n' "${arr[@]}" | sort -n | uniq
}

# Merge target options into existing opts, preserving other keys
merge_opts() {
  local existing="$1"; shift
  local -A keep
  IFS=',' read -r -a parts <<< "$existing"
  for kv in "${parts[@]}"; do
    [[ -z "$kv" ]] && continue
    if [[ "$kv" == *"="* ]]; then
      local k=${kv%%=*}
      local v=${kv#*=}
      case "$k" in
        ssd|discard|iothread|cache|aio) ;; # will be overridden
        *) keep["$k"]="$v" ;;
      esac
    else
      # Bare flag (rare), keep as-is using key without value
      keep["$kv"]=""
    fi
  done
  # Rebuild, then append our desired values
  local out=()
  for k in "${!keep[@]}"; do
    if [[ -n "${keep[$k]}" ]]; then
      out+=("$k=${keep[$k]}")
    else
      out+=("$k")
    fi
  done
  out+=(
    "ssd=1"
    "discard=on"
    "iothread=1"
    "cache=none"
    "aio=io_uring"
  )
  local IFS=','
  printf '%s' "${out[*]}"
}

update_slot() {
  local vmid="$1" slot="$2"
  local line
  if ! line=$(qm config "$vmid" | awk -F': ' -v s="^"$slot":$" '$0 ~ s {print $2}'); then
    return 0
  fi
  [[ -z "$line" ]] && return 0

  local disk opts new_opts new_line
  disk=$(printf '%s' "$line" | cut -d',' -f1)
  opts=$(printf '%s' "$line" | cut -d',' -f2- || true)
  new_opts=$(merge_opts "${opts:-}")
  if [[ -n "$new_opts" ]]; then
    new_line="$disk,$new_opts"
  else
    new_line="$disk"
  fi

  echo "  -> ${slot}: $disk"
  if $DO_APPLY; then
    qm set "$vmid" --"$slot" "$new_line" >/dev/null
  else
    echo "     (dry-run) qm set $vmid --$slot '$new_line'"
  fi
}

# Apply GPU passthrough optimizations
apply_gpu_settings() {
  local vmid="$1"
  
  echo "  -> Applying GPU passthrough optimizations..."
  
  # Settings for optimal GPU passthrough performance:
  # - cpu: host - Pass through all host CPU features (essential for GPU compute)
  # - machine: q35 - Modern chipset with native PCIe support
  # - numa: 1 - Enable NUMA for better memory locality with large RAM
  # - hugepages: 1048576 - Use 1GB hugepages (value in KB)
  # - balloon: 0 - Disable memory ballooning (required for GPU/hugepages)
  # - args: KVM paravirt optimizations for lower latency
  
  local settings=(
    "cpu:host"
    "machine:q35"
    "numa:1"
    "hugepages:1048576"
    "balloon:0"
  )
  
  # Additional args for KVM optimizations
  local kvm_args="-cpu host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=proxmox,hv_spinlocks=0x1fff"
  
  for setting in "${settings[@]}"; do
    local key="${setting%%:*}"
    local val="${setting#*:}"
    
    if $DO_APPLY; then
      qm set "$vmid" --"$key" "$val" >/dev/null 2>&1 || echo "     Warning: Failed to set $key"
      echo "     $key=$val"
    else
      echo "     (dry-run) qm set $vmid --$key '$val'"
    fi
  done
  
  # Set CPU args (need special handling)
  if $DO_APPLY; then
    qm set "$vmid" --args "$kvm_args" >/dev/null 2>&1 || echo "     Warning: Failed to set args"
    echo "     args=$kvm_args"
  else
    echo "     (dry-run) qm set $vmid --args '$kvm_args'"
  fi
  
  echo ""
  echo "  -> GPU passthrough reminders:"
  echo "     1. Add PCI device via Proxmox UI: Hardware → Add → PCI Device"
  echo "     2. Select your GPU with 'All Functions' and 'PCI-Express' enabled"
  echo "     3. Ensure IOMMU is enabled in BIOS and Proxmox host"
  echo "     4. For NVIDIA: Add vfio modules to /etc/modules"
}

# Add second NIC for 10G storage network
add_10g_nic() {
  local vmid="$1"
  local bridge="$2"
  
  echo "  -> Adding 10G storage NIC (net1) on bridge $bridge..."
  
  # Check if net1 already exists
  if qm config "$vmid" | grep -q "^net1:"; then
    echo "     net1 already exists, skipping"
    return 0
  fi
  
  # Add virtio NIC on the specified bridge
  local nic_config="virtio,bridge=${bridge},firewall=0"
  
  if $DO_APPLY; then
    qm set "$vmid" --net1 "$nic_config" >/dev/null 2>&1 || echo "     Warning: Failed to add net1"
    echo "     net1=$nic_config"
  else
    echo "     (dry-run) qm set $vmid --net1 '$nic_config'"
  fi
  
  echo ""
  echo "  -> After VM starts, configure in Talos (ens19 will be the 10G NIC):"
  echo "     machine:"
  echo "       network:"
  echo "         interfaces:"
  echo "           - interface: ens19"
  echo "             dhcp: false"
  echo "             addresses:"
  echo "               - 172.31.250.X/24"
}

main() {
  mapfile -t VMIDS < <(collect_vmids)
  if [[ ${#VMIDS[@]} -eq 0 ]]; then
    echo "No matching VMs found." >&2
    exit 0
  fi

  echo "============================================"
  echo "Proxmox VM Post-Install Optimization Script"
  echo "============================================"
  echo ""
  
  if $GPU_MODE; then
    echo "Mode: GPU Passthrough Optimization"
    echo "Settings: cpu=host, machine=q35, numa=1, hugepages=1GB, balloon=0"
  elif $ADD_10G_NIC; then
    echo "Mode: Add 10G Storage NIC"
    echo "Bridge: $NIC_BRIDGE"
  else
    echo "Mode: Disk Optimization"
    echo "Settings: ssd=1, discard=on, iothread=1, cache=none, aio=io_uring"
  fi
  echo ""
  
  $DO_APPLY || echo "⚠️  Dry-run mode (no changes). Use --apply to execute."
  echo ""

  for vmid in "${VMIDS[@]}"; do
    echo "Processing VM $vmid..."
    local status
    status=$(qm status "$vmid" | awk '{print $2}') || status="unknown"
    if [[ "$status" == "running" && "$INCLUDE_RUNNING" == false ]]; then
      echo "  -> Skipping: VM is running (use --include-running to override)"
      echo "--------------------------------------------"
      continue
    fi
    
    # Apply GPU settings if requested
    if $GPU_MODE; then
      apply_gpu_settings "$vmid"
    fi
    
    # Add 10G NIC if requested
    if $ADD_10G_NIC; then
      add_10g_nic "$vmid" "$NIC_BRIDGE"
    fi

    # Always apply disk optimizations (unless only adding NIC)
    if ! $ADD_10G_NIC || $GPU_MODE; then
      if $ALL_SCSI; then
        while read -r key _; do
          update_slot "$vmid" "$key"
        done < <(qm config "$vmid" | awk -F':' '/^scsi[0-9]+:/ {print $1 ":"}')
      else
        update_slot "$vmid" "$SLOT"
      fi
    fi

    echo "--------------------------------------------"
  done

  if $DO_APPLY; then
    echo "✅ Done. Changes applied."
  else
    echo "Preview complete. Re-run with --apply to make changes."
  fi
}

main "$@"
