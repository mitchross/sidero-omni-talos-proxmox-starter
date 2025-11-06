#!/usr/bin/env bash

set -euo pipefail

# Script to set up SSL certificates using Certbot with Cloudflare DNS
# This script automates the certificate generation process for Omni

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Omni SSL Certificate Setup"
echo "======================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Install Certbot if not already installed
if ! command -v certbot &> /dev/null; then
    echo "Installing Certbot..."
    snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot || true
    snap set certbot trust-plugin-with-root=ok
    snap install certbot-dns-cloudflare
    echo "✓ Certbot installed"
else
    echo "✓ Certbot already installed"
fi

echo ""
echo "======================================"
echo "Cloudflare API Configuration"
echo "======================================"
echo ""

# Prompt for domain name
read -p "Enter your domain name (e.g., omni.example.com): " DOMAIN_NAME

# Create omni directory if it doesn't exist
mkdir -p ~/omni

# Prompt for Cloudflare API token
echo ""
echo "You need a Cloudflare API Token with DNS edit permissions."
echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
echo ""
read -p "Enter your Cloudflare API Token: " CF_API_TOKEN

# Create Cloudflare credentials file
cat > ~/omni/cloudflare.ini << EOF
# Cloudflare API token
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF

chmod 600 ~/omni/cloudflare.ini
echo "✓ Cloudflare credentials saved to ~/omni/cloudflare.ini"

echo ""
echo "======================================"
echo "Generating SSL Certificate"
echo "======================================"
echo ""

# Generate certificate
certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials ~/omni/cloudflare.ini \
    -d "${DOMAIN_NAME}" \
    --non-interactive \
    --agree-tos \
    --email "admin@${DOMAIN_NAME}"

if [[ $? -eq 0 ]]; then
    echo ""
    echo "======================================"
    echo "✓ Certificate generated successfully!"
    echo "======================================"
    echo ""
    echo "Certificate location: /etc/letsencrypt/live/${DOMAIN_NAME}/"
    echo "  - fullchain.pem"
    echo "  - privkey.pem"
    echo ""
    echo "These certificates will be automatically mounted in the Docker container."
else
    echo ""
    echo "❌ Certificate generation failed!"
    exit 1
fi

echo ""
echo "Note: Certificates will auto-renew via Certbot's systemd timer."
echo "To manually renew: sudo certbot renew"
