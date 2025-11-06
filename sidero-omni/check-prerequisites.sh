#!/usr/bin/env bash

set -euo pipefail

# Script to check if all prerequisites are installed for Omni deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Omni Prerequisites Checker"
echo "======================================"
echo ""

MISSING=0
WARNINGS=0

# Check Docker
echo "Checking Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | tr -d ',')
    echo "✓ Docker installed: ${DOCKER_VERSION}"

    # Check if Docker daemon is running
    if docker ps &> /dev/null; then
        echo "✓ Docker daemon is running"
    else
        echo "⚠️  Docker is installed but daemon is not running"
        echo "   Run: sudo systemctl start docker"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check if user is in docker group
    if groups | grep -q docker; then
        echo "✓ Current user is in docker group"
    else
        echo "⚠️  Current user is not in docker group"
        echo "   Run: sudo usermod -aG docker ${USER}"
        echo "   Then log out and back in"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "❌ Docker not installed"
    echo "   Run: ./install-docker.sh"
    MISSING=$((MISSING + 1))
fi

echo ""

# Check Docker Compose
echo "Checking Docker Compose..."
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || docker compose version)
    echo "✓ Docker Compose installed: ${COMPOSE_VERSION}"
else
    echo "❌ Docker Compose not installed"
    echo "   Run: ./install-docker.sh"
    MISSING=$((MISSING + 1))
fi

echo ""

# Check Certbot
echo "Checking Certbot..."
if command -v certbot &> /dev/null; then
    CERTBOT_VERSION=$(certbot --version | cut -d ' ' -f2)
    echo "✓ Certbot installed: ${CERTBOT_VERSION}"

    # Check for Cloudflare plugin
    if certbot plugins 2>/dev/null | grep -q cloudflare; then
        echo "✓ Certbot Cloudflare DNS plugin installed"
    else
        echo "⚠️  Certbot Cloudflare DNS plugin not found"
        echo "   Run: sudo snap install certbot-dns-cloudflare"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "❌ Certbot not installed"
    echo "   Run: ./setup-certificates.sh"
    MISSING=$((MISSING + 1))
fi

echo ""

# Check GPG
echo "Checking GPG..."
if command -v gpg &> /dev/null; then
    GPG_VERSION=$(gpg --version | head -n 1 | cut -d ' ' -f3)
    echo "✓ GPG installed: ${GPG_VERSION}"
else
    echo "❌ GPG not installed"
    echo "   Run: sudo apt-get install gnupg"
    MISSING=$((MISSING + 1))
fi

echo ""

# Check for required ports
echo "Checking port availability..."
PORTS=(443 8090 8100 50180)
for PORT in "${PORTS[@]}"; do
    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":${PORT} "; then
            echo "⚠️  Port ${PORT} is already in use"
            WARNINGS=$((WARNINGS + 1))
        else
            echo "✓ Port ${PORT} is available"
        fi
    else
        echo "⚠️  Cannot check port ${PORT} (ss command not available)"
    fi
done

echo ""

# Check for configuration files
echo "Checking configuration files..."
if [[ -f "${SCRIPT_DIR}/omni.env" ]]; then
    echo "✓ omni.env exists"

    # Check if critical variables are set
    source "${SCRIPT_DIR}/omni.env" 2>/dev/null || true

    if [[ -z "${OMNI_ACCOUNT_UUID:-}" ]]; then
        echo "⚠️  OMNI_ACCOUNT_UUID not set in omni.env"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [[ -z "${OMNI_DOMAIN_NAME:-}" && -z "${ADVERTISED_API_URL:-}" ]]; then
        echo "⚠️  Domain name not configured in omni.env"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [[ -z "${AUTH:-}" ]]; then
        echo "⚠️  Authentication not configured in omni.env"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "⚠️  omni.env not found"
    echo "   Run: cp .env.example omni.env"
    echo "   Then edit omni.env with your values"
    WARNINGS=$((WARNINGS + 1))
fi

if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    echo "✓ docker-compose.yml exists"
else
    echo "❌ docker-compose.yml not found"
    MISSING=$((MISSING + 1))
fi

echo ""

# Check for GPG key
echo "Checking GPG key..."
if [[ -f "${SCRIPT_DIR}/omni.asc" ]]; then
    echo "✓ omni.asc exists"

    # Verify it's a valid GPG key
    if gpg --show-keys "${SCRIPT_DIR}/omni.asc" &>/dev/null; then
        echo "✓ omni.asc is a valid GPG key"
    else
        echo "⚠️  omni.asc exists but may not be a valid GPG key"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "⚠️  omni.asc not found"
    echo "   Run: ./generate-gpg-key.sh"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# Check for SSL certificates
echo "Checking SSL certificates..."
if [[ -f "${SCRIPT_DIR}/omni.env" ]]; then
    source "${SCRIPT_DIR}/omni.env" 2>/dev/null || true
    CERT_PATH="${TLS_CERT:-/etc/letsencrypt/live/${OMNI_DOMAIN_NAME}/fullchain.pem}"
    KEY_PATH="${TLS_KEY:-/etc/letsencrypt/live/${OMNI_DOMAIN_NAME}/privkey.pem}"

    if [[ -f "${CERT_PATH}" ]]; then
        echo "✓ SSL certificate found: ${CERT_PATH}"
    else
        echo "⚠️  SSL certificate not found: ${CERT_PATH}"
        echo "   Run: sudo ./setup-certificates.sh"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [[ -f "${KEY_PATH}" ]]; then
        echo "✓ SSL key found: ${KEY_PATH}"
    else
        echo "⚠️  SSL key not found: ${KEY_PATH}"
        echo "   Run: sudo ./setup-certificates.sh"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

echo ""

# Check etcd directory
echo "Checking etcd directory..."
if [[ -f "${SCRIPT_DIR}/omni.env" ]]; then
    source "${SCRIPT_DIR}/omni.env" 2>/dev/null || true
    ETCD_DIR="${ETCD_VOLUME_PATH:-./etcd}"

    # Convert relative path to absolute
    if [[ "${ETCD_DIR}" != /* ]]; then
        ETCD_DIR="${SCRIPT_DIR}/${ETCD_DIR}"
    fi

    if [[ -d "${ETCD_DIR}" ]]; then
        echo "✓ etcd directory exists: ${ETCD_DIR}"

        # Check permissions
        if [[ -w "${ETCD_DIR}" ]]; then
            echo "✓ etcd directory is writable"
        else
            echo "⚠️  etcd directory is not writable"
            echo "   Run: sudo chown -R ${USER}:${USER} ${ETCD_DIR}"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "⚠️  etcd directory not found: ${ETCD_DIR}"
        echo "   It will be created automatically on first run"
    fi
fi

echo ""
echo "======================================"
echo "Summary"
echo "======================================"
echo ""

if [[ $MISSING -eq 0 && $WARNINGS -eq 0 ]]; then
    echo "✓ All prerequisites met!"
    echo ""
    echo "You're ready to deploy Omni:"
    echo "  docker compose --env-file omni.env up -d"
    exit 0
elif [[ $MISSING -eq 0 ]]; then
    echo "⚠️  ${WARNINGS} warning(s) found"
    echo ""
    echo "You can proceed with deployment, but please review the warnings above."
    echo "Some features may not work correctly until warnings are resolved."
    exit 0
else
    echo "❌ ${MISSING} critical prerequisite(s) missing"
    if [[ $WARNINGS -gt 0 ]]; then
        echo "⚠️  ${WARNINGS} warning(s) found"
    fi
    echo ""
    echo "Please install the missing prerequisites before deploying Omni."
    exit 1
fi
