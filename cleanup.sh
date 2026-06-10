#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 Cleanup Script
# Author: Rabindra
# Description: Completely removes Aegis-VPN setup, configs,
#              logs, firewall rules, and optionally WireGuard.
# Usage: sudo ./cleanup.sh
#===========================================================

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

echo -e "${RED}[!] WARNING:${RESET} This will remove ALL Aegis-VPN files and configurations."
read -rp "Do you really want to continue? [y/N]: " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "[*] Cleanup aborted."
    exit 0
fi

# Stop and disable WireGuard
echo "[*] Stopping and disabling WireGuard..."
systemctl stop "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
systemctl daemon-reload

# Remove Aegis-VPN directories and files
echo "[*] Removing Aegis-VPN files..."
PROJECT_DIRS=(
    "/etc/wireguard"
    "${BASE_DIR}/clients"
    "${BASE_DIR}/diagrams"
    "${BASE_DIR}/docs"
    "${BASE_DIR}/scripts"
    "${BASE_DIR}/bin"
    "${BASE_DIR}/var"
    "${BASE_DIR}/setup.sh"
    "${BASE_DIR}/LICENSE"
)

for entry in "${PROJECT_DIRS[@]}"; do
    if [[ -e "$entry" ]]; then
        rm -rf "$entry"
        echo "    Removed: ${entry}"
    fi
done

# Remove any backup archives created by aegis-vpn backup
for archive in "${BASE_DIR}"/aegis-backup-*.tar.gz; do
    if [[ -f "$archive" ]]; then
        rm -f "$archive"
        echo "    Removed: ${archive}"
    fi
done

# Remove firewall rules
echo "[*] Removing firewall rules..."
ufw delete allow "${WG_PORT}/udp" 2>/dev/null || true
ufw reload 2>/dev/null || true
iptables -F 2>/dev/null || true
ip6tables -F 2>/dev/null || true

# Optional: Remove WireGuard & dependencies
read -rp "Remove WireGuard and dependencies (wireguard, qrencode, ufw)? [y/N]: " dep_confirm
if [[ "${dep_confirm,,}" == "y" ]]; then
    echo "[*] Removing WireGuard and dependencies..."
    apt-get remove --purge -y wireguard wireguard-tools qrencode ufw 2>/dev/null || true
    apt-get autoremove -y || true
fi

echo ""
echo "[*] Cleanup complete — all Aegis-VPN files and settings have been removed."
