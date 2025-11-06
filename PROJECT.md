# Project Documentation & Development Notes

> **For Claude Code / GitHub Copilot**: This document provides context for AI coding assistants to understand the project architecture, goals, completed work, and future tasks.

## Project Vision & Goals

### Primary Objective
Create a **production-ready, fully automated starter kit** for deploying self-hosted Sidero Omni with Talos Linux clusters on Proxmox VE infrastructure.

### Target Audience
- Homelab enthusiasts running multi-server Proxmox clusters
- Small teams deploying on-premises Kubernetes infrastructure
- Users wanting full control over their Kubernetes management platform
- Organizations requiring air-gapped or self-hosted cluster management

### Core Requirements (User-Driven)

1. **Self-Hosted Omni Deployment**
   - Docker Compose based (not Kubernetes)
   - Official Siderolabs v1.3.0-beta.2+ format
   - Real-world production configuration
   - Auth0/SAML authentication support
   - Let's Encrypt SSL with Cloudflare DNS
   - GPG-encrypted etcd storage

2. **Multi-Proxmox Server Support**
   - Support 2-3+ Proxmox servers
   - Flexible VM distribution across servers
   - Per-server storage configuration (highly variable per environment)
   - Automatic load balancing of VMs

3. **Flexible Node Types**
   - Control planes: Odd numbers (1, 3, 5, 7) for etcd quorum
   - Standard workers: General compute workloads
   - GPU workers: NVIDIA GPU passthrough for AI/ML workloads

4. **Secondary Disk Support**
   - OS disk (sda): Talos Linux system
   - Data disk (sdb): Longhorn persistent volumes
   - Only for control planes and GPU workers (workers optional)

5. **Static IP & Hostname Configuration**
   - Talos is immutable, doesn't support traditional config
   - Dual strategy:
     - Primary: DHCP reservations (MAC → IP mapping)
     - Backup: Talos machine patches via Omni
   - Automated MAC address generation with rolling pattern

6. **Complete Automation**
   - Infrastructure → VMs → Configured Machines → Ready Cluster
   - Minimal manual intervention (only GPU passthrough)
   - Script-driven workflow for repeatability

## Architecture Decisions

### Why Docker Compose for Omni?
- **User preference**: Already running on dedicated VM/mini PC, not Kubernetes
- **Simpler deployment**: Single Docker Compose file vs. Kubernetes manifests
- **Official support**: Siderolabs provides official Docker Compose template
- **Resource efficiency**: Lower overhead than full Kubernetes cluster

### Why Terraform Instead of Proxmox UI?
- **Infrastructure as Code**: Repeatable, version-controlled deployments
- **Multi-server support**: Manage VMs across multiple Proxmox nodes
- **Inventory generation**: Automatic machine inventory for omnictl integration
- **MAC address automation**: Consistent MAC generation for DHCP reservations

### Why Scripts Instead of Direct Cluster Templates?
- **Machine UUID discovery**: Need to match Terraform VMs to Omni-registered machines by MAC
- **Dynamic configuration**: Generate configs based on actual registered machines
- **Flexibility**: Easier to modify and debug than pure YAML templates
- **Validation**: Verify each step before proceeding

### Why Dual IP Assignment Strategy?
1. **DHCP Reservations** (Primary):
   - More reliable with Talos
   - Router/firewall manages IP consistency
   - Works with existing network infrastructure (Firewalla, pfSense, UniFi)
   - Survives VM reboots automatically

2. **Talos Patches** (Backup):
   - Ensures static IP even if DHCP reservation fails
   - Required for hostname configuration anyway
   - Provides redundancy

### Why Manual GPU Passthrough?
- **Cannot automate**: GPU passthrough requires:
  - BIOS/UEFI changes (IOMMU enablement)
  - Proxmox host configuration (GRUB, kernel modules)
  - Host driver blacklisting
  - VFIO binding
  - Per-VM PCI device assignment
- **Highly environment-specific**: GPU PCI IDs vary per server
- **Manual validation required**: Need to verify GPU visibility after passthrough
- **One-time setup**: Typically done once during initial deployment

## Technical Implementation

### Terraform Architecture

**File Structure**:
```
terraform/
├── main.tf          # VM resources, MAC generation, machine inventory
├── variables.tf     # Input variables (servers, VMs, network)
├── outputs.tf       # Machine inventory, DHCP tables, GPU config
└── terraform.tfvars # User configuration (not in repo)
```

**Key Implementation Details**:

1. **Multi-Proxmox Provider**:
   ```hcl
   # One provider alias per Proxmox server
   provider "proxmox" {
     alias    = "pve1"
     endpoint = var.proxmox_servers["pve1"].api_url
     # ... credentials
   }
   ```

2. **MAC Address Generation**:
   ```
   Format: BC:24:11:NODE_TYPE:00:INDEX

   NODE_TYPE:
   - 01 = control-plane
   - 02 = worker
   - 03 = gpu-worker

   Example: BC:24:11:01:00:00 (first control plane)
   ```

3. **Machine Inventory Structure**:
   ```json
   {
     "talos-cp-1": {
       "hostname": "talos-cp-1",
       "ip_address": "192.168.10.100",
       "mac_address": "BC:24:11:01:00:00",
       "role": "control-plane",
       "proxmox_server": "pve1",
       "cpu_cores": 4,
       "memory_mb": 8192,
       "os_disk_gb": 50,
       "data_disk_gb": 100,
       "has_data_disk": true,
       "gateway": "192.168.10.1",
       "dns_servers": ["1.1.1.1", "8.8.8.8"]
     }
   }
   ```

4. **Dynamic Disk Blocks**:
   ```hcl
   # OS Disk (always present)
   disk {
     slot = 0
     size = "${each.value.os_disk_size_gb}G"
     storage = var.proxmox_servers[each.value.proxmox_server].storage_os
   }

   # Data Disk (conditional)
   dynamic "disk" {
     for_each = each.value.data_disk_size_gb > 0 ? [1] : []
     content {
       slot = 1
       size = "${each.value.data_disk_size_gb}G"
       storage = var.proxmox_servers[each.value.proxmox_server].storage_data
     }
   }
   ```

### Scripts Workflow

**Phase 1: discover-machines.sh**
- Queries Omni API: `omnictl get machines -o json`
- Reads Terraform inventory: `terraform output -json machine_inventory`
- Matches by MAC address (case-insensitive comparison)
- Creates mapping files:
  - `machine-data/matched-machines.json`: Full matched inventory
  - `machine-data/machine-uuids.txt`: hostname=uuid pairs
  - `machine-data/mac-to-uuid.txt`: MAC → UUID
  - `machine-data/ip-to-uuid.txt`: IP → UUID

**Phase 2: generate-machine-configs.sh**
- Reads matched machines from Phase 1
- Generates Talos Machine YAML documents:
  ```yaml
  kind: Machine
  name: <OMNI_UUID>
  labels:
    role: <control-plane|worker|gpu-worker>
    hostname: <hostname>
  patches:
    - name: <hostname>-network-config
      inline:
        machine:
          network:
            hostname: <hostname>
            interfaces:
              - interface: eth0
                dhcp: false
                addresses: [<IP>/24]
                routes: [{network: 0.0.0.0/0, gateway: <GATEWAY>}]
            nameservers: [<DNS_SERVERS>]
  ```
- Adds secondary disk patches for Longhorn (if data_disk_gb > 0)
- Includes GPU driver extensions for GPU workers
- Creates individual configs + combined `cluster-template.yaml`

**Phase 3: apply-machine-configs.sh**
- Validates omnictl connectivity
- Shows configuration preview (counts, sample configs)
- Interactive confirmation
- Applies: `omnictl cluster template sync -f cluster-template.yaml`
- Verification: `omnictl get machines -o wide`

### Omni Configuration

**Docker Compose Format** (v1.3.0-beta.2):
```yaml
name: omni-on-prem
services:
  omni:
    image: ghcr.io/siderolabs/omni:${OMNI_IMG_TAG}
    env_file: omni.env
    command: >
      --account-id=${OMNI_ACCOUNT_UUID}
      --name=${NAME}
      --cert=/tls.crt
      --key=/tls.key
      --private-key-source=file:///omni.asc
      ${AUTH}
    # ... volumes, devices, network_mode, etc.
```

**Key Environment Variables**:
- `OMNI_ACCOUNT_UUID`: Unique account identifier (from Omni registration)
- `NAME`: Omni instance name
- `SIDEROLINK_WIREGUARD_ADVERTISED_ADDR`: Public endpoint for VMs to connect
- `AUTH0_*` or `SAML_*`: Authentication configuration
- `ETCD_VOLUME_PATH`: Local directory for etcd data (NOT /etc/etcd/)
- `ETCD_ENCRYPTION_KEY`: GPG key path for encryption

**Network Ports**:
- 443: HTTPS (Omni UI/API)
- 8090: Internal gRPC
- 8100: Internal metrics
- 50180: SideroLink WireGuard (was 50042 in older versions)

## Completed Work

### Phase 1: Omni Deployment (Completed)
✅ Updated to official Siderolabs v1.3.0-beta.2 Docker Compose format
✅ Created `.env.example` with comprehensive documentation
✅ Fixed etcd path recommendation (`./etcd` instead of `/etc/etcd/`)
✅ Created helper scripts:
  - `install-docker.sh`: Automated Docker installation
  - `setup-certificates.sh`: Let's Encrypt + Cloudflare DNS
  - `generate-gpg-key.sh`: GPG key generation for etcd
  - `check-prerequisites.sh`: Pre-deployment validation
  - `cleanup-omni.sh`: Complete cleanup for fresh deployments

✅ Comprehensive sidero-omni/README.md with:
  - Real-world troubleshooting (etcd permissions, port conflicts)
  - Auth0 and SAML configuration examples
  - Network firewall requirements
  - Resource limits and health checks

### Phase 2: Terraform Multi-Proxmox (Completed)
✅ Complete rewrite from single-server to multi-server architecture
✅ Changed from count-based to declarative list-based VM definitions
✅ `proxmox_servers` map for per-server configuration
✅ Flexible per-VM configuration (name, server, IP, MAC, resources, disks)
✅ Automated MAC address generation with configurable prefix
✅ Secondary disk support with dynamic blocks
✅ Comprehensive outputs:
  - `machine_inventory`: Complete VM inventory
  - `dhcp_reservations_table`: Formatted for easy router config
  - `machine_configs_data`: Data for Talos config generation
  - `gpu_configuration_needed`: Manual GPU setup instructions

✅ Detailed terraform.tfvars.example with examples for 1, 2, 3+ servers
✅ Comprehensive terraform/README.md

### Phase 3: Integration Scripts (Completed)
✅ `discover-machines.sh`: Machine discovery and MAC-based matching
✅ `generate-machine-configs.sh`: Talos Machine YAML generation
✅ `apply-machine-configs.sh`: Configuration application via omnictl
✅ Comprehensive scripts/README.md with:
  - Complete workflow documentation
  - Troubleshooting guide
  - Advanced usage patterns
  - Network configuration strategies

### Phase 4: Documentation (Completed)
✅ GPU passthrough guide (docs/gpu-passthrough-guide.md):
  - BIOS/UEFI configuration (IOMMU/VT-d)
  - Proxmox host setup (GRUB, VFIO modules)
  - GPU identification (lspci, IOMMU groups)
  - VM configuration (qm set commands)
  - Verification steps
  - Comprehensive troubleshooting
  - Advanced topics (SR-IOV, ROM extraction, CPU pinning)

✅ Main README.md rewrite:
  - 5-phase deployment workflow
  - Architecture diagrams (infrastructure, workflow)
  - Complete quick start guide
  - Troubleshooting section
  - Advanced topics (HA, GitOps, multi-cluster)
  - Project status and roadmap

✅ PROJECT.md (this file):
  - Project vision and goals
  - Architecture decisions and rationale
  - Technical implementation details
  - Completed work summary
  - Future roadmap
  - Development guidelines

## Known Issues & Limitations

### Current Limitations

1. **Talos Template Creation Not Documented**
   - Users must manually create Talos template VM in Proxmox
   - Template must exist on ALL Proxmox servers
   - Need guide for downloading Talos ISO and creating template

2. **GPU Passthrough is Manual**
   - Cannot be automated via Terraform
   - Requires per-server BIOS/host configuration
   - Documented but still requires manual steps

3. **No Automated Cluster Creation**
   - Scripts only configure machines
   - User must still create cluster via Omni UI
   - Could be automated with cluster templates

4. **No Backup/Restore Procedures**
   - etcd backups not automated
   - No documented recovery procedures
   - Need scripts for disaster recovery

5. **Testing Limited to Single Environment**
   - Tested with specific Proxmox configuration
   - Need community testing with various setups
   - Storage backends beyond local-lvm not tested

### Known Bugs
None currently reported. This is a new implementation based on real-world deployment.

## Future Roadmap

### High Priority (Should be next)

1. **Talos Template VM Creation Guide**
   - Document downloading Talos ISO
   - Creating template VM in Proxmox UI
   - Converting to template
   - Cloning template to all Proxmox servers
   - Template best practices

2. **Automated Cluster Creation**
   - Create cluster template YAML
   - Script to generate cluster template from Terraform inventory
   - Automatic cluster creation via omnictl
   - Integration with existing scripts

3. **Backup & Restore Procedures**
   - etcd backup automation
   - Omni configuration backup
   - Terraform state backup
   - Complete disaster recovery guide

### Medium Priority

4. **Monitoring Stack Integration**
   - Prometheus operator installation
   - Grafana dashboards for Talos
   - Omni metrics integration
   - Alert rules for cluster health

5. **Storage Configuration Examples**
   - Longhorn installation guide
   - Secondary disk automatic formatting
   - Storage class configuration
   - Backup configuration

6. **Network Policy Examples**
   - Cilium network policies
   - Service mesh integration (Istio/Linkerd)
   - Ingress controller setup (nginx, Traefik)

### Low Priority / Future Enhancements

7. **Multi-Cluster Federation**
   - Managing multiple clusters from one Omni
   - Cross-cluster networking
   - Federated service discovery

8. **Advanced Terraform Features**
   - Terraform workspaces for multi-cluster
   - Remote state backend configuration
   - Terraform Cloud integration

9. **CI/CD Integration**
   - GitHub Actions for Terraform validation
   - Automated testing of scripts
   - Container image building

10. **Alternative Configurations**
    - AMD GPU support documentation
    - Alternative storage backends (Ceph, NFS)
    - Alternative CNI configurations
    - Air-gapped deployment guide

## Development Guidelines

### For AI Assistants (Claude Code / Copilot)

**When modifying Terraform**:
- Always maintain backward compatibility with existing tfvars files
- Update outputs.tf if changing machine_inventory structure
- Test MAC address generation logic carefully (must be unique)
- Document any breaking changes prominently

**When modifying scripts**:
- Maintain the three-script workflow (discover → generate → apply)
- Always validate input files exist before processing
- Provide clear error messages with remediation steps
- Test jq queries with various edge cases

**When updating documentation**:
- Keep all READMEs synchronized (main, sidero-omni, terraform, scripts)
- Update troubleshooting sections based on new issues
- Include code examples with actual file paths
- Reference official Siderolabs documentation when applicable

**Code style**:
- Bash scripts: Use `set -euo pipefail`, validate prerequisites
- HCL: Use consistent indentation (2 spaces), descriptive variable names
- YAML: Follow Talos/Omni official format exactly
- Markdown: Use GitHub-flavored markdown, include code fences

### Testing Requirements

Before committing changes:
1. Validate Terraform: `terraform validate && terraform fmt -check`
2. Check bash scripts: `shellcheck *.sh`
3. Verify YAML: `yamllint` or manual validation
4. Test outputs: Ensure machine_inventory structure is maintained
5. Update documentation: Reflect any changes in relevant READMEs

### Git Workflow

**Branching**:
- Feature branches: `feature/<description>`
- Bug fixes: `fix/<description>`
- Documentation: `docs/<description>`

**Commit Messages**:
```
<type>: <short description>

<detailed explanation>

<breaking changes if any>
```

Types: feat, fix, docs, refactor, test, chore

**Pull Requests**:
- Reference related issues
- Include testing evidence
- Update documentation
- Add to CHANGELOG (if exists)

## Important Context for Future Sessions

### User's Actual Environment
- Running Sidero Omni v1.3.0-beta.1+ (not stable v1.2.1)
- 2-3 Proxmox servers in production
- Using Firewalla for DHCP/firewall
- Auth0 for authentication (not SAML)
- Had issues with:
  - `/etc/etcd/` permissions (now using `./etcd`)
  - Port 50042 vs 50180 (now using 50180)
  - Docker Compose format mismatches (now using official format)

### Critical Files & Their Purpose
- `sidero-omni/docker-compose.yml`: Official v1.3.0-beta.2 format (DO NOT change structure)
- `sidero-omni/.env.example`: Template for user configuration (keep comprehensive)
- `terraform/variables.tf`: Input schema (breaking changes require careful migration)
- `terraform/outputs.tf`: Machine inventory (scripts depend on this structure)
- `scripts/discover-machines.sh`: MAC matching logic (tested and working)
- `scripts/generate-machine-configs.sh`: Talos YAML generation (matches official format)

### What NOT to Change Without Good Reason
- MAC address generation pattern (BC:24:11:NODE:00:IDX)
- Machine inventory structure in outputs.tf
- Docker Compose command format (official Siderolabs format)
- Three-script workflow (discover → generate → apply)
- Official Talos Machine YAML format

### Where to Be Creative
- Additional helper scripts
- Enhanced error handling
- Better user experience (prompts, validation)
- Additional documentation
- Troubleshooting guides
- Integration examples

## Quick Reference

### Key Commands
```bash
# Omni deployment
cd sidero-omni && docker compose --env-file omni.env up -d

# Terraform deployment
cd terraform && terraform init && terraform apply

# Machine configuration
cd scripts
./discover-machines.sh
./generate-machine-configs.sh
./apply-machine-configs.sh

# Cluster creation (manual via Omni UI)
# Then get kubeconfig:
omnictl kubeconfig -c talos-cluster > kubeconfig
```

### File Paths
- Omni config: `sidero-omni/omni.env`
- Terraform config: `terraform/terraform.tfvars`
- Machine inventory: `terraform machine_inventory` (output)
- Machine UUIDs: `scripts/machine-data/machine-uuids.txt`
- Machine configs: `scripts/machine-configs/*.yaml`

### Common Tasks
- **Add new Proxmox server**: Edit `terraform/terraform.tfvars`, add to `proxmox_servers`
- **Add new VM**: Edit `terraform/terraform.tfvars`, add to `control_planes`, `workers`, or `gpu_workers`
- **Regenerate configs**: Re-run `scripts/generate-machine-configs.sh` and `scripts/apply-machine-configs.sh`
- **Clean up Omni**: Run `sidero-omni/cleanup-omni.sh`

## Support & Resources

### Official Documentation
- [Sidero Omni Docs](https://www.siderolabs.com/omni/docs/)
- [Talos Linux Docs](https://www.talos.dev/)
- [Omni Cluster Templates](https://www.siderolabs.com/omni/docs/reference/cluster-templates/)

### Community Resources
- [Siderolabs Discord](https://discord.gg/siderolabs)
- [Talos GitHub Discussions](https://github.com/siderolabs/talos/discussions)
- [Omni GitHub Issues](https://github.com/siderolabs/omni/issues)

### Project Repository
- GitHub: [mitchross/sidero-omni-talos-proxmox-starter](https://github.com/mitchross/sidero-omni-talos-proxmox-starter)
- Issues: Report bugs and feature requests
- Discussions: Ask questions and share experiences

---

**Last Updated**: 2025-11-06
**Version**: 1.0 (Initial completion of core features)
**Status**: Production-ready for basic deployments, additional features in roadmap
