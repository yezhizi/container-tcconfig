#!/bin/bash

# =============================================================================
# Script Name: set_bandwidth_limit.sh
# Description: Uses the tc command to limit the bandwidth between two Docker containers (bidirectional).
#              Supports multiple invocations.
# Usage:
#   sudo ./set_bandwidth_limit.sh [-d] <VETH1> <IP1> <VETH2> <IP2> <RATE>
# Example:
#   sudo ./set_bandwidth_limit.sh -d vethabcd1234 172.17.0.2 vethefgh5678 172.17.0.3 100mbit
# =============================================================================

# ----------------------------------------------------------------------------- 
# Function: Display usage help
# ----------------------------------------------------------------------------- 
usage() {
    echo "Usage: sudo $0 [-d] <VETH1> <IP1> <VETH2> <IP2> <RATE>"
    echo
    echo "Parameters:"
    echo "  -d     - Enable debug output (optional)"
    echo "  VETH1  - veth interface name for Node 1"
    echo "  IP1    - Container IP address for Node 1"
    echo "  VETH2  - veth interface name for Node 2"
    echo "  IP2    - Container IP address for Node 2"
    echo "  RATE   - Bandwidth rate limit (e.g., 100mbit)"
    echo
    echo "Example:"
    echo "  sudo $0 -d vethabcd1234 172.17.0.2 vethefgh5678 172.17.0.3 100mbit"
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
# Parse options and arguments
# ----------------------------------------------------------------------------- 
while getopts ":d" opt; do
    case $opt in
        d)
            DEBUG=true
            ;;
        \?)
            echo "Error: Invalid option: -$OPTARG"
            usage
            ;;
    esac
done
shift $((OPTIND - 1))  # Remove parsed options from arguments list

# Validate the number of remaining arguments
if [ "$#" -ne 5 ]; then
    echo "Error: Incorrect number of parameters."
    usage
fi

# ----------------------------------------------------------------------------- 
# Read input parameters
# ----------------------------------------------------------------------------- 
VETH1=$1
IP1=$2
VETH2=$3
IP2=$4
RATE=$(echo "$5" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

# Check if running with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   usage
fi

# -----------------------------------------------------------------------------
# Check if veth interfaces exist
# -----------------------------------------------------------------------------
if ! ip link show "$VETH1" > /dev/null 2>&1; then
    echo "Error: Interface $VETH1 does not exist."
    exit 1
fi

if ! ip link show "$VETH2" > /dev/null 2>&1; then
    echo "Error: Interface $VETH2 does not exist."
    exit 1
fi

# -----------------------------------------------------------------------------
# Function: Initialize HTB root queue on the interface
# -----------------------------------------------------------------------------
init_htb() {
    local iface=$1
    # Check if a root qdisc already exists; if not, add it
    if ! tc qdisc show dev "$iface" | grep -q "htb 1:"; then
        debug "Adding HTB root queue to interface $iface..."
        tc qdisc add dev "$iface" root handle 1: htb default 9999 || { echo "Failed to add root qdisc"; exit 1; }
        # Create default classes to prevent unmatched traffic from occupying bandwidth
        tc class add dev "$iface" parent 1: classid 1:1 htb rate 10000mbit ceil 10000mbit || { echo "Failed to add default class 1:1"; exit 1; }
        tc class add dev "$iface" parent 1: classid 1:9999 htb rate 10000mbit ceil 10000mbit || { echo "Failed to add default class 1:9999"; exit 1; }
    fi
}

# -----------------------------------------------------------------------------
# Function: Generate unique class ID and filter priority
# -----------------------------------------------------------------------------
generate_ids() {
    local src_ip=$1
    local dst_ip=$2
    local iface=$3
    local major_id=1  # Use a distinct major ID to avoid conflicts

    # Generate a hash from src_ip and dst_ip
    local hash=$(echo -n "${src_ip}-${dst_ip}" | md5sum | head -c 4)

    # Validate the hash is a hexadecimal number
    if [[ ! "$hash" =~ ^[0-9a-fA-F]{4}$ ]]; then
        echo "Error: Generated hash is invalid, cannot create classid."
        exit 1
    fi

    # Convert hash to a decimal minor ID within 1-4095
    local minor_id=$(( 0x$hash % 4095 + 1 ))
    CLASS_ID_FULL="${major_id}:${minor_id}"
}

# -----------------------------------------------------------------------------
# Function: Check if class exists
# -----------------------------------------------------------------------------
class_exists() {
    local iface=$1
    local classid=$2
    tc class show dev "$iface" | grep -qw "$classid"
}

# -----------------------------------------------------------------------------
# Function: Add or update bandwidth limit rules
# -----------------------------------------------------------------------------
add_or_update_tc_rules() {
    local iface=$1
    local src_ip=$2
    local dst_ip=$3
    local rate=$4

    generate_ids "$src_ip" "$dst_ip" "$iface"

    init_htb "$iface"

    if class_exists "$iface" "$CLASS_ID_FULL"; then

        debug "Updating bandwidth limit on interface $iface from $src_ip to $dst_ip to $rate..."

        # Update the class bandwidth
        tc class change dev "$iface" parent 1: classid "$CLASS_ID_FULL" htb rate "$rate" ceil "$rate" || { echo "Failed to update class"; exit 1; }
    else
        
        debug "Adding bandwidth limit on interface $iface from $src_ip to $dst_ip ($rate)..."

        # Add a new class
        tc class add dev "$iface" parent 1: classid "$CLASS_ID_FULL" htb rate "$rate" ceil "$rate" || { echo "Failed to add class"; exit 1; }

        # Add filters using flowid
        tc filter add dev "$iface" protocol ip parent 1: prio 1 flower src_ip "$dst_ip" dst_ip "$src_ip" flowid "$CLASS_ID_FULL" || { echo "Failed to add filter"; exit 1; }
        tc filter add dev "$iface" protocol ip parent 1: prio 1 flower src_ip "$src_ip" dst_ip "$dst_ip" flowid "$CLASS_ID_FULL" || { echo "Failed to add filter"; exit 1; }
    fi
}

# -----------------------------------------------------------------------------
# Add or update bandwidth limit rules
# -----------------------------------------------------------------------------
# Limit traffic from VETH1 (IP1) to VETH2 (IP2)
add_or_update_tc_rules "$VETH1" "$IP1" "$IP2" "$RATE"

# Limit traffic from VETH2 (IP2) to VETH1 (IP1)
add_or_update_tc_rules "$VETH2" "$IP2" "$IP1" "$RATE"

# -----------------------------------------------------------------------------
# Output results
# -----------------------------------------------------------------------------

debug "Bandwidth limits have been successfully applied or updated:"
debug "  - Interface $VETH1, limiting traffic from $IP1 to $IP2 at $RATE"
debug "  - Interface $VETH2, limiting traffic from $IP2 to $IP1 at $RATE"

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0