#!/bin/bash

# =============================================================================
# Script Name: clear_tc_rules.sh
# Description: Clears all tc (Traffic Control) rules inside a specified Docker container.
# Usage:
#   sudo ./clear_tc_rules.sh [-d] <CONTAINER> [INTERFACE]
# Example:
#   sudo ./clear_tc_rules.sh -d my_container eth0
# =============================================================================

# -----------------------------------------------------------------------------
# Function: Display usage help
# -----------------------------------------------------------------------------
usage() {
    echo "Usage: sudo $0 [-d] <CONTAINER> [INTERFACE]"
    echo
    echo "Parameters:"
    echo "  -d          - Enable debug output (optional)"
    echo "  CONTAINER   - Docker container name or ID"
    echo "  INTERFACE   - Network interface inside the container (default: eth0)"
    echo
    echo "Example:"
    echo "  sudo $0 -d my_container eth0"
    exit 1
}

# -----------------------------------------------------------------------------
# Initialize debugging
# -----------------------------------------------------------------------------
DEBUG=false  # Default is debugging disabled

# Debug function
debug() {
    if $DEBUG; then
        echo "[DEBUG][$(date '+%m-%d %H:%M:%S')][${BASH_SOURCE[1]}:${BASH_LINENO[0]}]: $*" >&2
    fi
}

# -----------------------------------------------------------------------------
# Check if running with root privileges
# -----------------------------------------------------------------------------
# if [[ $EUID -ne 0 ]]; then
#     echo "Error: This script must be run as root."
#     usage
# fi

# -----------------------------------------------------------------------------
# Parse options and arguments
# -----------------------------------------------------------------------------
if [ "$#" -lt 1 ]; then
    echo "Error: Incorrect number of parameters."
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d)
            DEBUG=true
            shift
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
# Read input parameters
# -----------------------------------------------------------------------------
CONTAINER=$1
INTERFACE=${2:-eth0}  # Default to eth0 if not specified

if [ -z "$CONTAINER" ]; then
    echo "Error: Missing CONTAINER parameter."
    usage
fi

# -----------------------------------------------------------------------------
# Check if the container exists
# -----------------------------------------------------------------------------
if ! docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER"; then
    echo "Error: Container $CONTAINER does not exist."
    exit 1
fi

# -----------------------------------------------------------------------------
# Function: Execute command inside the Docker container
# -----------------------------------------------------------------------------
exec_in_container() {
    local container="$1"
    shift
    docker exec "$container" "$@"
}

# -----------------------------------------------------------------------------
# Function: Clear tc rules on the interface inside the container
# -----------------------------------------------------------------------------
clear_tc_in_container() {
    local container="$1"
    local iface="$2"
    debug "Clearing all tc rules on interface $iface inside container $container..."
    if exec_in_container "$container" tc qdisc del dev "$iface" root 2>/dev/null; then
        debug "Successfully cleared tc rules on $iface in container $container."
    else
        debug "No tc rules found on $iface in container $container or failed to delete."
    fi
}

# -----------------------------------------------------------------------------
# Clear tc rules
# -----------------------------------------------------------------------------
clear_tc_in_container "$CONTAINER" "$INTERFACE"

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0