# Sidero Omni Self-Hosted

This directory contains configuration files and documentation for deploying Sidero Omni in a self-hosted Docker environment on a dedicated VM or mini PC.

## Overview

Sidero Omni is a SaaS service for managing Talos Linux clusters. This self-hosted deployment allows you to run Omni within your own infrastructure using Docker Compose.

## Prerequisites

- Ubuntu/Debian-based Linux VM or mini PC (recommended: 4+ CPU cores, 8GB+ RAM)
- Docker and Docker Compose installed
- Domain name with DNS configured to point to your server
- Cloudflare account (for automated SSL certificate management)
- Auth0 account (for authentication)
- Static IP address or DHCP reservation for your server

## Files

- `docker-compose.yml` - Docker Compose configuration for Omni
- `.env.example` - Example environment variables
- `config.yaml` - Omni configuration reference
- `setup-certificates.sh` - Automated SSL certificate setup script
- `generate-gpg-key.sh` - GPG key generation for etcd encryption

## Quick Start

### Step 1: Install Prerequisites

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose -y

# Log out and back in for group changes to take effect
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
# Copy example environment file
cp .env.example .env

# Edit with your values
nano .env
```

Required environment variables:
- `OMNI_VERSION` - Omni version (e.g., 1.2.1)
- `OMNI_ACCOUNT_UUID` - Generate with `uuidgen` command
- `OMNI_DOMAIN_NAME` - Your domain (e.g., omni.yourdomain.com)
- `OMNI_WG_IP` - WireGuard IP for SideroLink (e.g., 10.10.1.100)
- `OMNI_ADMIN_EMAIL` - Your admin email address
- `AUTH0_CLIENT_ID` - Auth0 application client ID
- `AUTH0_DOMAIN` - Auth0 domain (e.g., dev-xxxxxxxx.us.auth0.com)

**Setting up Auth0:**
1. Create an Auth0 account at https://auth0.com
2. Create a new Application (Single Page Application)
3. Configure Allowed Callback URLs: `https://omni.yourdomain.com/oidc/callback`
4. Configure Allowed Logout URLs: `https://omni.yourdomain.com`
5. Copy the Client ID and Domain

### Step 5: Create etcd Data Directory

```bash
mkdir -p etcd
```

**Note:** To start fresh, delete existing etcd data:
```bash
sudo rm -rf etcd/*
```

### Step 6: Deploy Omni

```bash
# Start Omni
docker-compose up -d

# View logs
docker-compose logs -f

# Check status
docker-compose ps
```

### Step 7: Access Omni

Open your browser and navigate to: `https://omni.yourdomain.com`

You should see the Omni login page. Sign in with your Auth0 credentials using the admin email you specified.

## Post-Deployment

After deployment:
1. Complete the initial setup in the Omni UI
2. Configure machine registration settings
3. Set up cluster templates from the `../bootstrap` directory
4. Start registering Talos machines created by the Terraform configuration in `../terraform`

## Maintenance

### Updating Omni

```bash
# Update the version in .env
nano .env  # Change OMNI_VERSION

# Pull new image and restart
docker-compose pull
docker-compose up -d
```

### Viewing Logs

```bash
docker-compose logs -f omni
```

### Backing Up etcd Data

```bash
# Stop Omni
docker-compose down

# Backup etcd directory and GPG key
tar -czf omni-backup-$(date +%Y%m%d).tar.gz etcd/ omni.asc

# Restart Omni
docker-compose up -d
```

### Certificate Renewal

Certbot automatically renews certificates. To manually renew:

```bash
sudo certbot renew
docker-compose restart
```

## Troubleshooting

### Cannot connect to Omni
- Check firewall rules: Allow ports 443, 8080, 8090, 8100, 50042
- Verify DNS is pointing to your server IP
- Check Docker logs: `docker-compose logs omni`

### Authentication issues
- Verify Auth0 configuration in .env
- Check callback URLs in Auth0 dashboard
- Ensure OMNI_ADMIN_EMAIL matches your Auth0 user email

### Certificate errors
- Verify Cloudflare credentials
- Check DNS propagation: `dig omni.yourdomain.com`
- Ensure port 443 is accessible from the internet for ACME challenge

### etcd errors
- Ensure GPG key (omni.asc) exists and is readable
- Check etcd directory permissions
- Try starting fresh: `sudo rm -rf etcd/*`

## Network Configuration

Omni requires the following ports to be accessible:
- **443** - HTTPS web interface
- **8080** - HTTP (redirects to HTTPS)
- **8090** - SideroLink API
- **8100** - Kubernetes proxy
- **50042** - WireGuard (SideroLink)

Configure your firewall:
```bash
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 8090/tcp
sudo ufw allow 8100/tcp
sudo ufw allow 50042/udp
```

## Integration with Terraform

Once Omni is deployed and running:
1. Use the cluster templates from `../bootstrap` directory
2. Configure clusters for VMs created by Terraform in `../terraform`
3. Machines will automatically register with Omni when they boot with Talos
