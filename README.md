# Sidero Omni + Talos + Proxmox Starter Kit

A comprehensive starter kit for deploying self-hosted Sidero Omni with Talos Linux clusters on Proxmox VE infrastructure.

## Overview

This repository provides a complete Infrastructure as Code (IaC) solution for:

1. **Sidero Omni Self-Hosted** - Deploy and manage Omni in your own infrastructure
2. **Terraform for Proxmox** - Automated VM provisioning on Proxmox VE
3. **Talos Cluster Templates** - Pre-configured cluster templates for Sidero Omni

## Repository Structure

```
.
├── README.md
├── sidero-omni/              # Sidero Omni self-hosted deployment (Docker)
│   ├── README.md
│   ├── docker-compose.yml    # Docker Compose configuration
│   ├── .env.example          # Environment variables template
│   ├── setup-certificates.sh # SSL certificate setup script
│   ├── generate-gpg-key.sh   # GPG key generation script
│   └── config.yaml           # Omni configuration reference
├── terraform/                # Terraform IaC for Proxmox VMs
│   ├── README.md
│   ├── main.tf              # Main Terraform configuration
│   ├── variables.tf         # Variable definitions
│   ├── outputs.tf           # Output definitions
│   └── terraform.tfvars.example  # Example variables
└── bootstrap/               # Talos cluster bootstrap configuration
    ├── README.md
    ├── cluster-template.yaml    # Cluster template
    ├── machines.yaml            # Machine definitions
    ├── generate-cluster-template.sh  # Template generator script
    └── patches/                 # Machine configuration patches
        ├── control-plane.yaml
        ├── regular-worker.yaml
        └── gpu-worker.yaml
```

## Quick Start

### Prerequisites

- Proxmox VE 7.x or later
- Terraform 1.0+
- Docker and Docker Compose
- Ubuntu/Debian VM or mini PC (for Omni)
- Domain name with Cloudflare DNS
- Auth0 account for authentication

### Step 1: Deploy Sidero Omni

Navigate to the `sidero-omni/` directory and follow the Docker-based deployment instructions:

```bash
cd sidero-omni

# Set up SSL certificates
sudo ./setup-certificates.sh

# Generate GPG key for etcd encryption
./generate-gpg-key.sh

# Configure environment variables
cp .env.example .env
nano .env

# Deploy Omni
docker-compose up -d
```

See [sidero-omni/README.md](sidero-omni/README.md) for detailed instructions.

### Step 2: Provision VMs with Terraform

Configure and deploy VMs on Proxmox:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
terraform init
terraform plan
terraform apply
```

See [terraform/README.md](terraform/README.md) for detailed instructions.

### Step 3: Bootstrap Talos Cluster

Use the cluster templates to bootstrap your Talos cluster:

```bash
cd bootstrap
./generate-cluster-template.sh
# Follow the instructions to apply the template to Omni
```

See [bootstrap/README.md](bootstrap/README.md) for detailed instructions.

## Architecture

### Components

1. **Sidero Omni**: Central management platform for Talos clusters
   - Runs as Docker container on dedicated VM or mini PC
   - Provides a web UI and API for cluster management
   - Handles machine registration and lifecycle via SideroLink
   - Manages cluster templates and configurations
   - Uses embedded etcd for storage with GPG encryption

2. **Proxmox VE**: Virtualization platform
   - Hosts the Talos Linux VMs
   - Provides compute, storage, and networking resources

3. **Talos Linux**: Kubernetes-optimized OS
   - Runs on Proxmox VMs
   - Managed by Sidero Omni
   - Immutable and secure by default

### Workflow

1. **Infrastructure Provisioning**: Terraform creates VMs in Proxmox
2. **Machine Registration**: VMs boot with Talos and register with Omni
3. **Cluster Creation**: Use Omni to create clusters from registered machines
4. **Configuration Management**: Apply patches and templates via Omni

## Configuration

### Machine Types

This starter kit supports three types of nodes:

- **Control Plane**: 3 nodes (4 vCPU, 8GB RAM, 50GB disk)
- **Regular Workers**: 3 nodes (8 vCPU, 16GB RAM, 100GB disk)
- **GPU Workers**: 2 nodes (16 vCPU, 32GB RAM, 200GB disk)

All configurations can be customized in `terraform/variables.tf` and `bootstrap/machines.yaml`.

## Documentation

- [Sidero Omni Documentation](https://www.siderolabs.com/omni/docs/)
- [Talos Linux Documentation](https://www.talos.dev/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is provided as-is for use as a starter template.
