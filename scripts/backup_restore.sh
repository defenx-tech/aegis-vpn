#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Backup & Restore
# Author: Rabindra
# Description: Creates and restores tarball backups of all
#              WireGuard configs and client configurations.
# Usage: sourced by bin/aegis-vpn; or run directly
#===========================================================

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=log_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/log_hooks.sh"

# ── Create backup ─────────────────────────────────────────
do_backup() {
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local out="${BASE_DIR}/aegis-backup-${ts}.tar.gz"

    print_info "Creating backup..."

    local -a include=()
    [[ -d "$WG_DIR" ]]      && include+=("$WG_DIR")
    [[ -d "$CLIENTS_DIR" ]] && include+=("$CLIENTS_DIR")
    [[ -f "$IP_COUNTER_FILE" ]] && include+=("$IP_COUNTER_FILE")

    if (( ${#include[@]} == 0 )); then
        print_warn "Nothing to back up — no WireGuard config or clients found."
        return 1
    fi

    tar -czf "$out" "${include[@]}" 2>/dev/null
    chmod 600 "$out"

    print_ok "Backup created: ${out}"
    log_audit "Backup created: ${out}"
    echo "$out"
}

# ── Restore from backup ───────────────────────────────────
do_restore() {
    local archive="$1"

    if [[ ! -f "$archive" ]]; then
        print_err "Backup file not found: ${archive}"
        exit 1
    fi

    echo -e "${YELLOW}[!]${RESET} This will overwrite /etc/wireguard/ and ${CLIENTS_DIR}/."
    read -rp "    Continue? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi

    print_info "Stopping WireGuard before restore..."
    systemctl stop "wg-quick@${WG_INTERFACE}" 2>/dev/null || true

    print_info "Extracting ${archive}..."
    tar -xzf "$archive" -C / 2>/dev/null

    # Re-apply correct permissions
    [[ -f "${WG_DIR}/${WG_INTERFACE}.conf" ]] && chmod 600 "${WG_DIR}/${WG_INTERFACE}.conf"
    [[ -f "${WG_DIR}/privatekey" ]]           && chmod 600 "${WG_DIR}/privatekey"

    print_info "Restarting WireGuard..."
    systemctl start "wg-quick@${WG_INTERFACE}"

    print_ok "Restore complete from: ${archive}"
    log_audit "Restore performed from: ${archive}"
}

# Run directly if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        backup)  do_backup ;;
        restore) do_restore "${2:-}" ;;
        *) echo "Usage: $0 backup | restore <file>" ;;
    esac
fi
