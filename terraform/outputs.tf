# Control Plane Outputs
output "control_plane_vms" {
  description = "Control plane VM details"
  value = {
    for vm in proxmox_vm_qemu.control_plane : vm.name => {
      id        = vm.id
      ip_address = vm.default_ipv4_address
    }
  }
}

# Worker Outputs
output "worker_vms" {
  description = "Worker VM details"
  value = {
    for vm in proxmox_vm_qemu.worker : vm.name => {
      id        = vm.id
      ip_address = vm.default_ipv4_address
    }
  }
}

# GPU Worker Outputs
output "gpu_worker_vms" {
  description = "GPU worker VM details"
  value = {
    for vm in proxmox_vm_qemu.gpu_worker : vm.name => {
      id        = vm.id
      ip_address = vm.default_ipv4_address
    }
  }
}

# All VMs summary
output "all_vms" {
  description = "Summary of all VMs created"
  value = {
    control_plane_count = var.control_plane_count
    worker_count       = var.worker_count
    gpu_worker_count   = var.gpu_worker_count
    total_count        = var.control_plane_count + var.worker_count + var.gpu_worker_count
  }
}
