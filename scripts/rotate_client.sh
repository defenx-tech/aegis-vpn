#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Key Rotation
# Author: Rabindra
# Description: Regenerates WireGuard keys for an existing
#              client, updates server config, and re-displays
#              the QR code without changing the client's IP.
# Usage: sudo ./rotate_client.sh <client-name>
#===========================================================

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=log_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/log_hooks.sh"

# ── Input validation ──────────────────────────────────────
if [[ $# -lt 1 ]]; then
    print_err "Usage: rotate_client.sh <client-name>"
    exit 1
fi

CLIENT_NAME="$1"
validate_client_name "$CLIENT_NAME"
require_wg_running

CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
if [[ ! -f "$CLIENT_CONF" ]]; then
    print_err "Client not found: ${CLIENT_NAME}"
    exit 1
fi

# ── Extract current client settings ──────────────────────
print_info "Reading current config for ${CLIENT_NAME}..."

OLD_PRIVATE=$(awk '/^PrivateKey[[:space:]]*=/{print $3}' "$CLIENT_CONF")
OLD_PUBLIC=$(echo "$OLD_PRIVATE" | wg pubkey)

CLIENT_ADDR=$(awk '/^Address[[:space:]]*=/{print $3}' "$CLIENT_CONF")   # e.g. 10.10.0.3/32, fd86:..../128
CLIENT_DNS=$(awk '/^DNS[[:space:]]*=/{$1=$2=""; gsub(/^[[:space:]]+/,"",$0); print}' "$CLIENT_CONF")
CLIENT_ALLOWED=$(awk '/^AllowedIPs[[:space:]]*=/{$1=$2=""; gsub(/^[[:space:]]+/,"",$0); print}' "$CLIENT_CONF")
CLIENT_KA=$(awk '/^PersistentKeepalive[[:space:]]*=/{print $3}' "$CLIENT_CONF")
SERVER_PUBLIC=$(awk '/^PublicKey[[:space:]]*=/{print $3}' "$CLIENT_CONF")
SERVER_ENDPOINT=$(awk '/^Endpoint[[:space:]]*=/{print $3}' "$CLIENT_CONF")

# ── Generate new keys ─────────────────────────────────────
print_info "Generating new keys for ${CLIENT_NAME}..."
NEW_PRIVATE=$(wg genkey)
NEW_PUBLIC=$(echo "$NEW_PRIVATE" | wg pubkey)

# ── Remove old peer from server config ────────────────────
print_info "Removing old peer from server config..."
remove_peer_block "$CLIENT_NAME"

# Remove old peer from live WireGuard
wg set "$WG_INTERFACE" peer "$OLD_PUBLIC" remove 2>/dev/null || true

# ── Rewrite client conf with new keys ────────────────────
print_info "Writing updated client configuration..."
cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${NEW_PRIVATE}
Address = ${CLIENT_ADDR}
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUBLIC}
Endpoint = ${SERVER_ENDPOINT}
AllowedIPs = ${CLIENT_ALLOWED}
PersistentKeepalive = ${CLIENT_KA:-25}
EOF
chmod 600 "$CLIENT_CONF"

# ── Extract IPs for peer re-registration ─────────────────
# AllowedIPs for the server peer entry: client's /32 and /128
IPv4_CIDR=$(echo "$CLIENT_ADDR" | tr ',' '\n' | awk '/[0-9]{1,3}\.[0-9]/{gsub(/[[:space:]]/,""); print}')
IPv6_CIDR=$(echo "$CLIENT_ADDR" | tr ',' '\n' | awk '/::/{gsub(/[[:space:]]/,""); print}')

# Adjust mask: /32 → /32, /128 → /128 (already correct in ADDRESS field)
SERVER_PEER_IPS="${IPv4_CIDR}"
[[ -n "$IPv6_CIDR" ]] && SERVER_PEER_IPS="${SERVER_PEER_IPS}, ${IPv6_CIDR}"

# ── Append new peer block to server config ────────────────
cat >> "${WG_DIR}/${WG_INTERFACE}.conf" <<EOF

# ${CLIENT_NAME}
[Peer]
PublicKey = ${NEW_PUBLIC}
AllowedIPs = ${SERVER_PEER_IPS}
EOF

# ── Add new peer to live WireGuard ────────────────────────
wg set "$WG_INTERFACE" peer "$NEW_PUBLIC" allowed-ips "${IPv4_CIDR}${IPv6_CIDR:+,${IPv6_CIDR}}"

log_audit "Key rotated for client: ${CLIENT_NAME}"
print_ok "Keys rotated successfully for ${CLIENT_NAME}."

# ── Regenerate QR code ────────────────────────────────────
if command -v qrencode &>/dev/null; then
    echo ""
    print_info "New QR code for ${CLIENT_NAME}:"
    echo ""
    qrencode -t ansiutf8 < "$CLIENT_CONF"
else
    print_warn "'qrencode' not installed — skipping QR code."
fi

echo ""
print_ok "Config file: ${CLIENT_CONF}"
print_warn "Distribute the new config/QR to the client — the old one no longer works."
