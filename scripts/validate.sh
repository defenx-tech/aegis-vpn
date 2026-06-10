#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Config Validator
# Author: Rabindra
# Description: Validates wg0.conf integrity and detects
#              orphaned peers or client configurations.
# Usage: sourced by bin/aegis-vpn; or run directly for testing
#===========================================================

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=log_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/log_hooks.sh"

# ── Validate WireGuard configuration integrity ────────────
validate_config() {
    local errors=0
    local conf="${WG_DIR}/${WG_INTERFACE}.conf"

    print_info "Running Aegis-VPN v${AEGIS_VERSION} config validation..."
    echo ""

    # 1. Config file exists
    if [[ ! -f "$conf" ]]; then
        print_err "wg0.conf not found at ${WG_DIR}/"
        errors=$((errors + 1))
    else
        print_ok "Found ${conf}"

        # 2. Server PrivateKey is valid base64 (44 chars ending in =)
        local privkey
        privkey=$(awk '/^\[Interface\]/{f=1} f && /^PrivateKey/{print $3; exit}' "$conf")
        if [[ "$privkey" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
            print_ok "Server PrivateKey format valid"
        else
            print_err "Server PrivateKey appears malformed or missing"
            errors=$((errors + 1))
        fi

        # 3. Every peer PublicKey is valid base64 (44 chars)
        local bad_keys=0
        while IFS= read -r pk; do
            if [[ ! "$pk" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
                print_err "Malformed peer PublicKey: ${pk}"
                bad_keys=$((bad_keys + 1))
                errors=$((errors + 1))
            fi
        done < <(awk '/^\[Peer\]/{p=1} p && /^PublicKey/{print $3; p=0}' "$conf")
        if (( bad_keys == 0 )); then
            local peer_count
            peer_count=$(grep -c '^\[Peer\]' "$conf" 2>/dev/null) || peer_count=0
            print_ok "All ${peer_count} peer PublicKey(s) valid"
        fi

        # 4. Orphaned peers: in wg0.conf but no matching client conf
        local orphaned_peers=0
        while IFS= read -r comment; do
            local cname="${comment#\# }"
            # Skip generic comments (not peer labels)
            [[ "$cname" == "$comment" ]] && continue
            if [[ ! -f "${CLIENTS_DIR}/${cname}.conf" ]]; then
                print_warn "Orphaned peer in wg0.conf — no client conf for: ${cname}"
                orphaned_peers=$((orphaned_peers + 1))
                errors=$((errors + 1))
            fi
        done < <(grep '^# [^#]' "$conf" 2>/dev/null)
        if (( orphaned_peers == 0 )); then
            print_ok "No orphaned peers in wg0.conf"
        fi
    fi

    # 5. Orphaned client confs: conf file but no matching peer in wg0.conf
    local orphaned_confs=0
    for conf_file in "${CLIENTS_DIR}"/*.conf; do
        [[ -f "$conf_file" ]] || continue
        local cname
        cname=$(basename "$conf_file" .conf)
        if [[ -f "$conf" ]] && ! grep -q "^# ${cname}$" "$conf" 2>/dev/null; then
            print_warn "Client conf exists but no server peer: ${cname}"
            orphaned_confs=$((orphaned_confs + 1))
            errors=$((errors + 1))
        fi
    done
    if (( orphaned_confs == 0 )); then
        print_ok "All client confs have matching server peers"
    fi

    echo ""
    if (( errors == 0 )); then
        print_ok "Validation passed — no issues found."
        log_audit "Config validation passed"
    else
        print_err "${errors} issue(s) found. Review the warnings above."
        log_audit "Config validation found ${errors} issue(s)"
        return 1
    fi
}

# Run directly if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    validate_config
fi
