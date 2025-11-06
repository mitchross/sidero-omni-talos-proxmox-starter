# Sidero Omni Self-Hosted

This directory contains configuration files and documentation for deploying Sidero Omni in a self-hosted environment.

## Overview

Sidero Omni is a SaaS service for managing Talos Linux clusters. This self-hosted deployment allows you to run Omni within your own infrastructure.

## Prerequisites

- Kubernetes cluster (can be a Talos cluster)
- PostgreSQL database
- etcd cluster (optional, can use embedded)
- Valid SSL certificates
- DNS records configured

## Files

- `deployment.yaml` - Kubernetes deployment manifest for Omni
- `config.yaml` - Omni configuration file
- `values.yaml` - Helm values (if using Helm chart)

## Deployment

### Using kubectl

1. Configure your `config.yaml` with appropriate settings
2. Create a namespace for Omni:
   ```bash
   kubectl create namespace omni-system
   ```

3. Create secrets for sensitive data:
   ```bash
   kubectl create secret generic omni-secrets \
     --from-literal=postgres-password=your-password \
     --namespace omni-system
   ```

4. Apply the deployment:
   ```bash
   kubectl apply -f deployment.yaml -n omni-system
   ```

### Using Helm (if available)

```bash
helm install omni ./chart -n omni-system -f values.yaml
```

## Configuration

Edit `config.yaml` to customize:
- Database connection settings
- Authentication providers
- Storage backends
- Network settings
- TLS certificates

## Post-Deployment

After deployment:
1. Verify all pods are running: `kubectl get pods -n omni-system`
2. Access the Omni UI via the configured ingress
3. Complete the initial setup wizard
4. Configure machine registration and cluster templates

## Integration with Terraform

Once Omni is deployed, use the cluster templates from the `../bootstrap` directory to configure clusters for the VMs created by the Terraform configuration in `../terraform`.
