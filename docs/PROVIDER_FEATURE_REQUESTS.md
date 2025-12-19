# Proxmox Provider Feature Requests & Backlog

> **Repository**: [siderolabs/omni-infra-provider-proxmox](https://github.com/siderolabs/omni-infra-provider-proxmox)
> 
> This document captures missing features in the Proxmox infrastructure provider that require manual post-provisioning workarounds. Each item includes evidence from the provider source code showing what's currently supported vs what's missing.

---

## Executive Summary

The Proxmox provider handles basic VM creation but lacks advanced Proxmox features needed for production workloads. Users must run post-install scripts on Proxmox nodes to configure:
- Disk performance optimizations
- GPU passthrough settings
- Multiple NICs for storage networks
- Advanced CPU/machine type settings

**Impact**: Every VM provisioned requires manual intervention, breaking GitOps workflows and automation.

---

## Current Provider Capabilities

### Supported Options (from `data.go`)

```go
// Source: internal/pkg/provider/data.go
type Data struct {
    Node            string `yaml:"node,omitempty"`
    StorageSelector string `yaml:"storage_selector,omitempty"`
    NetworkBridge   string `yaml:"network_bridge"`
    Cores           int    `yaml:"cores"`
    DiskSize        int    `yaml:"disk_size"`
    Sockets         int    `yaml:"sockets"`
    Memory          uint64 `yaml:"memory"`
    Vlan            uint64 `yaml:"vlan"`
}
```

### Hardcoded Values (from `provision.go`)

```go
// Source: internal/pkg/provider/provision.go lines 292-317
proxmox.VirtualMachineOption{
    Name:  "cpu",
    Value: "x86-64-v2-AES",  // ❌ HARDCODED - cannot specify 'host'
},
proxmox.VirtualMachineOption{
    Name:  "scsihw",
    Value: "virtio-scsi-single",  // ✅ Good default
},
proxmox.VirtualMachineOption{
    Name:  "onboot",
    Value: 1,  // ✅ Good default
},
proxmox.VirtualMachineOption{
    Name:  "agent",
    Value: "enabled=true",  // ✅ Good - qemu-guest-agent ready
},
```

### Missing from VM Creation

The `NewVirtualMachine` call does NOT set:
- Disk options (ssd, discard, iothread, cache, aio)
- Machine type (q35 vs i440fx)
- NUMA settings
- Hugepages
- Balloon device control
- Multiple network interfaces
- PCI passthrough devices
- CPU args/flags

---

## Feature Requests

### 🔴 P0 - Critical (Blocking Production Use)

---

#### FR-001: Disk Performance Optimization Options

**Problem**: Provider creates disks with default settings, missing critical SSD optimizations.

**Current Workaround** (post-install script):
```bash
qm set $VMID --scsi0 "storage:disk,ssd=1,discard=on,iothread=1,cache=none,aio=io_uring"
```

**Evidence** - Current disk creation (provision.go:309-312):
```go
proxmox.VirtualMachineOption{
    Name:  "scsi0",
    Value: fmt.Sprintf("%s:%d", selectedStorage, data.DiskSize),
    // ❌ Missing: ssd=1,discard=on,iothread=1,cache=none,aio=io_uring
},
```

**Proposed Schema Addition**:
```yaml
providerdata: |
  disk_size: 100
  disk_options:
    ssd: true           # Enable SSD emulation (ssd=1)
    discard: true       # Enable TRIM/discard (discard=on)
    iothread: true      # Dedicated IO thread (iothread=1)
    cache: none         # No caching (cache=none)
    aio: io_uring       # Use io_uring for async IO
```

**Impact**: Without these settings, SSDs/NVMe perform like HDDs. TRIM doesn't work, causing storage bloat.

**Proxmox API**: These are comma-separated options on the disk value string.

---

#### FR-002: Multiple Network Interfaces

**Problem**: Provider only creates one NIC (net0). Production setups need separate management and storage networks.

**Current Workaround** (post-install script):
```bash
qm set $VMID --net1 "virtio,bridge=vmbr1,firewall=0"
```

**Evidence** - Single NIC creation (provision.go:325-328):
```go
proxmox.VirtualMachineOption{
    Name:  "net0",
    Value: networkString,  // ❌ Only net0, no support for net1, net2, etc.
},
```

**Proposed Schema Addition**:
```yaml
providerdata: |
  network_bridge: vmbr0
  additional_nics:
    - bridge: vmbr1        # 10G storage network
      firewall: false
      vlan: 0
    - bridge: vmbr2        # Backup network
      firewall: true
      vlan: 100
```

**Use Case**: 
- ens18 (net0/vmbr0): Management network with DHCP, SideroLink
- ens19 (net1/vmbr1): 10G DAC to TrueNAS for SMB/NFS storage
- ens20 (net2/vmbr2): Backup or VXLAN network

**Impact**: Without this, storage traffic competes with cluster communication on a single NIC.

---

#### FR-003: CPU Type Selection (host passthrough)

**Problem**: CPU type is hardcoded to `x86-64-v2-AES`. GPU passthrough and compute workloads need `host` CPU type.

**Current Workaround** (post-install script):
```bash
qm set $VMID --cpu host
```

**Evidence** - Hardcoded CPU (provision.go:298-301):
```go
proxmox.VirtualMachineOption{
    Name:  "cpu",
    Value: "x86-64-v2-AES",  // ❌ HARDCODED
},
```

**Proposed Schema Addition**:
```yaml
providerdata: |
  cpu_type: host           # Options: host, x86-64-v2-AES, kvm64, etc.
```

**Impact**: 
- GPU passthrough fails or has reduced performance without `cpu=host`
- AVX-512, specific CPU features unavailable
- Performance-sensitive workloads (ML inference) run slower

---

### 🟠 P1 - High Priority (GPU/HPC Workloads)

---

#### FR-004: Machine Type Selection (Q35)

**Problem**: Provider uses default machine type (i440fx). Q35 is required for:
- Native PCIe passthrough (GPU)
- Modern UEFI boot
- Better device emulation

**Current Workaround**:
```bash
qm set $VMID --machine q35
```

**Evidence**: No machine type set in provision.go - uses Proxmox default (i440fx).

**Proposed Schema Addition**:
```yaml
providerdata: |
  machine_type: q35        # Options: i440fx, q35
```

---

#### FR-005: NUMA Configuration

**Problem**: Multi-socket systems need NUMA awareness for optimal memory locality.

**Current Workaround**:
```bash
qm set $VMID --numa 1
```

**Evidence**: No NUMA configuration in provision.go.

**Proposed Schema Addition**:
```yaml
providerdata: |
  sockets: 2
  numa: true               # Enable NUMA topology
```

**Impact**: Without NUMA, VMs on dual-socket servers have ~30% higher memory latency.

---

#### FR-006: Hugepages Support

**Problem**: GPU and HPC workloads benefit from 1GB hugepages (reduced TLB misses).

**Current Workaround**:
```bash
qm set $VMID --hugepages 1048576  # 1GB in KB
```

**Evidence**: No hugepages configuration in provision.go.

**Proposed Schema Addition**:
```yaml
providerdata: |
  hugepages: 1GB           # Options: 2MB, 1GB, or false
```

**Impact**: Up to 10% performance improvement for memory-intensive workloads.

---

#### FR-007: Balloon Device Control

**Problem**: Memory ballooning must be disabled for GPU passthrough and hugepages.

**Current Workaround**:
```bash
qm set $VMID --balloon 0
```

**Evidence**: No balloon configuration in provision.go.

**Proposed Schema Addition**:
```yaml
providerdata: |
  balloon: false           # Disable memory ballooning
```

**Impact**: VMs with GPU passthrough can crash if balloon is enabled.

---

#### FR-008: Custom CPU Args/Flags

**Problem**: KVM paravirtualization optimizations and Hyper-V enlightenments need custom args.

**Current Workaround**:
```bash
qm set $VMID --args "-cpu host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=proxmox,hv_spinlocks=0x1fff"
```

**Evidence**: No args configuration in provision.go.

**Proposed Schema Addition**:
```yaml
providerdata: |
  cpu_args: "+kvm_pv_unhalt,+kvm_pv_eoi"
  hv_vendor_id: proxmox    # Hide virtualization from GPU drivers
```

**Impact**: NVIDIA drivers may refuse to load without `hv_vendor_id` workaround.

---

### 🟡 P2 - Medium Priority (Nice to Have)

---

#### FR-009: PCI Passthrough Devices

**Problem**: GPU passthrough requires adding PCI devices to VMs.

**Current Workaround**: Manual Proxmox UI configuration after VM creation.

**Proposed Schema Addition**:
```yaml
providerdata: |
  pci_devices:
    - id: "0000:41:00"     # GPU
      all_functions: true
      pcie: true
      rombar: false
```

**Complexity**: High - requires IOMMU group detection and validation.

---

#### FR-010: Multiple Disks

**Problem**: Some workloads need separate OS and data disks.

**Evidence** - Single disk (provision.go:309-312):
```go
proxmox.VirtualMachineOption{
    Name:  "scsi0",  // ❌ Only scsi0
    Value: fmt.Sprintf("%s:%d", selectedStorage, data.DiskSize),
},
```

**Proposed Schema Addition**:
```yaml
providerdata: |
  disks:
    - size: 50             # OS disk
      storage: fastpool
    - size: 500            # Data disk
      storage: ssdpool
```

---

#### FR-011: SCSI Controller Type Selection

**Problem**: While `virtio-scsi-single` is a good default, some workloads need `virtio-scsi-pci`.

**Evidence** - Hardcoded (provision.go:315-318):
```go
proxmox.VirtualMachineOption{
    Name:  "scsihw",
    Value: "virtio-scsi-single",  // ✅ Good default but not configurable
},
```

**Proposed Schema Addition**:
```yaml
providerdata: |
  scsi_controller: virtio-scsi-single  # or virtio-scsi-pci
```

---

#### FR-012: VM Description/Notes

**Problem**: No way to add metadata/notes to VMs for documentation.

**Proposed Schema Addition**:
```yaml
providerdata: |
  description: "Talos worker node for ML cluster"
  tags:
    - talos
    - ml-cluster
    - gpu
```

---

### 🟢 P3 - Low Priority (Future)

---

#### FR-013: Cloud-Init Support

**Problem**: While Talos doesn't need cloud-init, other use cases might.

**Proposed Schema Addition**:
```yaml
providerdata: |
  cloud_init:
    enabled: true
    user: admin
    ssh_keys:
      - "ssh-ed25519 AAAA..."
```

---

#### FR-014: USB Passthrough

**Problem**: Some edge cases need USB device passthrough.

**Proposed Schema Addition**:
```yaml
providerdata: |
  usb_devices:
    - vendorid: "1234"
      productid: "5678"
```

---

#### FR-015: EFI/BIOS Selection

**Problem**: UEFI boot with secure boot for compliance requirements.

**Proposed Schema Addition**:
```yaml
providerdata: |
  bios: ovmf              # Options: seabios, ovmf
  efidisk: local-lvm
```

---

## Implementation Priority Matrix

| Feature | Priority | Complexity | Impact | Workaround Available |
|---------|----------|------------|--------|---------------------|
| FR-001: Disk Options | P0 | Low | High | Yes (script) |
| FR-002: Multiple NICs | P0 | Medium | High | Yes (script) |
| FR-003: CPU Type | P0 | Low | High | Yes (script) |
| FR-004: Machine Type | P1 | Low | High | Yes (script) |
| FR-005: NUMA | P1 | Low | Medium | Yes (script) |
| FR-006: Hugepages | P1 | Low | Medium | Yes (script) |
| FR-007: Balloon | P1 | Low | Medium | Yes (script) |
| FR-008: CPU Args | P1 | Medium | Medium | Yes (script) |
| FR-009: PCI Passthrough | P2 | High | High | Manual UI |
| FR-010: Multiple Disks | P2 | Medium | Medium | Manual |
| FR-011: SCSI Controller | P2 | Low | Low | Not needed |
| FR-012: Description | P3 | Low | Low | Not needed |

---

## Suggested Implementation Approach

### Phase 1: Quick Wins (P0 Items)

Update `data.go`:
```go
type Data struct {
    // Existing fields...
    
    // FR-001: Disk options
    DiskSSD       bool   `yaml:"disk_ssd,omitempty"`
    DiskDiscard   bool   `yaml:"disk_discard,omitempty"`
    DiskIOThread  bool   `yaml:"disk_iothread,omitempty"`
    DiskCache     string `yaml:"disk_cache,omitempty"`
    DiskAIO       string `yaml:"disk_aio,omitempty"`
    
    // FR-002: Additional NICs
    AdditionalNICs []NetworkConfig `yaml:"additional_nics,omitempty"`
    
    // FR-003: CPU type
    CPUType string `yaml:"cpu_type,omitempty"`
}

type NetworkConfig struct {
    Bridge   string `yaml:"bridge"`
    Firewall bool   `yaml:"firewall"`
    VLAN     int    `yaml:"vlan,omitempty"`
}
```

Update `provision.go` disk creation:
```go
diskOptions := []string{fmt.Sprintf("%s:%d", selectedStorage, data.DiskSize)}
if data.DiskSSD {
    diskOptions = append(diskOptions, "ssd=1")
}
if data.DiskDiscard {
    diskOptions = append(diskOptions, "discard=on")
}
// ... etc

proxmox.VirtualMachineOption{
    Name:  "scsi0",
    Value: strings.Join(diskOptions, ","),
},
```

### Phase 2: GPU Support (P1 Items)

Add machine type, NUMA, hugepages, balloon, and args options.

### Phase 3: Advanced Features (P2/P3)

PCI passthrough, multiple disks, cloud-init support.

---

## References

- [Proxmox QEMU Options](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines)
- [Proxmox PCI Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough)
- [go-proxmox Library](https://github.com/luthermonson/go-proxmox)
- [Provider Source Code](https://github.com/siderolabs/omni-infra-provider-proxmox)

---

## Workaround Script

Until these features are implemented, use the post-install script:

```bash
# Location: proxmox-provider/scripts/post-install-vm-golden-settings.sh

# Apply disk optimizations to all Talos VMs
./post-install-vm-golden-settings.sh --name-contains talos- --apply

# Apply GPU optimizations
./post-install-vm-golden-settings.sh --name-contains gpu-worker --gpu --apply

# Add 10G storage NIC
./post-install-vm-golden-settings.sh --name-contains worker --add-10g-nic --apply
```

---

*Last Updated: December 2024*
*Based on: omni-infra-provider-proxmox source analysis*
