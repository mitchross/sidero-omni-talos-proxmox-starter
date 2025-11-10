#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Machine Configuration Applier for Omni
# =============================================================================
# This script intelligently applies machine configurations based on cluster state:
#
# Scenario 1: No cluster exists
#   → Creates new cluster with all machines
#
# Scenario 2: Cluster exists
#   → Adds new machines to existing cluster
#   → Updates patches on existing machines
#
# Prerequisites:
# - generate-machine-configs.sh has been run
# - omnictl is configured and authenticated
# - Cluster template and individual machine YAML files exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/machine-configs"
DATA_DIR="${SCRIPT_DIR}/machine-data"
MATCHED_FILE="${DATA_DIR}/matched-machines.json"
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

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found"
    echo "Install jq: brew install jq"
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "⚠️  yq not found - some features may be limited"
    echo "Install yq: brew install yq"
fi

if [[ ! -f "${MATCHED_FILE}" ]]; then
    echo "❌ Matched machines file not found: ${MATCHED_FILE}"
    echo "Run ./discover-machines.sh first"
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
# Extract Cluster Information
# =============================================================================

# Get cluster name from template
CLUSTER_NAME=$(grep "^name:" "${CLUSTER_TEMPLATE}" | head -1 | awk '{print $2}')

if [[ -z "${CLUSTER_NAME}" ]]; then
    echo "❌ Could not extract cluster name from template"
    exit 1
fi

echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# =============================================================================
# Load Machine Data
# =============================================================================

MATCHED_MACHINES=$(cat "${MATCHED_FILE}")
MACHINE_COUNT=$(echo "${MATCHED_MACHINES}" | jq 'length')

# Count by role using awk to extract sections properly
CONTROL_COUNT=$(awk '/^kind: ControlPlane$/,/^---$/' "${CLUSTER_TEMPLATE}" | grep -c "^  - [0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}$" 2>/dev/null || echo 0)
WORKER_COUNT=$(awk '/^kind: Workers$/,/^---$/' "${CLUSTER_TEMPLATE}" | grep -c "^  - [0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}$" 2>/dev/null || echo 0)

# Get GPU worker count (second Workers section)
GPU_COUNT=$(awk '/^kind: Workers$/,/^---$/' "${CLUSTER_TEMPLATE}" | awk '/^name: gpu-workers$/,/^---$/' | grep -c "^  - [0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}$" 2>/dev/null || echo 0)

# =============================================================================
# Detect Cluster State
# =============================================================================

echo "======================================"
echo "Detecting Cluster State"
echo "======================================"
echo ""

CLUSTER_EXISTS=false
if omnictl get cluster "${CLUSTER_NAME}" &> /dev/null; then
    CLUSTER_EXISTS=true
    echo "✓ Cluster '${CLUSTER_NAME}' already exists"
else
    echo "• Cluster '${CLUSTER_NAME}' does not exist"
fi

echo ""

# =============================================================================
# Get Existing Machines (if cluster exists)
# =============================================================================

EXISTING_MACHINES=()
NEW_MACHINES=()
EXISTING_MACHINE_COUNT=0

if [[ "${CLUSTER_EXISTS}" == "true" ]]; then
    echo "======================================"
    echo "Analyzing Existing Cluster"
    echo "======================================"
    echo ""

    # Get machines already in the cluster
    echo "Fetching existing machines from cluster..."

    # Get control plane machines
    EXISTING_CP=$(omnictl get controlplane -o json 2>/dev/null | jq -r '.metadata.labels."omni.sidero.dev/cluster" as $cluster | select($cluster == "'${CLUSTER_NAME}'") | .spec.machines[]?' 2>/dev/null || echo "")

    # Get worker machines
    EXISTING_WORKERS=$(omnictl get workers -o json 2>/dev/null | jq -r '.metadata.labels."omni.sidero.dev/cluster" as $cluster | select($cluster == "'${CLUSTER_NAME}'") | .spec.machines[]?' 2>/dev/null || echo "")

    # Combine into array
    if [[ -n "${EXISTING_CP}" ]]; then
        while IFS= read -r machine; do
            EXISTING_MACHINES+=("${machine}")
        done <<< "${EXISTING_CP}"
    fi

    if [[ -n "${EXISTING_WORKERS}" ]]; then
        while IFS= read -r machine; do
            EXISTING_MACHINES+=("${machine}")
        done <<< "${EXISTING_WORKERS}"
    fi

    EXISTING_MACHINE_COUNT=${#EXISTING_MACHINES[@]}

    echo "  Existing machines in cluster: ${EXISTING_MACHINE_COUNT}"

    # Determine which machines are new
    ALL_MACHINES=$(awk '/^kind: Machine$/,/^---$/' "${CLUSTER_TEMPLATE}" | grep "^name:" | awk '{print $2}')

    while IFS= read -r machine_uuid; do
        if [[ -n "${machine_uuid}" ]]; then
            # Check if machine already exists in cluster
            MACHINE_EXISTS=false
            for existing in "${EXISTING_MACHINES[@]}"; do
                if [[ "${existing}" == "${machine_uuid}" ]]; then
                    MACHINE_EXISTS=true
                    break
                fi
            done

            if [[ "${MACHINE_EXISTS}" == "false" ]]; then
                NEW_MACHINES+=("${machine_uuid}")
            fi
        fi
    done <<< "${ALL_MACHINES}"

    NEW_MACHINE_COUNT=${#NEW_MACHINES[@]}

    echo "  New machines to add: ${NEW_MACHINE_COUNT}"

    if [[ ${NEW_MACHINE_COUNT} -gt 0 ]]; then
        echo ""
        echo "New machines:"
        for new_machine in "${NEW_MACHINES[@]}"; do
            HOSTNAME=$(echo "${MATCHED_MACHINES}" | jq -r ".[] | select(.omni_uuid == \"${new_machine}\") | .hostname")
            echo "  - ${HOSTNAME} (${new_machine})"
        done
    fi

    echo ""
fi

# =============================================================================
# Display Configuration Preview
# =============================================================================

echo "======================================"
echo "Configuration Preview"
echo "======================================"
echo ""

if [[ "${CLUSTER_EXISTS}" == "false" ]]; then
    echo "Action: Create new cluster with machines"
    echo ""
    echo "This will:"
    echo "  ✓ Create cluster '${CLUSTER_NAME}'"
    echo "  ✓ Assign ${CONTROL_COUNT} control plane machines"
    echo "  ✓ Assign ${WORKER_COUNT} worker machines"
    if [[ ${GPU_COUNT} -gt 0 ]]; then
        echo "  ✓ Assign ${GPU_COUNT} GPU worker machines"
    fi
    echo "  ✓ Apply all machine patches (hostnames, labels, configs)"
    echo ""

    echo "Machine Sets:"
    echo "  Control Planes: ${CONTROL_COUNT}"
    echo "  Workers:        ${WORKER_COUNT}"
    if [[ ${GPU_COUNT} -gt 0 ]]; then
        echo "  GPU Workers:    ${GPU_COUNT}"
    fi
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
else
    echo "Action: Update existing cluster"
    echo ""

    if [[ ${NEW_MACHINE_COUNT} -gt 0 ]]; then
        echo "This will:"
        echo "  ✓ Add ${NEW_MACHINE_COUNT} new machines to cluster '${CLUSTER_NAME}'"
        echo "  ✓ Update patches on ${EXISTING_MACHINE_COUNT} existing machines"
        echo ""
    else
        echo "This will:"
        echo "  ✓ Update patches on ${EXISTING_MACHINE_COUNT} existing machines"
        echo "  • No new machines to add"
        echo ""
    fi
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

if [[ "${CLUSTER_EXISTS}" == "false" ]]; then
    read -p "Create cluster '${CLUSTER_NAME}' with ${MACHINE_COUNT} machines? (yes/no): " CONFIRM
else
    if [[ ${NEW_MACHINE_COUNT} -gt 0 ]]; then
        read -p "Add ${NEW_MACHINE_COUNT} new machines and update existing patches? (yes/no): " CONFIRM
    else
        read -p "Update patches on ${EXISTING_MACHINE_COUNT} existing machines? (yes/no): " CONFIRM
    fi
fi

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

if [[ "${CLUSTER_EXISTS}" == "false" ]]; then
    # =============================================================================
    # Scenario 1: Create New Cluster
    # =============================================================================

    echo "Creating new cluster with full template..."
    echo ""

    echo "Running dry-run first..."
    if omnictl cluster template sync --dry-run -f "${CLUSTER_TEMPLATE}" 2>&1 | head -30; then
        echo ""
        echo "✓ Dry-run successful"
        echo ""
        echo "Applying cluster template..."
        echo ""

        if omnictl cluster template sync -f "${CLUSTER_TEMPLATE}"; then
            echo ""
            echo "✓ Cluster created successfully"
            APPLIED_COUNT=${MACHINE_COUNT}
            FAILED_COUNT=0
        else
            echo ""
            echo "❌ Failed to create cluster"
            exit 1
        fi
    else
        echo ""
        echo "❌ Dry-run failed"
        exit 1
    fi

else
    # =============================================================================
    # Scenario 2: Update Existing Cluster
    # =============================================================================

    if [[ ${NEW_MACHINE_COUNT} -gt 0 ]]; then
        echo "Adding new machines and updating existing patches..."
        echo ""

        # Apply full template - Omni will handle merging
        echo "Running dry-run first..."
        if omnictl cluster template sync --dry-run -f "${CLUSTER_TEMPLATE}" 2>&1 | head -30; then
            echo ""
            echo "✓ Dry-run successful"
            echo ""
            echo "Applying updated cluster template..."
            echo ""

            if omnictl cluster template sync -f "${CLUSTER_TEMPLATE}"; then
                echo ""
                echo "✓ Cluster updated successfully"
                APPLIED_COUNT=${NEW_MACHINE_COUNT}
                FAILED_COUNT=0
            else
                echo ""
                echo "❌ Failed to update cluster"
                exit 1
            fi
        else
            echo ""
            echo "❌ Dry-run failed"
            exit 1
        fi
    else
        echo "Updating patches on existing machines..."
        echo ""

        # No new machines, just update patches
        echo "Running dry-run first..."
        if omnictl cluster template sync --dry-run -f "${CLUSTER_TEMPLATE}" 2>&1 | head -30; then
            echo ""
            echo "✓ Dry-run successful"
            echo ""
            echo "Applying patch updates..."
            echo ""

            if omnictl cluster template sync -f "${CLUSTER_TEMPLATE}"; then
                echo ""
                echo "✓ Patches updated successfully"
                APPLIED_COUNT=${EXISTING_MACHINE_COUNT}
                FAILED_COUNT=0
            else
                echo ""
                echo "❌ Failed to update patches"
                exit 1
            fi
        else
            echo ""
            echo "❌ Dry-run failed"
            exit 1
        fi
    fi
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "======================================"
echo "Apply Summary"
echo "======================================"
echo ""

if [[ "${CLUSTER_EXISTS}" == "false" ]]; then
    echo "Cluster Created: ${CLUSTER_NAME}"
    echo "Machines Added:  ${APPLIED_COUNT}/${MACHINE_COUNT}"
    echo "  Control Planes: ${CONTROL_COUNT}"
    echo "  Workers:        ${WORKER_COUNT}"
    if [[ ${GPU_COUNT} -gt 0 ]]; then
        echo "  GPU Workers:    ${GPU_COUNT}"
    fi
else
    if [[ ${NEW_MACHINE_COUNT} -gt 0 ]]; then
        echo "Cluster Updated: ${CLUSTER_NAME}"
        echo "New Machines Added:    ${NEW_MACHINE_COUNT}"
        echo "Existing Machines:     ${EXISTING_MACHINE_COUNT}"
        echo "Patches Updated:       ${APPLIED_COUNT}"
    else
        echo "Cluster Updated: ${CLUSTER_NAME}"
        echo "Patches Updated: ${APPLIED_COUNT}"
    fi
fi

echo ""

# =============================================================================
# Verification
# =============================================================================

echo "======================================"
echo "Verification"
echo "======================================"
echo ""

echo "Waiting 10 seconds for changes to propagate..."
sleep 10

echo ""
echo "Checking cluster status..."
omnictl get cluster "${CLUSTER_NAME}" 2>/dev/null || echo "  (Use 'omnictl get cluster ${CLUSTER_NAME}' to view status)"

echo ""
echo "Checking machine status..."
omnictl get machines 2>/dev/null | head -20 || echo "  (Use 'omnictl get machines' to view machine status)"

echo ""
echo "Checking config patches..."
omnictl get configpatches 2>/dev/null | head -20 || echo "  (Use 'omnictl get configpatches' to view patches)"

echo ""

# =============================================================================
# Next Steps
# =============================================================================

echo "======================================"
echo "Next Steps"
echo "======================================"
echo ""

if [[ "${CLUSTER_EXISTS}" == "false" ]]; then
    echo "Your cluster '${CLUSTER_NAME}' has been created!"
    echo ""
    echo "Monitor cluster creation:"
    echo "  omnictl get machines --watch"
    echo "  omnictl get cluster ${CLUSTER_NAME}"
    echo ""
    echo "View in Omni UI:"
    echo "  https://your-omni-instance/clusters/${CLUSTER_NAME}"
    echo ""
    echo "Once cluster is ready, get kubeconfig:"
    echo "  omnictl kubeconfig ${CLUSTER_NAME} > ~/.kube/${CLUSTER_NAME}.yaml"
    echo "  export KUBECONFIG=~/.kube/${CLUSTER_NAME}.yaml"
    echo "  kubectl get nodes"
    echo ""
else
    if [[ ${NEW_MACHINE_COUNT} -gt 0 ]]; then
        echo "Added ${NEW_MACHINE_COUNT} new machines to cluster '${CLUSTER_NAME}'"
        echo ""
        echo "Monitor new machines joining:"
        echo "  omnictl get machines --watch"
        echo "  kubectl get nodes --watch"
        echo ""
    else
        echo "Updated patches on existing machines in cluster '${CLUSTER_NAME}'"
        echo ""
        echo "Monitor patch application:"
        echo "  omnictl get configpatches"
        echo "  kubectl get nodes -o wide"
        echo ""
    fi
fi

echo "======================================"
echo "Troubleshooting"
echo "======================================"
echo ""
echo "If machines don't appear in cluster:"
echo "  - Check machine connectivity: omnictl get machines"
echo "  - Verify patches applied: omnictl get configpatches"
echo "  - Check cluster status: omnictl get cluster ${CLUSTER_NAME}"
echo ""
echo "To add more machines later:"
echo "  1. Update terraform.tfvars with new machines"
echo "  2. Run: terraform apply"
echo "  3. Run: ./discover-machines.sh"
echo "  4. Run: ./generate-machine-configs.sh"
echo "  5. Run: ./apply-machine-configs.sh (this script)"
echo ""
echo "To update machine configurations:"
echo "  1. Edit scripts/generate-machine-configs.sh"
echo "  2. Run: ./generate-machine-configs.sh"
echo "  3. Run: ./apply-machine-configs.sh (this script)"
echo ""

echo "======================================"
echo "Complete!"
echo "======================================"
echo ""
