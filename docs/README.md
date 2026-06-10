# Aegis-VPN v3.0

![Aegis-VPN](https://github.com/rabindra789/aegis-vpn/blob/main/images/image.png)

Aegis-VPN is a fully automated, self-hosted WireGuard VPN manager for Linux servers. It handles everything from server setup and client onboarding to key rotation, backups, and real-time monitoring — all from a single CLI with no external dependencies beyond WireGuard itself.

---

## Features

- **Automated server setup** — one command installs WireGuard, configures the firewall, and auto-detects your network interface
- **Client management** — add, remove, and list clients with QR codes for mobile onboarding
- **DNS & tunnel mode selection** — choose Cloudflare, Google, Quad9, or custom DNS; full tunnel or VPN-only routing per client
- **Client key rotation** — regenerate a client's keys without changing their IP, DNS, or tunnel mode
- **Server key rotation** — rotate the server private key in-place with minimal disruption; all client configs updated automatically
- **Live dashboard** — real-time peer status, last handshake, and per-peer bandwidth from `wg show`
- **Backup & restore** — timestamped tarballs of all WireGuard and client configs
- **Config validation** — detect orphaned peers, malformed keys, and config drift
- **Log rotation** — connection, error, and audit logs with automatic 10 MB rotation
- **IPv6 dual-stack** — every client gets both IPv4 and IPv6 addresses
- **Privacy mode** — mask IPs in logs and dashboard with `--privacy`

---

## Repository Structure

```
aegis-vpn/
├── bin/
│   └── aegis-vpn              # Main CLI entrypoint
├── clients/                   # Generated client config files
├── diagrams/                  # Architecture and network diagrams
├── docs/                      # Documentation
├── images/                    # Images used in docs
├── scripts/
│   ├── lib.sh                 # Shared constants, colors, utility functions
│   ├── log_hooks.sh           # Logging framework with rotation
│   ├── add_client.sh          # Client key generation and registration
│   ├── manage_clients.sh      # Add / remove / list wrapper
│   ├── rotate_client.sh       # Client key rotation
│   ├── rotate_server.sh       # Server key rotation
│   ├── backup_restore.sh      # Backup and restore
│   └── validate.sh            # Config integrity validation
├── server/
│   ├── wg0.conf.template      # WireGuard server config template
│   └── hardening.md           # Security hardening guide
├── var/log/aegis-vpn/         # Runtime logs
├── cleanup.sh                 # Full removal script
└── setup.sh                   # Automated server setup
```

---

## Installation

### Requirements

- Ubuntu / Debian (systemd)
- Root / sudo access
- Outbound internet for package installation

### 1. Clone

```bash
git clone https://github.com/rabindra789/aegis-vpn.git
cd aegis-vpn
```

### 2. Set up the server

```bash
sudo ./setup.sh
```

For unattended / cloud-init installs:

```bash
sudo ./setup.sh --auto
```

This will:
- Install WireGuard, qrencode, ufw
- Auto-detect your network interface
- Generate server keys
- Configure NAT, IP forwarding, and firewall rules
- Start and enable `wg-quick@wg0`

---

## Usage

### Interactive menu

```bash
sudo ./bin/aegis-vpn
```

```
┌──────────────── Aegis-VPN v3.0.0 ────────────────┐
│  Active peers : 3                                 │
│                                                   │
│   1) Setup          7) Status                    │
│   2) Add Client     8) Rotate Client Keys        │
│   3) Remove Client  9) Rotate Server Key         │
│   4) List Clients  10) Backup                    │
│   5) View Logs     11) Restore                   │
│   6) Dashboard     12) Check Config              │
│                   13) Exit                       │
└──────────────────────────────────────────────────┘
```

### CLI reference

```bash
# Client management
sudo ./bin/aegis-vpn add                    # Add a new client (DNS + tunnel mode prompt)
sudo ./bin/aegis-vpn remove                 # Remove a client
sudo ./bin/aegis-vpn list                   # List clients with live status

# Monitoring
sudo ./bin/aegis-vpn status                 # Service state + per-peer bandwidth
sudo ./bin/aegis-vpn dashboard              # Live dashboard (refreshes every 5s)
sudo ./bin/aegis-vpn dashboard --privacy    # Dashboard with IPs masked
sudo ./bin/aegis-vpn logs                   # Stream connection log
sudo ./bin/aegis-vpn logs --errors          # Stream error log
sudo ./bin/aegis-vpn logs --audit           # Stream audit log
sudo ./bin/aegis-vpn logs --privacy         # Stream with IPs masked

# Key rotation
sudo ./bin/aegis-vpn rotate <client>        # Rotate a client's keys (keeps IP/DNS)
sudo ./bin/aegis-vpn rotate-server          # Rotate server key; update all client configs
sudo ./bin/aegis-vpn rotate-server --qr     # Same + display updated QR codes for all clients

# Maintenance
sudo ./bin/aegis-vpn backup                 # Create timestamped config backup
sudo ./bin/aegis-vpn restore <file>         # Restore from backup
sudo ./bin/aegis-vpn check                  # Validate wg0.conf integrity

# Info
sudo ./bin/aegis-vpn version
sudo ./bin/aegis-vpn --help
```

---

## Adding a Client

When you run `aegis-vpn add`, you will be prompted for:

1. **Client name** — alphanumeric, max 32 characters
2. **DNS resolver** — Cloudflare (1.1.1.1), Google (8.8.8.8), Quad9 (9.9.9.9), or custom
3. **Tunnel mode** — full tunnel (all traffic via VPN) or VPN-only (VPN subnet only)

A QR code is displayed for mobile import. The config file is saved to `clients/<name>.conf`.

---

## Key Rotation

### Client key rotation

Regenerates the client's private/public key pair without changing their assigned IP, DNS, or tunnel mode. The server peer entry is updated live.

```bash
sudo ./bin/aegis-vpn rotate alice
```

### Server key rotation

Rotates the server's private key with the shortest possible disruption window:

1. Auto-backs up all configs
2. Generates new key pair
3. Applies new key to the live interface via `wg set` (no interface restart)
4. Updates `PrivateKey` in `wg0.conf`
5. Updates `PublicKey` in every `clients/*.conf`
6. Writes a full audit record

```bash
sudo ./bin/aegis-vpn rotate-server
sudo ./bin/aegis-vpn rotate-server --qr    # Also redisplay QR codes for all clients
```

Clients will be disconnected for approximately one handshake cycle (~5 seconds) and reconnect automatically once they receive the updated config.

---

## Backup & Restore

```bash
# Create backup
sudo ./bin/aegis-vpn backup
# → aegis-backup-20260221_153000.tar.gz

# Restore
sudo ./bin/aegis-vpn restore aegis-backup-20260221_153000.tar.gz
```

Backups include `/etc/wireguard/` and `clients/`.

---

## Logs

Three separate log files under `var/log/aegis-vpn/`:

| File | Contents |
|------|----------|
| `connections.log` | Client connect / disconnect events |
| `errors.log` | Script and runtime errors |
| `audit.log` | Config changes, key rotations, backups |

Logs rotate automatically at 10 MB, keeping 3 rotations.

---

## Cleanup

To fully remove Aegis-VPN and WireGuard:

```bash
sudo ./cleanup.sh
```

---

## Documentation

| File | Description |
|------|-------------|
| [`docs/security-model.md`](security-model.md) | Threat model and mitigations |
| [`docs/why-wireguard.md`](why-wireguard.md) | Why WireGuard over OpenVPN / IPSec |
| [`server/hardening.md`](../server/hardening.md) | Server hardening checklist |
| [`clients/README.md`](../clients/README.md) | Client onboarding guide |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | How to contribute |

![Architecture](https://github.com/rabindra789/aegis-vpn/blob/main/diagrams/architecture.png)
![Networking](https://github.com/rabindra789/aegis-vpn/blob/main/diagrams/networking.png)

---

## License

MIT — see [LICENSE](../LICENSE).
