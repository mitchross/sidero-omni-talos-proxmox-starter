#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Machine Configuration Applier for Omni
# =============================================================================
# This script applies machine configurations to Omni using omnictl
#
# Prerequisites:
# - generate-machine-configs.sh has been run
# - omnictl is configured and authenticated
# - cluster-template.yaml exists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/machine-configs"
CLUSTER_TEMPLATE="${CONFIG_DIR}/cluster-template.yaml"

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

if [[ ! -f "${CLUSTER_TEMPLATE}" ]]; then
    echo "❌ Cluster template not found: ${CLUSTER_TEMPLATE}"
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
# Display Configuration Preview
# =============================================================================

echo "======================================"
echo "Configuration Preview"
echo "======================================"
echo ""

# Count machines (match only UUID lines, not patch lines)
# Use awk to extract sections properly (grep -A 100 was grabbing too many lines)
# UUIDs have format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (8-4-4-4-12 hex digits)

# ControlPlane section: from "kind: ControlPlane" to next "---"
CONTROL_COUNT=$(awk '/^kind: ControlPlane$/,/^---$/' "${CLUSTER_TEMPLATE}" | grep -c "^  - [0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}$" 2>/dev/null || echo 0)

# Workers section with name: workers (not gpu-workers)
WORKER_COUNT=$(awk '
  /^kind: Workers$/ { in_workers=1; section=""; next }
  in_workers && /^name: workers$/ { section="workers"; next }
  in_workers && /^name: gpu-workers$/ { section="gpu"; next }
  in_workers && section=="workers" && /^  - [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/ { print }
  /^---$/ { in_workers=0; section="" }
' "${CLUSTER_TEMPLATE}" | wc -l || echo 0)

# Workers section with name: gpu-workers
GPU_COUNT=$(awk '
  /^kind: Workers$/ { in_workers=1; section=""; next }
  in_workers && /^name: workers$/ { section="workers"; next }
  in_workers && /^name: gpu-workers$/ { section="gpu"; next }
  in_workers && section=="gpu" && /^  - [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/ { print }
  /^---$/ { in_workers=0; section="" }
' "${CLUSTER_TEMPLATE}" | wc -l || echo 0)

echo "Cluster Template: ${CLUSTER_TEMPLATE}"
echo ""
echo "Machine Sets:"
echo "  Control Planes: ${CONTROL_COUNT}"
echo "  Workers:        ${WORKER_COUNT}"
echo "  GPU Workers:    ${GPU_COUNT}"
echo "  Total:          $((CONTROL_COUNT + WORKER_COUNT + GPU_COUNT))"
echo ""

# Show sample machine configs
echo "Sample machine configurations:"
echo ""
head -n 30 "${CLUSTER_TEMPLATE}" | grep -A 20 "^kind: Machine" | head -n 25 || true
echo "..."
echo ""

# =============================================================================
# Confirmation
# =============================================================================

read -p "Apply this configuration to Omni? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# =============================================================================
# Apply Configuration
# =============================================================================

echo "======================================"
echo "Applying Configuration"
echo "======================================"
echo ""

echo "Applying cluster template..."
echo ""

# Apply the cluster template
if omnictl cluster template sync -f "${CLUSTER_TEMPLATE}"; then
    echo ""
    echo "✓ Cluster template applied successfully"
else
    echo ""
    echo "❌ Failed to apply cluster template"
    echo ""
    echo "Check the error message above for details."
    echo "Common issues:"
    echo "  - Machines not registered in Omni yet"
    echo "  - Invalid YAML syntax"
    echo "  - Network configuration conflicts"
    echo "  - Permission issues"
    exit 1
fi

echo ""

# =============================================================================
# Verification
# =============================================================================

echo "======================================"
echo "Verification"
echo "======================================"
echo ""

echo "Waiting 5 seconds for configuration to propagate..."
sleep 5

echo ""
echo "Checking machine status..."
echo ""

# Get machine status from Omni
omnictl get machines -o wide || true

echo ""

# =============================================================================
# Next Steps
# =============================================================================

echo "======================================"
echo "Next Steps"
echo "======================================"
echo ""
echo "1. Verify machine configurations in Omni UI"
echo "   https://YOUR_OMNI_URL/machines"
echo ""
echo "2. Check that hostnames are set:"
echo "   omnictl get machines -o json | jq '.items[] | {name: .metadata.name, hostname: .spec.hostname}'"
echo ""
echo "3. Verify static IPs are applied:"
echo "   Check each machine in Omni UI → Machine → Network"
echo ""
echo "4. For GPU workers, manually configure GPU passthrough:"
echo "   cd ../terraform"
echo "   terraform output gpu_configuration_needed"
echo ""
echo "5. Create the cluster in Omni UI or via cluster template"
echo ""
echo "6. Monitor machine status:"
echo "   omnictl get machines --watch"
echo ""

echo "======================================"
echo "Troubleshooting"
echo "======================================"
echo ""
echo "If machines don't get static IPs:"
echo "  - Check that DHCP reservations are configured"
echo "  - Verify network configuration in machine patches"
echo "  - Check Omni logs: docker logs omni"
echo ""
echo "If hostnames don't apply:"
echo "  - Machine patches may take a few minutes to apply"
echo "  - Check patch status: omnictl get configpatches"
echo ""
echo "If secondary disks aren't mounted:"
echo "  - Verify disk exists: omnictl get machines -o json | jq '.items[].spec.hardware.blockdevices'"
echo "  - Check Talos logs via Omni UI"
echo ""
