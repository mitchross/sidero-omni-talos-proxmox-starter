#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Proxmox Cluster Resource Discovery & VM Recommendation Tool
# =============================================================================
# This script SSH's into your Proxmox servers, queries actual resources,
# and dynamically calculates optimal VM configurations.
#
# Prerequisites:
# - SSH access to Proxmox servers (key-based auth recommended)
# - bc for floating point math: sudo apt-get install bc
# - jq for JSON: sudo apt-get install jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Proxmox Cluster Resource Discovery"
echo "Dynamic Resource-Based VM Calculator"
echo "========================================"
echo ""

# =============================================================================
# Configuration
# =============================================================================

declare -A PROXMOX_SERVERS
declare -A NODE_RESOURCES

echo "This tool will SSH into your Proxmox servers and calculate optimal VM configs."
echo ""
echo "Prerequisites:"
echo "  - SSH access to Proxmox servers (as root)"
echo "  - Recommended: SSH key-based authentication"
echo ""

read -p "How many Proxmox servers? (1-10): " SERVER_COUNT

if [[ ! "$SERVER_COUNT" =~ ^[0-9]+$ ]] || [ "$SERVER_COUNT" -lt 1 ] || [ "$SERVER_COUNT" -gt 10 ]; then
    echo "❌ Invalid count. Must be 1-10."
    exit 1
fi

# Collect server information
echo ""
for i in $(seq 1 "$SERVER_COUNT"); do
    echo "--- Server $i ---"
    read -p "Hostname/IP (e.g., 192.168.10.160): " HOST
    read -p "SSH user (default: root): " SSH_USER
    SSH_USER=${SSH_USER:-root}
    read -p "Node name (e.g., pve1): " NODE_NAME

    # Test SSH connection
    echo -n "Testing SSH connection to $HOST... "
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${SSH_USER}@${HOST}" "echo OK" &>/dev/null; then
        echo "✓ Connected"
    else
        echo "❌ Failed"
        echo "Please ensure SSH key-based auth is set up:"
        echo "  ssh-copy-id ${SSH_USER}@${HOST}"
        exit 1
    fi

    PROXMOX_SERVERS["$NODE_NAME"]="${SSH_USER}@${HOST}"
    echo ""
done

echo "========================================"
echo "Querying Resources..."
echo "========================================"
echo ""

# =============================================================================
# Query Proxmox Resources via SSH
# =============================================================================

for NODE in "${!PROXMOX_SERVERS[@]}"; do
    SSH_HOST="${PROXMOX_SERVERS[$NODE]}"

    echo "Querying: $NODE ($SSH_HOST)..."

    # Get CPU info
    CPU_TOTAL=$(ssh "$SSH_HOST" "nproc")
    CPU_USAGE=$(ssh "$SSH_HOST" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1")
    CPU_AVAILABLE=$(echo "scale=0; $CPU_TOTAL * (100 - $CPU_USAGE) / 100" | bc)

    # Get memory info (in GB)
    MEM_INFO=$(ssh "$SSH_HOST" "free -g | grep Mem")
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    MEM_AVAILABLE=$(echo "$MEM_INFO" | awk '{print $7}')

    # Get storage info for largest pool
    STORAGE_INFO=$(ssh "$SSH_HOST" "pvs --noheadings --units g -o pv_name,vg_name,pv_size,pv_free 2>/dev/null | head -1" || echo "")

    if [[ -n "$STORAGE_INFO" ]]; then
        STORAGE_TOTAL=$(echo "$STORAGE_INFO" | awk '{print $3}' | sed 's/[^0-9.]//g')
        STORAGE_FREE=$(echo "$STORAGE_INFO" | awk '{print $4}' | sed 's/[^0-9.]//g')
        STORAGE_NAME=$(echo "$STORAGE_INFO" | awk '{print $2}')
    else
        # Fallback to df
        STORAGE_INFO=$(ssh "$SSH_HOST" "df -BG / | tail -1")
        STORAGE_TOTAL=$(echo "$STORAGE_INFO" | awk '{print $2}' | sed 's/G//')
        STORAGE_FREE=$(echo "$STORAGE_INFO" | awk '{print $4}' | sed 's/G//')
        STORAGE_NAME="local"
    fi

    # Store results
    NODE_RESOURCES["$NODE"]="${CPU_TOTAL}|${CPU_AVAILABLE}|${MEM_TOTAL}|${MEM_AVAILABLE}|${STORAGE_TOTAL}|${STORAGE_FREE}|${STORAGE_NAME}"

    echo "  ✓ CPU: $CPU_TOTAL cores ($CPU_AVAILABLE available after current load)"
    echo "  ✓ RAM: ${MEM_TOTAL}GB total (${MEM_AVAILABLE}GB available)"
    echo "  ✓ Storage: ${STORAGE_TOTAL}GB total (${STORAGE_FREE}GB free) [$STORAGE_NAME]"
    echo ""
done

# =============================================================================
# Calculate Total Cluster Resources
# =============================================================================

echo "========================================"
echo "Cluster Analysis"
echo "========================================"
echo ""

TOTAL_CPU=0
TOTAL_RAM=0
TOTAL_STORAGE=0
AVAIL_CPU=0
AVAIL_RAM=0
AVAIL_STORAGE=0

for NODE in "${!NODE_RESOURCES[@]}"; do
    IFS='|' read -r CPU_TOTAL CPU_AVAIL RAM_TOTAL RAM_AVAIL STOR_TOTAL STOR_AVAIL STOR_NAME <<< "${NODE_RESOURCES[$NODE]}"

    TOTAL_CPU=$((TOTAL_CPU + CPU_TOTAL))
    TOTAL_RAM=$((TOTAL_RAM + RAM_TOTAL))
    TOTAL_STORAGE=$(echo "scale=0; $TOTAL_STORAGE + $STOR_TOTAL" | bc)

    AVAIL_CPU=$((AVAIL_CPU + CPU_AVAIL))
    AVAIL_RAM=$((AVAIL_RAM + RAM_AVAIL))
    AVAIL_STORAGE=$(echo "scale=0; $AVAIL_STORAGE + $STOR_AVAIL" | bc)
done

echo "Total Cluster Resources:"
echo "  CPU: $TOTAL_CPU cores ($AVAIL_CPU available)"
echo "  RAM: ${TOTAL_RAM}GB (${AVAIL_RAM}GB available)"
echo "  Storage: ${TOTAL_STORAGE}GB (${AVAIL_STORAGE}GB free)"
echo ""

# Reserve 20% headroom for host and operations
USABLE_CPU=$(echo "scale=0; $AVAIL_CPU * 0.8 / 1" | bc)
USABLE_RAM=$(echo "scale=0; $AVAIL_RAM * 0.8 / 1" | bc)
USABLE_STORAGE=$(echo "scale=0; $AVAIL_STORAGE * 0.8 / 1" | bc)

echo "Usable Resources (80% of available, 20% reserved):"
echo "  CPU: $USABLE_CPU cores"
echo "  RAM: ${USABLE_RAM}GB"
echo "  Storage: ${USABLE_STORAGE}GB"
echo ""

# =============================================================================
# Dynamic VM Configuration Calculation
# =============================================================================

echo "========================================"
echo "Calculating Optimal VM Configuration"
echo "========================================"
echo ""

# Control planes: 1 per server for HA (odd total)
CP_COUNT=$SERVER_COUNT
if [ $((CP_COUNT % 2)) -eq 0 ]; then
    CP_COUNT=$((CP_COUNT + 1))
fi

# Dynamically size control planes based on available resources
# Minimum: 2 cores, 4GB RAM
# Target: 4 cores, 8GB RAM
# Maximum: 8 cores, 16GB RAM

if [ "$USABLE_CPU" -lt $((CP_COUNT * 4)) ] || [ "$USABLE_RAM" -lt $((CP_COUNT * 8)) ]; then
    # Constrained resources - use smaller CPs
    CP_CPU=2
    CP_RAM=4
    echo "⚠️  Limited resources detected - using minimal control plane size"
elif [ "$USABLE_CPU" -ge $((CP_COUNT * 8)) ] && [ "$USABLE_RAM" -ge $((CP_COUNT * 16)) ]; then
    # Abundant resources - use larger CPs
    CP_CPU=8
    CP_RAM=16
    echo "✓ Abundant resources - using enhanced control plane size"
else
    # Standard configuration
    CP_CPU=4
    CP_RAM=8
    echo "✓ Standard resources - using recommended control plane size"
fi

# Disk sizing based on available storage
if [ "$(echo "$USABLE_STORAGE > 500" | bc)" -eq 1 ]; then
    CP_OS_DISK=50
    CP_DATA_DISK=100
else
    CP_OS_DISK=30
    CP_DATA_DISK=50
    echo "⚠️  Limited storage - reducing disk sizes"
fi

# Calculate remaining resources after control planes
REMAINING_CPU=$((USABLE_CPU - (CP_COUNT * CP_CPU)))
REMAINING_RAM=$((USABLE_RAM - (CP_COUNT * CP_RAM)))

echo ""
echo "After allocating $CP_COUNT control planes:"
echo "  Remaining CPU: $REMAINING_CPU cores"
echo "  Remaining RAM: ${REMAINING_RAM}GB"
echo ""

# Dynamically size workers based on remaining resources
# Calculate optimal worker size to maximize utilization

# Start with target worker size based on total cluster capacity
AVG_CPU_PER_SERVER=$((TOTAL_CPU / SERVER_COUNT))

if [ "$AVG_CPU_PER_SERVER" -le 8 ]; then
    # Small servers: smaller workers
    TARGET_WORKER_CPU=4
    TARGET_WORKER_RAM=8
elif [ "$AVG_CPU_PER_SERVER" -ge 24 ]; then
    # Large servers: larger workers for better efficiency
    TARGET_WORKER_CPU=8
    TARGET_WORKER_RAM=16
else
    # Medium servers: standard workers
    TARGET_WORKER_CPU=8
    TARGET_WORKER_RAM=16
fi

# Calculate how many workers we can fit
WORKERS_BY_CPU=$((REMAINING_CPU / TARGET_WORKER_CPU))
WORKERS_BY_RAM=$((REMAINING_RAM / TARGET_WORKER_RAM))

WORKER_COUNT=$WORKERS_BY_CPU
if [ "$WORKERS_BY_RAM" -lt "$WORKER_COUNT" ]; then
    WORKER_COUNT=$WORKERS_BY_RAM
fi

# If we can't fit any workers, try smaller size
if [ "$WORKER_COUNT" -eq 0 ]; then
    TARGET_WORKER_CPU=2
    TARGET_WORKER_RAM=4
    WORKERS_BY_CPU=$((REMAINING_CPU / TARGET_WORKER_CPU))
    WORKERS_BY_RAM=$((REMAINING_RAM / TARGET_WORKER_RAM))
    WORKER_COUNT=$WORKERS_BY_CPU
    if [ "$WORKERS_BY_RAM" -lt "$WORKER_COUNT" ]; then
        WORKER_COUNT=$WORKERS_BY_RAM
    fi
    echo "⚠️  Adjusting worker size to fit: ${TARGET_WORKER_CPU} cores, ${TARGET_WORKER_RAM}GB RAM"
fi

# Cap at reasonable maximum
if [ "$WORKER_COUNT" -gt 20 ]; then
    WORKER_COUNT=20
    echo "⚠️  Capping workers at 20 for manageability"
fi

WORKER_CPU=$TARGET_WORKER_CPU
WORKER_RAM=$TARGET_WORKER_RAM

# Worker disk sizing
if [ "$(echo "$USABLE_STORAGE > 1000" | bc)" -eq 1 ]; then
    WORKER_OS_DISK=100
    WORKER_DATA_DISK=200
elif [ "$(echo "$USABLE_STORAGE > 500" | bc)" -eq 1 ]; then
    WORKER_OS_DISK=80
    WORKER_DATA_DISK=100
else
    WORKER_OS_DISK=50
    WORKER_DATA_DISK=0
    echo "⚠️  Limited storage - workers will not have data disks"
fi

# Calculate actual utilization
TOTAL_CPU_ALLOCATED=$((CP_COUNT * CP_CPU + WORKER_COUNT * WORKER_CPU))
TOTAL_RAM_ALLOCATED=$((CP_COUNT * CP_RAM + WORKER_COUNT * WORKER_RAM))

CPU_UTIL=$(echo "scale=1; $TOTAL_CPU_ALLOCATED * 100 / $USABLE_CPU" | bc)
RAM_UTIL=$(echo "scale=1; $TOTAL_RAM_ALLOCATED * 100 / $USABLE_RAM" | bc)

echo ""
echo "========================================"
echo "RECOMMENDED CONFIGURATION"
echo "========================================"
echo ""
echo "Control Planes: $CP_COUNT"
echo "  Resources: ${CP_CPU} cores, ${CP_RAM}GB RAM each"
echo "  Disks: OS=${CP_OS_DISK}GB, Data=${CP_DATA_DISK}GB"
echo "  Total: $((CP_COUNT * CP_CPU)) cores, $((CP_COUNT * CP_RAM))GB RAM"
echo ""
echo "Workers: $WORKER_COUNT"
echo "  Resources: ${WORKER_CPU} cores, ${WORKER_RAM}GB RAM each"
echo "  Disks: OS=${WORKER_OS_DISK}GB, Data=${WORKER_DATA_DISK}GB"
echo "  Total: $((WORKER_COUNT * WORKER_CPU)) cores, $((WORKER_COUNT * WORKER_RAM))GB RAM"
echo ""
echo "CLUSTER TOTALS:"
echo "  VMs: $((CP_COUNT + WORKER_COUNT))"
echo "  CPU: ${TOTAL_CPU_ALLOCATED}/${USABLE_CPU} cores (${CPU_UTIL}% utilization)"
echo "  RAM: ${TOTAL_RAM_ALLOCATED}/${USABLE_RAM}GB (${RAM_UTIL}% utilization)"
echo ""

# Warn if utilization is too high or too low
if [ "$(echo "$CPU_UTIL > 90" | bc)" -eq 1 ] || [ "$(echo "$RAM_UTIL > 90" | bc)" -eq 1 ]; then
    echo "⚠️  WARNING: High resource utilization - consider reducing VMs or adding capacity"
elif [ "$(echo "$CPU_UTIL < 40" | bc)" -eq 1 ] && [ "$(echo "$RAM_UTIL < 40" | bc)" -eq 1 ]; then
    echo "💡 Low utilization - you could add more workers or increase VM sizes"
else
    echo "✓ Good resource utilization"
fi
echo ""

# =============================================================================
# Generate terraform.tfvars
# =============================================================================

read -p "Generate terraform.tfvars with this configuration? (yes/no): " GENERATE

if [[ "$GENERATE" != "yes" ]]; then
    echo "Configuration not saved. Re-run script to try again."
    exit 0
fi

# Collect API credentials for terraform.tfvars
echo ""
echo "========================================"
echo "API Credentials for Terraform"
echo "========================================"
echo ""
echo "Terraform needs API tokens for each Proxmox server."
echo "See README.md for setup instructions."
echo ""

declare -A API_TOKENS

for NODE in "${!PROXMOX_SERVERS[@]}"; do
    IFS='@' read -r USER HOST <<< "${PROXMOX_SERVERS[$NODE]}"
    echo "--- $NODE ($HOST) ---"
    read -p "API token ID (e.g., terraform@pve!terraform): " TOKEN_ID
    read -s -p "API token secret: " TOKEN_SECRET
    echo ""
    API_TOKENS["$NODE"]="$TOKEN_ID|$TOKEN_SECRET|$HOST"
    echo ""
done

echo ""
echo "Generating terraform.tfvars..."

cat > "$SCRIPT_DIR/terraform.tfvars" <<EOF
# =============================================================================
# Auto-generated by recommend-cluster.sh
# Generated: $(date)
#
# Cluster Capacity:
#   - Servers: $SERVER_COUNT
#   - Total CPU: $TOTAL_CPU cores ($USABLE_CPU usable)
#   - Total RAM: ${TOTAL_RAM}GB (${USABLE_RAM}GB usable)
#   - Total Storage: ${TOTAL_STORAGE}GB (${USABLE_STORAGE}GB usable)
#
# Recommended Configuration:
#   - Control Planes: $CP_COUNT x (${CP_CPU} cores, ${CP_RAM}GB RAM)
#   - Workers: $WORKER_COUNT x (${WORKER_CPU} cores, ${WORKER_RAM}GB RAM)
#   - Utilization: CPU ${CPU_UTIL}%, RAM ${RAM_UTIL}%
# =============================================================================

# =============================================================================
# Proxmox Servers Configuration
# =============================================================================

proxmox_servers = {
EOF

# Add each Proxmox server
for NODE in "${!NODE_RESOURCES[@]}"; do
    IFS='|' read -r CPU_TOTAL CPU_AVAIL RAM_TOTAL RAM_AVAIL STOR_TOTAL STOR_AVAIL STOR_NAME <<< "${NODE_RESOURCES[$NODE]}"
    IFS='|' read -r TOKEN_ID TOKEN_SECRET HOST <<< "${API_TOKENS[$NODE]}"

    cat >> "$SCRIPT_DIR/terraform.tfvars" <<EOF
  "$NODE" = {
    api_url          = "https://${HOST}:8006/api2/json"
    api_token_id     = "$TOKEN_ID"
    api_token_secret = "$TOKEN_SECRET"
    node_name        = "$NODE"
    tls_insecure     = true
    storage_os       = "${STOR_NAME}-lvm"
    storage_data     = "${STOR_NAME}-lvm"
    network_bridge   = "vmbr0"
  }
EOF
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

# Generate control plane VMs with distribution across nodes
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

# Generate worker VMs with smart distribution
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
# Uncomment and configure if you have GPUs

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

# =============================================================================
# Show per-server allocation
# =============================================================================

echo "========================================"
echo "VM Distribution Across Servers"
echo "========================================"
echo ""

for NODE in "${!NODE_RESOURCES[@]}"; do
    IFS='|' read -r CPU_TOTAL CPU_AVAIL RAM_TOTAL RAM_AVAIL STOR_TOTAL STOR_AVAIL STOR_NAME <<< "${NODE_RESOURCES[$NODE]}"

    VMS_ON_NODE=0
    CPU_ALLOCATED=0
    RAM_ALLOCATED=0

    # Count control planes on this node
    for i in $(seq 1 $CP_COUNT); do
        NODE_INDEX=$(( (i - 1) % SERVER_COUNT ))
        if [ "${NODE_ARRAY[$NODE_INDEX]}" == "$NODE" ]; then
            VMS_ON_NODE=$((VMS_ON_NODE + 1))
            CPU_ALLOCATED=$((CPU_ALLOCATED + CP_CPU))
            RAM_ALLOCATED=$((RAM_ALLOCATED + CP_RAM))
        fi
    done

    # Count workers on this node
    for i in $(seq 1 $WORKER_COUNT); do
        NODE_INDEX=$(( (i - 1) % SERVER_COUNT ))
        if [ "${NODE_ARRAY[$NODE_INDEX]}" == "$NODE" ]; then
            VMS_ON_NODE=$((VMS_ON_NODE + 1))
            CPU_ALLOCATED=$((CPU_ALLOCATED + WORKER_CPU))
            RAM_ALLOCATED=$((RAM_ALLOCATED + WORKER_RAM))
        fi
    done

    CPU_PERCENT=$(echo "scale=1; $CPU_ALLOCATED * 100 / $CPU_TOTAL" | bc)
    RAM_PERCENT=$(echo "scale=1; $RAM_ALLOCATED * 100 / $RAM_TOTAL" | bc)

    echo "$NODE:"
    echo "  VMs: $VMS_ON_NODE"
    echo "  CPU: ${CPU_ALLOCATED}/${CPU_TOTAL} cores (${CPU_PERCENT}%)"
    echo "  RAM: ${RAM_ALLOCATED}/${RAM_TOTAL}GB (${RAM_PERCENT}%)"
    echo ""
done

echo "========================================"
echo "Next Steps"
echo "========================================"
echo ""
echo "1. Review terraform.tfvars (optional customization):"
echo "   nano terraform.tfvars"
echo ""
echo "2. Verify network settings (default: 192.168.10.0/24)"
echo ""
echo "3. Deploy with Terraform:"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "4. Configure DHCP reservations:"
echo "   terraform output dhcp_reservations_table"
echo ""
