#!/bin/bash
set -e

# Download Talos GPU ISO with NVIDIA Extensions
# Schematic ID: 6db1f20beb0d74f938132978f24a9e6096928c248969a61f56c43bbe530f274a
# Talos Version: v1.11.5

SCHEMATIC_ID="6db1f20beb0d74f938132978f24a9e6096928c248969a61f56c43bbe530f274a"
TALOS_VERSION="v1.11.5"
ISO_NAME="talos-1.11.5-gpu.iso"
ISO_URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-amd64.iso"

# Optional: Proxmox server IP (set via environment or edit here)
PROXMOX_IP="${PROXMOX_IP:-192.168.10.160}"

echo "============================================"
echo "Talos GPU ISO Download Script"
echo "============================================"
echo ""
echo "Schematic ID: ${SCHEMATIC_ID}"
echo "Talos Version: ${TALOS_VERSION}"
echo "ISO URL: ${ISO_URL}"
echo ""

# Download ISO
echo "📥 Downloading GPU ISO (this may take a few minutes)..."
if command -v wget &> /dev/null; then
    wget -O "${ISO_NAME}" "${ISO_URL}"
elif command -v curl &> /dev/null; then
    curl -L -o "${ISO_NAME}" "${ISO_URL}"
else
    echo "❌ Error: Neither wget nor curl found. Please install one of them."
    exit 1
fi

echo "✅ Download complete: ${ISO_NAME}"
echo ""

# Get file size
ISO_SIZE=$(du -h "${ISO_NAME}" | cut -f1)
echo "📦 ISO Size: ${ISO_SIZE}"
echo ""

# Ask about upload to Proxmox
echo "Would you like to upload to Proxmox? (y/n)"
read -r UPLOAD

if [[ "$UPLOAD" =~ ^[Yy]$ ]]; then
    echo ""
    echo "📤 Uploading to Proxmox at ${PROXMOX_IP}..."
    echo ""
    
    if scp "${ISO_NAME}" "root@${PROXMOX_IP}:/var/lib/vz/template/iso/${ISO_NAME}"; then
        echo ""
        echo "✅ Upload successful!"
        echo ""
        echo "Next steps:"
        echo "1. Verify in Proxmox UI: Datacenter → local → ISO Images"
        echo "2. Update terraform.tfvars if needed:"
        echo "   talos_gpu_iso = \"local:iso/${ISO_NAME}\""
        echo "3. Run: cd terraform && terraform apply"
    else
        echo ""
        echo "❌ Upload failed. You can manually upload via Proxmox UI or try:"
        echo "   scp ${ISO_NAME} root@${PROXMOX_IP}:/var/lib/vz/template/iso/"
    fi
else
    echo ""
    echo "ℹ️  To upload manually later:"
    echo "   scp ${ISO_NAME} root@${PROXMOX_IP}:/var/lib/vz/template/iso/"
    echo ""
    echo "   Or use Proxmox UI: Datacenter → local → ISO Images → Upload"
fi

echo ""
echo "============================================"
echo "✨ ISO ready for GPU worker deployment!"
echo "============================================"
