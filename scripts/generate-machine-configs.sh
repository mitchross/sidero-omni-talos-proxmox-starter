#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Machine Configuration Generator for Omni
# =============================================================================
# This script:
# 1. Reads matched machines from discover-machines.sh output
# 2. Generates Talos Machine YAML documents with patches for:
#    - Static IP configuration
#    - Hostname
#    - Secondary disk mounting (for Longhorn)
# 3. Creates omnictl-compatible YAML files
#
# Prerequisites:
# - discover-machines.sh has been run successfully
# - matched-machines.json exists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/machine-data"
OUTPUT_DIR="${SCRIPT_DIR}/machine-configs"
MATCHED_FILE="${DATA_DIR}/matched-machines.json"

echo "======================================"
echo "Omni Machine Config Generator"
echo "======================================"
echo ""

# =============================================================================
# Validate Prerequisites
# =============================================================================

if [[ ! -f "${MATCHED_FILE}" ]]; then
    echo "❌ Matched machines file not found: ${MATCHED_FILE}"
    echo "Run ./discover-machines.sh first"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found"
    echo "Install jq: sudo apt-get install jq"
    exit 1
fi

# =============================================================================
# Load Matched Machines
# =============================================================================

MATCHED_MACHINES=$(cat "${MATCHED_FILE}")
MACHINE_COUNT=$(echo "${MATCHED_MACHINES}" | jq 'length')

if [[ ${MACHINE_COUNT} -eq 0 ]]; then
    echo "❌ No matched machines found"
    exit 1
fi

echo "Found ${MACHINE_COUNT} matched machines"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}"/*.yaml 2>/dev/null || true

# =============================================================================
# Generate Machine Configurations
# =============================================================================

echo "Generating machine configurations..."
echo ""

# Process each matched machine
CONTROL_PLANE_MACHINES=()
WORKER_MACHINES=()
GPU_WORKER_MACHINES=()

while IFS= read -r machine; do
    # Extract machine details
    HOSTNAME=$(echo "${machine}" | jq -r '.hostname')
    OMNI_UUID=$(echo "${machine}" | jq -r '.omni_uuid')
    IP_ADDRESS=$(echo "${machine}" | jq -r '.ip_address')
    ROLE=$(echo "${machine}" | jq -r '.role')
    GATEWAY=$(echo "${machine}" | jq -r '.terraform_data.gateway')
    DNS_SERVERS=$(echo "${machine}" | jq -r '.terraform_data.dns_servers | join("\",\"")' | sed 's/^/["/; s/$/"]/')
    HAS_DATA_DISK=$(echo "${machine}" | jq -r '.terraform_data.has_data_disk')

    echo "Processing: ${HOSTNAME} (${OMNI_UUID})"

    # Track machines by role
    case "${ROLE}" in
        "control-plane")
            CONTROL_PLANE_MACHINES+=("${OMNI_UUID}")
            ;;
        "worker")
            WORKER_MACHINES+=("${OMNI_UUID}")
            ;;
        "gpu-worker")
            GPU_WORKER_MACHINES+=("${OMNI_UUID}")
            ;;
    esac

    # Create machine config file
    CONFIG_FILE="${OUTPUT_DIR}/${HOSTNAME}.yaml"

    # Generate Machine YAML document
    cat > "${CONFIG_FILE}" <<EOF
---
kind: Machine
name: ${OMNI_UUID}
labels:
  role: ${ROLE}
  hostname: ${HOSTNAME}
patches:
  - name: ${HOSTNAME}-network-config
    inline:
      machine:
        network:
          hostname: ${HOSTNAME}
          interfaces:
            - interface: eth0
              dhcp: false
              addresses:
                - ${IP_ADDRESS}/24
              routes:
                - network: 0.0.0.0/0
                  gateway: ${GATEWAY}
          nameservers:
            - ${DNS_SERVERS}
EOF

    # Add secondary disk configuration if present
    if [[ "${HAS_DATA_DISK}" == "true" ]]; then
        cat >> "${CONFIG_FILE}" <<EOF
  - name: ${HOSTNAME}-storage-config
    inline:
      machine:
        kubelet:
          extraMounts:
            - destination: /var/lib/longhorn
              type: bind
              source: /var/lib/longhorn
              options:
                - bind
                - rshared
                - rw
        disks:
          - device: /dev/sdb
            partitions:
              - mountpoint: /var/lib/longhorn
EOF
    fi

    # Add GPU-specific configuration for GPU workers
    if [[ "${ROLE}" == "gpu-worker" ]]; then
        cat >> "${CONFIG_FILE}" <<EOF
  - name: ${HOSTNAME}-gpu-config
    inline:
      machine:
        install:
          extensions:
            - image: ghcr.io/siderolabs/nvidia-container-toolkit:latest
            - image: ghcr.io/siderolabs/nonfree-kmod-nvidia:latest
        kernel:
          modules:
            - name: nvidia
            - name: nvidia_uvm
            - name: nvidia_drm
            - name: nvidia_modeset
        kubelet:
          extraArgs:
            feature-gates: DevicePlugins=true
EOF
    fi

done < <(echo "${MATCHED_MACHINES}" | jq -c '.[]')

echo ""
echo "✓ Generated ${MACHINE_COUNT} machine configurations"
echo ""

# =============================================================================
# Generate Combined Cluster Template
# =============================================================================

echo "Generating combined cluster template..."

CLUSTER_TEMPLATE="${OUTPUT_DIR}/cluster-template.yaml"

# Generate cluster template header
cat > "${CLUSTER_TEMPLATE}" <<EOF
# =============================================================================
# Talos Cluster Template for Omni
# Generated by generate-machine-configs.sh
# =============================================================================
#
# This file contains:
# - Cluster configuration
# - Control Plane definition
# - Worker machine sets
# - Individual Machine configurations with static IPs
#
# Apply with:
#   omnictl cluster template sync -f ${CLUSTER_TEMPLATE}
#
# Or apply individual machine configs:
#   omnictl cluster template sync -f machine-configs/<hostname>.yaml
# =============================================================================

---
kind: Cluster
name: talos-cluster
kubernetes:
  version: v1.30.0
talos:
  version: v1.7.0
features:
  diskEncryption: false
  enableWorkloadProxy: true
EOF

# Add control plane section
if [[ ${#CONTROL_PLANE_MACHINES[@]} -gt 0 ]]; then
    cat >> "${CLUSTER_TEMPLATE}" <<EOF

---
kind: ControlPlane
machines:
EOF
    for uuid in "${CONTROL_PLANE_MACHINES[@]}"; do
        echo "  - ${uuid}" >> "${CLUSTER_TEMPLATE}"
    done
fi

# Add regular workers section
if [[ ${#WORKER_MACHINES[@]} -gt 0 ]]; then
    cat >> "${CLUSTER_TEMPLATE}" <<EOF

---
kind: Workers
name: workers
machines:
EOF
    for uuid in "${WORKER_MACHINES[@]}"; do
        echo "  - ${uuid}" >> "${CLUSTER_TEMPLATE}"
    done
fi

# Add GPU workers section
if [[ ${#GPU_WORKER_MACHINES[@]} -gt 0 ]]; then
    cat >> "${CLUSTER_TEMPLATE}" <<EOF

---
kind: Workers
name: gpu-workers
machines:
EOF
    for uuid in "${GPU_WORKER_MACHINES[@]}"; do
        echo "  - ${uuid}" >> "${CLUSTER_TEMPLATE}"
    done
fi

# Append all individual machine configs
echo "" >> "${CLUSTER_TEMPLATE}"
echo "# ==============================================================================" >> "${CLUSTER_TEMPLATE}"
echo "# Machine Configurations" >> "${CLUSTER_TEMPLATE}"
echo "# ==============================================================================" >> "${CLUSTER_TEMPLATE}"
echo "" >> "${CLUSTER_TEMPLATE}"

for config_file in "${OUTPUT_DIR}"/*.yaml; do
    if [[ "$(basename ${config_file})" != "cluster-template.yaml" ]]; then
        cat "${config_file}" >> "${CLUSTER_TEMPLATE}"
        echo "" >> "${CLUSTER_TEMPLATE}"
    fi
done

echo "✓ Combined cluster template created"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "======================================"
echo "Summary"
echo "======================================"
echo ""
echo "Generated configurations:"
echo "  Control Planes: ${#CONTROL_PLANE_MACHINES[@]}"
echo "  Workers:        ${#WORKER_MACHINES[@]}"
echo "  GPU Workers:    ${#GPU_WORKER_MACHINES[@]}"
echo "  Total:          ${MACHINE_COUNT}"
echo ""
echo "Files created:"
echo "  Individual configs: ${OUTPUT_DIR}/<hostname>.yaml"
echo "  Combined template:  ${CLUSTER_TEMPLATE}"
echo ""

echo "======================================"
echo "Next Steps"
echo "======================================"
echo ""
echo "Option 1: Apply combined cluster template (recommended):"
echo "  omnictl cluster template sync -f ${CLUSTER_TEMPLATE}"
echo ""
echo "Option 2: Apply individual machine configs:"
echo "  for f in ${OUTPUT_DIR}/*.yaml; do"
echo "    omnictl cluster template sync -f \$f"
echo "  done"
echo ""
echo "Option 3: Use the apply script:"
echo "  ./apply-machine-configs.sh"
echo ""
