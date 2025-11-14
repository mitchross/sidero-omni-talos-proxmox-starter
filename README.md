# Sidero Omni + Talos on Proxmox Starter Kit

A complete, production-ready starter kit for deploying self-hosted Sidero Omni with the Proxmox infrastructure provider to automatically provision Talos Linux clusters.

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
4. **Create Clusters** - Use Omni UI to define machine classes and provision clusters

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
└── docs/                      # Additional documentation
    ├── ARCHITECTURE.md
    ├── PREREQUISITES.md
    └── TROUBLESHOOTING.md
```

## Key Features

### Automated Provisioning
Define "machine classes" in Omni that specify CPU, RAM, and disk resources. The Proxmox provider watches for new machines and automatically creates VMs matching your specifications.

### GPU Support (Optional)
Include NVIDIA GPU support for AI/ML workloads. See [talos-configs/README.md](talos-configs/README.md) for configuration details.

### Production Ready
- SSL/TLS encryption with Let's Encrypt
- Etcd data encryption with GPG
- Auth0, SAML, or OIDC authentication
- High availability support

## Important Notes

⚠️ **Proxmox Provider Status**: The Proxmox infrastructure provider is currently in **beta**. Expect some limitations and potential bugs. Please report issues to the [upstream repository](https://github.com/siderolabs/omni-infra-provider-proxmox).

⚠️ **Known Limitations**:
- Single disk per VM (multiple disk support is a potential enhancement)
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
