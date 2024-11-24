#!/bin/bash

# =============================================================================
# Script Name: find_container_ip.sh
# Description: Retrieves the IP address of a Docker container.
# Usage:
#   ./find_container_ip.sh <container_name_or_id>
# Example:
#   ./find_container_ip.sh my_container
# =============================================================================

# Check if container name or ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <container_name_or_id>" >&2
    exit 1
fi

CONTAINER=$1

# Check if the container exists
if ! docker inspect "$CONTAINER" > /dev/null 2>&1; then
    echo "Container '$CONTAINER' does not exist." >&2
    exit 1
fi

# Get the IP address of the container
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER")

# Check if IP address was retrieved
if [ -z "$IP" ]; then
    echo "Could not retrieve IP address for container '$CONTAINER'." >&2
    exit 1
fi

# Output the IP address
echo "$IP"
