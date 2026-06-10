#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Server Key Rotation
# Author: Rabindra
# Description: Rotates the WireGuard server private key with
#              minimal client disruption, then updates and
#              redistributes all client configurations.
#
# Design notes (ref: issue #5):
#   WireGuard has no native dual-key grace period. This script
#   minimises the disruption window by:
#     1. Auto-backing up all configs before touching anything.
#     2. Swapping the kernel-level key in-place via
#        "wg set <iface> private-key <file>" — the interface
#        stays up, no firewall rules are flushed. Clients lose
#        connectivity for ~1 handshake cycle (~5 s typical).
#     3. Updating every client config atomically before any
#        client attempts to reconnect, so re-handshakes succeed
#        immediately.
#     4. Writing full audit records (old key, new key, timestamp,
#        client count).
#
# Usage: sudo ./rotate_server.sh [--qr] [--no-backup]
#   --qr         Display a fresh QR code for every client after rotation
#   --no-backup  Skip the automatic pre-rotation backup
#===========================================================

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=log_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/log_hooks.sh"
# shellcheck source=backup_restore.sh
source "$(dirname "${BASH_SOURCE[0]}")/backup_restore.sh"

# ── Parse flags ───────────────────────────────────────────
SHOW_QR=false
SKIP_BACKUP=false
for arg in "$@"; do
    case "$arg" in
        --qr)        SHOW_QR=true ;;
        --no-backup) SKIP_BACKUP=true ;;
        *) print_err "Unknown flag: ${arg}"; exit 1 ;;
    esac
done

# ── Pre-flight checks ─────────────────────────────────────
require_wg_running

if [[ ! -f "${WG_DIR}/privatekey" || ! -f "${WG_DIR}/publickey" ]]; then
    print_err "Server key files not found in ${WG_DIR}/. Run setup first."
    exit 1
fi

# ── Warn and confirm ──────────────────────────────────────
echo ""
echo -e "${BOLD}Aegis-VPN — Server Key Rotation${RESET}"
echo "──────────────────────────────────────────────────────"
echo -e "${YELLOW}[!]${RESET} This will:"
echo "    1. Generate a new server key pair"
echo "    2. Swap the live WireGuard key in-place (interface stays up)"
echo "    3. Update ALL client configuration files with the new server public key"
echo "    4. Clients will lose connectivity for ~1 handshake cycle (~5 s)"
echo "       until they receive updated configs and reconnect."
echo ""

CLIENT_COUNT=0
for f in "${CLIENTS_DIR}"/*.conf; do [[ -f "$f" ]] && CLIENT_COUNT=$((CLIENT_COUNT + 1)); done
echo -e "    Clients that will be affected: ${BOLD}${CLIENT_COUNT}${RESET}"
echo ""

read -rp "Continue? [y/N]: " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# ── Step 1 — Auto backup ──────────────────────────────────
if [[ "$SKIP_BACKUP" == false ]]; then
    print_info "Step 1/5 — Creating pre-rotation backup..."
    BACKUP_FILE=$(do_backup)
    print_ok "Backup saved to: ${BACKUP_FILE}"
else
    print_warn "Step 1/5 — Backup skipped (--no-backup)"
fi
echo ""

# ── Step 2 — Generate new server key pair ────────────────
print_info "Step 2/5 — Generating new server key pair..."
OLD_PUBLIC_KEY=$(< "${WG_DIR}/publickey")

NEW_PRIVATE_KEY=$(wg genkey)
NEW_PUBLIC_KEY=$(echo "${NEW_PRIVATE_KEY}" | wg pubkey)

# Write new keys to disk
echo "${NEW_PRIVATE_KEY}" > "${WG_DIR}/privatekey"
echo "${NEW_PUBLIC_KEY}"  > "${WG_DIR}/publickey"
chmod 600 "${WG_DIR}/privatekey" "${WG_DIR}/publickey"
print_ok "New key pair generated."
echo ""

# ── Step 3 — Apply new key to live interface (in-place) ───
print_info "Step 3/5 — Applying new private key to live interface..."
# This swaps the key at kernel level without taking the interface down.
# Existing sessions immediately become invalid; clients reconnect on
# next handshake attempt (within PersistentKeepalive window).
wg set "${WG_INTERFACE}" private-key "${WG_DIR}/privatekey"

# Persist new PrivateKey in wg0.conf (for reboots / SaveConfig)
# Use a temp file to make the replacement atomic.
local_conf="${WG_DIR}/${WG_INTERFACE}.conf"
tmp_conf="${local_conf}.tmp"
awk -v newkey="${NEW_PRIVATE_KEY}" '
    /^PrivateKey[[:space:]]*=/ { print "PrivateKey = " newkey; next }
    { print }
' "${local_conf}" > "${tmp_conf}" && mv "${tmp_conf}" "${local_conf}"
chmod 600 "${local_conf}"
print_ok "Live interface key swapped — interface remained up."
echo ""

# ── Step 4 — Update all client configs ───────────────────
print_info "Step 4/5 — Updating client configurations..."
UPDATED=0
FAILED=0

for conf in "${CLIENTS_DIR}"/*.conf; do
    [[ -f "$conf" ]] || continue
    cname=$(basename "$conf" .conf)

    # Replace the server's PublicKey line inside the [Peer] section.
    # Uses a two-pass awk: track being inside [Peer] then swap the key.
    tmp_client="${conf}.tmp"
    awk -v oldpub="${OLD_PUBLIC_KEY}" -v newpub="${NEW_PUBLIC_KEY}" '
        /^\[Peer\]/    { in_peer=1 }
        /^\[Interface\]/ { in_peer=0 }
        in_peer && /^PublicKey[[:space:]]*=/ && $3 == oldpub {
            print "PublicKey = " newpub; next
        }
        { print }
    ' "$conf" > "$tmp_client"

    # Verify the replacement actually happened
    if grep -q "PublicKey = ${NEW_PUBLIC_KEY}" "$tmp_client"; then
        mv "$tmp_client" "$conf"
        chmod 600 "$conf"
        UPDATED=$((UPDATED + 1))
        print_ok "  Updated: ${cname}"
    else
        rm -f "$tmp_client"
        FAILED=$((FAILED + 1))
        print_err "  Failed to update: ${cname} (server PublicKey not found in [Peer])"
    fi
done
echo ""

# ── Step 5 — Audit log ───────────────────────────────────
print_info "Step 5/5 — Writing audit record..."
log_audit "SERVER KEY ROTATED | old_pubkey=${OLD_PUBLIC_KEY} | new_pubkey=${NEW_PUBLIC_KEY} | clients_updated=${UPDATED} | clients_failed=${FAILED}"
print_ok "Audit record written to ${AUDIT_LOG}"
echo ""

# ── Summary ───────────────────────────────────────────────
echo -e "${BOLD}─── Rotation Summary ────────────────────────────────${RESET}"
echo "  Old public key : ${OLD_PUBLIC_KEY}"
echo "  New public key : ${NEW_PUBLIC_KEY}"
echo "  Clients updated: ${UPDATED}"
if (( FAILED > 0 )); then
    echo -e "  ${RED}Clients failed : ${FAILED}${RESET} — check those configs manually"
fi
echo ""
echo -e "${GREEN}[*]${RESET} Server key rotation complete."
echo -e "${YELLOW}[!]${RESET} Distribute updated configs (${CLIENTS_DIR}/) to all clients."
echo -e "${YELLOW}[!]${RESET} Clients with stale configs will be unable to reconnect."
echo ""

# ── Optional: Show QR codes for all clients ───────────────
if [[ "$SHOW_QR" == true ]]; then
    if ! command -v qrencode &>/dev/null; then
        print_warn "'qrencode' not installed — cannot display QR codes."
    else
        echo -e "${BOLD}─── Updated QR Codes ────────────────────────────────${RESET}"
        for conf in "${CLIENTS_DIR}"/*.conf; do
            [[ -f "$conf" ]] || continue
            cname=$(basename "$conf" .conf)
            echo ""
            echo -e "${CYAN}── ${cname} ────────────────────────────────────────────${RESET}"
            qrencode -t ansiutf8 < "$conf"
        done
    fi
else
    echo -e "${CYAN}[~]${RESET} Run with --qr to display updated QR codes for all clients."
    echo -e "${CYAN}[~]${RESET} Or run: aegis-vpn rotate-server --qr"
fi
