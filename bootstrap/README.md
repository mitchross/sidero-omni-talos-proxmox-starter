# Bootstrap Configuration

This directory contains the configuration files needed to bootstrap a Talos cluster using Sidero Omni.

## Files

- `cluster-template.yaml` - Main cluster template configuration
- `machines.yaml` - Machine definitions and configurations
- `generate-cluster-template.sh` - Script to generate cluster templates
- `patches/` - Directory containing patch files for different node types

## Usage

1. Configure your machine definitions in `machines.yaml`
2. Apply any necessary patches from the `patches/` directory
3. Run `generate-cluster-template.sh` to generate the cluster template
4. Apply the generated template to your Sidero Omni instance
