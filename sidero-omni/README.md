# Sidero Omni Self-Hosted

This directory contains configuration files and documentation for deploying Sidero Omni in a self-hosted Docker environment on a dedicated VM or mini PC.

## Overview

Sidero Omni is a SaaS service for managing Talos Linux clusters. This self-hosted deployment allows you to run Omni within your own infrastructure using Docker Compose based on the official Siderolabs deployment format (v1.3.0-beta.2+).

## Prerequisites

- Ubuntu/Debian-based Linux VM or mini PC (recommended: 4+ CPU cores, 8GB+ RAM, 100GB+ storage)
- Docker and Docker Compose installed
- Domain name with DNS configured to point to your server
- Cloudflare account (for automated SSL certificate management)
- Auth0 or SAML provider account (for authentication)
- Static IP address or DHCP reservation for your server

## Files

- `docker-compose.yml` - Docker Compose configuration for Omni (official Siderolabs format)
- `.env.example` - Example environment variables template
- `config.yaml` - Omni configuration reference
- `install-docker.sh` - Automated Docker installation script
- `setup-certificates.sh` - Automated SSL certificate setup script
- `generate-gpg-key.sh` - GPG key generation for etcd encryption
- `check-prerequisites.sh` - Prerequisites checker script
- `cleanup-omni.sh` - Complete cleanup and reset script

## Quick Start

### Step 0: Check Prerequisites (Recommended)

Before starting, run the prerequisites checker:

```bash
./check-prerequisites.sh
```

This will verify all required software is installed and configured correctly.

### Step 1: Install Docker (if not already installed)

Use the provided installation script:

```bash
# Run the automated Docker installation script
./install-docker.sh

# After installation, log out and back in for group changes to take effect
# Or run: newgrp docker
```

**Manual Installation** (if you prefer):

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Step 2: Set Up SSL Certificates

Run the automated certificate setup script:

```bash
sudo ./setup-certificates.sh
```

This script will:
- Install Certbot and the Cloudflare DNS plugin
- Prompt for your domain name and Cloudflare API token
- Generate SSL certificates using Let's Encrypt
- Configure automatic renewal

**Manual Certificate Setup** (if you prefer):

```bash
# Install Certbot
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo snap set certbot trust-plugin-with-root=ok
sudo snap install certbot-dns-cloudflare

# Create Cloudflare credentials
mkdir -p ~/omni
cat > ~/omni/cloudflare.ini << EOF
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
EOF
chmod 600 ~/omni/cloudflare.ini

# Generate certificate
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials ~/omni/cloudflare.ini \
  -d omni.yourdomain.com
```

**Getting a Cloudflare API Token:**
1. Log into Cloudflare Dashboard
2. Go to Profile → API Tokens
3. Create Token → Edit zone DNS template
4. Select your domain zone
5. Copy the generated token

### Step 3: Generate GPG Key for etcd Encryption

Run the GPG key generation script:

```bash
./generate-gpg-key.sh
```

This script will:
- Generate a GPG key pair for etcd data encryption
- Add an encryption subkey
- Export the key to `omni.asc`

**Manual GPG Key Generation** (if you prefer):

```bash
# Generate master key (press Enter for no passphrase)
gpg --quick-generate-key "Omni (Used for etcd data encryption) admin@yourdomain.com" rsa4096 cert never

# List keys to get the key ID
gpg --list-secret-keys

# Add encryption subkey (replace KEY_ID with your actual key ID)
gpg --quick-add-key KEY_ID rsa4096 encr never

# View key fingerprint
gpg -K --with-subkey-fingerprint

# Export the key
gpg --export-secret-key --armor admin@yourdomain.com > omni.asc
chmod 600 omni.asc
```

### Step 4: Configure Environment Variables

```bash
# Copy example environment file to omni.env
cp .env.example omni.env

# Edit with your values
nano omni.env
```

**Required environment variables:**

- `OMNI_IMG_TAG` - Omni version (e.g., v1.3.0-beta.2 or v1.2.1)
- `OMNI_ACCOUNT_UUID` - Generate with `uuidgen` command
- `NAME` - Display name for your Omni instance
- `OMNI_DOMAIN_NAME` - Your domain (e.g., omni.example.com)
- `TLS_CERT` - Path to SSL certificate (fullchain.pem)
- `TLS_KEY` - Path to SSL private key (privkey.pem)
- `ETCD_VOLUME_PATH` - Path to etcd data directory (use `./etcd` for local)
- `ETCD_ENCRYPTION_KEY` - Path to GPG key file (`./omni.asc`)
- `BIND_ADDR` - API bind address (e.g., `0.0.0.0:443`)
- `MACHINE_API_BIND_ADDR` - Machine API bind address (e.g., `0.0.0.0:8090`)
- `K8S_PROXY_BIND_ADDR` - Kubernetes proxy bind address (e.g., `0.0.0.0:8100`)
- `ADVERTISED_API_URL` - Public API URL (e.g., `https://omni.example.com`)
- `SIDEROLINK_ADVERTISED_API_URL` - SideroLink API URL (e.g., `https://omni.example.com:8090/`)
- `ADVERTISED_K8S_PROXY_URL` - K8s proxy URL (e.g., `https://omni.example.com:8100/`)
- `SIDEROLINK_WIREGUARD_ADVERTISED_ADDR` - WireGuard address (e.g., `omni.example.com:50180`)
- `INITIAL_USER_EMAILS` - Admin email address(es)
- `AUTH` - Authentication configuration (Auth0 or SAML)

**Setting up Auth0:**

1. Create an Auth0 account at https://auth0.com
2. Create a new Application (Single Page Application)
3. Configure the following in Auth0:
   - **Allowed Callback URLs**: `https://omni.example.com/oidc/callback`
   - **Allowed Logout URLs**: `https://omni.example.com`
   - **Allowed Web Origins**: `https://omni.example.com`
4. Copy the Client ID and Domain from Auth0 dashboard
5. Update the `AUTH` variable in `omni.env`:
   ```bash
   AUTH='--auth-auth0-enabled=true \
         --auth-auth0-domain=dev-xxxxxxxx.us.auth0.com \
         --auth-auth0-client-id=your-auth0-client-id'
   ```

**Version Selection:**
- **Stable**: Use `v1.2.1` for production
- **Beta**: Use `v1.3.0-beta.2` or later for latest features (cluster import, kernel args support)
- See the [release discussion](https://github.com/siderolabs/omni/discussions/1807) for beta features

### Step 5: Create etcd Data Directory

```bash
# Create etcd directory locally (recommended)
mkdir -p etcd

# IMPORTANT: Avoid using /etc/etcd/ as it requires sudo for cleanup
# If you used /etc/etcd/ in ETCD_VOLUME_PATH, change it to ./etcd
```

**⚠️  Important Note about etcd Location:**

Using `/etc/etcd/` requires root permissions for cleanup and maintenance. It's recommended to use a local directory like `./etcd` instead. If you already have data in `/etc/etcd/`, see the cleanup section below.

### Step 6: Deploy Omni

```bash
# Start Omni using the omni.env file
docker compose --env-file omni.env up -d

# View logs
docker compose --env-file omni.env logs -f

# Check status
docker compose --env-file omni.env ps
```

**Note:** The new Docker Compose command is `docker compose` (with space), not `docker-compose` (with hyphen).

### Step 7: Verify Deployment

```bash
# Check if Omni is running
docker ps | grep omni

# Check container logs for errors
docker logs omni --tail 50

# Verify ports are listening
ss -tuln | grep -E ':(443|8090|8100|50180)'
```

### Step 8: Access Omni

1. Open your browser and navigate to: `https://omni.yourdomain.com`
2. You should see the Omni login page
3. Click "Sign in" and authenticate with your Auth0 credentials
4. Use the admin email address you specified in `INITIAL_USER_EMAILS`

## Post-Deployment

After deployment:
1. Complete the initial setup in the Omni UI
2. Configure machine registration settings
3. Deploy Booter for PXE boot (see `../deployment-methods/pxe-boot/README.md`)
4. Create VMs with Terraform in `../terraform`
5. Use automation scripts in `../scripts` to match machines and apply configurations

## Maintenance

### Updating Omni

```bash
# Update the version in omni.env
nano omni.env  # Change OMNI_IMG_TAG

# Pull new image and restart
docker compose --env-file omni.env pull
docker compose --env-file omni.env up -d

# Verify the update
docker logs omni --tail 20
```

### Viewing Logs

```bash
# View all logs
docker compose --env-file omni.env logs -f

# View only Omni container logs
docker logs omni -f

# View last 100 lines
docker logs omni --tail 100

# View logs with timestamps
docker logs omni -f --timestamps
```

### Backing Up etcd Data

```bash
# Stop Omni
docker compose --env-file omni.env down

# Backup etcd directory, GPG key, and configuration
tar -czf omni-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  etcd/ \
  omni.asc \
  omni.env \
  docker-compose.yml

# Restart Omni
docker compose --env-file omni.env up -d

echo "Backup saved: omni-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
```

**Automated Backup Script:**

```bash
#!/bin/bash
# Save as backup-omni.sh and run daily via cron
BACKUP_DIR="/home/$(whoami)/omni-backups"
mkdir -p "${BACKUP_DIR}"
cd /path/to/sidero-omni
docker compose --env-file omni.env down
tar -czf "${BACKUP_DIR}/omni-backup-$(date +%Y%m%d-%H%M%S).tar.gz" etcd/ omni.asc omni.env
docker compose --env-file omni.env up -d
# Keep only last 7 days of backups
find "${BACKUP_DIR}" -name "omni-backup-*.tar.gz" -mtime +7 -delete
```

### Restoring from Backup

```bash
# Stop Omni
docker compose --env-file omni.env down

# Extract backup
tar -xzf omni-backup-YYYYMMDD-HHMMSS.tar.gz

# Restart Omni
docker compose --env-file omni.env up -d
```

### Certificate Renewal

Certbot automatically renews certificates via systemd timer. To manually renew:

```bash
# Test renewal (dry run)
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Restart Omni to pick up new certificates
docker compose --env-file omni.env restart
```

### Cleaning Up and Starting Fresh

Use the cleanup script to completely reset Omni:

```bash
./cleanup-omni.sh
```

This will:
- Stop and remove Docker containers
- Delete etcd data
- Remove GPG keys
- Clean up exported key files

After cleanup, regenerate GPG keys and redeploy:
```bash
./generate-gpg-key.sh
docker compose --env-file omni.env up -d
```

## Troubleshooting

### Common Issues (Real-World Experience)

#### 1. etcd Permission Errors

**Problem:** Cannot access or clean up etcd data directory
```
Error: permission denied: /etc/etcd
```

**Solution:**
```bash
# If you used /etc/etcd/, move to local directory
docker compose --env-file omni.env down

# Create local etcd directory
mkdir -p ./etcd

# Move data (if preserving)
sudo mv /etc/etcd/* ./etcd/ 2>/dev/null || true
sudo chown -R $USER:$USER ./etcd

# Update omni.env
# Change: ETCD_VOLUME_PATH=/etc/etcd/
# To:     ETCD_VOLUME_PATH=./etcd

# Restart
docker compose --env-file omni.env up -d
```

#### 2. GPG Key Issues

**Problem:** Need to regenerate GPG keys or wrong email used

**Solution:**
```bash
# Stop Omni
docker compose --env-file omni.env down

# Remove old keys
gpg --delete-secret-keys YOUR_EMAIL 2>/dev/null || true
gpg --delete-keys YOUR_EMAIL 2>/dev/null || true
rm -f omni.asc

# Regenerate with correct email
./generate-gpg-key.sh

# Update omni.env with correct email in INITIAL_USER_EMAILS

# Restart with fresh etcd
rm -rf etcd/*
docker compose --env-file omni.env up -d
```

#### 3. Container Fails to Start

**Problem:** Omni container exits immediately

**Diagnosis:**
```bash
# Check container status
docker ps -a | grep omni

# View full logs
docker logs omni

# Check for common issues
docker inspect omni | grep -A 10 "State"
```

**Common causes:**
- Missing or invalid GPG key (omni.asc)
- Invalid SSL certificates
- Port conflicts
- Incorrect environment variables

**Solution:**
```bash
# Run prerequisites check
./check-prerequisites.sh

# Verify all paths in omni.env exist
ls -la $(grep TLS_CERT omni.env | cut -d'=' -f2)
ls -la omni.asc
ls -ld etcd/
```

#### 4. Cannot Connect to Omni Web Interface

**Problem:** Browser cannot reach `https://omni.example.com`

**Diagnosis:**
```bash
# Check if Omni is running
docker ps | grep omni

# Check if ports are listening
ss -tuln | grep -E ':(443|8090|8100)'

# Check firewall
sudo ufw status | grep -E '443|8090|8100|50180'

# Test DNS resolution
dig omni.example.com
nslookup omni.example.com
```

**Solution:**
```bash
# Allow required ports through firewall
sudo ufw allow 443/tcp
sudo ufw allow 8090/tcp
sudo ufw allow 8100/tcp
sudo ufw allow 50180/udp

# Verify DNS points to your server
# Update DNS A record to point to your server's public IP

# Check if Omni is listening
curl -k https://localhost:443
```

#### 5. Authentication Issues with Auth0

**Problem:** Cannot sign in, redirected to error page

**Checklist:**
1. Verify Auth0 configuration in omni.env:
   ```bash
   grep AUTH omni.env
   ```

2. Check Auth0 Application Settings:
   - **Allowed Callback URLs**: `https://omni.example.com/oidc/callback`
   - **Allowed Logout URLs**: `https://omni.example.com`
   - **Allowed Web Origins**: `https://omni.example.com`
   - **Application Type**: Single Page Application

3. Verify initial user email matches Auth0 user:
   ```bash
   grep INITIAL_USER_EMAILS omni.env
   ```

4. Check Omni logs for auth errors:
   ```bash
   docker logs omni | grep -i auth
   ```

#### 6. Certificate Errors

**Problem:** SSL certificate errors or cert-manager issues

**Diagnosis:**
```bash
# Verify certificates exist
ls -la /etc/letsencrypt/live/omni.example.com/

# Check certificate expiration
sudo openssl x509 -in /etc/letsencrypt/live/omni.example.com/fullchain.pem -noout -dates

# Test Certbot renewal
sudo certbot renew --dry-run
```

**Solution:**
```bash
# Regenerate certificate
sudo ./setup-certificates.sh

# Or manually renew
sudo certbot renew --force-renewal

# Restart Omni
docker compose --env-file omni.env restart
```

#### 7. WireGuard / SideroLink Connection Issues

**Problem:** Machines cannot connect to Omni via SideroLink

**Diagnosis:**
```bash
# Check if WireGuard port is listening
ss -ulpn | grep 50180

# Check firewall
sudo ufw status | grep 50180

# Verify advertised address is correct
grep SIDEROLINK_WIREGUARD omni.env
```

**Solution:**
```bash
# Ensure firewall allows UDP traffic
sudo ufw allow 50180/udp

# Verify domain resolves to correct IP
dig +short omni.example.com

# Check container has NET_ADMIN capability
docker inspect omni | grep -A 5 CapAdd

# Restart Omni
docker compose --env-file omni.env restart
```

#### 8. Docker Group Permission Issues

**Problem:** `permission denied` when running Docker commands

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Apply group changes
newgrp docker

# Or log out and back in

# Verify
docker ps
```

#### 9. Port Already in Use

**Problem:** `bind: address already in use`

**Diagnosis:**
```bash
# Find process using the port
sudo lsof -i :443
sudo ss -tulpn | grep :443
```

**Solution:**
```bash
# Stop conflicting service
sudo systemctl stop apache2  # or nginx, etc.

# Or change Omni ports in omni.env
# BIND_ADDR=0.0.0.0:8443  # Use different port
```

### Getting Help

If you encounter issues not covered here:

1. **Check logs**: `docker logs omni --tail 100`
2. **Run diagnostics**: `./check-prerequisites.sh`
3. **Verify configuration**: Review all paths and URLs in `omni.env`
4. **Community support**: [Siderolabs Slack](https://slack.dev.talos.dev/)
5. **GitHub issues**: [Omni Issues](https://github.com/siderolabs/omni/issues)

## Network Configuration

Omni requires the following ports to be accessible:
- **443** (TCP) - HTTPS web interface and API
- **8090** (TCP) - SideroLink API (machine communication)
- **8100** (TCP) - Kubernetes proxy
- **50180** (UDP) - WireGuard (SideroLink VPN)
- **8091** (TCP) - Event sink port (internal, not exposed)

**Note:** Port 50180 is the recommended WireGuard port. The old default was 50042.

Configure your firewall:
```bash
sudo ufw allow 443/tcp comment 'Omni HTTPS'
sudo ufw allow 8090/tcp comment 'Omni SideroLink API'
sudo ufw allow 8100/tcp comment 'Omni K8s Proxy'
sudo ufw allow 50180/udp comment 'Omni WireGuard'

# Enable firewall if not already enabled
sudo ufw enable

# Check status
sudo ufw status numbered
```

**Router/NAT Configuration:**

If Omni is behind a router, configure port forwarding:
- External Port 443 → Internal IP:443
- External Port 8090 → Internal IP:8090
- External Port 8100 → Internal IP:8100
- External Port 50180 (UDP) → Internal IP:50180

**DNS Configuration:**

Create an A record pointing to your server's public IP:
```
omni.example.com  A  YOUR.PUBLIC.IP.ADDRESS
```

Verify DNS propagation:
```bash
dig omni.example.com +short
nslookup omni.example.com
```

## Integration with Terraform

Once Omni is deployed and running:
1. Deploy Booter for PXE network boot (see `../deployment-methods/pxe-boot/`)
2. Create VMs with Terraform in `../terraform` directory
3. Machines will automatically PXE boot and register with Omni
4. Use automation scripts in `../scripts/` to match UUIDs to hostnames/IPs
5. Create clusters in Omni UI with properly labeled machines
6. See [Cluster Templates Documentation](https://docs.siderolabs.com/omni/reference/cluster-templates)

## Quick Reference

### Essential Commands

```bash
# Start Omni
docker compose --env-file omni.env up -d

# Stop Omni
docker compose --env-file omni.env down

# View logs
docker logs omni -f

# Restart Omni
docker compose --env-file omni.env restart

# Check status
docker ps | grep omni

# Run prerequisites check
./check-prerequisites.sh

# Cleanup everything
./cleanup-omni.sh
```

### File Locations

- Configuration: `./omni.env`
- Docker Compose: `./docker-compose.yml`
- GPG Key: `./omni.asc`
- etcd Data: `./etcd/` (or as configured in ETCD_VOLUME_PATH)
- SSL Certificates: `/etc/letsencrypt/live/YOUR_DOMAIN/`
- Cloudflare Credentials: `~/omni/cloudflare.ini`

### Important URLs

- Omni Web UI: `https://omni.example.com`
- SideroLink API: `https://omni.example.com:8090`
- Kubernetes Proxy: `https://omni.example.com:8100`

## Resources

- **Official Documentation**: https://docs.siderolabs.com/omni/
- **Deployment Guide**: https://docs.siderolabs.com/omni/infrastructure-and-extensions/self-hosted/deploy-omni-on-prem
- **Cluster Templates**: https://docs.siderolabs.com/omni/reference/cluster-templates
- **GitHub Repository**: https://github.com/siderolabs/omni
- **Release Notes**: https://github.com/siderolabs/omni/releases
- **Beta Discussion**: https://github.com/siderolabs/omni/discussions/1807
- **Talos Documentation**: https://www.talos.dev/
- **Community Slack**: https://slack.dev.talos.dev/

## Version History

- **v1.3.0-beta.2** (Latest Beta)
  - Cluster import (experimental)
  - Kernel arguments support
  - Multi-select for machines
  - Enhanced UI improvements

- **v1.2.1** (Stable)
  - Production-ready release
  - Stable feature set

## Contributing

Found an issue or have an improvement? Please open an issue or submit a pull request in the parent repository.

## License

This starter kit is provided as-is for use as a reference template. See the official Sidero Omni documentation for product licensing.
