#!/bin/bash

# =============================================================================
# Script Name: set_bandwidth_limit.sh
# Description: Uses the tc command to limit the bandwidth between two Docker containers (bidirectional).
#              Supports multiple invocations.
# Usage:
#   sudo ./set_bandwidth_limit.sh [-d] [--iface1 INTERFACE1] [--iface2 INTERFACE2] <CONTAINER1> <IP1> <CONTAINER2> <IP2> <RATE>
# Example:
#   sudo ./set_bandwidth_limit.sh -d --iface1 eth0 --iface2 eth1 CONTAINER1 172.17.0.2 CONTAINER2 172.17.0.3 100mbit
# =============================================================================

# -----------------------------------------------------------------------------
# Function: Display usage help
# -----------------------------------------------------------------------------
usage() {
    echo "Usage: sudo $0 [-d] [--iface1 INTERFACE1] [--iface2 INTERFACE2] <CONTAINER1> <IP1> <CONTAINER2> <IP2> <RATE>"
    echo
    echo "Parameters:"
    echo "  -d                  - Enable debug output (optional)"
    echo "  --iface1 INTERFACE1 - Interface name for CONTAINER1 (default: eth0)"
    echo "  --iface2 INTERFACE2 - Interface name for CONTAINER2 (default: eth0)"
    echo "  CONTAINER1          - Docker container name or ID for Node 1"
    echo "  IP1                 - IP address for Node 1"
    echo "  CONTAINER2          - Docker container name or ID for Node 2"
    echo "  IP2                 - IP address for Node 2"
    echo "  RATE                - Bandwidth rate limit (e.g., 100mbit)"
    echo
    echo "Example:"
    echo "  sudo $0 -d --iface1 eth0 --iface2 eth1 CONTAINER1 172.17.0.2 CONTAINER2 172.17.0.3 100mbit"
    exit 1
}

# -----------------------------------------------------------------------------
# Function: Debug settings
# -----------------------------------------------------------------------------

DEBUG=false  # Default: debugging disabled

debug() {
    if $DEBUG; then
        echo "[DEBUG][$(date '+%m-%d %H:%M:%S')][${BASH_SOURCE[1]}:${BASH_LINENO[0]}]: $*" >&2
    fi
}

# -----------------------------------------------------------------------------
# Default interface names
# -----------------------------------------------------------------------------
iface1="eth0"
iface2="eth0"

# -----------------------------------------------------------------------------
# Parse options and arguments
# -----------------------------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d)
            DEBUG=true
            shift
        ;;
        --iface1)
            iface1="$2"
            shift 2
        ;;
        --iface2)
            iface2="$2"
            shift 2
        ;;
        -*)
            echo "Error: Unknown option: $1"
            usage
        ;;
        *)
            break
        ;;
    esac
done

# Validate the number of remaining arguments
if [ "$#" -ne 5 ]; then
    echo "Error: Incorrect number of parameters."
    usage
fi

# -----------------------------------------------------------------------------
# Read input parameters
# -----------------------------------------------------------------------------
CONTAINER1=$1
IP1=$2
CONTAINER2=$3
IP2=$4
RATE=$(echo "$5" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

# Check if running with root privileges
# if [[ $EUID -ne 0 ]]; then
#     echo "Error: This script must be run as root."
#     usage
# fi

# -----------------------------------------------------------------------------
# Check if the containers exist
# -----------------------------------------------------------------------------
if ! docker ps -a --format '{{.Names}}' | grep -q "$CONTAINER1"; then
    echo "Error: Container $CONTAINER1 does not exist."
    exit 1
fi
 
if ! docker ps -a --format '{{.Names}}' | grep -q "$CONTAINER2"; then
    echo "Error: Container $CONTAINER2 does not exist."
    exit 1
fi

# -----------------------------------------------------------------------------
# Check dependencies based on ACTION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_SCRIPT="$SCRIPT_DIR/functions.sh"

source "$FUNCTIONS_SCRIPT"

# -----------------------------------------------------------------------------
# Function: Add or update bandwidth limit rules
# -----------------------------------------------------------------------------
add_or_update_tc_rules() {
    local container="$1"
    local iface="$2"
    local dst_ip="$3"
    local rate="$4"
    
    generate_ids "$dst_ip"
    debug "Generated class ID: $CLASS_ID_FULL"
    
    init_htb "$container" "$iface"
    
    if class_exists "$container" "$iface" "$CLASS_ID_FULL"; then
        
        debug "Updating bandwidth limit on interface $iface from $src_ip to $dst_ip to $rate..."
        # Update the class bandwidth
        exec_tc "$container" class change dev "$iface" parent 1: classid "$CLASS_ID_FULL" htb rate "$rate" ceil "$rate" || { echo "Failed to update class"; exit 1; }
    else
        
        debug "Adding bandwidth limit on interface $iface from $src_ip to $dst_ip ($rate)..."
        # Add a new class
        exec_tc "$container" class add dev "$iface" parent 1: classid "$CLASS_ID_FULL" htb rate "$rate" ceil "$rate" || { echo "Failed to add class"; exit 1; }
        # Add filters using flowid
        exec_tc "$container" filter add dev "$iface" protocol ip parent 1: prio 1 u32 match ip dst "$dst_ip"/32 flowid "$CLASS_ID_FULL" || { echo "Failed to add filter"; exit 1; }
    fi
}

# -----------------------------------------------------------------------------
# Add or update bandwidth limit rules
# -----------------------------------------------------------------------------
# Limit traffic from CONTAINER1 (IP1) to CONTAINER2 (IP2)
add_or_update_tc_rules "$CONTAINER1" "$iface1" "$IP2" "$RATE"

# Limit traffic from CONTAINER2 (IP2) to CONTAINER1 (IP1)
add_or_update_tc_rules "$CONTAINER2" "$iface2" "$IP1" "$RATE"

# -----------------------------------------------------------------------------
# Output results
# -----------------------------------------------------------------------------
debug "Bandwidth limits have been successfully applied or updated:"
debug "  - Interface $CONTAINER1, limiting traffic from $IP1 to $IP2 at $RATE"
debug "  - Interface $CONTAINER2, limiting traffic from $IP2 to $IP1 at $RATE"

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0