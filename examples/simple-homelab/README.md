# Simple Homelab Cluster

A minimal 3-node Kubernetes cluster perfect for homelab environments and learning.

## Overview

This example provides a basic, cost-effective cluster configuration:
- **1 control plane node** - Manages the cluster
- **2 worker nodes** - Run your workloads
- **Default CNI** - Flannel (simple and reliable)
- **Minimal resources** - Suitable for modest hardware

## Resource Requirements

### Per Node

**Control Plane**:
- CPU: 4 cores
- RAM: 8GB
- Disk: 50GB
- Role: Kubernetes control plane + etcd

**Worker Nodes** (x2):
- CPU: 4 cores
- RAM: 8GB
- Disk: 100GB
- Role: Application workloads

**Total Resources**:
- CPU: 12 cores
- RAM: 24GB
- Disk: 250GB

## Machine Classes

### Control Plane Machine Class

Create in Omni UI → Settings → Machine Classes:

```yaml
name: homelab-control-plane
provider: your-proxmox-provider
cpu: 4
memory: 8192  # 8GB in MB
disk: 50      # 50GB
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

### Worker Machine Class

```yaml
name: homelab-worker
provider: your-proxmox-provider
cpu: 4
memory: 8192  # 8GB in MB
disk: 100     # 100GB
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

## Deployment Steps

### 1. Create Machine Classes

1. Log into Omni UI
2. Navigate to **Settings** → **Machine Classes**
3. Create `homelab-control-plane` with specs above
4. Create `homelab-worker` with specs above

### 2. Create Cluster

1. Click **Create Cluster**
2. Cluster configuration:
   - **Name**: `homelab`
   - **Kubernetes Version**: Latest stable (e.g., v1.30.0)
   - **Control Plane**:
     - Machine Class: `homelab-control-plane`
     - Replicas: `1`
   - **Workers**:
     - Machine Class: `homelab-worker`
     - Replicas: `2`
3. Click **Create**

### 3. Wait for Provisioning

The Proxmox provider will:
1. Create 3 VMs in Proxmox (1-2 minutes)
2. Download and boot Talos Linux (2-3 minutes)
3. Bootstrap Kubernetes (3-5 minutes)

**Total time**: ~10 minutes

Monitor progress:
- Omni UI shows cluster status
- Proxmox UI shows VMs being created
- Check provider logs: `docker compose logs -f` (in proxmox-provider/)

### 4. Download kubeconfig

Once cluster is ready:

1. In Omni UI, click your cluster name
2. Click **Download Kubeconfig**
3. Save to `~/.kube/config` or custom location

```bash
# Save to default location
mkdir -p ~/.kube
mv ~/Downloads/homelab-kubeconfig.yaml ~/.kube/config

# Or use custom location
export KUBECONFIG=~/homelab-kubeconfig.yaml
```

### 5. Verify Cluster

```bash
# Check nodes
kubectl get nodes

# Expected output:
# NAME                STATUS   ROLES           AGE   VERSION
# homelab-cp-xxx      Ready    control-plane   5m    v1.30.0
# homelab-worker-yyy  Ready    <none>          5m    v1.30.0
# homelab-worker-zzz  Ready    <none>          5m    v1.30.0

# Check system pods
kubectl get pods -n kube-system

# Check cluster info
kubectl cluster-info
```

## Default CNI: Flannel

Talos includes Flannel CNI by default. No additional configuration needed.

**Flannel Features**:
- Simple VXLAN overlay network
- Works out of the box
- Low overhead
- Good for basic use cases

**Want Cilium instead?** See the [production-ha example](../production-ha/) or [Cilium CNI Guide](../../docs/CILIUM_CNI.md).

## What Can I Run?

This cluster is suitable for:
- **Learning Kubernetes** - Perfect for tutorials and experimentation
- **Home automation** - Home Assistant, Node-RED, etc.
- **Media services** - Plex, Jellyfin, Sonarr, Radarr
- **Development** - Test applications before production
- **Self-hosted apps** - Nextcloud, Bitwarden, GitLab, etc.

## Example Workload: Nginx

Deploy a simple nginx web server:

```bash
# Create deployment
kubectl create deployment nginx --image=nginx:latest --replicas=2

# Expose as service
kubectl expose deployment nginx --port=80 --type=NodePort

# Get service details
kubectl get svc nginx

# Access nginx (replace NODE_IP and NODE_PORT)
curl http://<NODE_IP>:<NODE_PORT>
```

## Scaling

### Add More Workers

1. In Omni UI, click your cluster
2. Go to **Machine Classes**
3. Increase worker replica count (e.g., 2 → 4)
4. Save changes

New worker nodes will be automatically provisioned.

### Scale Control Plane (HA)

For high availability, scale to 3 control plane nodes:

1. Go to control plane machine class
2. Increase replicas: `1` → `3`
3. Save

**Note**: Always use odd numbers (1, 3, 5) for control plane nodes (etcd requirement).

## Upgrading Kubernetes

To upgrade Kubernetes version:

1. In Omni UI, click cluster name
2. Go to **Settings**
3. Select new Kubernetes version
4. Click **Upgrade**

Talos will perform rolling upgrade with zero downtime.

## Storage Options

### Option 1: Local Path Provisioner

Simple local storage:

```bash
# Install local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Set as default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Option 2: Longhorn

Distributed block storage:

```bash
# Install Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# Access UI (port-forward)
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

Open http://localhost:8080

### Option 3: NFS

Use existing NFS server:

```bash
# Install NFS CSI driver
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system
```

Create StorageClass pointing to your NFS server.

## Monitoring (Optional)

### Prometheus + Grafana

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Access Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

# Default credentials: admin / prom-operator
```

Open http://localhost:3000

## Ingress (Optional)

### Traefik Ingress Controller

```bash
# Install Traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort
```

### Nginx Ingress Controller

```bash
# Install nginx-ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml
```

## Backup and Disaster Recovery

### Etcd Backup (via Omni)

Omni automatically backs up etcd. To create manual backup:

1. Omni UI → Cluster → Backups
2. Click **Create Backup**
3. Download backup file

### Restore from Backup

1. Omni UI → Create Cluster
2. Select **Restore from Backup**
3. Upload backup file
4. Follow wizard

## Cost Analysis

**Hardware Requirements** (approximate):
- Single Proxmox host with 12+ cores, 32GB+ RAM
- Or distributed across multiple Proxmox nodes

**Power Consumption** (example with Intel i5):
- ~50-100W idle
- ~$5-15/month electricity (at $0.12/kWh)

**Comparison to Cloud**:
- AWS EKS equivalent: ~$200-300/month
- **Savings**: $2,400-3,600/year

## Troubleshooting

### Nodes Not Appearing in Omni

1. Check Proxmox provider logs:
   ```bash
   docker compose logs -f omni-infra-provider-proxmox
   ```
2. Verify VMs created in Proxmox
3. Check VM console for boot errors
4. Verify network connectivity (VMs can reach Omni)

### Cluster Stuck in Bootstrap

1. Check node status in Omni UI
2. Verify all nodes are "Ready"
3. Check control plane logs:
   ```bash
   talosctl -n <control-plane-ip> logs controller-runtime
   ```

### Can't Access Services

1. Verify pod is running: `kubectl get pods`
2. Check service exists: `kubectl get svc`
3. For NodePort, use any node IP + NodePort
4. Check firewall rules on Proxmox host

## Next Steps

Once your homelab cluster is running:

1. **Add persistent storage** - Install local-path-provisioner or Longhorn
2. **Set up ingress** - Traefik or nginx-ingress for HTTP routing
3. **Deploy applications** - Start with simple apps like nginx or redis
4. **Add monitoring** - Install Prometheus and Grafana
5. **Explore GitOps** - Try ArgoCD or Flux
6. **Scale up** - Add more worker nodes as needed

## Upgrading to GPU Support

Want to add GPU nodes for AI/ML workloads? See:
- [GPU ML Cluster Example](../gpu-ml-cluster/)
- [Talos GPU Configuration Guide](../../talos-configs/README.md)

## Upgrading to Production

Ready for production? Check out:
- [Production HA Example](../production-ha/) - 5-node HA cluster with Cilium
- [Production Best Practices](../../docs/ARCHITECTURE.md)

## Resources

- [Talos Documentation](https://docs.siderolabs.com/talos/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Omni Documentation](https://docs.siderolabs.com/omni/)
- [Proxmox Documentation](https://pve.proxmox.com/pve-docs/)
