# Why WireGuard?

Aegis-VPN is built on WireGuard. Here's why.

---

## Modern Cryptography, Fixed Stack

WireGuard uses a single, non-negotiable cryptographic suite: Curve25519, ChaCha20-Poly1305, BLAKE2s, and HKDF. There is no algorithm negotiation, so there is no downgrade attack surface. Compare this to OpenVPN or IPSec, which support dozens of cipher combinations — many of them weak or obsolete.

---

## Minimal Codebase

WireGuard's kernel implementation is around 4,000 lines of code. OpenVPN is over 100,000. Smaller code means a smaller attack surface, easier auditing, and fewer places for bugs to hide.

---

## Performance

WireGuard lives in the kernel (or as a fast userspace implementation). Benchmarks consistently show 2–5× higher throughput than OpenVPN at equivalent CPU usage. This matters on low-power servers and VPS instances with limited resources.

---

## Simplicity

A WireGuard config is a plain INI file with a private key, an address, and a list of peers. There are no certificates, no CAs, no certificate revocation lists, no complex daemon configuration. This makes it easy to automate — which is exactly what Aegis-VPN does.

---

## Compared to Alternatives

| | WireGuard | OpenVPN | IPSec (IKEv2) |
|---|---|---|---|
| Lines of code | ~4,000 | ~100,000+ | Complex |
| Crypto stack | Fixed, modern | Negotiated, legacy options | Negotiated |
| Config complexity | Low | High | Very high |
| Kernel integration | Native (Linux 5.6+) | Userspace (tun) | Kernel |
| Mobile support | Excellent | Good | Good |
| NAT traversal | Built-in | Manual | Varies |
| Performance | High | Moderate | High |

---

## Relevant Reading

- [WireGuard Whitepaper](https://www.wireguard.com/papers/wireguard.pdf)
- [Official WireGuard website](https://www.wireguard.com)
- [Linux kernel inclusion announcement](https://lkml.org/lkml/2020/1/28/740)
