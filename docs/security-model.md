# Aegis-VPN Security Model

## Cryptographic Foundation

Aegis-VPN is built on WireGuard, which uses a fixed, modern cryptographic stack:

| Primitive | Algorithm |
|-----------|-----------|
| Key exchange | Curve25519 (ECDH) |
| Symmetric encryption | ChaCha20 |
| Authentication | Poly1305 MAC |
| Hashing | BLAKE2s |
| Key derivation | HKDF |

There is no algorithm negotiation — the attack surface is minimal compared to OpenVPN or IPSec.

---

## Threat Model

### Threats Mitigated

| Threat | Mitigation |
|--------|-----------|
| Man-in-the-middle | Public-key authentication — both sides verify each other's identity before any data flows |
| Unauthorized peer access | WireGuard silently drops packets from peers whose public key is not in the allowed list |
| IP leaks | `AllowedIPs = 0.0.0.0/0, ::/0` (full tunnel) routes all traffic through the VPN; `PersistentKeepalive = 25` prevents NAT holes from closing |
| Replay attacks | WireGuard uses session-level nonces and rejects replayed packets |
| Compromised client key | `aegis-vpn rotate <client>` regenerates the client's key pair; the old key is immediately removed from the server |
| Compromised server key | `aegis-vpn rotate-server` rotates the server private key in-place; all client configs are updated atomically |
| Log exposure | `--privacy` flag masks all IPv4 and IPv6 addresses in logs and dashboard output |
| Config tampering | `aegis-vpn check` validates key formats and detects orphaned or mismatched peer entries |

### Threats Not Mitigated (Out of Scope)

- **Compromised server root access** — if an attacker has root on the server, they can read `/etc/wireguard/privatekey`. Mitigate with OS-level controls (disk encryption, SSH hardening, minimal attack surface).
- **Client device compromise** — if a client device is compromised, its private key may be stolen. Rotate immediately with `aegis-vpn rotate <client>`.
- **Traffic analysis** — VPN masks payload content and source/destination, but timing and volume patterns may still be observable by a network-level adversary.
- **DNS outside the tunnel** — in VPN-only tunnel mode (`10.10.0.0/24`), DNS queries may leak outside the VPN. Use full tunnel mode for maximum privacy.

---

## Key Management

### Server Keys

- Server private key: `/etc/wireguard/privatekey` (`chmod 600`, root-only)
- Server public key: `/etc/wireguard/publickey`
- Rotate with: `sudo ./bin/aegis-vpn rotate-server`

**Rotation procedure:**
1. New key pair generated
2. New private key applied to the live WireGuard interface in-place (no restart)
3. `wg0.conf` updated atomically
4. Every `clients/*.conf` updated with the new server public key
5. Full audit record written to `var/log/aegis-vpn/audit.log`

### Client Keys

- Client private key is embedded in `clients/<name>.conf` and the client's device
- Never stored on the server after the initial QR/config distribution
- Rotate with: `sudo ./bin/aegis-vpn rotate <client>`

### Key Rotation Recommendations

| Key | Recommended rotation interval |
|-----|-------------------------------|
| Individual client | On compromise, on device loss, or every 90 days |
| Server | On suspected compromise, or every 180 days |

---

## Audit Logging

All sensitive operations are recorded in `var/log/aegis-vpn/audit.log`:

- Client added (name, IPv4, IPv6)
- Client removed
- Client key rotated
- Server key rotated (old public key, new public key, client count updated)
- Config validation results
- Backups created or restored

Log format:
```
[YYYY-MM-DD HH:MM:SS] event=audit message="..."
```

Logs rotate automatically at 10 MB, keeping 3 rotations.

---

## Firewall

Setup configures UFW to:
- Allow UDP `51820` (WireGuard)
- Enable NAT/masquerading via iptables on the detected outbound interface
- Enable IPv6 forwarding with ip6tables rules

The firewall rules are applied via WireGuard's `PostUp`/`PostDown` hooks in `wg0.conf`, so they are automatically removed if WireGuard is stopped.

---

## Assumptions

- The server private key at `/etc/wireguard/privatekey` is readable only by root.
- Clients keep their private keys secure and do not share config files.
- The operator monitors `var/log/aegis-vpn/audit.log` and runs `aegis-vpn check` periodically.
- Backups (`aegis-vpn backup`) are stored securely — they contain the server private key.
