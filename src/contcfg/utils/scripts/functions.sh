#!/bin/bash
# -----------------------------------------------------------------------------
# Function to execute tc command inside Docker container
# -----------------------------------------------------------------------------
exec_tc() {
    local container="$1"
    shift
    docker exec "$container" tc "$@" || { echo "Failed to execute tc command"; exit 1; }
}

# -----------------------------------------------------------------------------
# Function: Initialize HTB root queue on the interface
# -----------------------------------------------------------------------------
init_htb() {
    local container="$1"
    local iface="$2"
    if ! exec_tc "$container" qdisc show dev "$iface" | grep -q "htb 1:"; then
        debug "Adding HTB root queue to interface $iface in container $container..."
        exec_tc "$container" qdisc add dev "$iface" root handle 1: htb default 9999 || { echo "Failed to add root qdisc"; exit 1; }
        exec_tc "$container" class add dev "$iface" parent 1: classid 1:1 htb rate 10000000mbit ceil 10000000mbit || { echo "Failed to add default class 1:1"; exit 1; }
        exec_tc "$container" class add dev "$iface" parent 1: classid 1:9999 htb rate 10000000mbit ceil 10000000mbit || { echo "Failed to add default class 1:9999"; exit 1; }
    fi
}

# -----------------------------------------------------------------------------
# Function: Generate unique class ID and filter priority
# -----------------------------------------------------------------------------
generate_ids() {
    local dst_ip=$1
    local major_id=1  # Use a distinct major ID to avoid conflicts
    
    # Generate a hash from src_ip and dst_ip
    local hash=$(echo -n "${dst_ip}" | md5sum | head -c 4)
    
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
    local container="$1"
    local iface="$2"
    local classid="$3"
    exec_tc "$container" class show dev "$iface" | grep -q "class htb $classid"
}