#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Client Config Generator
# Author: Rabindra
# Description: Generates client keys, WireGuard config, and
#              QR code for easy mobile/desktop onboarding.
# Usage: sudo ./add_client.sh <client-name>
#===========================================================

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=log_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/log_hooks.sh"

# ── Input validation ──────────────────────────────────────
if [[ $# -lt 1 || -z "$1" ]]; then
    print_err "Usage: sudo ./add_client.sh <client-name>"
    log_error "Failed to add client: missing client name"
    exit 1
fi

CLIENT_NAME="$1"
validate_client_name "$CLIENT_NAME" || exit 1

if [[ -f "${CLIENTS_DIR}/${CLIENT_NAME}.conf" ]]; then
    print_err "Client '${CLIENT_NAME}' already exists."
    print_info "Use 'aegis-vpn rotate ${CLIENT_NAME}' to regenerate keys."
    exit 1
fi

require_wg_running

# ── DNS selection ─────────────────────────────────────────
select_dns() {
    echo ""
    print_info "Select DNS resolver:"
    echo "   1) Cloudflare   1.1.1.1, 1.0.0.1"
    echo "   2) Google       8.8.8.8, 8.8.4.4"
    echo "   3) Quad9        9.9.9.9, 149.112.112.112"
    echo "   4) Custom"
    read -rp "Choice [1]: " dns_choice
    case "${dns_choice:-1}" in
        1) echo "1.1.1.1, 1.0.0.1" ;;
        2) echo "8.8.8.8, 8.8.4.4" ;;
        3) echo "9.9.9.9, 149.112.112.112" ;;
        4)
            read -rp "Enter DNS IP(s) (comma-separated): " custom_dns
            echo "${custom_dns:-1.1.1.1}"
            ;;
        *) echo "1.1.1.1, 1.0.0.1" ;;
    esac
}

# ── Tunnel mode selection ─────────────────────────────────
select_tunnel_mode() {
    echo ""
    print_info "Select tunnel mode:"
    echo "   1) Full tunnel  — all traffic routed through VPN  (0.0.0.0/0, ::/0)"
    echo "   2) VPN only     — only VPN subnet traffic         (${VPN_SUBNET_CIDR})"
    read -rp "Choice [1]: " mode_choice
    case "${mode_choice:-1}" in
        1) echo "0.0.0.0/0, ::/0" ;;
        2) echo "${VPN_SUBNET_CIDR}" ;;
        *) echo "0.0.0.0/0, ::/0" ;;
    esac
}

CLIENT_DNS=$(select_dns)
CLIENT_ALLOWED_IPS=$(select_tunnel_mode)
echo ""

# ── Fetch server public key and IP ───────────────────────
if [[ ! -f "${WG_DIR}/publickey" ]]; then
    print_err "Server public key not found at ${WG_DIR}/publickey. Run setup first."
    exit 1
fi
SERVER_PUBLIC_KEY=$(< "${WG_DIR}/publickey")

print_info "Detecting server public IP..."
SERVER_IP=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || true)
if [[ -z "$SERVER_IP" ]]; then
    print_warn "Could not auto-detect public IP. Please enter it manually:"
    read -rp "Server public IP: " SERVER_IP
fi

# ── Allocate unique client IPs (race-safe) ───────────────
acquire_lock
CLIENT_OCTET=$(next_client_octet)
CLIENT_IPv4="${VPN_SUBNET}.${CLIENT_OCTET}"
CLIENT_IPv6="${VPN_IPv6_PREFIX}::${CLIENT_OCTET}"
# Lock is released by the EXIT trap in lib.sh

# ── Generate client keys ──────────────────────────────────
print_info "Generating keys for ${CLIENT_NAME}..."
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# ── Create client configuration ───────────────────────────
CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
print_info "Creating client configuration at ${CLIENT_CONF}..."

cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IPv4}/32, ${CLIENT_IPv6}/128
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = ${CLIENT_ALLOWED_IPS}
PersistentKeepalive = 25
EOF
sed -i 's/\r$//' "$CLIENT_CONF"

chmod 600 "$CLIENT_CONF"

# ── Register peer on server ───────────────────────────────
print_info "Adding ${CLIENT_NAME} to server configuration..."
cat >> "${WG_DIR}/${WG_INTERFACE}.conf" <<EOF

# ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IPv4}/32, ${CLIENT_IPv6}/128
EOF
sed -i 's/\r$//' "${WG_DIR}/${WG_INTERFACE}.conf"

wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC_KEY" \
    allowed-ips "${CLIENT_IPv4}/32,${CLIENT_IPv6}/128"

# ── Log ───────────────────────────────────────────────────
log_connection "$CLIENT_NAME" "$CLIENT_IPv4" "connected"
log_audit "Client added: ${CLIENT_NAME} (${CLIENT_IPv4}, ${CLIENT_IPv6})"

# ── Generate QR code ──────────────────────────────────────
if command -v qrencode &>/dev/null; then
    echo ""
    print_info "QR code for ${CLIENT_NAME} (scan with WireGuard mobile app):"
    echo ""
    qrencode -t ansiutf8 < "$CLIENT_CONF" &
    spinner $! "Generating QR code..."
    wait
else
    print_warn "'qrencode' not found — install it to generate QR codes."
fi

echo ""
print_ok "Client '${CLIENT_NAME}' added successfully!"
echo "   IPv4        : ${CLIENT_IPv4}"
echo "   IPv6        : ${CLIENT_IPv6}"
echo "   DNS         : ${CLIENT_DNS}"
echo "   Tunnel mode : ${CLIENT_ALLOWED_IPS}"
echo "   Config file : ${CLIENT_CONF}"

send_telegram_alert "Aegis-VPN: client ${CLIENT_NAME} added at $(date '+%Y-%m-%d %H:%M:%S')"
