#!/usr/bin/env bash

set -euo pipefail

# Script to completely clean up Omni installation
# Use this when you want to start fresh or remove all Omni data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Omni Cleanup Script"
echo "======================================"
echo ""
echo "⚠️  WARNING: This will DELETE all Omni data including:"
echo "   - etcd database"
echo "   - GPG encryption keys"
echo "   - Docker containers and volumes"
echo ""
echo "This action CANNOT be undone!"
echo ""

read -p "Are you sure you want to continue? Type 'yes' to proceed: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Cleanup aborted."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Load environment variables if they exist
if [[ -f "${SCRIPT_DIR}/omni.env" ]]; then
    source "${SCRIPT_DIR}/omni.env"
    echo "✓ Loaded environment variables from omni.env"
fi

# Stop and remove Docker containers
echo "Stopping Omni container..."
cd "${SCRIPT_DIR}"
if docker compose --env-file omni.env down 2>/dev/null; then
    echo "✓ Docker container stopped and removed"
else
    echo "⚠️  No running containers found or docker-compose.yml not found"
fi

# Remove etcd data
echo ""
echo "Removing etcd data..."
if [[ -n "${ETCD_VOLUME_PATH:-}" ]]; then
    # Handle absolute paths
    if [[ "${ETCD_VOLUME_PATH}" = /* ]]; then
        ETCD_PATH="${ETCD_VOLUME_PATH}"
    else
        ETCD_PATH="${SCRIPT_DIR}/${ETCD_VOLUME_PATH}"
    fi

    if [[ -d "${ETCD_PATH}" ]]; then
        # Check if we need sudo
        if [[ -w "${ETCD_PATH}" ]]; then
            rm -rf "${ETCD_PATH}"/*
            echo "✓ Removed etcd data from ${ETCD_PATH}"
        else
            sudo rm -rf "${ETCD_PATH}"/*
            echo "✓ Removed etcd data from ${ETCD_PATH} (required sudo)"
        fi
    else
        echo "⚠️  etcd directory not found: ${ETCD_PATH}"
    fi
else
    # Try default locations
    if [[ -d "${SCRIPT_DIR}/etcd" ]]; then
        rm -rf "${SCRIPT_DIR}/etcd"/*
        echo "✓ Removed etcd data from ${SCRIPT_DIR}/etcd"
    fi
    if [[ -d "/etc/etcd" ]]; then
        sudo rm -rf /etc/etcd/*
        echo "✓ Removed etcd data from /etc/etcd (required sudo)"
    fi
fi

# Remove GPG keys
echo ""
echo "Removing GPG keys..."

# Get admin email from env or prompt
ADMIN_EMAIL="${INITIAL_USER_EMAILS:-}"
if [[ -z "${ADMIN_EMAIL}" ]]; then
    echo "Enter the email address used for GPG key generation (or leave blank to skip):"
    read -p "Email: " ADMIN_EMAIL
fi

if [[ -n "${ADMIN_EMAIL}" ]]; then
    # Remove secret keys
    if gpg --list-secret-keys "${ADMIN_EMAIL}" &>/dev/null; then
        gpg --batch --yes --delete-secret-keys "${ADMIN_EMAIL}" 2>/dev/null || true
        echo "✓ Removed secret GPG key for ${ADMIN_EMAIL}"
    fi

    # Remove public keys
    if gpg --list-keys "${ADMIN_EMAIL}" &>/dev/null; then
        gpg --batch --yes --delete-keys "${ADMIN_EMAIL}" 2>/dev/null || true
        echo "✓ Removed public GPG key for ${ADMIN_EMAIL}"
    fi
else
    echo "⚠️  Skipping GPG key removal (no email provided)"
fi

# Remove exported GPG key file
if [[ -f "${SCRIPT_DIR}/omni.asc" ]]; then
    rm -f "${SCRIPT_DIR}/omni.asc"
    echo "✓ Removed omni.asc file"
fi

# Remove Cloudflare credentials if they exist
if [[ -f ~/omni/cloudflare.ini ]]; then
    rm -f ~/omni/cloudflare.ini
    echo "✓ Removed Cloudflare credentials"
fi

echo ""
echo "======================================"
echo "✓ Cleanup complete!"
echo "======================================"
echo ""
echo "The following were removed:"
echo "  - Docker containers and volumes"
echo "  - etcd database"
echo "  - GPG encryption keys"
echo "  - omni.asc file"
echo ""
echo "The following were preserved:"
echo "  - docker-compose.yml"
echo "  - omni.env (your configuration)"
echo "  - SSL certificates (in /etc/letsencrypt/)"
echo "  - setup scripts"
echo ""
echo "To start fresh, run:"
echo "  1. ./generate-gpg-key.sh"
echo "  2. docker compose --env-file omni.env up -d"
