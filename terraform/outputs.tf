# =============================================================================
# Machine Inventory Output
# =============================================================================

output "machine_inventory" {
  description = "Complete inventory of all machines for omnictl configuration"
  value       = local.machine_inventory
}

output "machine_inventory_json" {
  description = "Machine inventory in JSON format for scripting"
  value       = jsonencode(local.machine_inventory)
}

# =============================================================================
# Network Information
# =============================================================================

output "mac_to_ip_mapping" {
  description = "MAC address to IP address mapping for DHCP reservations"
  value = {
    for vm_name, vm in local.machine_inventory :
    vm.mac_address => {
      ip_address = vm.ip_address
      hostname   = vm.hostname
      role       = vm.role
    }
  }
}

output "dhcp_reservations_table" {
  description = "Formatted DHCP reservations table for easy copy-paste"
  value = join("\n", concat(
    ["# DHCP Reservations for Talos Cluster"],
    ["# MAC Address       | IP Address      | Hostname"],
    ["#-------------------+-----------------+---------------------------"],
    [for vm_name, vm in local.machine_inventory :
      format("%-19s | %-15s | %s", vm.mac_address, vm.ip_address, vm.hostname)
    ]
  ))
}

# =============================================================================
# Control Plane Outputs
# =============================================================================

output "control_plane_vms" {
  description = "Control plane VM details"
  value = {
    for vm_name, vm in local.machine_inventory :
    vm_name => vm if vm.role == "control-plane"
  }
}

output "control_plane_count" {
  description = "Number of control plane nodes"
  value       = length([for vm_name, vm in local.machine_inventory : vm if vm.role == "control-plane"])
}

output "control_plane_endpoints" {
  description = "Control plane IP addresses for cluster endpoint"
  value       = [for vm_name, vm in local.machine_inventory : vm.ip_address if vm.role == "control-plane"]
}

# =============================================================================
# Worker Outputs
# =============================================================================

output "worker_vms" {
  description = "Worker VM details"
  value = {
    for vm_name, vm in local.machine_inventory :
    vm_name => vm if vm.role == "worker"
  }
}

output "worker_count" {
  description = "Number of worker nodes"
  value       = length([for vm_name, vm in local.machine_inventory : vm if vm.role == "worker"])
}

# =============================================================================
# GPU Worker Outputs
# =============================================================================

output "gpu_worker_vms" {
  description = "GPU worker VM details"
  value = {
    for vm_name, vm in local.machine_inventory :
    vm_name => vm if vm.role == "gpu-worker"
  }
}

output "gpu_worker_count" {
  description = "Number of GPU worker nodes"
  value       = length([for vm_name, vm in local.machine_inventory : vm if vm.role == "gpu-worker"])
}

output "gpu_configuration_needed" {
  description = "List of GPU workers requiring manual GPU passthrough configuration"
  value = [
    for vm_name, vm in local.machine_inventory :
    {
      hostname   = vm.hostname
      server     = vm.proxmox_server
      node       = vm.proxmox_node
      gpu_pci_id = vm.gpu_pci_id
      instructions = "1. SSH to ${vm.proxmox_node}, 2. Run: qm set <VM_ID> -hostpci0 ${vm.gpu_pci_id},pcie=1"
    }
    if vm.role == "gpu-worker" && vm.gpu_pci_id != ""
  ]
}

# =============================================================================
# Distribution by Server
# =============================================================================

output "vms_by_server" {
  description = "VMs distributed across Proxmox servers"
  value = {
    for server_key in keys(var.proxmox_servers) :
    server_key => [
      for vm_name, vm in local.machine_inventory :
      {
        name = vm.hostname
        role = vm.role
        ip   = vm.ip_address
      }
      if vm.proxmox_server == server_key
    ]
  }
}

# =============================================================================
# Summary Information
# =============================================================================

output "cluster_summary" {
  description = "Overall cluster summary"
  value = {
    cluster_name        = var.cluster_name
    total_vms           = length(local.machine_inventory)
    control_plane_count = length([for vm_name, vm in local.machine_inventory : vm if vm.role == "control-plane"])
    worker_count        = length([for vm_name, vm in local.machine_inventory : vm if vm.role == "worker"])
    gpu_worker_count    = length([for vm_name, vm in local.machine_inventory : vm if vm.role == "gpu-worker"])
    proxmox_servers     = keys(var.proxmox_servers)
    network_subnet      = var.network_config.subnet
    network_gateway     = var.network_config.gateway
  }
}

# =============================================================================
# Omnictl Config Generation Helper
# =============================================================================

output "omnictl_ready" {
  description = "Instructions for next steps with omnictl"
  value = <<-EOT

  ✅ Terraform has created ${length(local.machine_inventory)} VMs across ${length(keys(var.proxmox_servers))} Proxmox server(s).

  Next Steps:

  1. Configure DHCP Reservations:
     Run: terraform output dhcp_reservations_table
     Add these reservations to your router/DHCP server (Firewalla)

  2. Wait for VMs to boot and register with Omni:
     - VMs will boot with Talos
     - Talos will connect to Omni via SideroLink
     - Check Omni UI for registered machines

  3. Generate omnictl machine configurations:
     cd ../scripts
     ./discover-machines.sh

  4. Apply machine configurations:
     ./apply-machine-configs.sh

  5. (GPU Workers Only) Manually configure GPU passthrough:
     Run: terraform output gpu_configuration_needed

  For detailed instructions, see: ../terraform/README.md

  EOT
}

# =============================================================================
# Machine Config Templates Export
# =============================================================================

output "machine_configs_data" {
  description = "Data structure for generating Talos machine configs"
  sensitive   = false
  value = {
    for vm_name, vm in local.machine_inventory :
    vm_name => {
      # Network configuration for Talos
      network = {
        hostname = vm.hostname
        interfaces = [{
          interface = "eth0"
          dhcp      = false  # We set static IP
          addresses = ["${vm.ip_address}/24"]
          routes = [{
            network = "0.0.0.0/0"
            gateway = vm.gateway
          }]
        }]
        nameservers = vm.dns_servers
      }

      # Disk configuration
      disks = {
        os_disk = {
          device = "/dev/sda"
          size   = vm.os_disk_gb
        }
        data_disk = vm.has_data_disk ? {
          device = "/dev/sdb"
          size   = vm.data_disk_gb
          mount  = "/var/lib/longhorn"  # For Longhorn storage
        } : null
      }

      # Role and resources
      role = vm.role
      resources = {
        cpu_cores = vm.cpu_cores
        memory_mb = vm.memory_mb
      }

      # MAC address for machine identification
      mac_address = vm.mac_address
    }
  }
}
