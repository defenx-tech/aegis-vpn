#!/usr/bin/env bash
#===========================================================
# Aegis-VPN v3.0 — Log Hooks
# Author: Rabindra
# Description: Logging functions for connection, error, and
#              audit events with automatic log rotation.
#===========================================================

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Ensure log files exist with correct permissions
touch "$CONNECTION_LOG" "$ERROR_LOG" "$AUDIT_LOG"
chmod 600 "$CONNECTION_LOG" "$ERROR_LOG" "$AUDIT_LOG"

# ── Timestamp ─────────────────────────────────────────────
timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# ── Log rotation ──────────────────────────────────────────
# Rotates $logfile when it exceeds LOG_MAX_BYTES.
# Keeps LOG_KEEP_ROTATIONS numbered copies (.1, .2, .3).
rotate_log() {
    local logfile="$1"
    [[ ! -f "$logfile" ]] && return
    local size
    size=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
    if (( size >= LOG_MAX_BYTES )); then
        local i
        for i in $(seq $((LOG_KEEP_ROTATIONS - 1)) -1 1); do
            [[ -f "${logfile}.${i}" ]] && mv "${logfile}.${i}" "${logfile}.$((i + 1))"
        done
        mv "$logfile" "${logfile}.1"
        touch "$logfile"
        chmod 600 "$logfile"
    fi
}

# ── Logging functions ─────────────────────────────────────

# Log client connection/disconnection
# Usage: log_connection "peer_name" "vpn_ip" "connected|disconnected"
log_connection() {
    local peer="$1"
    local ip="$2"
    local action="$3"
    rotate_log "$CONNECTION_LOG"
    echo "[$(timestamp)] event=client_${action} peer=${peer} ip=${ip}" >> "$CONNECTION_LOG"
}

# Log errors
# Usage: log_error "Error message"
log_error() {
    local msg="$1"
    rotate_log "$ERROR_LOG"
    echo "[$(timestamp)] event=error message=\"${msg}\"" >> "$ERROR_LOG"
}

# Log audit events (server start/stop/config changes)
# Usage: log_audit "Audit message"
log_audit() {
    local msg="$1"
    rotate_log "$AUDIT_LOG"
    echo "[$(timestamp)] event=audit message=\"${msg}\"" >> "$AUDIT_LOG"
}
