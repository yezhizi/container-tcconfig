#!/bin/bash

# =============================================================================
# Script Name: docker_tcconfig.sh
# Description: Limits or clears the bandwidth between Docker containers.
#              Supports setting and clearing bandwidth limits.
# Usage:
#   sudo ./docker_tcconfig.sh [OPTIONS] <CONTAINER1> <CONTAINER2> [RATE]
#   sudo ./docker_tcconfig.sh [OPTIONS] <CONTAINER>
# Options:
#   -c      Clear bandwidth limits for the specified container
#   -d      Enable debug output
# Example:
#   # Set bandwidth between two containers
#   sudo ./docker_tcconfig.sh container1 container2 1mbit
#
#   # Clear bandwidth for a single container
#   sudo ./docker_tcconfig.sh -c container1
# =============================================================================

# -----------------------------------------------------------------------------
# Function: Display usage help
# -----------------------------------------------------------------------------
usage() {
    echo "Usage:"
    echo "  sudo $0 [OPTIONS] <CONTAINER1> <CONTAINER2> [RATE]    # Set bandwidth between two containers"
    echo "  sudo $0 [OPTIONS] -c <CONTAINER>                     # Clear bandwidth for a single container"
    echo
    echo "Options:"
    echo "  -c      Clear bandwidth limits for the specified container"
    echo "  -d      Enable debug output"
    echo
    echo "Parameters for Setting Bandwidth:"
    echo "  CONTAINER1 - First container's name or ID"
    echo "  CONTAINER2 - Second container's name or ID"
    echo "  RATE       - Bandwidth rate limit (e.g., 1mbit)"
    echo
    echo "Example (Set):"
    echo "  sudo $0 container1 container2 1mbit"
    echo
    echo "Example (Clear):"
    echo "  sudo $0 -c container1"
    exit 1
}

# -----------------------------------------------------------------------------
# Function: Debug settings
# -----------------------------------------------------------------------------

DEBUG=false  # Set to true to enable debug output

# Debug function
debug() {
    if $DEBUG; then
        echo "[DEBUG][$(date '+%m-%d %H:%M:%S')][${BASH_SOURCE[1]}:${BASH_LINENO[0]}]: $*" >&2
    fi
}

# -----------------------------------------------------------------------------
# Parse options
# -----------------------------------------------------------------------------
ACTION="set"
while getopts ":cd" opt; do
    case $opt in
        c)
            ACTION="clear"
            ;;
        d)
            DEBUG=true
            ;;
        \?)
            echo "Error: Invalid option: -$OPTARG"
            usage
            ;;
    esac
done
shift $((OPTIND -1))

# -----------------------------------------------------------------------------
# Validate and read arguments based on ACTION
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "set" ]]; then
    if [ "$#" -ne 3 ]; then
        echo "Error: Incorrect number of parameters for setting bandwidth."
        usage
    fi

    CONTAINER1=$1
    CONTAINER2=$2
    RATE=$3
elif [[ "$ACTION" == "clear" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Error: Incorrect number of parameters for clearing bandwidth."
        usage
    fi

    CONTAINER1=$1
fi

# -----------------------------------------------------------------------------
# Check if running with root privileges
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   usage
fi

# -----------------------------------------------------------------------------
# Check dependencies based on ACTION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VETH_SCRIPT="$SCRIPT_DIR/find_container_veth_name.sh"
IP_SCRIPT="$SCRIPT_DIR/find_container_ip.sh"
TC_SCRIPT="$SCRIPT_DIR/set_network_limit.sh"
CLEAR_SCRIPT="$SCRIPT_DIR/clear_tc_rules.sh"

if [[ "$ACTION" == "set" ]]; then
    if [[ ! -x "$VETH_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $VETH_SCRIPT."
        exit 1
    fi

    if [[ ! -x "$IP_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $IP_SCRIPT."
        exit 1
    fi

    if [[ ! -x "$TC_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $TC_SCRIPT."
        exit 1
    fi
elif [[ "$ACTION" == "clear" ]]; then
    if [[ ! -x "$CLEAR_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $CLEAR_SCRIPT."
        exit 1
    fi

    if [[ ! -x "$VETH_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $VETH_SCRIPT."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Function: Get veth name of a container
# -----------------------------------------------------------------------------
get_veth() {
    local container=$1
    local veth
    veth=$("$VETH_SCRIPT" "$container")
    echo "$veth"
}

# -----------------------------------------------------------------------------
# Function: Get IP address of a container
# -----------------------------------------------------------------------------
get_ip() {
    local container=$1
    local ip
    ip=$("$IP_SCRIPT" "$container")
    echo "$ip"
}

# -----------------------------------------------------------------------------
# Function: Clear tc rules on an interface
# -----------------------------------------------------------------------------
clear_tc_rules() {
    local iface=$1
    debug "Clearing tc rules on interface $iface..."
    "$CLEAR_SCRIPT" "$iface"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to clear tc rules on $iface."
        exit 1
    fi
    debug "Successfully cleared tc rules on $iface."
}

# -----------------------------------------------------------------------------
# Function: Apply bandwidth limits
# -----------------------------------------------------------------------------
apply_bandwidth_limits() {
    local veth1=$1
    local ip1=$2
    local veth2=$3
    local ip2=$4
    local rate=$5

    debug "Applying bandwidth limit: $rate between $ip1 and $ip2 on interfaces $veth1 and $veth2."
    if $DEBUG; then
        "$TC_SCRIPT" "-d" "$veth1" "$ip1" "$veth2" "$ip2" "$rate" 
    else
        "$TC_SCRIPT" "$veth1" "$ip1" "$veth2" "$ip2" "$rate"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to apply bandwidth limit."
        exit 1
    fi
    debug "Successfully applied bandwidth limit: $rate between $ip1 and $ip2."
}

# -----------------------------------------------------------------------------
# Main logic
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "set" ]]; then
    # Get container1's veth and IP
    debug "Retrieving veth and IP for container '$CONTAINER1'..."
    VETH1=$(get_veth "$CONTAINER1")
    if [[ -z "$VETH1" ]]; then
        echo "Error: Unable to get veth name for container '$CONTAINER1'."
        exit 1
    fi

    IP1=$(get_ip "$CONTAINER1")
    if [[ -z "$IP1" ]]; then
        echo "Error: Unable to get IP address for container '$CONTAINER1'."
        exit 1
    fi

    # Get container2's veth and IP
    debug "Retrieving veth and IP for container '$CONTAINER2'..."
    VETH2=$(get_veth "$CONTAINER2")
    if [[ -z "$VETH2" ]]; then
        echo "Error: Unable to get veth name for container '$CONTAINER2'."
        exit 1
    fi
    debug "Container '$CONTAINER2' veth interface: $VETH2"

    IP2=$(get_ip "$CONTAINER2")
    if [[ -z "$IP2" ]]; then
        echo "Error: Unable to get IP address for container '$CONTAINER2'."
        exit 1
    fi
    debug "Container '$CONTAINER2' IP address: $IP2"

    # Apply bandwidth limits
    debug "Applying bandwidth limit: $RATE"
    apply_bandwidth_limits "$VETH1" "$IP1" "$VETH2" "$IP2" "$RATE"

    # Optional: Verify bandwidth limits
    # echo
    # echo "Verifying bandwidth limits..."
    # echo "Starting iperf3 server in container '$CONTAINER1'..."
    # docker exec "$CONTAINER1" iperf3 -s -D

    # sleep 2  # Wait for iperf3 server to start

    # echo "Running iperf3 client in container '$CONTAINER2' to test bandwidth to '$IP1'..."
    # docker exec "$CONTAINER2" iperf3 -c "$IP1" -t 10
elif [[ "$ACTION" == "clear" ]]; then
    # Get container's veth
    debug "Retrieving veth for container '$CONTAINER1'..."
    VETH1=$(get_veth "$CONTAINER1")
    if [[ -z "$VETH1" ]]; then
        echo "Error: Unable to get veth name for container '$CONTAINER1'."
        exit 1
    fi
    debug "Container '$CONTAINER1' veth interface: $VETH1"

    # Clear tc rules on the interface
    debug "Clearing tc rules on interface $VETH1..."
    clear_tc_rules "$VETH1"

    debug "Bandwidth limits for container '$CONTAINER1' have been successfully cleared."
fi

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0