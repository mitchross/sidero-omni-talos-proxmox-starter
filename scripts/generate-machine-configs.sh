#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Machine Configuration Generator for Omni
# =============================================================================
# This script:
# 1. Reads matched machines from discover-machines.sh output
# 2. Generates Talos Machine YAML documents with patches for:
#    - Hostname and node labels
#    - System extensions (iscsi-tools, nfsd, qemu-guest-agent, util-linux-tools)
#    - NVIDIA extensions (for GPU workers: nonfree-kmod-nvidia, nvidia-container-toolkit)
#    - Role-specific configurations (hostDNS, kubePrism, containerd)
#    - Secondary disk mounting (for Longhorn on workers)
# 3. Creates omnictl-compatible YAML files
#
# Prerequisites:
# - discover-machines.sh has been run successfully
# - matched-machines.json exists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/machine-data"
OUTPUT_DIR="${SCRIPT_DIR}/machine-configs"
MATCHED_FILE="${DATA_DIR}/matched-machines.json"

echo "====================================="
echo "Omni Machine Config Generator"
echo "====================================="
echo ""

# =============================================================================
# Clean Previous Configurations
# =============================================================================

echo "Cleaning previous machine configurations..."
if [[ -d "${OUTPUT_DIR}" ]]; then
    rm -rf "${OUTPUT_DIR}"
    echo "✓ Removed ${OUTPUT_DIR}"
fi
mkdir -p "${OUTPUT_DIR}"
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

# =============================================================================
# Prompt for Cluster Name
# =============================================================================

# Get default cluster name from Terraform
DEFAULT_CLUSTER_NAME=$(cd "${SCRIPT_DIR}/../terraform" && terraform output -raw cluster_summary 2>/dev/null | jq -r '.cluster_name' 2>/dev/null || echo "talos-cluster")

echo "======================================"
echo "Cluster Configuration"
echo "======================================"
echo ""
echo "Enter a name for your Talos cluster."
echo "This name will be used in Omni to identify the cluster."
echo ""
read -p "Cluster name [${DEFAULT_CLUSTER_NAME}]: " CLUSTER_NAME

if [[ -z "${CLUSTER_NAME}" ]]; then
    CLUSTER_NAME="${DEFAULT_CLUSTER_NAME}"
fi

# Validate cluster name (lowercase alphanumeric and hyphens only)
if ! [[ "${CLUSTER_NAME}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    echo ""
    echo "⚠️  Invalid cluster name: ${CLUSTER_NAME}"
    echo "Cluster name must:"
    echo "  - Start and end with lowercase letter or number"
    echo "  - Contain only lowercase letters, numbers, and hyphens"
    echo ""
    echo "Using default: ${DEFAULT_CLUSTER_NAME}"
    CLUSTER_NAME="${DEFAULT_CLUSTER_NAME}"
fi

echo ""
echo "✓ Cluster name: ${CLUSTER_NAME}"
echo ""

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
    PROXMOX_NODE=$(echo "${machine}" | jq -r '.terraform_data.proxmox_server')
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
patches:
  - idOverride: 400-cm-${OMNI_UUID}-set-hostname-${HOSTNAME}
    annotations:
      name: set-hostname-${HOSTNAME}
    inline:
      machine:
        network:
          hostname: ${HOSTNAME}
        nodeLabels:
          management-ip: ${IP_ADDRESS}
          node-role: ${ROLE}
          topology.kubernetes.io/zone: proxmox
          topology.proxmox.io/node: ${PROXMOX_NODE}
EOF

    # Add GPU label for GPU workers
    if [[ "${ROLE}" == "gpu-worker" ]]; then
        cat >> "${CONFIG_FILE}" <<'GPULABEL'
          nvidia.com/gpu: "true"
GPULABEL
    fi

    # Generate role-specific configuration patch
    if [[ "${ROLE}" == "control-plane" ]]; then
        cat >> "${CONFIG_FILE}" <<EOF
  - idOverride: 401-cm-${OMNI_UUID}-control-plane-config
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
        sysctls:
          fs.inotify.max_user_instances: "8192"
          fs.inotify.max_user_watches: "1048576"
        time:
          disabled: false
          servers:
            - time.cloudflare.com
EOF

    elif [[ "${ROLE}" == "gpu-worker" ]]; then
        cat >> "${CONFIG_FILE}" <<EOF
  - idOverride: 401-cm-${OMNI_UUID}-gpu-worker-config
    annotations:
      name: gpu-worker-config
    inline:
      machine:
        features:
          hostDNS:
            enabled: true
            forwardKubeDNSToHost: true
          kubePrism:
            enabled: true
            port: 7445
        files:
          - content: |
              [plugins."io.containerd.grpc.v1.cri"]
                enable_unprivileged_ports = true
                enable_unprivileged_icmp = true
              [plugins."io.containerd.grpc.v1.cri".containerd]
                default_runtime_name = "nvidia"
              [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
                privileged_without_host_devices = false
                runtime_engine = ""
                runtime_root = ""
                runtime_type = "io.containerd.runc.v2"
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
                  BinaryName = "/usr/bin/nvidia-container-runtime"
            op: create
            path: /etc/cri/conf.d/20-customization.part
        kernel:
          modules:
            - name: nvidia
            - name: nvidia_uvm
            - name: nvidia_drm
            - name: nvidia_modeset
            - name: br_netfilter
              parameters:
                - nf_conntrack_max=131072
EOF
        # Add Longhorn mount for GPU workers (if they have data disk)
        if [[ "${HAS_DATA_DISK}" == "true" ]]; then
            cat >> "${CONFIG_FILE}" <<EOF
        kubelet:
          extraMounts:
            - destination: /var/lib/longhorn
              options:
                - bind
                - rshared
                - rw
              source: /var/mnt/longhorn
              type: bind
EOF
        fi
        cat >> "${CONFIG_FILE}" <<EOF
        sysctls:
          fs.inotify.max_user_instances: "8192"
          fs.inotify.max_user_watches: "1048576"
          net.core.bpf_jit_harden: "1"
        time:
          disabled: false
          servers:
            - time.cloudflare.com
EOF

    else  # Regular worker
        cat >> "${CONFIG_FILE}" <<EOF
  - idOverride: 401-cm-${OMNI_UUID}-regular-worker-config
    annotations:
      name: regular-worker-config
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
        files:
          - content: |
              [plugins."io.containerd.grpc.v1.cri"]
                enable_unprivileged_ports = true
                enable_unprivileged_icmp = true
            op: create
            path: /etc/cri/conf.d/20-customization.part
        kernel:
          modules:
            - name: br_netfilter
              parameters:
                - nf_conntrack_max=131072
EOF
        # Add Longhorn mount for regular workers (if they have data disk)
        if [[ "${HAS_DATA_DISK}" == "true" ]]; then
            cat >> "${CONFIG_FILE}" <<EOF
        kubelet:
          extraMounts:
            - destination: /var/lib/longhorn
              options:
                - bind
                - rshared
                - rw
              source: /var/mnt/longhorn
              type: bind
EOF
        fi
        cat >> "${CONFIG_FILE}" <<EOF
        sysctls:
          fs.inotify.max_user_instances: "8192"
          fs.inotify.max_user_watches: "1048576"
        time:
          disabled: false
          servers:
            - time.cloudflare.com
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

# Generate cluster template header (CLUSTER_NAME was set earlier via user prompt)
cat > "${CLUSTER_TEMPLATE}" <<EOF
# =============================================================================
# Talos Cluster Template for Omni
# Generated by generate-machine-configs.sh
# =============================================================================
#
# This file contains:
# - Cluster configuration
# - Control Plane definition with untaint patch
# - Worker machine sets (regular + GPU)
# - Individual Machine configurations with:
#   - Hostnames
#   - Node labels (management-ip, node-role, zone, proxmox node)
#   - System extensions (iscsi-tools, nfsd, qemu-guest-agent, util-linux-tools)
#   - NVIDIA extensions (GPU workers: nonfree-kmod-nvidia, nvidia-container-toolkit)
#   - Role-specific configurations (hostDNS, kubePrism, containerd)
#   - Longhorn mounts (for workers with data disks)
#
# Network: Using DHCP (PXE boot), not static IPs
#
# Apply with:
#   omnictl cluster template sync -f ${CLUSTER_TEMPLATE}
#
# Or apply individual machine configs:
#   omnictl cluster template sync -f machine-configs/<hostname>.yaml
# =============================================================================

---
kind: Cluster
name: ${CLUSTER_NAME}
kubernetes:
  version: v1.34.1
talos:
  version: v1.11.5
features:
  diskEncryption: false
  enableWorkloadProxy: true
patches:
  - name: system-extensions
    inline:
      machine:
        install:
          extensions:
            - image: ghcr.io/siderolabs/iscsi-tools:v0.1.6
            - image: ghcr.io/siderolabs/nfsd:v1.11.0
            - image: ghcr.io/siderolabs/qemu-guest-agent:9.1.2
            - image: ghcr.io/siderolabs/util-linux-tools:2.40.2
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
    # Add untaint patch to prevent scheduling workloads on control planes
    cat >> "${CLUSTER_TEMPLATE}" <<'EOF'
patches:
  - idOverride: 400-control-planes-untaint
    annotations:
      name: ""
    inline:
      cluster:
        allowSchedulingOnControlPlanes: false
        proxy:
          disabled: true
EOF
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
    # Add GPU-specific extensions
    cat >> "${CLUSTER_TEMPLATE}" <<'EOF'
patches:
  - name: nvidia-extensions
    inline:
      machine:
        install:
          extensions:
            - image: ghcr.io/siderolabs/nonfree-kmod-nvidia-production:550.127.05-v1.11.0
            - image: ghcr.io/siderolabs/nvidia-container-toolkit-production:550.127.05-v1.11.0
EOF
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
