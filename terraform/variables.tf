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

    # Storage configuration per server
    storage_os     = string # Storage pool for OS disks
    storage_data   = string # Storage pool for data disks (optional)
    network_bridge = string # Network bridge (e.g., vmbr0)
  }))

  # Example:
  # proxmox_servers = {
  #   "pve1" = {
  #     api_url          = "https://192.168.10.160:8006/api2/json"
  #     api_token_id     = "terraform@pve!terraform"
  #     api_token_secret = "your-secret-here"
  #     node_name        = "pve1"
  #     tls_insecure     = true
  #     storage_os       = "local-lvm"
  #     storage_data     = "local-lvm"  # Can be same or different
  #     network_bridge   = "vmbr0"
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
  description = "Talos ISO file in Proxmox format: 'storage:iso/filename.iso'"
  type        = string
  default     = "local:iso/talos-amd64.iso"

  # To download Talos ISO:
  # 1. Go to https://factory.talos.dev or https://github.com/siderolabs/talos/releases
  # 2. Download the ISO (e.g., metal-amd64.iso)
  # 3. Upload to Proxmox: Datacenter → Storage → ISO Images → Upload
  # 4. Set this variable to: "local:iso/metal-amd64.iso" or your storage:iso/filename
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
    name              = string # e.g., "talos-cp-1"
    proxmox_server    = string # Key from proxmox_servers map
    ip_address        = string # e.g., "192.168.10.100"
    mac_address       = string # e.g., "BC:24:11:01:00:01" or leave empty for auto-generation
    cpu_cores         = number
    memory_mb         = number
    os_disk_size_gb   = number
    data_disk_size_gb = number # Set to 0 for no data disk
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
    name              = string
    proxmox_server    = string
    ip_address        = string
    mac_address       = string
    cpu_cores         = number
    memory_mb         = number
    os_disk_size_gb   = number
    data_disk_size_gb = number # Set to 0 for no data disk
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
    name              = string
    proxmox_server    = string
    ip_address        = string
    mac_address       = string
    cpu_cores         = number
    memory_mb         = number
    os_disk_size_gb   = number
    data_disk_size_gb = number
    gpu_pci_id        = string # e.g., "01:00" - Configure manually in Proxmox after creation
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
  description = "Enable QEMU guest agent (not used by Talos, but safe to enable)"
  type        = bool
  default     = false
}

variable "vm_protection" {
  description = "Prevent accidental VM deletion"
  type        = bool
  default     = false
}
