#!/usr/bin/env bash

set -euo pipefail

# Script to generate Sidero Omni cluster template
# This script merges the base cluster template with machine-specific patches

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_TEMPLATE="${SCRIPT_DIR}/cluster-template.yaml"
MACHINES_FILE="${SCRIPT_DIR}/machines.yaml"
PATCHES_DIR="${SCRIPT_DIR}/patches"
OUTPUT_FILE="${SCRIPT_DIR}/generated-cluster-template.yaml"

echo "Generating cluster template..."
echo "================================"

# Check if required files exist
if [[ ! -f "${CLUSTER_TEMPLATE}" ]]; then
    echo "Error: cluster-template.yaml not found"
    exit 1
fi

if [[ ! -f "${MACHINES_FILE}" ]]; then
    echo "Error: machines.yaml not found"
    exit 1
fi

if [[ ! -d "${PATCHES_DIR}" ]]; then
    echo "Error: patches directory not found"
    exit 1
fi

# Copy base template
cp "${CLUSTER_TEMPLATE}" "${OUTPUT_FILE}"

echo "✓ Base cluster template loaded"
echo "✓ Machine configurations loaded"

# List available patches
echo ""
echo "Available patches:"
for patch in "${PATCHES_DIR}"/*.yaml; do
    if [[ -f "${patch}" ]]; then
        echo "  - $(basename "${patch}")"
    fi
done

echo ""
echo "================================"
echo "Cluster template generated: ${OUTPUT_FILE}"
echo ""
echo "Next steps:"
echo "1. Review the generated template"
echo "2. Apply patches as needed for your environment"
echo "3. Deploy using: omnictl cluster template apply -f ${OUTPUT_FILE}"
