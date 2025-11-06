# =============================================================================
# Terraform and Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
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
      hostname        = vm.name
      role            = vm.role
      proxmox_server  = vm.proxmox_server
      proxmox_node    = var.proxmox_servers[vm.proxmox_server].node_name
      ip_address      = vm.ip_address
      mac_address     = vm.mac_address
      cpu_cores       = vm.cpu_cores
      memory_mb       = vm.memory_mb
      os_disk_gb      = vm.os_disk_size_gb
      data_disk_gb    = vm.data_disk_size_gb
      has_data_disk   = vm.data_disk_size_gb > 0
      gateway         = var.network_config.gateway
      dns_servers     = var.network_config.dns_servers
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
  target_node = var.proxmox_servers[each.value.proxmox_server].node_name
  desc        = "Talos Control Plane - Managed by Terraform"

  # Clone from Talos template
  clone = var.talos_template_name

  # Full clone for independent VMs
  full_clone = true

  # VM Resources
  cores   = each.value.cpu_cores
  sockets = 1
  memory  = each.value.memory_mb

  # SCSI Controller
  scsihw = "virtio-scsi-single"

  # Boot order
  boot = "order=scsi0"

  # OS Disk (scsi0)
  disk {
    slot    = 0
    size    = "${each.value.os_disk_size_gb}G"
    type    = "scsi"
    storage = var.proxmox_servers[each.value.proxmox_server].storage_os
    iothread = 1
    discard = "on"
    ssd     = 1
  }

  # Data Disk (scsi1) - Only if size > 0
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      slot    = 1
      size    = "${each.value.data_disk_size_gb}G"
      type    = "scsi"
      storage = var.proxmox_servers[each.value.proxmox_server].storage_data
      iothread = 1
      discard = "on"
      ssd     = 1
    }
  }

  # Network Configuration
  network {
    model   = "virtio"
    bridge  = var.proxmox_servers[each.value.proxmox_server].network_bridge
    macaddr = upper(each.value.mac_address)
    tag     = var.network_config.vlan_id == 0 ? -1 : var.network_config.vlan_id
  }

  # VM Options
  onboot    = var.vm_start_on_boot
  agent     = var.vm_qemu_agent ? 1 : 0
  protection = var.vm_protection

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
      network[0].macaddr,  # MAC address set once
      desc,                 # Description might be modified
    ]
  }
}

# =============================================================================
# Worker VMs
# =============================================================================

resource "proxmox_vm_qemu" "worker" {
  for_each = { for vm in local.workers_with_mac : vm.name => vm }

  name        = each.value.name
  target_node = var.proxmox_servers[each.value.proxmox_server].node_name
  desc        = "Talos Worker - Managed by Terraform"

  clone = var.talos_template_name
  full_clone = true

  cores   = each.value.cpu_cores
  sockets = 1
  memory  = each.value.memory_mb

  scsihw = "virtio-scsi-single"
  boot = "order=scsi0"

  # OS Disk
  disk {
    slot    = 0
    size    = "${each.value.os_disk_size_gb}G"
    type    = "scsi"
    storage = var.proxmox_servers[each.value.proxmox_server].storage_os
    iothread = 1
    discard = "on"
    ssd     = 1
  }

  # Data Disk (optional)
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      slot    = 1
      size    = "${each.value.data_disk_size_gb}G"
      type    = "scsi"
      storage = var.proxmox_servers[each.value.proxmox_server].storage_data
      iothread = 1
      discard = "on"
      ssd     = 1
    }
  }

  network {
    model   = "virtio"
    bridge  = var.proxmox_servers[each.value.proxmox_server].network_bridge
    macaddr = upper(each.value.mac_address)
    tag     = var.network_config.vlan_id == 0 ? -1 : var.network_config.vlan_id
  }

  onboot     = var.vm_start_on_boot
  agent      = var.vm_qemu_agent ? 1 : 0
  protection = var.vm_protection

  tags = join(";", [
    "talos",
    "worker",
    var.cluster_name,
    "terraform-managed"
  ])

  lifecycle {
    ignore_changes = [
      network[0].macaddr,
      desc,
    ]
  }
}

# =============================================================================
# GPU Worker VMs
# =============================================================================

resource "proxmox_vm_qemu" "gpu_worker" {
  for_each = { for vm in local.gpu_workers_with_mac : vm.name => vm }

  name        = each.value.name
  target_node = var.proxmox_servers[each.value.proxmox_server].node_name
  desc        = "Talos GPU Worker - Managed by Terraform - GPU PCI: ${each.value.gpu_pci_id} (Configure manually)"

  clone = var.talos_template_name
  full_clone = true

  cores   = each.value.cpu_cores
  sockets = 1
  memory  = each.value.memory_mb

  scsihw = "virtio-scsi-single"
  boot = "order=scsi0"

  # OS Disk
  disk {
    slot    = 0
    size    = "${each.value.os_disk_size_gb}G"
    type    = "scsi"
    storage = var.proxmox_servers[each.value.proxmox_server].storage_os
    iothread = 1
    discard = "on"
    ssd     = 1
  }

  # Data Disk (typically needed for GPU workloads)
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      slot    = 1
      size    = "${each.value.data_disk_size_gb}G"
      type    = "scsi"
      storage = var.proxmox_servers[each.value.proxmox_server].storage_data
      iothread = 1
      discard = "on"
      ssd     = 1
    }
  }

  network {
    model   = "virtio"
    bridge  = var.proxmox_servers[each.value.proxmox_server].network_bridge
    macaddr = upper(each.value.mac_address)
    tag     = var.network_config.vlan_id == 0 ? -1 : var.network_config.vlan_id
  }

  # GPU Passthrough - MUST be configured manually in Proxmox UI
  # Uncomment after manual GPU configuration:
  # hostpci0 = "${each.value.gpu_pci_id},pcie=1"

  onboot     = var.vm_start_on_boot
  agent      = var.vm_qemu_agent ? 1 : 0
  protection = var.vm_protection

  tags = join(";", [
    "talos",
    "gpu-worker",
    var.cluster_name,
    "terraform-managed",
    "gpu-${each.value.gpu_pci_id}"
  ])

  lifecycle {
    ignore_changes = [
      network[0].macaddr,
      desc,
      # Ignore GPU passthrough changes (configured manually)
      # hostpci0,
    ]
  }
}
