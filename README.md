# Sidero Omni + Talos on Proxmox Starter Kit

A complete, production-ready starter kit for deploying self-hosted Sidero Omni with the Proxmox infrastructure provider to automatically provision Talos Linux clusters.

## 📺 Video Tutorial: Part 3

[![Watch the Video](https://img.youtube.com/vi/PxnzfzkU6OU/maxresdefault.jpg)](https://www.youtube.com/watch?v=PxnzfzkU6OU)

**Welcome to Part 3 of the Ultimate Kubernetes HomeLab series!**

In this video, we’re diving deep into **Sidero Omni**, the **Omni Proxmox Infra Provider**, and deploying a full **Talos OS cluster from scratch**—all running fully self-hosted.

You’ll learn how to set up Omni, connect it to Proxmox using the official infra provider, provision Talos machines, and manage the entire lifecycle of your Kubernetes nodes through a clean, modern UI.

### 🚀 What You’ll Learn
- Installing *Omni* from the self-hosted GitHub repo
- Deploying the *Sidero Proxmox Infra Provider*
- Configuring Proxmox to work with Omni
- Creating Talos machine classes and templates
- Provisioning Talos nodes automatically on Proxmox
- Bootstrapping & lifecycle management workflows
- Best practices for scaling your Talos cluster

### 🔗 Video Series
- **Part 1**: [Complete Kubernetes GitOps Setup Guide: Argo CD, Cilium, K3s](https://www.youtube.com/watch?v=Jm0R74_RkUo)
- **Part 2**: [Complete Kubernetes GitOps Setup Guide Part 2: Talos OS, Proxmox, Terraform](https://www.youtube.com/watch?v=F-qV_n0xW-o)
- **Part 3 (This Video)**: [Sidero Omni + Talos on Proxmox](https://www.youtube.com/watch?v=PxnzfzkU6OU)

### 📦 Resources
- **Omni**: [https://github.com/siderolabs/omni](https://github.com/siderolabs/omni)
- **Proxmox Infra Provider**: [https://github.com/siderolabs/omni-infra-provider-proxmox](https://github.com/siderolabs/omni-infra-provider-proxmox)
- **Reference Guide**: [VirtualizationHowTo Guide](https://www.virtualizationhowto.com/2025/08/how-to-install-talos-omni-on-prem-for-effortless-kubernetes-management/)

---

> [!IMPORTANT]
> **Updated for Talos 1.13 / Omni v1.9 (2026-07).** Talos 1.13 replaced the
> install/upgrade flow with the LifecycleService API, which **requires an
> explicit `machine.install.disk`** — the cluster template now ships this as
> the `install-disk` patch. Without it, freshly provisioned VMs sit at
> `stage=UPGRADING, configuptodate=false` forever with **no error surfaced
> anywhere**. Keep `omnictl` on the same release as your Omni server
> (`OMNI_IMG_TAG` in `omni/omni.env.example`).

## The starter family (which repo do I want?)

| Repo | Provisioning | What you get |
|---|---|---|
| **this one** | Omni + Proxmox provider | no-SSH, UI-driven Talos cluster provisioning |
| [talos-argocd-proxmox-starter](https://github.com/mitchross/talos-argocd-proxmox-starter) | Terraform + talhelper | the non-Omni on-ramp: Talos on Proxmox + ArgoCD + simple apps |
| [talos-argocd-proxmox-advanced-starter](https://github.com/mitchross/talos-argocd-proxmox-advanced-starter) | Omni (this kit) | the production-shaped GitOps tier: sync waves, kopiur restore-before-bind PVC backups, CNPG Postgres, Gateway API, monitoring |
| [talos-argocd-proxmox](https://github.com/mitchross/talos-argocd-proxmox) | Omni | the live production cluster the others are pruned from |

## What This Provides

- **Self-hosted Omni deployment** - Run your own Omni instance on-premises
- **Proxmox integration** - Automatically provision Talos VMs in your Proxmox cluster
- **GPU support** (optional) - Configure NVIDIA GPU passthrough for AI/ML workloads
- **Complete examples** - Working configurations you can customize
- **Setup automation** - Scripts to streamline SSL and encryption setup

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Your Infrastructure                   │
│                                                          │
│  ┌──────────────┐         ┌─────────────────────────┐  │
│  │ Omni Server  │◄────────┤ Proxmox Infrastructure  │  │
│  │ (Self-hosted)│         │ Provider (Docker)       │  │
│  │              │         │                         │  │
│  │ - Web UI     │         │ - Watches Omni API     │  │
│  │ - API        │         │ - Creates VMs          │  │
│  │ - SideroLink │         │ - Manages lifecycle    │  │
│  └──────┬───────┘         └──────────┬──────────────┘  │
│         │                            │                  │
│         │         ┌──────────────────▼─────┐            │
│         │         │   Proxmox Cluster      │            │
│         │         │                        │            │
│         └────────►│  ┌──────────────────┐  │            │
│                   │  │ Talos VM Node 1  │  │            │
│                   │  │ Talos VM Node 2  │  │            │
│                   │  │ Talos VM Node 3  │  │            │
│                   │  └──────────────────┘  │            │
│                   └────────────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

1. **Prerequisites** - See [docs/PREREQUISITES.md](docs/PREREQUISITES.md)
2. **Deploy Omni** - Follow [omni/README.md](omni/README.md)
3. **Setup Provider** - Follow [proxmox-provider/README.md](proxmox-provider/README.md)
4. **Apply Machine Classes** - `omnictl apply -f machine-classes/control-plane.yaml` (repeat for all files)
5. **Sync Cluster Template** - `cd cluster-template && omnictl cluster template sync -v -f cluster-template.yaml`
6. **Create Clusters** - Follow the [Operations Guide](docs/OPERATIONS.md)

## Project Structure

```
.
├── omni/                      # Self-hosted Omni deployment
│   ├── docker-compose.yml
│   ├── omni.env.example
│   └── scripts/               # SSL and GPG setup automation
├── proxmox-provider/          # Proxmox infrastructure provider
│   ├── docker-compose.yml
│   ├── .env.example
│   └── config.yaml.example
├── talos-configs/             # Example Talos configurations
│   └── gpu-worker-patch.yaml  # NVIDIA GPU support
├── examples/                  # Complete deployment examples
│   ├── simple-homelab/        # Minimal 3-node cluster
│   ├── gpu-ml-cluster/        # GPU-enabled for AI/ML
│   └── production-ha/         # HA cluster with Cilium CNI
└── docs/                      # Additional documentation
    ├── ARCHITECTURE.md
    ├── PREREQUISITES.md
    └── TROUBLESHOOTING.md
```

## Key Features

### Automated Provisioning
Define "machine classes" in Omni that specify CPU, RAM, and disk resources. The Proxmox provider watches for new machines and automatically creates VMs matching your specifications.

### Dual Network Architecture (Management + Storage)
Separate networks for optimal performance:
- **Management Network (vmbr0/ens18)**: DHCP, cluster communication, SideroLink
- **Storage Network (vmbr1/ens19)**: Static IPs, 10G DAC to TrueNAS/NAS

### Storage Pool Separation
Control planes and workers use different Proxmox storage pools:
- **Control Planes**: `fastpool` (high-IOPS for etcd)
- **Workers**: `ssdpool` (balanced performance)

### GPU Support (Optional)
Include NVIDIA GPU support for AI/ML workloads with optimized VM settings:
- CPU passthrough (`cpu=host`)
- Q35 machine type for PCIe passthrough
- NUMA awareness for multi-socket systems
- 1GB hugepages for performance

See [talos-configs/README.md](talos-configs/README.md) for configuration details.

### Production Ready
- SSL/TLS encryption with Let's Encrypt
- Etcd data encryption with GPG  
- SQLite storage backend (Omni v1.4.0+)
- Auth0, SAML, or OIDC authentication
- High availability support



## Advanced Networking

### Cilium CNI

For production deployments, we recommend Cilium CNI:
- **10-40% better performance** vs traditional CNIs
- **eBPF-based** load balancing (replaces kube-proxy)
- **Gateway API** support with advanced routing
- **L3-L7 network policies** for security
- **Hubble** for deep network observability
- **Service mesh** capabilities without sidecars

See the official documentation: [https://docs.cilium.io](https://docs.cilium.io)

**Quick Install**:
```bash
# Disable kube-proxy in cluster config, then:
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

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

## Important Notes

⚠️ **Proxmox Provider Status**: The Proxmox infrastructure provider is currently in **beta**. Expect some limitations and potential bugs. Please report issues to the [upstream repository](https://github.com/siderolabs/omni-infra-provider-proxmox).

⚠️ **Known Limitations**:
- Extensions must be included in Talos image or specified in cluster template

## Use Cases

- **Homelab**: Self-hosted Kubernetes cluster management
- **Edge Computing**: Manage distributed Talos clusters
- **Development**: Rapid cluster provisioning for testing
- **Production**: Enterprise-grade cluster lifecycle management

## License

This starter kit is provided as-is for use with Sidero Omni. Note that:
- Omni uses Business Source License (BSL) - free for non-production use
- Talos Linux is MPL-2.0 licensed
- Proxmox provider is MPL-2.0 licensed

## Contributing

Found a bug? Have an enhancement? PRs welcome! This is a community-driven starter kit.

## Resources

- [Omni Documentation](https://docs.siderolabs.com/omni/)
- [Talos Documentation](https://docs.siderolabs.com/talos/)
- [Proxmox Provider](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [Sidero Labs Slack](https://slack.dev.talos-systems.io/)

## Credits

Built by the community, for the community. Special thanks to the Sidero Labs team for their support and tooling.
