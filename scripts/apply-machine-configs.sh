#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Machine Configuration Applier for Omni
# =============================================================================
# This script applies machine patches to Omni WITHOUT creating a cluster.
# This allows you to organize machines by hostname, role, and labels BEFORE
# creating a cluster, making it easier to group and identify machines in Omni.
#
# Prerequisites:
# - generate-machine-configs.sh has been run
# - omnictl is configured and authenticated
# - Individual machine YAML files exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/machine-configs"
DATA_DIR="${SCRIPT_DIR}/machine-data"
MATCHED_FILE="${DATA_DIR}/matched-machines.json"

echo "======================================"
echo "Omni Machine Config Applier"
echo "======================================"
echo ""

# =============================================================================
# Validate Prerequisites
# =============================================================================

if ! command -v omnictl &> /dev/null; then
    echo "❌ omnictl not found"
    echo "Install omnictl: https://www.siderolabs.com/omni/docs/cli/"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found"
    echo "Install jq: brew install jq"
    exit 1
fi

if [[ ! -f "${MATCHED_FILE}" ]]; then
    echo "❌ Matched machines file not found: ${MATCHED_FILE}"
    echo "Run ./discover-machines.sh first"
    exit 1
fi

if [[ ! -d "${CONFIG_DIR}" ]]; then
    echo "❌ Machine configs directory not found: ${CONFIG_DIR}"
    echo "Run ./generate-machine-configs.sh first"
    exit 1
fi

# Check omnictl connectivity
echo "Checking omnictl connectivity..."
if ! omnictl get machines &> /dev/null; then
    echo "❌ Cannot connect to Omni"
    echo "Configure omnictl with: omnictl config new"
    exit 1
fi

echo "✓ omnictl connected"
echo ""

# =============================================================================
# Load Machine Data
# =============================================================================

MATCHED_MACHINES=$(cat "${MATCHED_FILE}")
MACHINE_COUNT=$(echo "${MATCHED_MACHINES}" | jq 'length')

# Count by role
CONTROL_COUNT=$(echo "${MATCHED_MACHINES}" | jq '[.[] | select(.role == "control-plane")] | length')
WORKER_COUNT=$(echo "${MATCHED_MACHINES}" | jq '[.[] | select(.role == "worker")] | length')
GPU_COUNT=$(echo "${MATCHED_MACHINES}" | jq '[.[] | select(.role == "gpu-worker")] | length')

# =============================================================================
# Display Configuration Preview
# =============================================================================

echo "======================================"
echo "Configuration Preview"
echo "======================================"
echo ""
echo "This will apply machine patches ONLY (no cluster creation)."
echo "Machines will be labeled with hostname, role, and other metadata."
echo ""
echo "Machine Sets:"
echo "  Control Planes: ${CONTROL_COUNT}"
echo "  Workers:        ${WORKER_COUNT}"
echo "  GPU Workers:    ${GPU_COUNT}"
echo "  Total:          ${MACHINE_COUNT}"
echo ""

# Show machines grouped by role
echo "Control Plane Machines:"
echo "${MATCHED_MACHINES}" | jq -r '.[] | select(.role == "control-plane") | "  - \(.hostname) (\(.ip_address)) → \(.omni_uuid)"'
echo ""

if [[ ${WORKER_COUNT} -gt 0 ]]; then
    echo "Worker Machines:"
    echo "${MATCHED_MACHINES}" | jq -r '.[] | select(.role == "worker") | "  - \(.hostname) (\(.ip_address)) → \(.omni_uuid)"'
    echo ""
fi

if [[ ${GPU_COUNT} -gt 0 ]]; then
    echo "GPU Worker Machines:"
    echo "${MATCHED_MACHINES}" | jq -r '.[] | select(.role == "gpu-worker") | "  - \(.hostname) (\(.ip_address)) → \(.omni_uuid)"'
    echo ""
fi

echo "Each machine will get:"
echo "  ✓ Hostname set"
echo "  ✓ Node labels (management-ip, node-role, zone, proxmox node)"
echo "  ✓ Role-specific configurations (hostDNS, kubePrism, containerd)"
echo "  ✓ Longhorn mounts (for workers with data disks)"
echo "  ✓ NVIDIA GPU support (for GPU workers)"
echo ""

# =============================================================================
# Confirmation
# =============================================================================

read -p "Apply machine patches to Omni? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# =============================================================================
# Apply Machine Patches
# =============================================================================

echo "======================================"
echo "Applying Machine Patches"
echo "======================================"
echo ""

# Create a machines-only template (no cluster, just Machine resources)
MACHINES_ONLY_TEMPLATE="/tmp/machines-only-template.yaml"

echo "# Machines-only template for applying patches without creating a cluster" > "${MACHINES_ONLY_TEMPLATE}"
echo "# Generated by apply-machine-configs.sh" >> "${MACHINES_ONLY_TEMPLATE}"
echo "" >> "${MACHINES_ONLY_TEMPLATE}"

# Append all individual machine configs
for config_file in "${CONFIG_DIR}"/*.yaml; do
    if [[ "$(basename ${config_file})" != "cluster-template.yaml" ]]; then
        cat "${config_file}" >> "${MACHINES_ONLY_TEMPLATE}"
        echo "" >> "${MACHINES_ONLY_TEMPLATE}"
    fi
done

echo "Created machines-only template: ${MACHINES_ONLY_TEMPLATE}"
echo ""
echo "Applying ${MACHINE_COUNT} machine configurations..."
echo ""

# Apply the machines-only template
# This applies the patches to existing machines without creating a cluster
if omnictl cluster template sync --dry-run -f "${MACHINES_ONLY_TEMPLATE}" 2>&1 | head -20; then
    echo ""
    echo "Dry-run successful. Applying for real..."
    echo ""
    
    if omnictl cluster template sync -f "${MACHINES_ONLY_TEMPLATE}"; then
        echo ""
        echo "✓ Machine patches applied successfully"
        APPLIED_COUNT=${MACHINE_COUNT}
        FAILED_COUNT=0
    else
        echo ""
        echo "❌ Failed to apply machine patches"
        echo ""
        echo "This is expected if you're trying to apply Machine patches outside of a cluster context."
        echo "Omni requires machines to be associated with a cluster."
        echo ""
        echo "Alternative approach:"
        echo "1. Create the cluster first (in Omni UI or with cluster template)"
        echo "2. Then apply the full cluster template which includes machine patches"
        echo ""
        APPLIED_COUNT=0
        FAILED_COUNT=${MACHINE_COUNT}
    fi
else
    echo ""
    echo "❌ Dry-run failed"
    APPLIED_COUNT=0
    FAILED_COUNT=${MACHINE_COUNT}
fi

FAILED_MACHINES=()

echo "======================================"
echo "Apply Summary"
echo "======================================"
echo ""
echo "Applied:  ${APPLIED_COUNT}/${MACHINE_COUNT}"
echo "Failed:   ${FAILED_COUNT}/${MACHINE_COUNT}"

if [[ ${FAILED_COUNT} -gt 0 ]]; then
    echo ""
    echo "Failed machines:"
    for failed in "${FAILED_MACHINES[@]}"; do
        echo "  - ${failed}"
    done
fi

echo ""

if [[ ${APPLIED_COUNT} -eq 0 ]]; then
    echo "❌ No patches were applied successfully"
    exit 1
fi

# =============================================================================
# Verification
# =============================================================================

echo "======================================"
echo "Verification"
echo "======================================"
echo ""

echo "Waiting 10 seconds for patches to propagate..."
sleep 10

echo ""
echo "Checking machine status..."
echo ""

# Get machine status from Omni
omnictl get machines 2>/dev/null || echo "  (Use 'omnictl get machines' to view machine status)"

echo ""
echo "Checking config patches..."
echo ""

# Show applied config patches
omnictl get configpatches 2>/dev/null || echo "  (Use 'omnictl get configpatches' to view patches)"

echo ""

# =============================================================================
# Next Steps
# =============================================================================

echo "======================================"
echo "Next Steps"
echo "======================================"
echo ""
echo "1. Verify machines in Omni UI - they should now have:"
echo "   - Hostnames set (e.g., talos-control-1, talos-worker-1)"
echo "   - Labels visible (node-role, management-ip, zone)"
echo "   https://YOUR_OMNI_URL/machines"
echo ""
echo "2. Check machine details with:"
echo "   omnictl get machines -o json | jq '.items[] | {uuid: .metadata.id, hostname: .spec.network.hostname, labels: .metadata.labels}'"
echo ""
echo "3. Verify config patches are applied:"
echo "   omnictl get configpatches -o yaml"
echo ""
echo "4. Now you can create a cluster in Omni:"
echo "   - Use Omni UI to create cluster and select machines by hostname/role"
echo "   - OR use cluster template: omnictl cluster template sync -f ${CONFIG_DIR}/cluster-template.yaml"
echo ""
echo "5. Machines should be easy to identify and group by:"
echo "   - Hostname (talos-control-*, talos-worker-*, talos-gpu-*)"
echo "   - Role label (control-plane, worker, gpu-worker)"
echo "   - Management IP label"
echo ""

echo "======================================"
echo "Troubleshooting"
echo "======================================"
echo ""
echo "If hostnames don't appear:"
echo "  - Wait a few minutes for patches to apply"
echo "  - Check patch status: omnictl get configpatches"
echo "  - View machine details: omnictl get machines <uuid> -o yaml"
echo ""
echo "If labels don't appear:"
echo "  - Labels are applied as nodeLabels in the machine config"
echo "  - They appear after machine joins a cluster"
echo "  - Check: omnictl get machines <uuid> -o json | jq '.spec.nodeLabels'"
echo ""
echo "To see all patches for a specific machine:"
echo "  omnictl get configpatches -o yaml | grep -A 20 <machine-uuid>"
echo ""
