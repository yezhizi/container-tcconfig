#!/bin/bash

# =============================================================================
# Script Name: find_container_veth_name.sh
# Description: Retrieves the veth interface name of a Docker container.
# Usage:
#   ./find_container_veth_name.sh <container_name_or_id>
# Example:
#   ./find_container_veth_name.sh my_container
# =============================================================================

# Check if container name or ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <container_name_or_id>" >&2
    exit 1
fi

CONTAINER=$1

# Get the container's PID
PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null)
if [ -z "$PID" ]; then
    echo "Cannot retrieve PID for container '$CONTAINER'." >&2
    exit 1
fi

# Get eth0 interface information inside the container
ETH0_INFO=$(sudo nsenter -t "$PID" -n ip link show eth0 2>/dev/null)
if [ -z "$ETH0_INFO" ]; then
    echo "Cannot retrieve eth0 information for container '$CONTAINER'." >&2
    exit 1
fi

# Extract the peer ifindex
PEER_IFINDEX=$(echo "$ETH0_INFO" | awk -F'@if' '{split($2, a, ":"); print a[1]}')
if [ -z "$PEER_IFINDEX" ]; then
    echo "Cannot extract peer ifindex for eth0." >&2
    exit 1
fi

# Find the veth interface name on the host using ifindex
HOST_VETH=$(ip -o link | awk -v idx="$PEER_IFINDEX" '$1 == idx ":" {print $2}' | cut -d'@' -f1)
if [ -z "$HOST_VETH" ]; then
    echo "Cannot find corresponding veth interface on the host." >&2
    exit 1
fi

# Output the veth interface name
echo "$HOST_VETH"
