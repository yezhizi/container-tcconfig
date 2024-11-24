#!/bin/bash

# =============================================================================
# Script Name: set_bandwidth_limit.sh
# Description: Uses the tc command to limit the bandwidth and other network
#              parameters (delay, loss, duplication, corruption, reorder) 
#              between two Docker containers (bidirectional).
#              Supports setting network impairments.
# Usage:
#   sudo ./set_bandwidth_limit.sh [OPTIONS] <VETH1> <IP1> <VETH2> <IP2>
# Options:
#   -d, --debug                  Enable debug output
#   --rate <RATE>                Set bandwidth rate limit (e.g., 100mbit)
#   --delay <DELAY>              Add network delay (e.g., 100ms)
#   --loss <LOSS%>               Add packet loss percentage (e.g., 1%)
#   --dup <DUP%>                 Add packet duplication percentage (e.g., 0.5%)
#   --corrupt <CORR%>            Add packet corruption percentage (e.g., 0.2%)
#   --reorder <REP%>             Add packet reordering percentage (e.g., 0.1%)
# Example:
#   # Set bandwidth and add delay and packet loss between two interfaces
#   sudo ./set_bandwidth_limit.sh veth1 172.17.0.2 veth2 172.17.0.3 --rate 100mbit --delay 100ms --loss 1%
# =============================================================================

# -----------------------------------------------------------------------------
# Function: Display usage help
# -----------------------------------------------------------------------------
usage() {
    echo "Usage:"
    echo "  sudo $0 [OPTIONS] <VETH1> <IP1> <VETH2> <IP2>    # Set network parameters between two interfaces"
    echo
    echo "Options:"
    echo "  -d, --debug                  Enable debug output"
    echo "  --rate <RATE>                Set bandwidth rate limit (e.g., 100mbit)"
    echo "  --delay <DELAY>              Add network delay (e.g., 100ms)"
    echo "  --loss <LOSS%>               Add packet loss percentage (e.g., 1%)"
    echo "  --dup <DUP%>                 Add packet duplication percentage (e.g., 0.5%)"
    echo "  --corrupt <CORR%>            Add packet corruption percentage (e.g., 0.2%)"
    echo "  --reorder <REP%>             Add packet reordering percentage (e.g., 0.1%)"
    echo
    echo "Example (Set with bandwidth, delay, and loss):"
    echo "  sudo $0 veth1 172.17.0.2 veth2 172.17.0.3 --rate 100mbit --delay 100ms --loss 1%"
    exit 1
}

# -----------------------------------------------------------------------------
# Function: Debug settings
# -----------------------------------------------------------------------------

DEBUG=false  # Default: debugging disabled

debug() {
    if $DEBUG; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [${BASH_SOURCE[1]}:${BASH_LINENO[0]}] [DEBUG]: $*" >&2
    fi
}

# -----------------------------------------------------------------------------
# Function: Initialize HTB root queue on the interface
# -----------------------------------------------------------------------------
init_htb() {
    local iface=$1
    # Check if a root qdisc already exists; if not, add it
    if ! tc qdisc show dev "$iface" | grep -q "htb 1:"; then
        debug "Adding HTB root queue to interface $iface..."
        tc qdisc add dev "$iface" root handle 1: htb default 9999 || { echo "Failed to add root qdisc on $iface"; exit 1; }
        # Create default classes to prevent unmatched traffic from occupying bandwidth
        tc class add dev "$iface" parent 1: classid 1:1 htb rate 10000mbit ceil 10000mbit || { echo "Failed to add default class 1:1 on $iface"; exit 1; }
        tc class add dev "$iface" parent 1: classid 1:9999 htb rate 10000mbit ceil 10000mbit || { echo "Failed to add default class 1:9999 on $iface"; exit 1; }
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
    local hash
    hash=$(echo -n "${src_ip}-${dst_ip}" | md5sum | head -c 4)

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
# Function: Apply netem parameters to a specific class
# -----------------------------------------------------------------------------
apply_netem_class() {
    local iface=$1
    local classid=$2
    local delay=$3
    local loss=$4
    local dup=$5
    local corrupt=$6
    local reorder=$7

    local netem_params=()

    if [[ -n "$delay" ]]; then
        netem_params+=("delay" "$delay")
    fi

    if [[ -n "$loss" ]]; then
        netem_params+=("loss" "$loss")
    fi

    if [[ -n "$dup" ]]; then
        netem_params+=("duplicate" "$dup")
    fi

    if [[ -n "$corrupt" ]]; then
        netem_params+=("corrupt" "$corrupt")
    fi

    if [[ -n "$reorder" ]]; then
        netem_params+=("reorder" "$reorder")
    fi

    if [[ "${#netem_params[@]}" -gt 0 ]]; then
        debug "Applying netem parameters to class $classid on interface $iface: ${netem_params[*]}"
        tc qdisc add dev "$iface" parent "$classid" handle 10: netem "${netem_params[@]}" || {
            echo "Failed to add netem qdisc to class $classid on $iface"
            exit 1
        }
    fi
}

# -----------------------------------------------------------------------------
# Function: Add or update bandwidth and network parameters
# -----------------------------------------------------------------------------
add_or_update_tc_rules() {
    local iface=$1
    local src_ip=$2
    local dst_ip=$3
    local rate=$4
    local delay=$5
    local loss=$6
    local dup=$7
    local corrupt=$8
    local reorder=$9

    generate_ids "$src_ip" "$dst_ip" "$iface"

    init_htb "$iface"

    if class_exists "$iface" "$CLASS_ID_FULL"; then
        if [[ -n "$rate" ]]; then
            debug "Updating bandwidth limit on interface $iface from $src_ip to $dst_ip to $rate..."
            # Update the class bandwidth
            tc class change dev "$iface" parent 1: classid "$CLASS_ID_FULL" htb rate "$rate" ceil "$rate" || { echo "Failed to update class on $iface"; exit 1; }
        fi

        # Remove existing netem qdisc if any
        tc qdisc del dev "$iface" parent "$CLASS_ID_FULL" handle 10: netem 2>/dev/null
    else
        debug "Adding bandwidth limit on interface $iface from $src_ip to $dst_ip ($rate)..."
        # Add a new class
        tc class add dev "$iface" parent 1: classid "$CLASS_ID_FULL" htb rate "${rate:-10000mbit}" ceil "${rate:-10000mbit}" || { echo "Failed to add class on $iface"; exit 1; }
    fi

    # Apply netem parameters if any
    apply_netem_class "$iface" "$CLASS_ID_FULL" "$delay" "$loss" "$dup" "$corrupt" "$reorder"
}

# -----------------------------------------------------------------------------
# Parse options using getopt for long options
# -----------------------------------------------------------------------------
PARSED_OPTIONS=$(getopt -n "$0" -o d -l debug,rate:,delay:,loss:,dup:,corrupt:,reorder: -- "$@")
if [[ $? -ne 0 ]]; then
    usage
fi

eval set -- "$PARSED_OPTIONS"

ACTION="set"
VETH1=""
IP1=""
VETH2=""
IP2=""
RATE=""
DELAY=""
LOSS=""
DUP=""
CORRUPT=""
REORDER=""

while true; do
    case "$1" in
        -d|--debug)
            DEBUG=true
            debug "Debug mode enabled."
            shift
            ;;
        --rate)
            RATE="$2"
            debug "Rate set to $RATE."
            shift 2
            ;;
        --delay)
            DELAY="$2"
            debug "Delay set to $DELAY."
            shift 2
            ;;
        --loss)
            LOSS="$2"
            debug "Loss set to $LOSS."
            shift 2
            ;;
        --dup)
            DUP="$2"
            debug "Duplication set to $DUP."
            shift 2
            ;;
        --corrupt)
            CORRUPT="$2"
            debug "Corruption set to $CORRUPT."
            shift 2
            ;;
        --reorder)
            REORDER="$2"
            debug "Reorder set to $REORDER."
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: Invalid option encountered."
            usage
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Validate arguments
# -----------------------------------------------------------------------------
# Required positional arguments for set action
if [ "$#" -lt 4 ]; then
    echo "Error: Insufficient parameters for setting network parameters."
    usage
fi

VETH1=$1
IP1=$2
VETH2=$3
IP2=$4
shift 4

# Collect any remaining arguments as errors
if [ "$#" -ne 0 ]; then
    echo "Error: Too many arguments."
    usage
fi

# Ensure at least one network parameter is set
if [[ -z "$RATE" && -z "$DELAY" && -z "$LOSS" && -z "$DUP" && -z "$CORRUPT" && -z "$REORDER" ]]; then
    echo "Error: At least one network parameter (--rate, --delay, --loss, --dup, --corrupt, --reorder) must be specified."
    usage
fi

# -----------------------------------------------------------------------------
# Check if running with root privileges
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   usage
fi

# -----------------------------------------------------------------------------
# Main logic
# -----------------------------------------------------------------------------
# Validate veth interfaces
if ! ip link show "$VETH1" > /dev/null 2>&1; then
    echo "Error: Interface $VETH1 does not exist."
    exit 1
fi

if ! ip link show "$VETH2" > /dev/null 2>&1; then
    echo "Error: Interface $VETH2 does not exist."
    exit 1
fi

# Apply bandwidth and network parameters to both interfaces bidirectionally
add_or_update_tc_rules "$VETH1" "$IP1" "$IP2" "$RATE" "$DELAY" "$LOSS" "$DUP" "$CORRUPT" "$REORDER"

add_or_update_tc_rules "$VETH2" "$IP2" "$IP1" "$RATE" "$DELAY" "$LOSS" "$DUP" "$CORRUPT" "$REORDER"

echo "Bandwidth limits and network parameters have been successfully applied or updated."

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0