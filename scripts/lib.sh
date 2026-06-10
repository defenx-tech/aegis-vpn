#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Shared Library
# Author: Rabindra
# Description: Shared constants, colors, and utility functions
#              sourced by all Aegis-VPN scripts.
#===========================================================

# Version
AEGIS_VERSION="3.0.0"

# Paths (derived from this file's location, so they work from any cwd)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
CLIENTS_DIR="$BASE_DIR/clients"
LOG_DIR="$BASE_DIR/var/log/aegis-vpn"
VAR_DIR="$BASE_DIR/var"
LOCK_FILE="$VAR_DIR/aegis-vpn.lock"
IP_COUNTER_FILE="$VAR_DIR/next_ip.dat"

# WireGuard
WG_DIR="/etc/wireguard"
WG_INTERFACE="wg0"
WG_PORT="51820"
VPN_SUBNET="10.10.0"
VPN_SUBNET_CIDR="10.10.0.0/24"
VPN_IPv6_PREFIX="fd86:ea04:1115"

# Log files
CONNECTION_LOG="$LOG_DIR/connections.log"
ERROR_LOG="$LOG_DIR/errors.log"
AUDIT_LOG="$LOG_DIR/audit.log"
LOG_MAX_BYTES=10485760   # 10 MB
LOG_KEEP_ROTATIONS=3

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Telegram (optional — set in /etc/aegis-vpn/aegis.conf)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# ── Load optional config file ─────────────────────────────
load_config() {
    local conf_path="/etc/aegis-vpn/aegis.conf"
    if [[ -f "$conf_path" ]]; then
        # shellcheck source=/dev/null
        source "$conf_path"
    fi
}

# ── Send Telegram alert (optional) ────────────────────────
# Usage: send_telegram_alert "message text"
send_telegram_alert() {
    local msg="$1"
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return
    fi
    curl -s --max-time 5 -o /dev/null \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${msg}" \
        2>/dev/null || true
}

# Load config early so TELEGRAM_* vars are available
load_config

# Ensure runtime directories exist
mkdir -p "$CLIENTS_DIR" "$LOG_DIR" "$VAR_DIR"
chmod 700 "$CLIENTS_DIR" "$LOG_DIR"

# ── Print helpers ─────────────────────────────────────────
print_ok()   { echo -e "${GREEN}[*]${RESET} $*"; }
print_warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
print_err()  { echo -e "${RED}[!]${RESET} $*" >&2; }
print_info() { echo -e "${CYAN}[~]${RESET} $*"; }

# ── Auto-detect outgoing network interface ────────────────
detect_iface() {
    ip route 2>/dev/null | awk '/^default/ {print $5; exit}'
}

# ── Validate client name: [a-zA-Z0-9_-], max 32 chars ────
validate_client_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
        print_err "Invalid client name '${name}'. Use a-z, A-Z, 0-9, _ or - (max 32 chars)."
        return 1
    fi
}

# ── Atomic lock file (prevents IP allocation race) ────────
acquire_lock() {
    local timeout=10
    local waited=0
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        sleep 0.5
        waited=$((waited + 1))
        if (( waited >= timeout * 2 )); then
            print_err "Could not acquire lock — another aegis-vpn operation may be running."
            exit 1
        fi
    done
    # Always release on exit/signal
    trap 'release_lock' EXIT INT TERM
}

release_lock() {
    rm -rf "$LOCK_FILE"
}

# ── Spinner for long operations ───────────────────────────
# Usage: some_command & spinner $! "Doing something..."
spinner() {
    local pid="$1"
    local msg="${2:-Working...}"
    local frames=('|' '/' '-' '\')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}[%s]${RESET} %s" "${frames[i % 4]}" "$msg"
        i=$((i + 1))
        sleep 0.15
    done
    printf "\r%-60s\r" " "
}

# ── Guard: abort if WireGuard interface is not running ────
require_wg_running() {
    if ! systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        print_err "WireGuard (${WG_INTERFACE}) is not running. Start it first:"
        print_err "  systemctl start wg-quick@${WG_INTERFACE}"
        exit 1
    fi
}

# ── Next available client IP octet ───────────────────────
# Reads/writes $IP_COUNTER_FILE; scans wg0.conf to skip used IPs.
# Returns the octet (2-253) and increments the counter.
# Must be called inside acquire_lock / release_lock.
next_client_octet() {
    local counter=2
    if [[ -f "$IP_COUNTER_FILE" ]]; then
        counter=$(< "$IP_COUNTER_FILE")
    fi
    # Advance past any already-assigned addresses (handles gaps from deletions)
    while grep -q "AllowedIPs = ${VPN_SUBNET}\.${counter}/" \
          "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null; do
        counter=$((counter + 1))
        if (( counter > 253 )); then
            print_err "No available IP addresses in subnet ${VPN_SUBNET_CIDR}."
            exit 1
        fi
    done
    echo $((counter + 1)) > "$IP_COUNTER_FILE"
    echo "$counter"
}

# ── Remove a peer block from wg0.conf (awk state machine) ─
# Usage: remove_peer_block "client_name"
remove_peer_block() {
    local client_name="$1"
    local conf="${WG_DIR}/${WG_INTERFACE}.conf"
    local tmpfile="${conf}.tmp"

    awk -v target="# ${client_name}" '
        $0 == target      { in_block=1; next }
        in_block && /^\[/ { in_block=0 }
        !in_block         { print }
    ' "$conf" > "$tmpfile" && mv "$tmpfile" "$conf"
    chmod 600 "$conf"
}
