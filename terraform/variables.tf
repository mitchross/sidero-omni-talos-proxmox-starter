# Proxmox Configuration
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = false
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_storage" {
  description = "Proxmox storage pool name"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

# Talos Configuration
variable "talos_template_name" {
  description = "Name of the Talos template VM in Proxmox"
  type        = string
  default     = "talos-template"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-cluster"
}

# Control Plane Configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "control_plane_cpu" {
  description = "CPU cores for control plane nodes"
  type        = number
  default     = 4
}

variable "control_plane_memory" {
  description = "Memory (MB) for control plane nodes"
  type        = number
  default     = 8192
}

variable "control_plane_disk" {
  description = "Disk size (GB) for control plane nodes"
  type        = number
  default     = 50
}

# Worker Configuration
variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "worker_cpu" {
  description = "CPU cores for worker nodes"
  type        = number
  default     = 8
}

variable "worker_memory" {
  description = "Memory (MB) for worker nodes"
  type        = number
  default     = 16384
}

variable "worker_disk" {
  description = "Disk size (GB) for worker nodes"
  type        = number
  default     = 100
}

# GPU Worker Configuration
variable "gpu_worker_count" {
  description = "Number of GPU worker nodes"
  type        = number
  default     = 2
}

variable "gpu_worker_cpu" {
  description = "CPU cores for GPU worker nodes"
  type        = number
  default     = 16
}

variable "gpu_worker_memory" {
  description = "Memory (MB) for GPU worker nodes"
  type        = number
  default     = 32768
}

variable "gpu_worker_disk" {
  description = "Disk size (GB) for GPU worker nodes"
  type        = number
  default     = 200
}
