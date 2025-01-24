#!/bin/bash

# =============================================================================
# Script Name: docker_tcconfig.sh
# Description: Limits or clears the bandwidth between Docker containers.
#              Supports setting and clearing bandwidth limits.
# Usage:
#   sudo ./docker_tcconfig.sh [OPTIONS] <CONTAINER1> <CONTAINER2> <RATE>
#   sudo ./docker_tcconfig.sh [OPTIONS] -c <CONTAINER>
#   sudo ./docker_tcconfig.sh [OPTIONS] -init <CONTAINER>
# Options:
#   -c                  Clear bandwidth limits for specified containers
#   -init               Initialize HTB on the specified container
#   -d                  Enable debug output
#   --iface1 INTERFACE  Network interface for CONTAINER1 (default: eth0)
#   --iface2 INTERFACE  Network interface for CONTAINER2 (default: eth0)
# Example:
#   # Set bandwidth between two containers
#   sudo ./docker_tcconfig.sh --iface1 eth0 --iface2 eth1 container1 container2 1mbit
#
#   # Clear bandwidth for a single container
#   sudo ./docker_tcconfig.sh -c container1 [container2, container3, ...]
#
#   # Initialize HTB on a container
#   sudo ./docker_tcconfig.sh -init container1 [container2, container3, ...]
# =============================================================================

# -----------------------------------------------------------------------------
# Function: Display usage help
# -----------------------------------------------------------------------------
usage() {
    echo "Usage:"
    echo "  sudo $0 [OPTIONS] <CONTAINER1> <CONTAINER2> <RATE>    # Set bandwidth between two containers"
    echo "  sudo $0 [OPTIONS] -c <CONTAINER> [<CONTAINER> ...]    # Clear bandwidth for one or more containers"
    echo
    echo "Options:"
    echo "  -c                  Clear bandwidth limits for the specified container"
    echo "  -init               Initialize HTB on the specified container"
    echo "  -d                  Enable debug output"
    echo "  --iface1 INTERFACE  Network interface for CONTAINER1 (default: eth0)"
    echo "  --iface2 INTERFACE  Network interface for CONTAINER2 (default: eth0)"
    echo
    echo "Parameters for Setting Bandwidth:"
    echo "  CONTAINER1 - First container's name or ID"
    echo "  CONTAINER2 - Second container's name or ID"
    echo "  RATE       - Bandwidth rate limit (e.g., 1mbit)"
    echo
    echo "Example (Set):"
    echo "  sudo $0 --iface1 eth0 --iface2 eth1 container1 container2 1mbit"
    echo
    echo "Example (Clear):"
    echo "  sudo $0 -c container1 [container2 container3, ...]"
    echo
    echo "Example (Init):"
    echo "  sudo $0 -init container1 [container2 container3 ...]"
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
# Default interface names
# -----------------------------------------------------------------------------
iface1="eth0"
iface2="eth0"

# -----------------------------------------------------------------------------
# Parse options
# -----------------------------------------------------------------------------
ACTION="set"
CLEAR_CONTAINERS=()
INIT_CONTAINERS=()
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -c)
            ACTION="clear"
            shift
            while [[ "$#" -gt 0 && "$1" != -* ]]; do
                CLEAR_CONTAINERS+=("$1")
                shift
            done
            ;;
        -init)
            ACTION="init"
            shift
            while [[ "$#" -gt 0 && ! "$1" =~ ^- ]]; do
                INIT_CONTAINERS+=("$1")
                shift
            done
            ;;
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

# -----------------------------------------------------------------------------
# Validate and read arguments based on ACTION
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "set" ]]; then
    if [ "${#CLEAR_CONTAINERS[@]}" -ne 0 ] || [ "$#" -ne 3 ]; then
        echo "Error: Incorrect parameters for setting bandwidth."
        usage
    fi
    CONTAINER1=$1
    CONTAINER2=$2
    RATE=$3
elif [[ "$ACTION" == "clear" ]]; then
    if [ "${#CLEAR_CONTAINERS[@]}" -eq 0 ]; then
        echo "Error: No containers specified for clearing bandwidth."
        usage
    fi
elif [[ "$ACTION" == "init" ]]; then
    if [ "${#INIT_CONTAINERS[@]}" -eq 0 ]; then
        echo "Error: No containers specified for initializing HTB."
        usage
    fi
else
    echo "Error: Unknown action."
    usage
fi

# -----------------------------------------------------------------------------
# Check if running with root privileges
# -----------------------------------------------------------------------------
# if [[ $EUID -ne 0 ]]; then
#    echo "Error: This script must be run as root."
#    usage
# fi

# -----------------------------------------------------------------------------
# Check dependencies based on ACTION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIND_IP_SCRIPT="$SCRIPT_DIR/find_container_ip.sh"
SET_TC_SCRIPT="$SCRIPT_DIR/set_network_limit.sh"
CLEAR_TC_SCRIPT="$SCRIPT_DIR/clear_tc_rules.sh"
FUNCTIONS_SCRIPT="$SCRIPT_DIR/functions.sh"

if [[ "$ACTION" == "set" ]]; then
    if [[ ! -x "$FIND_IP_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $FIND_IP_SCRIPT."
        exit 1
    fi

    if [[ ! -x "$SET_TC_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $SET_TC_SCRIPT."
        exit 1
    fi
elif [[ "$ACTION" == "clear" ]]; then
    if [[ ! -x "$CLEAR_TC_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $CLEAR_TC_SCRIPT."
        exit 1
    fi
elif [[ "$ACTION" == "init" ]]; then
    if [[ ! -x "$FUNCTIONS_SCRIPT" ]]; then
        echo "Error: Cannot find or execute $FUNCTIONS_SCRIPT."
        exit 1
    fi
    source "$FUNCTIONS_SCRIPT"
fi

# -----------------------------------------------------------------------------
# Function: Get IP address of a container
# -----------------------------------------------------------------------------
get_ip() {
    local container=$1
    local ip
    ip=$("$FIND_IP_SCRIPT" "$container")
    echo "$ip"
}

# -----------------------------------------------------------------------------
# Function: Clear tc rules on an interface
# -----------------------------------------------------------------------------
clear_tc_rules() {
    local container=$1
    local iface=$2
    debug "Clearing tc rules on interface $iface in container $container..."
    if $DEBUG; then
        "$CLEAR_TC_SCRIPT" "-d" "$container" "$iface"
    else
        "$CLEAR_TC_SCRIPT" "$container" "$iface"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to clear tc rules on $iface in container $container."
        exit 1
    fi
    debug "Successfully cleared tc rules on $iface in container $container."
}

# -----------------------------------------------------------------------------
# Function: Apply bandwidth limits
# -----------------------------------------------------------------------------
apply_bandwidth_limits() {
    local container1=$1
    local ip1=$2
    local container2=$3
    local ip2=$4
    local rate=$5
    local iface1=$6
    local iface2=$7

    debug "Applying bandwidth limit: $rate between $ip1 ($container1) and $ip2 ($container2) on interfaces $iface1 and $iface2."
    local args=()
    if $DEBUG; then
        args+=("-d")
    fi
    args+=("--iface1" "$iface1" "--iface2" "$iface2")
    args+=("$container1" "$ip1" "$container2" "$ip2" "$rate")

    "$SET_TC_SCRIPT" "${args[@]}"
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
    # Get IP addresses of the containers
    debug "Retrieving IP addresses for containers..."
    IP1=$(get_ip "$CONTAINER1")
    if [[ -z "$IP1" ]]; then
        echo "Error: Unable to get IP address for container '$CONTAINER1'."
        exit 1
    fi
    debug "Container '$CONTAINER1' IP address: $IP1"

    IP2=$(get_ip "$CONTAINER2")
    if [[ -z "$IP2" ]]; then
        echo "Error: Unable to get IP address for container '$CONTAINER2'."
        exit 1
    fi
    debug "Container '$CONTAINER2' IP address: $IP2"

    # Apply bandwidth limits
    apply_bandwidth_limits "$CONTAINER1" "$IP1" "$CONTAINER2" "$IP2" "$RATE" "$iface1" "$iface2"

elif [[ "$ACTION" == "clear" ]]; then
    # Clear tc rules on the interface
    for container in "${CLEAR_CONTAINERS[@]}"; do
        clear_tc_rules "$container" "$iface1"

        debug "Bandwidth limits for container '$container' have been successfully cleared."
    done
elif [[ "$ACTION" == "init" ]]; then
    for container in "${INIT_CONTAINERS[@]}"; do
        debug "Initializing HTB on interface $iface1 in container $container..."
        init_htb "$container" "$iface1"

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to initialize HTB on $iface1 in container $container."
            exit 1
        fi
        debug "Successfully initialized HTB on $iface1 in container $container."
    done
fi

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0