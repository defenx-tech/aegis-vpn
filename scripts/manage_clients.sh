#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Client Manager
# Author: Rabindra
# Description: Add, remove, or list VPN clients.
# Usage: sudo ./manage_clients.sh [add|remove|list]
#===========================================================

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=log_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/log_hooks.sh"

# ── Add client ────────────────────────────────────────────
add_client() {
    read -rp "Enter client name: " CLIENT_NAME
    if [[ -z "$CLIENT_NAME" ]]; then
        print_err "Client name cannot be empty."
        log_error "Attempted to add client with empty name"
        return 1
    fi
    validate_client_name "$CLIENT_NAME" || return 1
    require_wg_running
    "$SCRIPTS_DIR/add_client.sh" "$CLIENT_NAME"
}

# ── Remove client ─────────────────────────────────────────
remove_client() {
    read -rp "Enter client name to remove: " CLIENT_NAME
    if [[ -z "$CLIENT_NAME" ]]; then
        print_err "Client name cannot be empty."
        log_error "Attempted to remove client with empty name"
        return 1
    fi

    local CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
    if [[ ! -f "$CONF" ]]; then
        print_err "Client '${CLIENT_NAME}' not found."
        log_error "Attempted to remove non-existing client: ${CLIENT_NAME}"
        return 1
    fi

    echo -e "${YELLOW}[!]${RESET} This will permanently remove client '${CLIENT_NAME}'."
    read -rp "    Are you sure? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Aborted."
        return 0
    fi

    require_wg_running

    # Extract public key BEFORE removing the conf file
    local CLIENT_PRIVATE CLIENT_PUBLIC
    CLIENT_PRIVATE=$(awk '/^PrivateKey[[:space:]]*=/{print $3}' "$CONF")
    CLIENT_PUBLIC=$(echo "$CLIENT_PRIVATE" | wg pubkey)

    local CLIENT_IPv4
    CLIENT_IPv4=$(awk -F'[ /,]' '/^Address[[:space:]]*=/{print $3}' "$CONF")

    # Remove client config file
    rm -f "$CONF"
    print_ok "Removed ${CONF}"

    # Remove peer block from wg0.conf using awk state machine (safe removal)
    remove_peer_block "$CLIENT_NAME"

    # Remove peer from live WireGuard
    if [[ -n "$CLIENT_PUBLIC" ]]; then
        wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC" remove 2>/dev/null || true
    fi

    log_connection "$CLIENT_NAME" "${CLIENT_IPv4:-N/A}" "disconnected"
    log_audit "Client removed: ${CLIENT_NAME}"
    print_ok "Client '${CLIENT_NAME}' removed successfully."
    send_telegram_alert "Aegis-VPN: client ${CLIENT_NAME} removed at $(date '+%Y-%m-%d %H:%M:%S')"
}

# ── List clients ──────────────────────────────────────────
list_clients() {
    local wg_running=false
    systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null && wg_running=true

    print_info "Clients (Aegis-VPN v${AEGIS_VERSION})"
    echo ""
    printf "%-20s %-16s %-20s %-10s %-20s\n" \
           "Name" "IPv4" "IPv6" "Status" "Last Handshake"
    printf '%0.s─' {1..90}; echo ""

    local found=false
    for conf in "${CLIENTS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        found=true

        local name ipv4 ipv6
        name=$(basename "$conf" .conf)
        ipv4=$(awk -F'[[:space:]/,]+' '/^Address[[:space:]]*=/{print $3}' "$conf")
        ipv6=$(awk -F'[[:space:]/,]+' '/^Address[[:space:]]*=/{print $5}' "$conf")

        local status_str="unknown" hs_str="n/a"

        if [[ "$wg_running" == true ]]; then
            local privkey pubkey hs_epoch
            privkey=$(awk '/^PrivateKey[[:space:]]*=/{print $3}' "$conf")
            pubkey=$(echo "$privkey" | wg pubkey 2>/dev/null || true)

            if [[ -n "$pubkey" ]]; then
                hs_epoch=$(wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null \
                           | awk -v pk="$pubkey" '$1==pk{print $2}')

                if [[ -n "$hs_epoch" && "$hs_epoch" != "0" ]]; then
                    local now delta
                    now=$(date +%s)
                    delta=$(( now - hs_epoch ))
                    hs_str=$(date -d "@${hs_epoch}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
                    if (( delta < 180 )); then
                        status_str="${GREEN}online${RESET} "
                    else
                        status_str="${RED}offline${RESET}"
                    fi
                else
                    status_str="${YELLOW}never${RESET}  "
                    hs_str="never"
                fi
            fi
        else
            status_str="${YELLOW}wg-down${RESET}"
        fi

        printf "%-20s %-16s %-20s " "$name" "$ipv4" "${ipv6:-—}"
        printf "${status_str} "
        printf "%-20s\n" "$hs_str"
    done

    if [[ "$found" == false ]]; then
        echo "  No clients found."
    fi
    echo ""
}

# ── Main ──────────────────────────────────────────────────
if [[ -z "${1:-}" ]]; then
    print_info "Choose action: add / remove / list"
    read -r ACTION
else
    ACTION="$1"
fi

case "$ACTION" in
    add)    add_client ;;
    remove) remove_client ;;
    list)   list_clients ;;
    *)
        print_err "Invalid action '${ACTION}'. Use: add, remove, list"
        log_error "Invalid action in manage_clients.sh: ${ACTION}"
        exit 1
        ;;
esac
