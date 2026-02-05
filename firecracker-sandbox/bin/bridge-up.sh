#!/bin/bash
# Script to create and configure firecracker bridge
# Called by systemd service

set -e

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Create bridge
ip link add "$BRIDGE_NAME" type bridge 2>/dev/null || true
ip addr add "$BRIDGE_IP" dev "$BRIDGE_NAME" 2>/dev/null || true
ip link set "$BRIDGE_NAME" up

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Set up NAT rules
HOST_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Add MASQUERADE rule (check if exists first)
iptables -t nat -C POSTROUTING -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$HOST_IFACE" -j MASQUERADE

# Add FORWARD rules (check if exist first)
iptables -C FORWARD -i "$BRIDGE_NAME" -o "$HOST_IFACE" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$BRIDGE_NAME" -o "$HOST_IFACE" -j ACCEPT

iptables -C FORWARD -i "$HOST_IFACE" -o "$BRIDGE_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$HOST_IFACE" -o "$BRIDGE_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "Bridge $BRIDGE_NAME created and configured"
