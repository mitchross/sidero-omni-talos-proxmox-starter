#!/usr/bin/env bash

set -euo pipefail

# Script to install Docker and Docker Compose on Ubuntu/Debian
# Based on official Docker installation instructions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Docker Installation Script"
echo "======================================"
echo ""

# Check if running on Ubuntu/Debian
if [[ ! -f /etc/debian_version ]]; then
    echo "❌ This script is designed for Ubuntu/Debian systems"
    exit 1
fi

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "✓ Docker is already installed: ${DOCKER_VERSION}"
    read -p "Do you want to reinstall Docker? (yes/no): " REINSTALL
    if [[ "$REINSTALL" != "yes" ]]; then
        echo "Skipping Docker installation."
        exit 0
    fi
fi

echo "Installing Docker..."
echo ""

# Update package index
echo "Updating package index..."
sudo apt-get update

# Install prerequisites
echo "Installing prerequisites..."
sudo apt-get install -y ca-certificates curl

# Add Docker's official GPG key
echo "Adding Docker GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again
sudo apt-get update

# Install Docker packages
echo "Installing Docker packages..."
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Create docker group if it doesn't exist
if ! getent group docker > /dev/null 2>&1; then
    echo "Creating docker group..."
    sudo groupadd docker
fi

# Add current user to docker group
echo "Adding user ${USER} to docker group..."
sudo usermod -aG docker ${USER}

echo ""
echo "======================================"
echo "✓ Docker installed successfully!"
echo "======================================"
echo ""
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo ""
echo "IMPORTANT: You need to log out and log back in for group changes to take effect."
echo "After logging back in, verify the installation with:"
echo "  docker run hello-world"
echo ""
echo "To start using Docker immediately without logging out, run:"
echo "  newgrp docker"
