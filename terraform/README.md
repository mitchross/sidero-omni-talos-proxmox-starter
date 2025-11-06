# Terraform Configuration for Proxmox VMs

This directory contains Terraform Infrastructure as Code (IaC) to provision virtual machines on Proxmox VE for use with Sidero Omni and Talos Linux.

## Prerequisites

- Proxmox VE 7.x or later
- Terraform 1.0 or later
- Proxmox API token with appropriate permissions

## Files

- `main.tf` - Main Terraform configuration
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `terraform.tfvars.example` - Example variables file

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Plan the deployment:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

## VM Configuration

This configuration will create:
- 3 control plane VMs (4 vCPU, 8GB RAM, 50GB disk)
- 3 regular worker VMs (8 vCPU, 16GB RAM, 100GB disk)
- 2 GPU worker VMs (16 vCPU, 32GB RAM, 200GB disk)

All VMs will be configured with the Talos Linux ISO and ready for bootstrapping via Sidero Omni.
