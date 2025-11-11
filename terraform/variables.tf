# =============================================================================
# Proxmox Server Configuration
# =============================================================================

variable "proxmox_servers" {
  description = "Map of Proxmox servers with their connection details"
  type = map(object({
    api_url          = string
    api_token_id     = string
    api_token_secret = string
    node_name        = string
    tls_insecure     = bool

    # Storage configuration per server - defaults for each VM type
    storage_control_plane_os   = string                # Default OS storage for control planes
    storage_control_plane_data = optional(string, "")  # Default data storage for control planes
    storage_worker_os          = string                # Default OS storage for workers
    storage_worker_data        = optional(string, "")  # Default data storage for workers
    storage_gpu_worker_os      = optional(string, "")  # Default OS storage for GPU workers (falls back to worker_os)
    storage_gpu_worker_data    = optional(string, "")  # Default data storage for GPU workers (falls back to worker_data)
    network_bridge             = string                # Network bridge (e.g., vmbr0)
  }))

  # Example:
  # proxmox_servers = {
  #   "pve1" = {
  #     api_url                    = "https://192.168.10.160:8006/api2/json"
  #     api_token_id               = "terraform@pve!terraform"
  #     api_token_secret           = "your-secret-here"
  #     node_name                  = "pve1"
  #     tls_insecure               = true
  #     storage_control_plane_os   = "local-lvm"     # Control planes on local-lvm
  #     storage_control_plane_data = ""              # No data disk for control planes
  #     storage_worker_os          = "local-lvm"     # Workers on local-lvm
  #     storage_worker_data        = "local-lvm"     # Worker data on local-lvm
  #     storage_gpu_worker_os      = "nvme-storage"  # GPU workers on fast storage
  #     storage_gpu_worker_data    = "nvme-storage"  # GPU data on fast storage
  #     network_bridge             = "vmbr0"
  #   }
  #   "pve2" = { ... }
  # }
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "network_config" {
  description = "Network configuration for static IP assignments"
  type = object({
    subnet      = string       # e.g., "192.168.10.0/24"
    gateway     = string       # e.g., "192.168.10.1"
    dns_servers = list(string) # e.g., ["1.1.1.1", "8.8.8.8"]
    vlan_id     = number       # Set to 0 for no VLAN, or VLAN ID
  })

  default = {
    subnet      = "192.168.10.0/24"
    gateway     = "192.168.10.1"
    dns_servers = ["1.1.1.1", "8.8.8.8"]
    vlan_id     = 0
  }
}

# =============================================================================
# Talos Configuration
# =============================================================================

variable "talos_iso" {
  description = "Talos ISO file in Proxmox format: 'storage:iso/filename.iso'. Leave empty to use PXE boot."
  type        = string
  default     = "local:iso/talos-1.11.5.iso"

  # Boot Strategy:
  # - If ISO is provided: VMs boot from ISO first, then disk (order=ide2;scsi0)
  # - If ISO is empty "": VMs boot from disk first, PXE fallback (order=scsi0;net0)
  #
  # To download Talos ISO:
  # 1. Go to https://factory.talos.dev or https://github.com/siderolabs/talos/releases
  # 2. Download the ISO for v1.11.5 (e.g., metal-amd64.iso)
  # 3. Upload to Proxmox: Datacenter → Storage → ISO Images → Upload
  # 4. Rename to: talos-1.11.5.iso
}

variable "talos_gpu_iso" {
  description = "Talos ISO with NVIDIA extensions for GPU workers (Proxmox format: 'storage:iso/filename.iso'). Leave empty to use PXE boot."
  type        = string
  default     = "local:iso/talos-1.11.5-gpu.iso"

  # Factory Image Schematic ID: 6db1f20beb0d74f938132978f24a9e6096928c248969a61f56c43bbe530f274a
  # Direct download: https://factory.talos.dev/image/6db1f20beb0d74f938132978f24a9e6096928c248969a61f56c43bbe530f274a/v1.11.5/metal-amd64.iso
  #
  # This ISO includes:
  # - iscsi-tools, nfsd, qemu-guest-agent, util-linux-tools (standard)
  # - nonfree-kmod-nvidia-production (NVIDIA proprietary drivers)
  # - nvidia-container-toolkit-production (container runtime support)
  #
  # Upload to Proxmox and rename to: talos-1.11.5-gpu.iso
}

variable "talos_version" {
  description = "Talos version for documentation purposes"
  type        = string
  default     = "v1.10.1"
}

variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-cluster"
}

# =============================================================================
# Control Plane Configuration
# =============================================================================

variable "control_planes" {
  description = "List of control plane nodes with their configurations"
  type = list(object({
    name                  = string # e.g., "talos-cp-1"
    proxmox_server        = string # Key from proxmox_servers map
    ip_address            = string # e.g., "192.168.10.100"
    mac_address           = string # e.g., "BC:24:11:01:00:01" or leave empty for auto-generation
    cpu_cores             = number
    memory_mb             = number
    os_disk_size_gb       = number
    data_disk_size_gb     = number               # Set to 0 for no data disk
    storage_os_override   = optional(string, "") # Optional: Override storage_os for this specific node
    storage_data_override = optional(string, "") # Optional: Override storage_data for this specific node
  }))

  # Example:
  # control_planes = [
  #   {
  #     name              = "talos-cp-1"
  #     proxmox_server    = "pve1"
  #     ip_address        = "192.168.10.100"
  #     mac_address       = ""  # Auto-generate
  #     cpu_cores         = 4
  #     memory_mb         = 8192
  #     os_disk_size_gb   = 50
  #     data_disk_size_gb = 100
  #   },
  #   {
  #     name              = "talos-cp-2"
  #     proxmox_server    = "pve2"
  #     ip_address        = "192.168.10.101"
  #     mac_address       = ""
  #     cpu_cores         = 4
  #     memory_mb         = 8192
  #     os_disk_size_gb   = 50
  #     data_disk_size_gb = 100
  #   },
  #   {
  #     name              = "talos-cp-3"
  #     proxmox_server    = "pve3"
  #     ip_address        = "192.168.10.102"
  #     mac_address       = ""
  #     cpu_cores         = 4
  #     memory_mb         = 8192
  #     os_disk_size_gb   = 50
  #     data_disk_size_gb = 100
  #   }
  # ]
}

# =============================================================================
# Worker Configuration
# =============================================================================

variable "workers" {
  description = "List of worker nodes with their configurations"
  type = list(object({
    name                  = string
    proxmox_server        = string
    ip_address            = string
    mac_address           = string
    cpu_cores             = number
    memory_mb             = number
    os_disk_size_gb       = number
    data_disk_size_gb     = number               # Set to 0 for no data disk
    storage_os_override   = optional(string, "") # Optional: Override storage_os for this specific node
    storage_data_override = optional(string, "") # Optional: Override storage_data for this specific node
  }))

  default = []

  # Example:
  # workers = [
  #   {
  #     name              = "talos-worker-1"
  #     proxmox_server    = "pve1"
  #     ip_address        = "192.168.10.110"
  #     mac_address       = ""
  #     cpu_cores         = 8
  #     memory_mb         = 16384
  #     os_disk_size_gb   = 100
  #     data_disk_size_gb = 0  # No data disk
  #   }
  # ]
}

# =============================================================================
# GPU Worker Configuration
# =============================================================================

variable "gpu_workers" {
  description = "List of GPU worker nodes with their configurations"
  type = list(object({
    name                  = string
    proxmox_server        = string
    ip_address            = string
    mac_address           = string
    cpu_cores             = number
    memory_mb             = number
    os_disk_size_gb       = number
    data_disk_size_gb     = number
    gpu_pci_id            = string               # e.g., "01:00" - Configure manually in Proxmox after creation
    storage_os_override   = optional(string, "") # Optional: Override storage_os for this specific node
    storage_data_override = optional(string, "") # Optional: Override storage_data for this specific node
  }))

  default = []

  # Example:
  # gpu_workers = [
  #   {
  #     name              = "talos-gpu-1"
  #     proxmox_server    = "pve2"
  #     ip_address        = "192.168.10.120"
  #     mac_address       = ""
  #     cpu_cores         = 16
  #     memory_mb         = 32768
  #     os_disk_size_gb   = 100
  #     data_disk_size_gb = 500
  #     gpu_pci_id        = "01:00"  # Find with: lspci | grep -i nvidia
  #   }
  # ]
}

# =============================================================================
# MAC Address Configuration
# =============================================================================

variable "mac_address_prefix" {
  description = "Prefix for auto-generated MAC addresses (e.g., 'BC:24:11')"
  type        = string
  default     = "BC:24:11"
}

# =============================================================================
# Advanced Options
# =============================================================================

variable "vm_start_on_boot" {
  description = "Start VMs automatically on Proxmox boot"
  type        = bool
  default     = true
}

variable "vm_qemu_agent" {
  description = "Enable QEMU guest agent (used by Talos via qemu-guest-agent system extension)"
  type        = bool
  default     = true
}

variable "vm_protection" {
  description = "Prevent accidental VM deletion"
  type        = bool
  default     = false
}
