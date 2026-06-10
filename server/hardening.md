# Server Hardening Guide

Recommendations for hardening the host running Aegis-VPN.

---

## 1. Keep the System Updated

```bash
apt update && apt upgrade -y
# Enable automatic security updates
apt install unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades
```

---

## 2. SSH Hardening

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PasswordAuthentication no
AllowUsers <your-username>
```

Restart SSH: `systemctl restart sshd`

Use key-based authentication only. Restrict SSH to known admin IPs with UFW:

```bash
ufw allow from <admin-ip> to any port 22
ufw delete allow 22   # remove the open rule if it exists
```

---

## 3. Firewall Rules

Aegis-VPN setup configures UFW automatically. Verify the rules are correct:

```bash
ufw status verbose
```

Expected rules:
- `51820/udp ALLOW IN` — WireGuard
- `22/tcp ALLOW IN` — SSH (ideally restricted to admin IPs)
- All other inbound traffic: DENY

Do not open unnecessary ports. Remove any default rules that allow broad inbound access.

---

## 4. WireGuard Key Security

```bash
ls -la /etc/wireguard/
```

Verify:
- `privatekey` — `chmod 600`, owned by `root`
- `wg0.conf` — `chmod 600`, owned by `root`

Never expose the server private key. Rotate it if there is any suspicion of compromise:

```bash
sudo ./bin/aegis-vpn rotate-server
```

Rotate individual client keys on device loss or suspected compromise:

```bash
sudo ./bin/aegis-vpn rotate <client-name>
```

---

## 5. Key Rotation Schedule

| Key | Recommended interval |
|-----|----------------------|
| Client keys | On device loss / compromise, or every 90 days |
| Server key | On suspected compromise, or every 180 days |

Use `aegis-vpn rotate-server --qr` to rotate the server key and immediately redisplay QR codes for all clients.

---

## 6. Backup Configs

Back up all WireGuard configs before making changes:

```bash
sudo ./bin/aegis-vpn backup
```

Store backups off-server (encrypted). Backup archives contain the server private key — treat them with the same sensitivity as the key itself.

---

## 7. Monitor Active Peers

```bash
sudo wg show                         # Live kernel view
sudo ./bin/aegis-vpn status          # Bandwidth per peer
sudo ./bin/aegis-vpn list            # Online/offline status per client
sudo ./bin/aegis-vpn dashboard       # Refreshing live view
```

Remove peers that are no longer needed:

```bash
sudo ./bin/aegis-vpn remove
```

---

## 8. Validate Config Integrity

Run after any manual changes or after restoring a backup:

```bash
sudo ./bin/aegis-vpn check
```

This detects:
- Malformed server or peer keys
- Peers in `wg0.conf` with no matching client config file
- Client config files with no matching server peer entry

---

## 9. Audit Logs

Review the audit log regularly:

```bash
sudo ./bin/aegis-vpn logs --audit
```

All key rotations, client additions/removals, backups, and config validations are recorded here with timestamps.

---

## 10. Fail2ban (Optional)

WireGuard itself does not expose a login surface, but SSH does. Install fail2ban to block brute-force SSH attempts:

```bash
apt install fail2ban
systemctl enable --now fail2ban
```

Default config bans IPs after 5 failed SSH attempts for 10 minutes. Adjust `/etc/fail2ban/jail.local` as needed.

---

## 11. Disable Unused Services

```bash
systemctl list-units --type=service --state=running
# Disable anything not needed:
systemctl disable --now <service>
```

---

## 12. Kernel IP Forwarding

Aegis-VPN setup enables forwarding automatically and persists it in `/etc/sysctl.conf`. Verify:

```bash
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
# Both should return 1
```
