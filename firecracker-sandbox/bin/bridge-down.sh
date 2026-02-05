#!/bin/bash
# Script to tear down firecracker bridge
# Called by systemd service

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Remove NAT rules
HOST_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

iptables -t nat -D POSTROUTING -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i "$BRIDGE_NAME" -o "$HOST_IFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$HOST_IFACE" -o "$BRIDGE_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# Remove bridge
ip link set "$BRIDGE_NAME" down 2>/dev/null || true
ip link delete "$BRIDGE_NAME" 2>/dev/null || true

echo "Bridge $BRIDGE_NAME removed"
