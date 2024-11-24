#!/bin/bash

# =============================================================================
# Script Name: clear_tc_rules.sh
# Description: Clears all tc (Traffic Control) rules on a specified network interface.
# Usage:
#   sudo ./clear_tc_rules.sh <INTERFACE>
# Example:
#   sudo ./clear_tc_rules.sh vethabcd1234
# =============================================================================

# -----------------------------------------------------------------------------
# Function: Display usage help
# -----------------------------------------------------------------------------
usage() {
    echo "Usage: sudo $0 <INTERFACE>"
    echo
    echo "Parameters:"
    echo "  INTERFACE  - Network interface name (e.g., vethabcd1234)"
    echo
    echo "Example:"
    echo "  sudo $0 vethabcd1234"
    exit 1
}

# -----------------------------------------------------------------------------
# Check if running with root privileges
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   usage
fi

# -----------------------------------------------------------------------------
# Check the number of input parameters
# -----------------------------------------------------------------------------
if [ "$#" -ne 1 ]; then
    echo "Error: Incorrect number of parameters."
    usage
fi

# -----------------------------------------------------------------------------
# Read input parameter
# -----------------------------------------------------------------------------
INTERFACE=$1

# -----------------------------------------------------------------------------
# Check if the interface exists
# -----------------------------------------------------------------------------
if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
    echo "Error: Interface $INTERFACE does not exist."
    exit 1
fi

# -----------------------------------------------------------------------------
# Function: Clear tc rules on the interface
# -----------------------------------------------------------------------------
clear_tc() {
    local iface=$1
    echo "Clearing all tc rules on interface $iface..."
    tc qdisc del dev "$iface" root 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Successfully cleared tc rules on $iface."
    else
        echo "No tc rules found on $iface or failed to delete."
    fi
}

# -----------------------------------------------------------------------------
# Clear tc rules
# -----------------------------------------------------------------------------
clear_tc "$INTERFACE"

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------
exit 0