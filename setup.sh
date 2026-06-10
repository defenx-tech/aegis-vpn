#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 Setup Script
# Author: Rabindra
# Description:
#   - WireGuard server (wg0) on 10.10.0.0/24
#   - IPv4 full tunnel for clients (0.0.0.0/0)
#   - IPv6 enabled inside tunnel only (no broken NAT66 hacks)
#   - iptables-only firewall (no UFW)
#   - NAT + forwarding correctly configured
# Usage:
#   sudo ./setup.sh [--auto]
#===========================================================

# Install figlet if missing (quietly)
if ! command -v figlet >/dev/null 2>&1; then
    echo "[*] Installing figlet for banner..."
    apt-get update -qq
    apt-get install -y figlet >/dev/null 2>&1
fi

# Display banner
clear
figlet -f big "AEGIS VPN"
echo -e "\e[1;32mSecure, Fast, Modern — v3.0\e[0m"
echo -e "\e[1;33mby Rabindra - 2026\e[0m"
echo

set -euo pipefail

# Variables
WG_INTERFACE="wg0"
WG_PORT="${WG_PORT:-51820}"

WG_DIR="/etc/wireguard"
CLIENTS_DIR="$PWD/clients"

SERVER_V4_CIDR="10.10.0.1/24"
SERVER_V6_CIDR="fd86:ea04:1115::1/64"

# Clients: full IPv4 tunnel, IPv6 internal only (safe default)
CLIENT_ALLOWED_IPS_V4="0.0.0.0/0"
CLIENT_ALLOWED_IPS_V6="fd86:ea04:1115::/64"

DNS_SERVERS="1.1.1.1, 1.0.0.1"
SSH_PORT="${SSH_PORT:-22}"
ALLOW_PING=true

AUTO_MODE=false
[[ "${1:-}" == "--auto" ]] && AUTO_MODE=true

# Auto-detect outgoing network interface (replaces hardcoded enX0)
WG_IFACE=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
if [[ -z "$WG_IFACE" ]]; then
    echo "[!] Could not auto-detect network interface."
    if [[ "$AUTO_MODE" == true ]]; then
        echo "[!] --auto mode requires a default route. Aborting."
        exit 1
    fi
    read -rp "Enter your network interface name (e.g. eth0): " WG_IFACE
fi
echo "[*] Using network interface: ${WG_IFACE}"

# Get public IP
echo "[*] Detecting server public IP..."
SERVER_PUBLIC_IP=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || true)
if [[ -z "$SERVER_PUBLIC_IP" ]]; then
    if [[ "$AUTO_MODE" == true ]]; then
        echo "[!] Could not detect public IP in --auto mode. Proceeding without it."
        SERVER_PUBLIC_IP="<your-server-ip>"
    else
        read -rp "[!] Could not detect public IP. Enter it manually: " SERVER_PUBLIC_IP
    fi
fi

# Install dependencies
echo "[*] Installing dependencies..."
apt-get update -qq
apt-get install -y wireguard qrencode ufw curl

# Enable IP forwarding (fix: correct sysctl.conf path)
echo "[*] Enabling IPv4 and IPv6 forwarding..."
SYSCTL_FILE="/etc/sysctl.conf"
if [[ ! -f "$SYSCTL_FILE" ]]; then
    echo "[*] /etc/sysctl.conf not found. Creating..."
    touch "$SYSCTL_FILE"
fi

# Generate server keys
echo "[*] Generating server keys..."
mkdir -p "$WG_DIR"
cd "$WG_DIR" || exit 1
wg genkey | tee privatekey | wg pubkey > publickey
chmod 600 privatekey publickey
SERVER_PRIVATE_KEY=$(< privatekey)
SERVER_PUBLIC_KEY=$(< publickey)

# Create wg0.conf from template (substitute placeholders)
echo "[*] Creating ${WG_INTERFACE}.conf..."
cat > "${WG_INTERFACE}.conf" <<EOF
[Interface]
Address = 10.10.0.1/24, fd86:ea04:1115::1/64
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = true
PostUp   = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WG_IFACE} -j MASQUERADE; ip6tables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; ip6tables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WG_IFACE} -j MASQUERADE; ip6tables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; ip6tables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT
EOF
sed -i 's/\r$//' "${WG_INTERFACE}.conf"
chmod 600 "${WG_INTERFACE}.conf"

# Start & Enable WireGuard
echo "[*] Starting WireGuard..."
systemctl enable "wg-quick@${WG_INTERFACE}"
systemctl start "wg-quick@${WG_INTERFACE}"

# Firewall
echo "[*] Applying firewall rules..."
ufw allow "${WG_PORT}/udp"
ufw --force enable

echo ""
echo "[*] Aegis-VPN v3.0 setup complete!"
echo "    Server Public IP  : ${SERVER_PUBLIC_IP}"
echo "    Network interface : ${WG_IFACE}"
echo "    Config file       : ${WG_DIR}/${WG_INTERFACE}.conf"
echo "    Server Public Key : ${SERVER_PUBLIC_KEY}"
echo ""
echo "[*] Next step: add clients with 'sudo ./bin/aegis-vpn add'"
