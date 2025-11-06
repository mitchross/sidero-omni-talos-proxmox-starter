terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = var.proxmox_tls_insecure
}

# Control Plane VMs
resource "proxmox_vm_qemu" "control_plane" {
  count       = var.control_plane_count
  name        = "${var.cluster_name}-cp-${count.index + 1}"
  target_node = var.proxmox_node
  
  clone = var.talos_template_name
  
  cores   = var.control_plane_cpu
  memory  = var.control_plane_memory
  scsihw  = "virtio-scsi-pci"
  
  disk {
    size    = "${var.control_plane_disk}G"
    type    = "scsi"
    storage = var.proxmox_storage
  }
  
  network {
    model  = "virtio"
    bridge = var.proxmox_bridge
  }
  
  onboot = true
  agent  = 1
  
  tags = "talos,control-plane,${var.cluster_name}"
}

# Regular Worker VMs
resource "proxmox_vm_qemu" "worker" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  target_node = var.proxmox_node
  
  clone = var.talos_template_name
  
  cores   = var.worker_cpu
  memory  = var.worker_memory
  scsihw  = "virtio-scsi-pci"
  
  disk {
    size    = "${var.worker_disk}G"
    type    = "scsi"
    storage = var.proxmox_storage
  }
  
  network {
    model  = "virtio"
    bridge = var.proxmox_bridge
  }
  
  onboot = true
  agent  = 1
  
  tags = "talos,worker,${var.cluster_name}"
}

# GPU Worker VMs
resource "proxmox_vm_qemu" "gpu_worker" {
  count       = var.gpu_worker_count
  name        = "${var.cluster_name}-gpu-worker-${count.index + 1}"
  target_node = var.proxmox_node
  
  clone = var.talos_template_name
  
  cores   = var.gpu_worker_cpu
  memory  = var.gpu_worker_memory
  scsihw  = "virtio-scsi-pci"
  
  disk {
    size    = "${var.gpu_worker_disk}G"
    type    = "scsi"
    storage = var.proxmox_storage
  }
  
  network {
    model  = "virtio"
    bridge = var.proxmox_bridge
  }
  
  # GPU passthrough configuration
  # Uncomment and configure based on your GPU setup
  # hostpci0 = "01:00,pcie=1"
  
  onboot = true
  agent  = 1
  
  tags = "talos,gpu-worker,${var.cluster_name}"
}
