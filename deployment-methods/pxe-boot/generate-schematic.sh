#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Talos Image Factory Schematic Generator
# =============================================================================
# This script generates a Talos Image Factory schematic ID for system extensions
# and shows how to update the Booter configuration.
#
# The schematic includes common system extensions for all PXE-booted machines:
# - iscsi-tools: iSCSI support for storage (Longhorn, etc.)
# - nfsd: NFS server/client for persistent volumes
# - qemu-guest-agent: Proxmox VM integration
# - util-linux-tools: Essential Linux utilities
#
# GPU-specific extensions (nvidia) are added via Omni cluster templates,
# not via Booter/PXE boot.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMATIC_FILE="${SCRIPT_DIR}/talos-schematic.yaml"

echo "========================================"
echo "Talos Schematic Generator"
echo "========================================"
echo ""

# Check if schematic file exists
if [[ ! -f "${SCHEMATIC_FILE}" ]]; then
    echo "❌ Schematic file not found: ${SCHEMATIC_FILE}"
    exit 1
fi

echo "Schematic file: ${SCHEMATIC_FILE}"
echo ""
echo "Extensions included:"
echo "  - siderolabs/iscsi-tools"
echo "  - siderolabs/nfsd"
echo "  - siderolabs/qemu-guest-agent"
echo "  - siderolabs/util-linux-tools"
echo ""

# =============================================================================
# Generate Schematic ID via Image Factory API
# =============================================================================

echo "Generating schematic ID via Talos Image Factory..."
echo ""

# Upload schematic to Image Factory and get the ID
SCHEMATIC_ID=$(curl -X POST --silent --data-binary @"${SCHEMATIC_FILE}" \
  https://factory.talos.dev/schematics | jq -r '.id')

if [[ -z "${SCHEMATIC_ID}" ]] || [[ "${SCHEMATIC_ID}" == "null" ]]; then
    echo "❌ Failed to generate schematic ID"
    echo ""
    echo "Manual alternative:"
    echo "  1. Visit https://factory.talos.dev"
    echo "  2. Select Talos version: v1.11.5"
    echo "  3. Add extensions:"
    echo "     - iscsi-tools"
    echo "     - nfsd"
    echo "     - qemu-guest-agent"
    echo "     - util-linux-tools"
    echo "  4. Copy the schematic ID"
    echo "  5. Update docker-compose.yml with --default-schematic=<SCHEMATIC_ID>"
    exit 1
fi

echo "✓ Schematic ID generated: ${SCHEMATIC_ID}"
echo ""

# =============================================================================
# Show Booter Configuration
# =============================================================================

echo "========================================"
echo "Booter Configuration"
echo "========================================"
echo ""

echo "Add this flag to your Booter command in docker-compose.yml:"
echo ""
echo "  - \"--default-schematic=${SCHEMATIC_ID}\""
echo ""
echo "Full example:"
echo ""
cat <<EOF
services:
  booter:
    image: ghcr.io/siderolabs/booter:v0.3.0
    container_name: sidero-booter
    network_mode: host
    restart: unless-stopped
    command:
      - "--api-advertise-address=192.168.10.15"
      - "--dhcp-proxy-iface-or-ip=enp1s0"
      - "--api-port=50084"
      - "--default-schematic=${SCHEMATIC_ID}"
      - "--extra-kernel-args=siderolink.api=https://omni.vanillax.me:8090/?jointoken=YOUR_TOKEN talos.events.sink=[fdae:41e4:649b:9303::1]:8091 talos.logging.kernel=tcp://[fdae:41e4:649b:9303::1]:8092"
EOF
echo ""

# =============================================================================
# Automatic Update Option
# =============================================================================

echo "========================================"
echo "Update docker-compose.yml?"
echo "========================================"
echo ""
read -p "Automatically update docker-compose.yml with this schematic ID? (yes/no): " CONFIRM

if [[ "${CONFIRM}" == "yes" ]]; then
    COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        echo "❌ docker-compose.yml not found"
        exit 1
    fi

    # Check if schematic flag already exists
    if grep -q "default-schematic" "${COMPOSE_FILE}"; then
        echo "Updating existing --default-schematic flag..."
        sed -i "s|--default-schematic=.*\"|--default-schematic=${SCHEMATIC_ID}\"|" "${COMPOSE_FILE}"
    else
        echo "Adding --default-schematic flag..."
        # Insert after --api-port line
        sed -i "/--api-port=/a\\      - \"--default-schematic=${SCHEMATIC_ID}\"" "${COMPOSE_FILE}"
    fi

    echo "✓ Updated ${COMPOSE_FILE}"
    echo ""
    echo "Restart Booter to apply changes:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  docker compose down"
    echo "  docker compose up -d"
else
    echo "Skipped automatic update."
    echo ""
    echo "Manually add the flag to docker-compose.yml:"
    echo "  - \"--default-schematic=${SCHEMATIC_ID}\""
fi

echo ""
echo "========================================"
echo "Complete!"
echo "========================================"
echo ""
echo "Schematic ID: ${SCHEMATIC_ID}"
echo ""
echo "This schematic will be used for all PXE-booted machines."
echo "GPU-specific extensions are added via Omni cluster templates."
echo ""
echo "Image Factory URL:"
echo "  https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=iscsi-tools&extensions=nfsd&extensions=qemu-guest-agent&extensions=util-linux-tools&platform=metal&secureboot=false&target=metal&version=1.11.5"
echo ""
