#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Machine Discovery Script for Omni + Terraform Integration
# =============================================================================
# This script:
# 1. Queries Omni API for registered Talos machines
# 2. Matches them to Terraform inventory by MAC address
# 3. Creates machine UUID mapping for configuration
#
# Prerequisites:
# - omnictl installed and configured
# - Terraform has been applied (VMs created)
# - Talos machines have booted and registered with Omni

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
OUTPUT_DIR="${SCRIPT_DIR}/machine-data"

echo "======================================"
echo "Omni Machine Discovery"
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
    echo "Install jq: sudo apt-get install jq"
    exit 1
fi

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    echo "❌ Terraform directory not found: ${TERRAFORM_DIR}"
    exit 1
fi

# Check if terraform state exists
if [[ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]]; then
    echo "❌ Terraform state not found"
    echo "Run 'terraform apply' first to create VMs"
    exit 1
fi

# Check omnictl connectivity
echo "Checking omnictl connectivity..."
if ! omnictl get machines &> /dev/null; then
    echo "❌ Cannot connect to Omni"
    echo "Configure omnictl with: omnictl config new"
    exit 1
fi

echo "✓ All prerequisites met"
echo ""

# =============================================================================
# Extract Terraform Inventory
# =============================================================================

echo "Extracting Terraform inventory..."
cd "${TERRAFORM_DIR}"

# Export machine inventory from Terraform
TERRAFORM_INVENTORY=$(terraform output -json machine_inventory 2>/dev/null)

if [[ -z "${TERRAFORM_INVENTORY}" || "${TERRAFORM_INVENTORY}" == "null" ]]; then
    echo "❌ No machine inventory found in Terraform state"
    exit 1
fi

# Count expected machines
EXPECTED_MACHINES=$(echo "${TERRAFORM_INVENTORY}" | jq 'length')
echo "✓ Found ${EXPECTED_MACHINES} machines in Terraform inventory"
echo ""

# =============================================================================
# Query Omni for Registered Machines
# =============================================================================

echo "Querying Omni for registered machines..."

# Get all machine statuses from Omni in JSON format
# Note: omnictl returns newline-delimited JSON, so we use jq -s to slurp into array
OMNI_MACHINES=$(omnictl get machinestatus -o json 2>/dev/null | jq -s '.')

if [[ -z "${OMNI_MACHINES}" || "${OMNI_MACHINES}" == "[]" ]]; then
    echo "⚠️  No machines registered in Omni yet"
    echo ""
    echo "Wait for Talos VMs to boot and register with Omni."
    echo "This can take 2-5 minutes after terraform apply."
    echo ""
    echo "Check Omni UI: https://YOUR_OMNI_URL/machines"
    exit 1
fi

REGISTERED_COUNT=$(echo "${OMNI_MACHINES}" | jq 'length')
echo "✓ Found ${REGISTERED_COUNT} machines registered in Omni"
echo ""

# =============================================================================
# Match Machines by MAC Address
# =============================================================================

echo "Matching machines by MAC address..."
echo ""

mkdir -p "${OUTPUT_DIR}"

# Create matched inventory
MATCHED_FILE="${OUTPUT_DIR}/matched-machines.json"
UNMATCHED_FILE="${OUTPUT_DIR}/unmatched-machines.json"

# Initialize arrays
MATCHED_MACHINES="[]"
UNMATCHED_TERRAFORM="[]"
UNMATCHED_OMNI="[]"

# For each Terraform machine, find matching Omni machine by MAC
while IFS= read -r tf_machine; do
    TF_NAME=$(echo "${tf_machine}" | jq -r '.key')
    TF_MAC=$(echo "${tf_machine}" | jq -r '.value.mac_address' | tr '[:lower:]' '[:upper:]')
    TF_IP=$(echo "${tf_machine}" | jq -r '.value.ip_address')
    TF_HOSTNAME=$(echo "${tf_machine}" | jq -r '.value.hostname')
    TF_ROLE=$(echo "${tf_machine}" | jq -r '.value.role')

    # Search for matching machine in Omni by MAC address
    # MAC addresses are in .spec.network.networklinks[].hardwareaddress
    # Use 'first' to ensure we only get one match even if multiple interfaces exist
    OMNI_MATCH=$(echo "${OMNI_MACHINES}" | jq --arg mac "$TF_MAC" '
        [.[] | select(.spec.network.networklinks[]? | .hardwareaddress | ascii_upcase == $mac)] | first
    ')

    if [[ -n "${OMNI_MATCH}" && "${OMNI_MATCH}" != "null" ]]; then
        OMNI_UUID=$(echo "${OMNI_MATCH}" | jq -r '.metadata.id')
        OMNI_NAME=$(echo "${OMNI_MATCH}" | jq -r '.metadata.name // .metadata.id')

        echo "✓ Matched: ${TF_HOSTNAME} (${TF_MAC}) -> Omni UUID: ${OMNI_UUID}"

        # Create matched entry - use safer method to pass JSON
        TF_DATA=$(echo "${tf_machine}" | jq -c '.value')
        OMNI_DATA=$(echo "${OMNI_MATCH}" | jq -c '.')

        if [[ -z "${TF_DATA}" || "${TF_DATA}" == "null" || -z "${OMNI_DATA}" || "${OMNI_DATA}" == "null" ]]; then
            echo "  ⚠️  Warning: Failed to extract JSON data for ${TF_HOSTNAME}, skipping..."
            continue
        fi

        MATCHED_ENTRY=$(jq -n \
            --arg tf_name "$TF_NAME" \
            --arg tf_hostname "$TF_HOSTNAME" \
            --arg tf_mac "$TF_MAC" \
            --arg tf_ip "$TF_IP" \
            --arg tf_role "$TF_ROLE" \
            --arg omni_uuid "$OMNI_UUID" \
            --arg omni_name "$OMNI_NAME" \
            --argjson tf_data "$TF_DATA" \
            --argjson omni_data "$OMNI_DATA" \
            '{
                terraform_name: $tf_name,
                hostname: $tf_hostname,
                mac_address: $tf_mac,
                ip_address: $tf_ip,
                role: $tf_role,
                omni_uuid: $omni_uuid,
                omni_name: $omni_name,
                terraform_data: $tf_data,
                omni_data: $omni_data
            }' 2>&1
        )

        if [[ $? -ne 0 ]]; then
            echo "  ⚠️  Warning: Failed to create matched entry for ${TF_HOSTNAME}, skipping..."
            echo "  Error: ${MATCHED_ENTRY}"
            continue
        fi

        MATCHED_MACHINES=$(echo "${MATCHED_MACHINES}" | jq ". + [$MATCHED_ENTRY]")
    else
        echo "⚠️  Not found in Omni: ${TF_HOSTNAME} (${TF_MAC})"
        UNMATCHED_TERRAFORM=$(echo "${UNMATCHED_TERRAFORM}" | jq ". + [${tf_machine}]")
    fi
done < <(echo "${TERRAFORM_INVENTORY}" | jq -c 'to_entries[]')

echo ""

# Save matched machines
echo "${MATCHED_MACHINES}" | jq '.' > "${MATCHED_FILE}"

MATCHED_COUNT=$(echo "${MATCHED_MACHINES}" | jq 'length')
UNMATCHED_COUNT=$(echo "${UNMATCHED_TERRAFORM}" | jq 'length')

echo "======================================"
echo "Discovery Summary"
echo "======================================"
echo ""
echo "Total Terraform machines: ${EXPECTED_MACHINES}"
echo "Total Omni machines:      ${REGISTERED_COUNT}"
echo "Matched:                  ${MATCHED_COUNT}"
echo "Unmatched (Terraform):    ${UNMATCHED_COUNT}"
echo ""

if [[ ${MATCHED_COUNT} -eq 0 ]]; then
    echo "❌ No machines matched!"
    echo ""
    echo "Possible reasons:"
    echo "1. VMs haven't booted yet"
    echo "2. Talos hasn't connected to Omni (check SideroLink)"
    echo "3. MAC address mismatch"
    echo ""
    echo "Check Omni UI for machine status"
    exit 1
fi

if [[ ${UNMATCHED_COUNT} -gt 0 ]]; then
    echo "⚠️  Some machines are not registered in Omni yet:"
    echo "${UNMATCHED_TERRAFORM}" | jq -r '.[] | "  - \(.value.hostname) (\(.value.mac_address))"'
    echo ""
    echo "These machines may still be booting or have connection issues."
    echo ""
fi

# Save results
echo "Results saved to:"
echo "  ${MATCHED_FILE}"
echo ""

# Create quick reference files
echo "Creating quick reference files..."

# Machine UUID list
echo "${MATCHED_MACHINES}" | jq -r '.[] | "\(.hostname)=\(.omni_uuid)"' > "${OUTPUT_DIR}/machine-uuids.txt"

# MAC to UUID mapping
echo "${MATCHED_MACHINES}" | jq -r '.[] | "\(.mac_address)=\(.omni_uuid)"' > "${OUTPUT_DIR}/mac-to-uuid.txt"

# IP to UUID mapping
echo "${MATCHED_MACHINES}" | jq -r '.[] | "\(.ip_address)=\(.omni_uuid)"' > "${OUTPUT_DIR}/ip-to-uuid.txt"

echo "✓ Quick reference files created in ${OUTPUT_DIR}/"
echo ""

echo "======================================"
echo "Next Steps"
echo "======================================"
echo ""
echo "1. Review matched machines:"
echo "   cat ${MATCHED_FILE} | jq '.'"
echo ""
echo "2. Generate machine configurations:"
echo "   ./generate-machine-configs.sh"
echo ""
echo "3. Apply configurations to Omni:"
echo "   ./apply-machine-configs.sh"
echo ""
