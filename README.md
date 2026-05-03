# pve-microvm

![pve-microvm](docs/icon-256.png)

<p align="center">
  <img src="docs/pve-microvm-demo.gif" alt="pve-microvm in the Proxmox web UI" width="720">
</p>

A Debian package that adds QEMU `microvm` machine type support to Proxmox VE.
Runs OCI container images, [Firecracker rootfs images](docs/firecracker.md), unikernels, and alternative OS as lightweight hardware-isolated VMs.

> **⚠️ Highly experimental.** This project patches `qemu-server` internals and
> has not been tested in production. Use at your own risk. The patches are
> fully reversible — uninstalling the package restores the original files.

📝 [Blog post with some background](https://taoofmac.com/space/notes/2026/04/19/1400#proxmox-microvms) · ❓ [FAQ](docs/faq.md)

---

## Why

We needed something between LXC containers and full QEMU VMs for running
coding agents and other semi-trusted workloads.

| | LXC | microvm | Standard VM |
|---|---|---|---|
| Isolation | Namespace (shared kernel) | **KVM (own kernel)** | KVM (own kernel) |
| Boot time | ~50 ms | **< 300 ms** | 2–10 s |
| Overhead | Minimal | **Minimal** | Moderate |
| Attack surface | Broad (host kernel) | **Minimal (virtio-pcie)** | Broad (emulated PC) |
| Untrusted code | ⚠️ risky | **✅ safe** | ✅ safe |

**Hardware-isolated VMs with container-like speed**, managed through the same
Proxmox tools you already use. No new runtime — QEMU's `microvm` machine type
is already on every PVE node.

---

## Highlights

- **50 features shipped** — templates, cloning, networking, HA, web UI, backups
- **21 guest OS** — 13 Linux distros + SmolBSD, OpenWrt, OPNsense, 9Front, OSv, gokrazy, Firecracker
- **31 ms boot** (SmolBSD) to **~2 s** (Alpine) to **~8 s** (Debian)
- **Create µVM button** in PVE web UI with OCI image picker
- **All storage backends** — LVM, LVM-thin, ZFS, NFS, CIFS, Ceph
- **HA + migration** — offline migration in 2 seconds, ha-manager relocate
- **Tested on 4 nodes** — from Atom x5-Z8350 (2 GB) to i7-12700 (128 GB)

---

## Quick start

```bash
# Install
dpkg -i pve-microvm_0.3.6-1_all.deb

# Create a template from any OCI image
pve-microvm-template --image debian:trixie-slim

# Clone and boot
qm clone 9000 901 --name my-sandbox --full
qm start 901
qm terminal 901
```

Or use the **Create µVM** button in the PVE web UI.

---

## Supported guests

| Category | Images |
|---|---|
| **Linux (apt)** | Debian, Ubuntu |
| **Linux (apk)** | Alpine |
| **Linux (dnf/tdnf)** | Fedora, Rocky, Alma, Amazon, Oracle, UBI, Photon, Azure Linux |
| **Router/Firewall** | OpenWrt, OPNsense |
| **BSD** | SmolBSD (NetBSD, 31ms boot) |
| **Plan 9** | 9Front |
| **Unikernel** | OSv, gokrazy |
| **Compatible** | Any Firecracker rootfs (ext4 import) |

---

## What's included

| Component | Description |
|---|---|
| **`pve-microvm-template`** | Create PVE templates from OCI images or specialist OS |
| **`pve-oci-import`** | Convert any OCI image to a bootable microvm disk |
| **`pve-microvm-share`** | Share host directories via virtiofs |
| **`pve-microvm-9p`** | Share host directories via 9p (no daemon) |
| **`pve-microvm-ssh-agent`** | Forward SSH agent via vsock |
| **`pve-microvm-run`** | Ephemeral microvms (run and destroy) |
| **`pve-microvm-bench`** | Boot time and overhead benchmarking |
| **Web UI** | Create µVM dialog, ⚡ icon, xterm.js console, panel hiding |
| **Kernel** | Pre-built 6.12.22 with PCIe virtio + vsock + virtiofs |

---

## Tested on

| | z83ii (worst-case) | borg (reference) |
|---|---|---|
| **CPU** | Atom x5-Z8350 @ 1.44 GHz | i7-12700 @ 4.9 GHz |
| **RAM** | 2 GB | 128 GB |
| **PVE** | 9.1.9 (qemu-server 9.1.8) | 9.1.7 (qemu-server 9.1.6) |
| **QEMU** | 10.1.2 | 10.1.2 |

Full cluster: 4 nodes — see [Cluster Hardware](docs/cluster-hardware.md).

---

## Documentation

- **[Installation](docs/installation.md)** — install, verify, uninstall
- **[Quick Start](docs/usage.md)** — templates, cloning, basic usage
- **[Guest OS](docs/guests.md)** — all supported distributions and specialist OS
- **[Networking & Storage](docs/networking.md)** — virtiofs, 9p, vsock, SSH agent
- **[Web UI](docs/webui.md)** — Create µVM dialog, console, icons, panel hiding
- **[Configuration](docs/configuration.md)** — supported/unsupported options
- **[Architecture](docs/architecture.md)** — how it works, QEMU command line
- **[Firecracker Compatibility](docs/firecracker.md)** — importing rootfs images
- **[High Availability](docs/ha.md)** — migration, HA relocate
- **[Test Matrix](docs/test-matrix.md)** — distros, features, hardware
- **[Cluster Hardware](docs/cluster-hardware.md)** — all 4 nodes
- **[Known Issues](docs/known-issues.md)** — workarounds and fixes
- **[Limitations](docs/limitations.md)** — what doesn't work (yet)
- **[Troubleshooting](docs/troubleshooting.md)** — common problems
- **[FAQ](docs/faq.md)** — frequently asked questions
- **[Development](docs/development.md)** — repo structure, building
- **[Changelog](docs/changelog.md)** — full feature list and release history

---

## Roadmap

| Feature | Priority |
|---|---|
| Network off by default | Medium |
| Egress allow-list (nftables) | Medium |
| CPU/memory hotplug | Low |
| Declarative VM config (TOML) | Low |
| GPU passthrough | Low |
| AArch64 guest support | Low |
| Upstream RFC for pve-devel | Low |

---

## License

[Apache-2.0](LICENSE)
