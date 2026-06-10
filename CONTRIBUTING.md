# Contributing to Aegis-VPN

Thank you for your interest in contributing to Aegis-VPN. Contributions of all kinds are welcome — bug fixes, new features, documentation improvements, and security reviews.

---

## Table of Contents

- [Reporting Issues](#reporting-issues)
- [Pull Request Workflow](#pull-request-workflow)
- [Local Development](#local-development)
- [Testing on VPS](#testing-on-vps)
- [Testing with QEMU](#testing-with-qemu)
- [ShellCheck Usage](#shellcheck-usage)
- [Good First Issues](#good-first-issues)

---

## Reporting Issues

If you find a bug or unexpected behaviour:

1. Search [existing issues](https://github.com/defenx-tech/aegis-vpn/issues) first.
2. Open a new issue with:
   - **Title** — short, descriptive
   - **Description** — what happened vs. what you expected
   - **Steps to reproduce** — commands, scripts, config snippets
   - **Environment** — OS, WireGuard version, server type
3. Attach logs (`var/log/aegis-vpn/`) or `aegis-vpn check` output if relevant.

For security vulnerabilities, please open a private advisory rather than a public issue.

---

## Pull Request Workflow

1. Fork the repository and clone your fork:
   ```bash
   git clone https://github.com/<your-username>/aegis-vpn.git
   cd aegis-vpn
   ```

2. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. Make your changes. See [ShellCheck Usage](#shellcheck-usage) to ensure code quality.

4. Commit with a clear message:
   ```bash
   git commit -m "feat: add X to improve client onboarding"
   ```

5. Push and open a PR against `main` on `defenx-tech/aegis-vpn`:
   - Describe what the PR does and why
   - Reference any related issues (e.g. `Closes #12`)
   - Include before/after output for CLI changes

> Do not push directly to `main`.

---

## Local Development

```bash
# Install dependencies
sudo apt update
sudo apt install wireguard qrencode curl figlet bash coreutils shellcheck

# Clone and set up
git clone https://github.com/<your-username>/aegis-vpn.git
cd aegis-vpn
sudo ./setup.sh --auto   # sets up WireGuard on the local machine

# Add a test client
sudo ./bin/aegis-vpn add

# Verify the CLI
sudo ./bin/aegis-vpn --help
sudo ./bin/aegis-vpn version
sudo ./bin/aegis-vpn check
sudo ./bin/aegis-vpn health
```

---

## Testing on VPS

1. Provision a fresh VPS (Ubuntu 22.04+ / Debian 12+).
2. Clone the repository:
   ```bash
   git clone https://github.com/<your-username>/aegis-vpn.git
   cd aegis-vpn
   ```
3. Run the automated setup:
   ```bash
   sudo ./setup.sh --auto
   ```
4. Test the full workflow:
   ```bash
   sudo ./bin/aegis-vpn add
   sudo ./bin/aegis-vpn list
   sudo ./bin/aegis-vpn health
   sudo ./bin/aegis-vpn check
   sudo ./bin/aegis-vpn backup
   sudo ./bin/aegis-vpn rotate <client>
   sudo ./bin/aegis-vpn rotate-server
   sudo ./bin/aegis-vpn remove
   ```
5. Verify cleanup:
   ```bash
   sudo ./cleanup.sh
   ```

---

## Testing with QEMU

For local VM-based testing:

```bash
# Install QEMU
sudo apt install qemu-system-x86 qemu-utils

# Create a disk image and install your preferred distro
qemu-img create -f qcow2 test-vm.qcow2 20G

# Boot the VM (use your preferred ISO)
qemu-system-x86_64 -enable-kvm -m 2048 -hda test-vm.qcow2 -cdrom ubuntu.iso

# Inside the VM, install git and clone the repo, then run the
# same test procedure as the VPS section above.
```

---

## ShellCheck Usage

All shell scripts must pass ShellCheck before merging.

```bash
# Run ShellCheck on all scripts
shellcheck **/*.sh

# Run on a specific script
shellcheck bin/aegis-vpn
shellcheck scripts/lib.sh

# Check syntax only (quick check)
bash -n scripts/your_script.sh
```

If ShellCheck is not installed:

```bash
sudo apt install shellcheck
```

---

## Good First Issues

If you are new to the project, consider tackling one of these:

- **Multiple WireGuard interfaces** — Support running multiple WireGuard interfaces (e.g. `wg0`, `wg1`) with separate VPN subnets and independent client management. This requires updating `lib.sh` variables, the CLI dispatcher, and all scripts that reference `WG_INTERFACE`.

- **IPv6-only mode** — Allow deploying Aegis-VPN on IPv6-only VPS instances. Currently the setup and client generation assume dual-stack or IPv4. Key areas: server detection, endpoint configuration, and firewall rules.

- **systemd watchdog integration** — Add watchdog support to the `wg-quick@` service or a companion service to automatically restart WireGuard if the interface goes down unexpectedly. This involves creating a drop-in unit file and optional alerting.

- **Logging improvements** — Enhance the logging system with structured JSON logs, log levels (info/warn/error), and optional remote log shipping via syslog or a lightweight forwarder.
