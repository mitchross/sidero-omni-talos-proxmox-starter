#!/usr/bin/env bash

set -euo pipefail

# Script to generate GPG key for etcd data encryption
# This key is used by Omni to encrypt etcd data at rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Omni GPG Key Generation"
echo "======================================"
echo ""

# Prompt for email
read -p "Enter your admin email address: " ADMIN_EMAIL

echo ""
echo "Generating GPG key for etcd encryption..."
echo "Note: Press Enter when prompted for a passphrase (no protection needed)"
echo ""

# Generate the key
gpg --batch --quick-generate-key "Omni (Used for etcd data encryption) ${ADMIN_EMAIL}" rsa4096 cert never

# Get the key fingerprint
KEY_ID=$(gpg --list-secret-keys --with-colons | grep '^sec' | head -n 1 | cut -d':' -f5)

if [[ -z "${KEY_ID}" ]]; then
    echo "❌ Failed to generate GPG key"
    exit 1
fi

echo "✓ Master key generated: ${KEY_ID}"

# Add encryption subkey
echo ""
echo "Adding encryption subkey..."
gpg --batch --quick-add-key "${KEY_ID}" rsa4096 encr never

echo "✓ Encryption subkey added"

echo ""
echo "======================================"
echo "Key Information"
echo "======================================"
echo ""

# Show key details
gpg -K --with-subkey-fingerprint

echo ""
echo "======================================"
echo "Exporting Key"
echo "======================================"
echo ""

# Export the key
OUTPUT_FILE="${SCRIPT_DIR}/omni.asc"
gpg --export-secret-key --armor "${ADMIN_EMAIL}" > "${OUTPUT_FILE}"

if [[ -f "${OUTPUT_FILE}" ]]; then
    echo "✓ Key exported to: ${OUTPUT_FILE}"
    chmod 600 "${OUTPUT_FILE}"
    echo ""
    echo "======================================"
    echo "✓ GPG key generation complete!"
    echo "======================================"
    echo ""
    echo "Key ID: ${KEY_ID}"
    echo "Key File: ${OUTPUT_FILE}"
    echo ""
    echo "This key will be used by Omni for etcd data encryption."
    echo "Keep this file secure and back it up safely!"
else
    echo "❌ Failed to export key"
    exit 1
fi

echo ""
echo "Note: To start fresh, you can delete the etcd data:"
echo "  sudo rm -rf ${SCRIPT_DIR}/etcd/*"
