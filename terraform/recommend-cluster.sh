#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Proxmox Cluster Resource Discovery & VM Recommendation Tool
# =============================================================================
# This script queries your Proxmox servers and recommends optimal VM
# configurations based on available resources (CPU, RAM, storage).
#
# Prerequisites:
# - Proxmox API tokens already created (see README.md)
# - jq installed: sudo apt-get install jq
# - curl installed (usually pre-installed)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}\")\" && pwd)"

echo "========================================"
echo "Proxmox Cluster Resource Discovery"
echo "========================================"
echo ""

# =============================================================================
# Configuration
# =============================================================================

# Proxmox servers (customize these)
declare -A PROXMOX_SERVERS

echo "This tool will query your Proxmox servers and recommend VM configurations."
echo ""
echo "You'll need:"
echo "  - Proxmox server IP/hostname"
echo "  - API token ID (e.g., terraform@pve!terraform)"
echo "  - API token secret"
echo ""

read -p "How many Proxmox servers do you have? (1-10): " SERVER_COUNT

if [[ ! "$SERVER_COUNT" =~ ^[0-9]+$ ]] || [ "$SERVER_COUNT" -lt 1 ] || [ "$SERVER_COUNT" -gt 10 ]; then
    echo "❌ Invalid server count. Must be between 1 and 10."
    exit 1
fi

# Collect server information
for i in $(seq 1 "$SERVER_COUNT"); do
    echo ""
    echo "--- Server $i ---"
    read -p "Proxmox hostname/IP (e.g., 192.168.10.160): " HOST
    read -p "API token ID (e.g., terraform@pve!terraform): " TOKEN_ID
    read -s -p "API token secret: " TOKEN_SECRET
    echo ""
    read -p "Node name (e.g., pve1): " NODE_NAME

    # Store server info
    PROXMOX_SERVERS["$NODE_NAME"]="$HOST|$TOKEN_ID|$TOKEN_SECRET"
done

echo ""
echo "========================================"
echo "Querying Proxmox Servers..."
echo "========================================"
echo ""

# =============================================================================
# Query Proxmox Resources
# =============================================================================

declare -A NODE_RESOURCES

for NODE in "${!PROXMOX_SERVERS[@]}"; do
    IFS='|' read -r HOST TOKEN_ID TOKEN_SECRET <<< "${PROXMOX_SERVERS[$NODE]}"

    echo "Querying: $NODE ($HOST)..."

    # Query node status
    RESPONSE=$(curl -k -s -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${HOST}:8006/api2/json/nodes/${NODE}/status" || echo "ERROR")

    if [[ "$RESPONSE" == "ERROR" ]]; then
        echo "  ❌ Failed to connect to $NODE"
        echo "     Check API token and network connectivity"
        continue
    fi

    # Parse resources
    CPU_TOTAL=$(echo "$RESPONSE" | jq -r '.data.cpuinfo.cpus // 0')
    CPU_USED=$(echo "$RESPONSE" | jq -r '.data.cpu // 0' | awk '{printf "%.0f", $1 * 100}')

    MEM_TOTAL_BYTES=$(echo "$RESPONSE" | jq -r '.data.memory.total // 0')
    MEM_USED_BYTES=$(echo "$RESPONSE" | jq -r '.data.memory.used // 0')
    MEM_TOTAL_GB=$(echo "scale=2; $MEM_TOTAL_BYTES / 1024 / 1024 / 1024" | bc)
    MEM_USED_GB=$(echo "scale=2; $MEM_USED_BYTES / 1024 / 1024 / 1024" | bc)
    MEM_FREE_GB=$(echo "scale=2; $MEM_TOTAL_GB - $MEM_USED_GB" | bc)

    # Query storage
    STORAGE_RESPONSE=$(curl -k -s -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${HOST}:8006/api2/json/nodes/${NODE}/storage" || echo "ERROR")

    # Find largest storage pool
    LARGEST_STORAGE=""
    LARGEST_SIZE=0

    if [[ "$STORAGE_RESPONSE" != "ERROR" ]]; then
        STORAGES=$(echo "$STORAGE_RESPONSE" | jq -r '.data[] | select(.type == "lvmthin" or .type == "dir" or .type == "lvm") | .storage')

        for STORAGE in $STORAGES; do
            STORAGE_INFO=$(curl -k -s -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
                "https://${HOST}:8006/api2/json/nodes/${NODE}/storage/${STORAGE}/status" || echo "ERROR")

            if [[ "$STORAGE_INFO" != "ERROR" ]]; then
                TOTAL=$(echo "$STORAGE_INFO" | jq -r '.data.total // 0')
                if [ "$TOTAL" -gt "$LARGEST_SIZE" ]; then
                    LARGEST_SIZE=$TOTAL
                    LARGEST_STORAGE=$STORAGE
                fi
            fi
        done
    fi

    STORAGE_TOTAL_GB=$(echo "scale=2; $LARGEST_SIZE / 1024 / 1024 / 1024" | bc)

    # Store results
    NODE_RESOURCES["$NODE"]="$CPU_TOTAL|$MEM_TOTAL_GB|$MEM_FREE_GB|$STORAGE_TOTAL_GB|$LARGEST_STORAGE"

    echo "  ✓ CPUs: $CPU_TOTAL cores"
    echo "  ✓ RAM: ${MEM_TOTAL_GB} GB total (${MEM_FREE_GB} GB free)"
    echo "  ✓ Storage: ${STORAGE_TOTAL_GB} GB ($LARGEST_STORAGE)"
    echo ""
done

# =============================================================================
# Generate Recommendations
# =============================================================================

echo "========================================"
echo "Cluster Recommendations"
echo "========================================"
echo ""

# Calculate total resources
TOTAL_CPU=0
TOTAL_RAM=0
TOTAL_STORAGE=0

for NODE in "${!NODE_RESOURCES[@]}"; do
    IFS='|' read -r CPU RAM FREE_RAM STORAGE STORAGE_NAME <<< "${NODE_RESOURCES[$NODE]}"
    TOTAL_CPU=$((TOTAL_CPU + CPU))
    TOTAL_RAM=$(echo "scale=2; $TOTAL_RAM + $RAM" | bc)
    TOTAL_STORAGE=$(echo "scale=2; $TOTAL_STORAGE + $STORAGE" | bc)
done

echo "Total Cluster Resources:"
echo "  CPUs: $TOTAL_CPU cores"
echo "  RAM: $TOTAL_RAM GB"
echo "  Storage: $TOTAL_STORAGE GB"
echo ""

# Recommend cluster configuration
# Reserve 20% for Proxmox host
USABLE_CPU=$(echo "scale=0; $TOTAL_CPU * 0.8 / 1" | bc)
USABLE_RAM=$(echo "scale=0; $TOTAL_RAM * 0.8 / 1" | bc)
USABLE_STORAGE=$(echo "scale=0; $TOTAL_STORAGE * 0.8 / 1" | bc)

echo "Usable Resources (80% of total, 20% reserved for host):"
echo "  CPUs: $USABLE_CPU cores"
echo "  RAM: $USABLE_RAM GB"
echo "  Storage: $USABLE_STORAGE GB"
echo ""

# Suggest control plane configuration (odd number, 1 per server recommended)
CP_COUNT=$SERVER_COUNT
if [ $((CP_COUNT % 2)) -eq 0 ]; then
    CP_COUNT=$((CP_COUNT + 1))  # Make it odd
fi

# Control planes: 4 cores, 8GB RAM each
CP_CPU=4
CP_RAM=8
CP_OS_DISK=50
CP_DATA_DISK=100

# Calculate remaining resources after control planes
REMAINING_CPU=$((USABLE_CPU - (CP_COUNT * CP_CPU)))
REMAINING_RAM=$((USABLE_RAM - (CP_COUNT * CP_RAM)))

# Suggest worker configuration
# Workers: 8 cores, 16GB RAM each (standard)
WORKER_CPU=8
WORKER_RAM=16
WORKER_OS_DISK=100
WORKER_DATA_DISK=0  # Optional

# How many workers can we fit?
WORKERS_BY_CPU=$((REMAINING_CPU / WORKER_CPU))
WORKERS_BY_RAM=$((REMAINING_RAM / WORKER_RAM))
WORKER_COUNT=$WORKERS_BY_CPU
if [ $WORKERS_BY_RAM -lt $WORKER_COUNT ]; then
    WORKER_COUNT=$WORKERS_BY_RAM
fi

# Cap at reasonable number
if [ $WORKER_COUNT -gt 10 ]; then
    WORKER_COUNT=10
fi

echo "========================================"
echo "RECOMMENDED CONFIGURATION"
echo "========================================"
echo ""
echo "Control Planes: $CP_COUNT (1 per server for HA)"
echo "  - $CP_CPU cores, $CP_RAM GB RAM per node"
echo "  - OS Disk: $CP_OS_DISK GB, Data Disk: $CP_DATA_DISK GB"
echo "  - Total: $((CP_COUNT * CP_CPU)) cores, $((CP_COUNT * CP_RAM)) GB RAM"
echo ""
echo "Workers: $WORKER_COUNT"
echo "  - $WORKER_CPU cores, $WORKER_RAM GB RAM per node"
echo "  - OS Disk: $WORKER_OS_DISK GB, Data Disk: $WORKER_DATA_DISK GB (optional)"
echo "  - Total: $((WORKER_COUNT * WORKER_CPU)) cores, $((WORKER_COUNT * WORKER_RAM)) GB RAM"
echo ""
echo "TOTAL ALLOCATION:"
echo "  CPUs: $((CP_COUNT * CP_CPU + WORKER_COUNT * WORKER_CPU)) / $USABLE_CPU cores"
echo "  RAM: $((CP_COUNT * CP_RAM + WORKER_COUNT * WORKER_RAM)) / $USABLE_RAM GB"
echo ""

# =============================================================================
# Generate terraform.tfvars
# =============================================================================

read -p "Generate terraform.tfvars with this configuration? (yes/no): " GENERATE

if [[ "$GENERATE" != "yes" ]]; then
    echo "Configuration not generated. You can re-run this script anytime."
    exit 0
fi

echo ""
echo "Generating terraform.tfvars..."

cat > "$SCRIPT_DIR/terraform.tfvars" <<EOF
# =============================================================================
# Auto-generated by recommend-cluster.sh
# Generated: $(date)
# =============================================================================

# =============================================================================
# Proxmox Servers Configuration
# =============================================================================

proxmox_servers = {
EOF

# Add each Proxmox server
SERVER_INDEX=1
for NODE in "${!NODE_RESOURCES[@]}"; do
    IFS='|' read -r CPU RAM FREE_RAM STORAGE STORAGE_NAME <<< "${NODE_RESOURCES[$NODE]}"
    IFS='|' read -r HOST TOKEN_ID TOKEN_SECRET <<< "${PROXMOX_SERVERS[$NODE]}"

    cat >> "$SCRIPT_DIR/terraform.tfvars" <<EOF
  "$NODE" = {
    api_url          = "https://${HOST}:8006/api2/json"
    api_token_id     = "$TOKEN_ID"
    api_token_secret = "$TOKEN_SECRET"
    node_name        = "$NODE"
    tls_insecure     = true
    storage_os       = "$STORAGE_NAME"
    storage_data     = "$STORAGE_NAME"
    network_bridge   = "vmbr0"
  }
EOF

    if [ $SERVER_INDEX -lt $SERVER_COUNT ]; then
        echo "" >> "$SCRIPT_DIR/terraform.tfvars"
    fi

    SERVER_INDEX=$((SERVER_INDEX + 1))
done

cat >> "$SCRIPT_DIR/terraform.tfvars" <<'EOF'
}

# =============================================================================
# Network Configuration
# =============================================================================

network_config = {
  subnet      = "192.168.10.0/24"
  gateway     = "192.168.10.1"
  dns_servers = ["1.1.1.1", "8.8.8.8"]
  vlan_id     = 0
}

# =============================================================================
# Talos Configuration
# =============================================================================

talos_template_name = "talos-template"
cluster_name        = "talos-cluster"

# =============================================================================
# Control Plane Configuration
# =============================================================================

control_planes = [
EOF

# Generate control plane VMs
NODE_ARRAY=(${!NODE_RESOURCES[@]})
for i in $(seq 1 $CP_COUNT); do
    NODE_INDEX=$(( (i - 1) % SERVER_COUNT ))
    NODE="${NODE_ARRAY[$NODE_INDEX]}"
    IP_SUFFIX=$((99 + i))

    cat >> "$SCRIPT_DIR/terraform.tfvars" <<EOF
  {
    name              = "talos-cp-$i"
    proxmox_server    = "$NODE"
    ip_address        = "192.168.10.$IP_SUFFIX"
    mac_address       = ""  # Auto-generated
    cpu_cores         = $CP_CPU
    memory_mb         = $((CP_RAM * 1024))
    os_disk_size_gb   = $CP_OS_DISK
    data_disk_size_gb = $CP_DATA_DISK
  }
EOF

    if [ $i -lt $CP_COUNT ]; then
        echo "" >> "$SCRIPT_DIR/terraform.tfvars"
    fi
done

cat >> "$SCRIPT_DIR/terraform.tfvars" <<'EOF'
]

# =============================================================================
# Worker Configuration
# =============================================================================

workers = [
EOF

# Generate worker VMs
for i in $(seq 1 $WORKER_COUNT); do
    NODE_INDEX=$(( (i - 1) % SERVER_COUNT ))
    NODE="${NODE_ARRAY[$NODE_INDEX]}"
    IP_SUFFIX=$((109 + i))

    cat >> "$SCRIPT_DIR/terraform.tfvars" <<EOF
  {
    name              = "talos-worker-$i"
    proxmox_server    = "$NODE"
    ip_address        = "192.168.10.$IP_SUFFIX"
    mac_address       = ""  # Auto-generated
    cpu_cores         = $WORKER_CPU
    memory_mb         = $((WORKER_RAM * 1024))
    os_disk_size_gb   = $WORKER_OS_DISK
    data_disk_size_gb = $WORKER_DATA_DISK
  }
EOF

    if [ $i -lt $WORKER_COUNT ]; then
        echo "" >> "$SCRIPT_DIR/terraform.tfvars"
    fi
done

cat >> "$SCRIPT_DIR/terraform.tfvars" <<'EOF'
]

# =============================================================================
# GPU Worker Configuration (Optional)
# =============================================================================

# gpu_workers = [
#   {
#     name              = "talos-gpu-1"
#     proxmox_server    = "pve2"  # Server with GPU
#     ip_address        = "192.168.10.120"
#     mac_address       = ""
#     cpu_cores         = 16
#     memory_mb         = 32768
#     os_disk_size_gb   = 100
#     data_disk_size_gb = 500
#     gpu_pci_id        = "01:00"  # Find with: lspci | grep -i nvidia
#   }
# ]
gpu_workers = []
EOF

echo ""
echo "✓ Generated: terraform.tfvars"
echo ""
echo "========================================"
echo "Next Steps"
echo "========================================"
echo ""
echo "1. Review and customize terraform.tfvars:"
echo "   nano terraform.tfvars"
echo ""
echo "2. Adjust IP addresses if needed (default: 192.168.10.0/24)"
echo ""
echo "3. Add GPU workers if you have GPUs (uncomment and configure)"
echo ""
echo "4. Initialize and apply Terraform:"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "5. Configure DHCP reservations:"
echo "   terraform output dhcp_reservations_table"
echo ""

echo "========================================"
echo "Resource Utilization"
echo "========================================"
echo ""

for NODE in "${!NODE_RESOURCES[@]}"; do
    IFS='|' read -r CPU RAM FREE_RAM STORAGE STORAGE_NAME <<< "${NODE_RESOURCES[$NODE]}"

    # Calculate VMs on this node
    VMS_ON_NODE=0
    CPU_ALLOCATED=0
    RAM_ALLOCATED=0

    # Count control planes
    for i in $(seq 1 $CP_COUNT); do
        NODE_INDEX=$(( (i - 1) % SERVER_COUNT ))
        if [ "${NODE_ARRAY[$NODE_INDEX]}" == "$NODE" ]; then
            VMS_ON_NODE=$((VMS_ON_NODE + 1))
            CPU_ALLOCATED=$((CPU_ALLOCATED + CP_CPU))
            RAM_ALLOCATED=$((RAM_ALLOCATED + CP_RAM))
        fi
    done

    # Count workers
    for i in $(seq 1 $WORKER_COUNT); do
        NODE_INDEX=$(( (i - 1) % SERVER_COUNT ))
        if [ "${NODE_ARRAY[$NODE_INDEX]}" == "$NODE" ]; then
            VMS_ON_NODE=$((VMS_ON_NODE + 1))
            CPU_ALLOCATED=$((CPU_ALLOCATED + WORKER_CPU))
            RAM_ALLOCATED=$((RAM_ALLOCATED + WORKER_RAM))
        fi
    done

    CPU_PERCENT=$(echo "scale=1; $CPU_ALLOCATED / $CPU * 100" | bc)
    RAM_PERCENT=$(echo "scale=1; $RAM_ALLOCATED / $RAM * 100" | bc)

    echo "$NODE:"
    echo "  VMs: $VMS_ON_NODE"
    echo "  CPU: ${CPU_ALLOCATED}/${CPU} cores (${CPU_PERCENT}%)"
    echo "  RAM: ${RAM_ALLOCATED}/${RAM} GB (${RAM_PERCENT}%)"
    echo ""
done
