# =============================================================================
# Terraform and Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc05"
    }
  }
}

# Primary Proxmox provider
# For clustered Proxmox: Connect to any node, VMs distributed via target_node
# For standalone servers: See README for multi-provider configuration
provider "proxmox" {
  # Use the first server's credentials as primary
  pm_api_url          = values(var.proxmox_servers)[0].api_url
  pm_api_token_id     = values(var.proxmox_servers)[0].api_token_id
  pm_api_token_secret = values(var.proxmox_servers)[0].api_token_secret
  pm_tls_insecure     = values(var.proxmox_servers)[0].tls_insecure
}

# =============================================================================
# Local Variables and Data Processing
# =============================================================================

locals {
  # Generate MAC addresses for VMs that don't have one specified
  # Pattern: ${prefix}:${node_type}:${index}
  # Example: BC:24:11:01:00:01 (prefix:01=control:00:01=first)

  control_planes_with_mac = [
    for idx, cp in var.control_planes : merge(cp, {
      mac_address = cp.mac_address != "" ? cp.mac_address : format(
        "%s:01:%02X:%02X",
        var.mac_address_prefix,
        floor(idx / 256),
        idx % 256
      )
      index = idx
      role  = "control-plane"
    })
  ]

  workers_with_mac = [
    for idx, worker in var.workers : merge(worker, {
      mac_address = worker.mac_address != "" ? worker.mac_address : format(
        "%s:02:%02X:%02X",
        var.mac_address_prefix,
        floor(idx / 256),
        idx % 256
      )
      index = idx
      role  = "worker"
    })
  ]

  gpu_workers_with_mac = [
    for idx, gpu in var.gpu_workers : merge(gpu, {
      mac_address = gpu.mac_address != "" ? gpu.mac_address : format(
        "%s:03:%02X:%02X",
        var.mac_address_prefix,
        floor(idx / 256),
        idx % 256
      )
      index = idx
      role  = "gpu-worker"
    })
  ]

  # Merge all VMs into a single map for easier management
  all_vms = merge(
    { for vm in local.control_planes_with_mac : vm.name => vm },
    { for vm in local.workers_with_mac : vm.name => vm },
    { for vm in local.gpu_workers_with_mac : vm.name => vm }
  )

  # Group VMs by Proxmox server for distribution validation
  vms_by_server = {
    for server_key in keys(var.proxmox_servers) :
    server_key => [
      for vm_name, vm in local.all_vms :
      vm if vm.proxmox_server == server_key
    ]
  }

  # Create machine inventory for export
  machine_inventory = {
    for vm_name, vm in local.all_vms :
    vm_name => {
      hostname       = vm.name
      role           = vm.role
      proxmox_server = vm.proxmox_server
      proxmox_node   = var.proxmox_servers[vm.proxmox_server].node_name
      ip_address     = vm.ip_address
      mac_address    = vm.mac_address
      cpu_cores      = vm.cpu_cores
      memory_mb      = vm.memory_mb
      os_disk_gb     = vm.os_disk_size_gb
      data_disk_gb   = vm.data_disk_size_gb
      has_data_disk  = vm.data_disk_size_gb > 0
      gateway        = var.network_config.gateway
      dns_servers    = var.network_config.dns_servers
      # GPU info for GPU workers
      gpu_pci_id = lookup(vm, "gpu_pci_id", "")
    }
  }
}

# =============================================================================
# Control Plane VMs
# =============================================================================

resource "proxmox_vm_qemu" "control_plane" {
  for_each = { for vm in local.control_planes_with_mac : vm.name => vm }

  name        = each.value.name
  vmid        = 100 + each.value.index  # Control planes: 100, 101, 102, ...
  target_node = var.proxmox_servers[each.value.proxmox_server].node_name
  description = "Talos Control Plane - Managed by Terraform - Talos ${var.talos_version} - Boot: ${var.talos_iso != "" ? "ISO" : "PXE"}"

  # VM Resources
  memory  = each.value.memory_mb
  machine = "q35"  # Modern chipset for better PCIe/GPU support
  cpu {
    cores   = each.value.cpu_cores
    sockets = 1
  }

  # SCSI Controller
  scsihw = "virtio-scsi-single"

  # Boot order depends on whether ISO is provided
  # ISO provided: Boot from CD-ROM first, then disk (order=ide2;scsi0)
  # No ISO: Boot from disk first, PXE fallback (order=scsi0;net0)
  #         This ensures machines boot from disk after Talos is installed,
  #         preventing UUID/identity changes on every reboot
  boot = var.talos_iso != "" ? "order=ide2;scsi0" : "order=scsi0;net0"

  # CD-ROM with Talos ISO (only if ISO is provided)
  dynamic "disk" {
    for_each = var.talos_iso != "" ? [1] : []
    content {
      type = "cdrom"
      slot = "ide2"
      iso  = var.talos_iso
    }
  }

  # OS Disk (scsi0)
  disk {
    slot       = "scsi0"
    size       = "${each.value.os_disk_size_gb}G"
    type       = "disk"
    storage    = each.value.storage_os_override != "" ? each.value.storage_os_override : var.proxmox_servers[each.value.proxmox_server].storage_control_plane_os
    iothread   = true
    discard    = true
    emulatessd = true
  }

  # Data Disk (scsi1) - Only if size > 0
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      slot       = "scsi1"
      size       = "${each.value.data_disk_size_gb}G"
      type       = "disk"
      storage    = each.value.storage_data_override != "" ? each.value.storage_data_override : var.proxmox_servers[each.value.proxmox_server].storage_control_plane_data
      iothread   = true
      discard    = true
      emulatessd = true
    }
  }

  # Network Configuration
  network {
    id      = 0
    model   = "virtio"
    bridge  = var.proxmox_servers[each.value.proxmox_server].network_bridge
    macaddr = upper(each.value.mac_address)
    tag     = var.network_config.vlan_id
  }

  # VM Options
  onboot = var.vm_start_on_boot
  agent  = 1  # QEMU Guest Agent enabled (requires qemu-guest-agent system extension in Talos)

  # Don't wait for guest agent during VM creation (agent won't be available until Talos boots)
  define_connection_info = false

  # Tags for organization
  tags = join(";", [
    "talos",
    "control-plane",
    var.cluster_name,
    "terraform-managed"
  ])

  # Prevent unnecessary changes
  lifecycle {
    ignore_changes = [
      network[0].macaddr, # MAC address set once
      description,        # Description might be modified
    ]
  }
}

# =============================================================================
# Worker VMs
# =============================================================================

resource "proxmox_vm_qemu" "worker" {
  for_each = { for vm in local.workers_with_mac : vm.name => vm }

  name        = each.value.name
  vmid        = 110 + each.value.index  # Workers: 110, 111, 112, ...
  target_node = var.proxmox_servers[each.value.proxmox_server].node_name
  description = "Talos Worker - Managed by Terraform - Talos ${var.talos_version} - Boot: ${var.talos_iso != "" ? "ISO" : "PXE"}"

  memory  = each.value.memory_mb
  machine = "q35"  # Modern chipset for better PCIe/GPU support
  scsihw  = "virtio-scsi-single"
  boot    = var.talos_iso != "" ? "order=ide2;scsi0" : "order=scsi0;net0"
  cpu {
    cores   = each.value.cpu_cores
    sockets = 1
  }

  # CD-ROM with Talos ISO (only if ISO is provided)
  dynamic "disk" {
    for_each = var.talos_iso != "" ? [1] : []
    content {
      type = "cdrom"
      slot = "ide2"
      iso  = var.talos_iso
    }
  }

  # OS Disk
  disk {
    slot       = "scsi0"
    size       = "${each.value.os_disk_size_gb}G"
    type       = "disk"
    storage    = each.value.storage_os_override != "" ? each.value.storage_os_override : var.proxmox_servers[each.value.proxmox_server].storage_worker_os
    iothread   = true
    discard    = true
    emulatessd = true
  }

  # Data Disk (optional)
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      slot       = "scsi1"
      size       = "${each.value.data_disk_size_gb}G"
      type       = "disk"
      storage    = each.value.storage_data_override != "" ? each.value.storage_data_override : var.proxmox_servers[each.value.proxmox_server].storage_worker_data
      iothread   = true
      discard    = true
      emulatessd = true
    }
  }

  network {
    id      = 0
    model   = "virtio"
    bridge  = var.proxmox_servers[each.value.proxmox_server].network_bridge
    macaddr = upper(each.value.mac_address)
    tag     = var.network_config.vlan_id
  }

  onboot = var.vm_start_on_boot
  agent  = 1  # QEMU Guest Agent enabled (requires qemu-guest-agent system extension in Talos)

  # Don't wait for guest agent during VM creation (agent won't be available until Talos boots)
  define_connection_info = false

  tags = join(";", [
    "talos",
    "worker",
    var.cluster_name,
    "terraform-managed"
  ])

  lifecycle {
    ignore_changes = [
      network[0].macaddr,
      description,
    ]
  }
}

# =============================================================================
# GPU Worker VMs
# =============================================================================

resource "proxmox_vm_qemu" "gpu_worker" {
  for_each = { for vm in local.gpu_workers_with_mac : vm.name => vm }

  name        = each.value.name
  vmid        = 120 + each.value.index  # GPU Workers: 120, 121, 122, ...
  target_node = var.proxmox_servers[each.value.proxmox_server].node_name
  description = "Talos GPU Worker - Managed by Terraform - Talos ${var.talos_version} - Boot: ${var.talos_gpu_iso != "" ? "ISO (GPU-enabled)" : "PXE"} - GPU: nvidia-gpu-1 (mapped resource)"

  memory  = each.value.memory_mb
  machine = "q35"  # Modern chipset required for GPU passthrough
  scsihw  = "virtio-scsi-single"
  boot    = var.talos_gpu_iso != "" ? "order=ide2;scsi0" : "order=scsi0;net0"
  cpu {
    cores   = each.value.cpu_cores
    sockets = 1
  }

  # CD-ROM with Talos GPU ISO (only if ISO is provided)
  # This ISO is generated from Image Factory with gpu-worker.yaml schematic
  # Includes NVIDIA drivers and extensions baked in
  dynamic "disk" {
    for_each = var.talos_gpu_iso != "" ? [1] : []
    content {
      type = "cdrom"
      slot = "ide2"
      iso  = var.talos_gpu_iso
    }
  }

  # OS Disk
  disk {
    slot       = "scsi0"
    size       = "${each.value.os_disk_size_gb}G"
    type       = "disk"
    storage    = each.value.storage_os_override != "" ? each.value.storage_os_override : (var.proxmox_servers[each.value.proxmox_server].storage_gpu_worker_os != "" ? var.proxmox_servers[each.value.proxmox_server].storage_gpu_worker_os : var.proxmox_servers[each.value.proxmox_server].storage_worker_os)
    iothread   = true
    discard    = true
    emulatessd = true
  }

  # Data Disk (typically needed for GPU workloads)
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      slot       = "scsi1"
      size       = "${each.value.data_disk_size_gb}G"
      type       = "disk"
      storage    = each.value.storage_data_override != "" ? each.value.storage_data_override : (var.proxmox_servers[each.value.proxmox_server].storage_gpu_worker_data != "" ? var.proxmox_servers[each.value.proxmox_server].storage_gpu_worker_data : var.proxmox_servers[each.value.proxmox_server].storage_worker_data)
      iothread   = true
      discard    = true
      emulatessd = true
    }
  }

  network {
    id      = 0
    model   = "virtio"
    bridge  = var.proxmox_servers[each.value.proxmox_server].network_bridge
    macaddr = upper(each.value.mac_address)
    tag     = var.network_config.vlan_id
  }

  # GPU Passthrough using Proxmox mapped resource
  # Mapped resource name: nvidia-gpu-1 (configured in Proxmox Datacenter → Resource Mappings)
  # This automatically assigns the correct GPU PCI device to the VM
  pcis {
    pci0 {
      mapping {
        mapping_id  = "nvidia-gpu-1"
        pcie        = true
        rombar      = true
        primary_gpu = false
      }
    }
  }

  onboot = var.vm_start_on_boot
  agent  = 1  # QEMU Guest Agent enabled (requires qemu-guest-agent system extension in Talos)

  # Don't wait for guest agent during VM creation (agent won't be available until Talos boots)
  define_connection_info = false

  tags = join(";", [
    "talos",
    "gpu-worker",
    var.cluster_name,
    "terraform-managed",
    "gpu-mapped"
  ])

  lifecycle {
    ignore_changes = [
      network[0].macaddr,
      description,
    ]
  }
}
