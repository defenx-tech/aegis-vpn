# Client Onboarding Guide

This guide explains how to add, connect, and manage VPN clients on Aegis-VPN v3.0.

---

## Adding a Client

```bash
sudo ./bin/aegis-vpn add
```

You will be prompted for:

1. **Client name** — letters, numbers, `_` and `-` only, max 32 characters
2. **DNS resolver**
   - `1` Cloudflare — `1.1.1.1, 1.0.0.1`
   - `2` Google — `8.8.8.8, 8.8.4.4`
   - `3` Quad9 — `9.9.9.9, 149.112.112.112`
   - `4` Custom — enter any IP(s)
3. **Tunnel mode**
   - `1` Full tunnel — all device traffic routed through the VPN
   - `2` VPN only — only traffic destined for `10.10.0.0/24` goes through the VPN

A QR code is displayed for mobile import. The config file is saved to `clients/<name>.conf`.

---

## Connecting

### Mobile (iOS / Android)

1. Install the [WireGuard app](https://www.wireguard.com/install/).
2. Tap **+** → **Create from QR code**.
3. Scan the QR code shown in the terminal.
4. Toggle the tunnel on.

### Desktop (Linux / macOS / Windows)

1. Install the [WireGuard client](https://www.wireguard.com/install/).
2. Import `clients/<name>.conf`:
   ```bash
   # Linux
   sudo wg-quick up clients/<name>.conf

   # Or copy to /etc/wireguard/ and manage via systemctl
   sudo cp clients/<name>.conf /etc/wireguard/<name>.conf
   sudo wg-quick up <name>
   ```
3. On Windows/macOS, use the GUI: **Add Tunnel → Import from file**.

---

## Verifying the Connection

From the client:
```bash
ping 10.10.0.1       # Ping the VPN server
curl ifconfig.me     # Should show the server's public IP (full tunnel mode)
```

From the server:
```bash
sudo wg show          # Client should appear with a recent last-handshake
sudo ./bin/aegis-vpn list   # Table view with online/offline status
```

---

## Rotating Client Keys

To regenerate a client's WireGuard keys (keeps the same IP, DNS, and tunnel mode):

```bash
sudo ./bin/aegis-vpn rotate <client-name>
```

A new QR code is displayed. The old config/QR immediately stops working — distribute the new one to the client device.

---

## Removing a Client

```bash
sudo ./bin/aegis-vpn remove
```

Enter the client name when prompted. The client config file and server peer entry are removed, and the client is disconnected from the live WireGuard interface.

---

## Listing Clients

```bash
sudo ./bin/aegis-vpn list
```

Displays a table with:

| Column | Description |
|--------|-------------|
| Name | Client name |
| IPv4 | Assigned VPN IPv4 address |
| IPv6 | Assigned VPN IPv6 address |
| Status | `online` (handshake < 3 min), `offline`, or `never` |
| Last Handshake | Timestamp of most recent WireGuard handshake |

---

## Config File Format

Each client config lives at `clients/<name>.conf`:

```ini
[Interface]
PrivateKey = <client-private-key>
Address    = 10.10.0.X/32, fd86:ea04:1115::X/128
DNS        = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey          = <server-public-key>
Endpoint           = <server-ip>:51820
AllowedIPs         = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

Keep the `PrivateKey` secure — it is the client's identity on the VPN.

---

## Notes

- Each client is assigned a unique IP automatically (no manual allocation needed).
- After a **server key rotation** (`aegis-vpn rotate-server`), all client configs are updated automatically. Clients must re-import the new config or QR code to reconnect.
- Client configs are backed up with `aegis-vpn backup` and restored with `aegis-vpn restore`.
