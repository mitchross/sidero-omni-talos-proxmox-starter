# Production HA Cluster with Cilium CNI

A production-ready, highly available Kubernetes cluster with Cilium CNI and Gateway API support.

## Overview

This example provides an enterprise-grade cluster:
- **3 control plane nodes** - High availability etcd + control plane
- **3+ worker nodes** - Distributed workload execution
- **Cilium CNI** - Advanced networking with eBPF
- **Gateway API** - Modern ingress with ALPN and AppProtocol
- **No kube-proxy** - Cilium replacement mode for better performance
- **Production ready** - Monitoring, backup, and disaster recovery

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Production Cluster                        │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Control Plane (HA - 3 nodes)               │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │  CP-1    │  │  CP-2    │  │  CP-3    │          │  │
│  │  │ + etcd   │  │ + etcd   │  │ + etcd   │          │  │
│  │  └──────────┘  └──────────┘  └──────────┘          │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────┴──────────────────────────────┐ │
│  │              Worker Nodes (3+)                         │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │ │
│  │  │ Worker-1 │  │ Worker-2 │  │ Worker-3 │   [...]    │ │
│  │  │ + Cilium │  │ + Cilium │  │ + Cilium │            │ │
│  │  └──────────┘  └──────────┘  └──────────┘            │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                              │
│  Cilium Features:                                           │
│  • eBPF datapath (no kube-proxy)                           │
│  • Gateway API with ALPN                                    │
│  • Network policies                                         │
│  • Load balancing                                           │
│  • Hubble observability                                     │
└─────────────────────────────────────────────────────────────┘
```

## Resource Requirements

### Per Node

**Control Plane Nodes** (x3):
- CPU: 4 cores
- RAM: 8GB
- Disk: 50GB
- Role: Kubernetes control plane + etcd

**Worker Nodes** (x3 minimum):
- CPU: 8 cores
- RAM: 16GB
- Disk: 200GB
- Role: Application workloads

**Total Resources** (minimum):
- CPU: 36 cores (12 CP + 24 workers)
- RAM: 72GB (24GB CP + 48GB workers)
- Disk: 750GB (150GB CP + 600GB workers)

**Scaling**: Add more workers as needed (4, 5, 6+ nodes)

## Why Cilium?

Cilium provides enterprise-grade networking with:

### Performance
- **eBPF datapath** - Kernel-level networking, no userspace overhead
- **No kube-proxy** - Direct eBPF load balancing
- **10-40% better throughput** vs traditional CNIs
- **Lower latency** - Especially for east-west traffic

### Features
- **Gateway API** - Modern HTTP/HTTPS routing with ALPN, AppProtocol
- **Network Policies** - Advanced L3-L7 security policies
- **Service Mesh** - Without sidecars (eBPF-based)
- **Multi-cluster** - Connect multiple K8s clusters
- **Hubble** - Deep network observability with UI

### Production Ready
- **Used by major companies** - Google, AWS, DigitalOcean, Adobe
- **CNCF Graduated** - Mature and well-maintained
- **Active development** - Regular updates and improvements

## Machine Classes

### Control Plane Machine Class

Create in Omni UI → Settings → Machine Classes:

```yaml
name: prod-control-plane
provider: your-proxmox-provider
cpu: 4
memory: 8192
disk: 50
storage: |
  storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

### Worker Machine Class

```yaml
name: prod-worker
provider: your-proxmox-provider
cpu: 8
memory: 16384  # 16GB
disk: 200
storage: |
  storage.filter(s, s.type == "zfspool" && s.enabled && s.active)[0].storage
```

## Deployment Steps

### 1. Create Machine Classes

1. Log into Omni UI
2. Navigate to **Settings** → **Machine Classes**
3. Create `prod-control-plane` with specs above
4. Create `prod-worker` with specs above

### 2. Disable kube-proxy (Critical for Cilium)

When using Cilium in kube-proxy replacement mode, you MUST disable kube-proxy.

In Omni UI, when creating cluster, add this **Cluster Config Patch**:

```yaml
cluster:
  proxy:
    disabled: true  # CRITICAL: Disable kube-proxy for Cilium
```

**Important**: This patch must be applied **before cluster creation**. If you forget, you'll need to recreate the cluster.

### 3. Create Cluster

1. Click **Create Cluster**
2. Cluster configuration:
   - **Name**: `production`
   - **Kubernetes Version**: v1.30.0 (or latest stable)
   - **Talos Version**: v1.11.0
   - **Control Plane**:
     - Machine Class: `prod-control-plane`
     - Replicas: `3` (for HA)
   - **Workers**:
     - Machine Class: `prod-worker`
     - Replicas: `3` (minimum, can add more)
3. Under **Config Patches**, add the proxy disable patch above
4. Click **Create**

### 4. Wait for Bootstrap

Initial cluster bootstrap takes ~10-15 minutes:
- VMs provisioned (2-3 min)
- Talos boots (2-3 min)
- etcd cluster forms (3-5 min)
- Control plane ready (3-5 min)

**Do NOT install Cilium yet** - cluster will be ready without CNI.

### 5. Download kubeconfig

Once cluster shows "Ready":

```bash
# Download from Omni UI
# Save to ~/.kube/config or custom location
mkdir -p ~/.kube
mv ~/Downloads/production-kubeconfig.yaml ~/.kube/config
```

### 6. Install Gateway API CRDs

Cilium Gateway API requires these CRDs:

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

Verify:
```bash
kubectl get crd | grep gateway
# Should show: gatewayclasses, gateways, httproutes, etc.
```

### 7. Install Cilium CLI

Install cilium CLI tool:

```bash
# Linux
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# macOS
brew install cilium-cli

# Verify installation
cilium version --client
```

### 8. Install Cilium with Gateway API

**Critical Configuration** - Use these exact parameters:

```bash
cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true
```

**Why these settings?**
- `ipam.mode=kubernetes` - Use Kubernetes IPAM
- `kubeProxyReplacement=true` - Replace kube-proxy with eBPF
- `securityContext.capabilities.*` - Required capabilities for Talos
- `cgroup.autoMount.enabled=false` - Talos manages cgroups
- `cgroup.hostRoot=/sys/fs/cgroup` - Talos cgroup path
- `k8sServiceHost/Port` - Talos API server endpoint (localhost:7445)
- `gatewayAPI.*` - Enable Gateway API with ALPN and AppProtocol

### 9. Verify Cilium Installation

```bash
# Check Cilium status
cilium status --wait

# Expected output:
#     /¯¯\
#  /¯¯\__/¯¯\    Cilium:             OK
#  \__/¯¯\__/    Operator:           OK
#  /¯¯\__/¯¯\    Envoy DaemonSet:    OK
#  \__/¯¯\__/    Hubble Relay:       disabled
#     \__/       ClusterMesh:        disabled
#
# DaemonSet              cilium             Desired: 6, Ready: 6/6, Available: 6/6
# Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
# Containers:            cilium             Running: 6
#                        cilium-operator    Running: 2
# Cluster Pods:          3/3 managed by Cilium

# Check nodes are ready
kubectl get nodes
# All nodes should show "Ready"

# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Run connectivity test (optional but recommended)
cilium connectivity test
```

### 10. Enable Hubble (Optional but Recommended)

Hubble provides network observability:

```bash
# Enable Hubble
cilium hubble enable --ui

# Verify Hubble
kubectl get pods -n kube-system -l k8s-app=hubble

# Port-forward Hubble UI
cilium hubble ui

# Opens browser to http://localhost:12000
```

## Gateway API Configuration

### Create Gateway Class

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
EOF
```

### Create Gateway

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: production-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    protocol: HTTP
    port: 80
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: tls-cert
EOF
```

### Example HTTPRoute

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-route
  namespace: default
spec:
  parentRefs:
  - name: production-gateway
  hostnames:
  - "example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: example-service
      port: 80
EOF
```

## Network Policies

Cilium supports advanced L3-L7 network policies:

### Example: Deny All Ingress by Default

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: default
spec:
  endpointSelector: {}
  ingress:
  - {}
```

### Example: Allow Specific Service

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-api
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
```

### Example: L7 HTTP Policy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-http-policy
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/.*"
```

## Load Balancing

Cilium provides advanced load balancing:

### External IPs (MetalLB alternative)

```bash
# Install Cilium LoadBalancer IP pool
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: production-pool
spec:
  cidrs:
  - cidr: 192.168.1.200/29  # Your IP range
EOF
```

### Example LoadBalancer Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: example-lb
spec:
  type: LoadBalancer
  selector:
    app: example
  ports:
  - port: 80
    targetPort: 8080
```

Cilium will automatically assign an IP from the pool.

## High Availability Verification

### Check etcd Health

```bash
# Check all control plane nodes are running
kubectl get nodes -l node-role.kubernetes.io/control-plane

# All 3 should show "Ready"
```

### Test Control Plane Failover

```bash
# Drain one control plane node
kubectl drain prod-cp-1 --ignore-daemonsets --delete-emptydir-data

# Cluster should remain healthy
kubectl get nodes

# Uncordon when done
kubectl uncordon prod-cp-1
```

### Test Worker Failover

```bash
# Create test deployment
kubectl create deployment nginx --image=nginx --replicas=3

# Drain a worker node
kubectl drain prod-worker-1 --ignore-daemonsets --delete-emptydir-data

# Pods should reschedule to other workers
kubectl get pods -o wide
```

## Monitoring Stack

### Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin
```

### Add Cilium Metrics

```bash
# Enable Prometheus metrics in Cilium
cilium hubble enable --prometheus

# Cilium metrics will be auto-discovered by Prometheus
```

### Import Cilium Dashboards

1. Access Grafana: `kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80`
2. Login: admin / admin
3. Import dashboards:
   - Cilium Metrics: Dashboard ID 16611
   - Hubble Metrics: Dashboard ID 16612

## Storage (Production)

### Longhorn for HA Storage

```bash
# Install Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# Wait for pods
kubectl get pods -n longhorn-system --watch

# Set as default storage class
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Access UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

**Longhorn Features**:
- Replicated block storage (3x by default)
- Snapshots and backups
- Disaster recovery
- Volume expansion
- Cross-node redundancy

### Configure Longhorn for HA

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-ha
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
```

## Backup and Disaster Recovery

### Velero for Cluster Backups

```bash
# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Install Velero (with MinIO backend)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=true \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.minio:9000 \
  --snapshot-location-config region=minio
```

### Create Scheduled Backups

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  template:
    includedNamespaces:
    - '*'
    excludedNamespaces:
    - kube-system
    - kube-public
    ttl: 720h  # 30 days
```

## Security Hardening

### Pod Security Standards

```bash
# Enforce baseline PSS for all namespaces
kubectl label namespace default pod-security.kubernetes.io/enforce=baseline

# Enforce restricted for production
kubectl label namespace production pod-security.kubernetes.io/enforce=restricted
```

### Network Policy: Default Deny

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Cilium Network Policy: Default Deny

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-deny
spec:
  endpointSelector: {}
  ingress:
  - fromEntities:
    - cluster
    - health
  egress:
  - toEntities:
    - cluster
    - kube-apiserver
    - health
```

## Autoscaling

### Horizontal Pod Autoscaler

```bash
# Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HPA
kubectl autoscale deployment example --cpu-percent=70 --min=3 --max=10
```

### Cluster Autoscaler (Manual via Omni)

To add nodes:
1. Omni UI → Cluster → Machine Classes
2. Increase worker replica count
3. New nodes auto-provision and join

To remove nodes:
1. Decrease worker replica count
2. Nodes drain and deprovision automatically

## Performance Tuning

### Cilium Tuning

```bash
# Enable BBR congestion control
cilium config set enable-bbr true

# Enable bandwidth manager
cilium config set enable-bandwidth-manager true

# Tune for high throughput
cilium config set tunnel disabled  # Use native routing if possible
```

### Kernel Tuning (via Talos)

Apply this patch to all nodes:

```yaml
machine:
  sysctls:
    net.core.somaxconn: "32768"
    net.core.netdev_max_backlog: "16384"
    net.ipv4.tcp_max_syn_backlog: "8192"
    net.ipv4.tcp_slow_start_after_idle: "0"
    net.ipv4.ip_local_port_range: "1024 65535"
```

## Upgrading

### Upgrade Kubernetes

1. Omni UI → Cluster → Settings
2. Select new Kubernetes version
3. Click **Upgrade**
4. Rolling upgrade with zero downtime

### Upgrade Cilium

```bash
# Check available versions
cilium version

# Upgrade Cilium
cilium upgrade --version 1.15.0

# Verify upgrade
cilium status
```

### Upgrade Talos

1. Omni UI → Cluster → Settings
2. Select new Talos version
3. Click **Upgrade**
4. Nodes upgrade sequentially

## Cost Analysis

**Hardware Requirements** (minimum):
- Single Proxmox cluster with 36+ cores, 80GB+ RAM
- Or distributed across 2-3 Proxmox hosts

**Power Consumption** (3-node setup):
- ~150-300W aggregate
- ~$15-40/month electricity (at $0.12/kWh)

**Comparison to Managed K8s**:
- AWS EKS: ~$500-800/month (3 CP + 3 workers)
- GKE: ~$450-750/month
- **Savings**: $5,000-9,000/year

## Troubleshooting

### Cilium Pods Crashing

```bash
# Check logs
kubectl logs -n kube-system -l k8s-app=cilium

# Common issues:
# - Wrong k8sServiceHost/Port (should be localhost:7445)
# - Missing capabilities
# - Incorrect cgroup path
```

### Connectivity Issues

```bash
# Run Cilium connectivity test
cilium connectivity test

# Check Cilium agent status
cilium status

# Check for network policy blocks
kubectl get ciliumnetworkpolicies --all-namespaces
```

### Gateway API Not Working

```bash
# Check Gateway status
kubectl get gateway -A

# Check HTTPRoute status
kubectl get httproute -A

# Check Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium | grep -i gateway
```

## Production Checklist

Before going to production:

- [ ] 3 control plane nodes running
- [ ] 3+ worker nodes running
- [ ] Cilium installed and healthy
- [ ] Gateway API CRDs installed
- [ ] Storage class configured (Longhorn)
- [ ] Monitoring stack deployed (Prometheus + Grafana)
- [ ] Backup solution configured (Velero)
- [ ] Network policies enforced
- [ ] Pod security standards applied
- [ ] Resource quotas set per namespace
- [ ] Ingress/Gateway configured with TLS
- [ ] DNS configured for cluster services
- [ ] Disaster recovery plan documented
- [ ] Team trained on Omni and Talos

## Next Steps

- Deploy your first production application
- Set up CI/CD pipeline (ArgoCD, Flux, Tekton)
- Configure external DNS (ExternalDNS)
- Implement GitOps workflow
- Add multi-cluster management
- Explore Cilium service mesh features
- Set up log aggregation (Loki, ElasticSearch)

## Resources

- [Cilium Documentation](https://docs.cilium.io/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/security/policy/)
- [Hubble Observability](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Talos Production Best Practices](https://www.talos.dev/v1.11/introduction/prodnotes/)
