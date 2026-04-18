# pve-microvm

<p align="center">
  <img src="docs/pve-microvm-demo.gif" alt="pve-microvm in the Proxmox web UI" width="720">
</p>

A Debian package that adds QEMU `microvm` machine type support to Proxmox VE.

> **⚠️ Highly experimental.** This project patches `qemu-server` internals and
> has not been tested in production. Use at your own risk. The patches are
> fully reversible — uninstalling the package restores the original files.

---

## Motivation

We needed something between LXC containers and full QEMU VMs for running
coding agents and other semi-trusted workloads.

| | LXC | microvm | Standard VM |
|---|---|---|---|
| Isolation | Namespace (shared kernel) | **KVM (own kernel)** | KVM (own kernel) |
| Boot time | ~50 ms | **< 200 ms** | 2–10 s |
| Overhead | Minimal | **Minimal** | Moderate |
| Attack surface | Broad (host kernel) | **Minimal (virtio-mmio)** | Broad (emulated PC) |
| Untrusted code | ⚠️ risky | **✅ safe** | ✅ safe |

**Hardware-isolated VMs with container-like speed**, managed through the same
Proxmox tools you already use. No new runtime — QEMU's `microvm` machine type
is already on every PVE node. This package just unlocks it.

## Prior art

As of April 2026, **nobody has done this** — no Proxmox patches, packages,
or integrations exist for the QEMU microvm machine type.

---

## Quick start

```bash
# Install
dpkg -i pve-microvm_0.1.4-1_all.deb

# Create a template from debian:trixie-slim (28 MB)
pve-microvm-template

# Clone and boot
qm clone 9000 901 --name my-sandbox --full
qm start 901
qm terminal 901

root@microvm:~#
```

Or manually:

```bash
qm create 900 --machine microvm --memory 256 --cores 1 \
  --name my-microvm --net0 virtio,bridge=vmbr0 \
  --serial0 socket --vga serial0

pve-oci-import --image alpine:latest --vmid 900 --configure

qm start 900
qm terminal 900
```

---

## What's included

| Component | Description |
|---|---|
| **`PVE::QemuServer::MicroVM`** | Perl module — microvm QEMU command generation |
| **`pve-microvm-patch`** | Safe apply/revert of qemu-server patches |
| **`pve-microvm-template`** | Create PVE templates from OCI images for instant cloning |
| **`pve-oci-import`** | Convert any OCI image to a bootable microvm disk |
| **`microvm-init`** | Minimal init for images without one (e.g., `debian:trixie-slim`) |
| **`vmlinuz-microvm`** | Pre-built 6.12 LTS kernel (all virtio built-in, no initrd needed) |
| **Web UI extension** | `microvm` in machine dropdown, ⚡ icon, xterm.js serial console |

## Tested on

| Component | Version |
|---|---|
| Proxmox VE | 9.1.7 |
| QEMU | 10.1.2 |
| Host kernel | 6.17.13-2-pve |
| Guest kernel | 6.12.22 LTS |
| Storage | LVM-thin |

---

## Documentation

- **[Installation](docs/installation.md)** — install, verify, uninstall
- **[Usage Guide](docs/usage.md)** — templates, OCI import, console, networking, guest agent
- **[Configuration](docs/configuration.md)** — supported/unsupported options, example config
- **[Architecture](docs/architecture.md)** — how it works, QEMU command line, storage backends
- **[Kernel Guide](kernel/README.md)** — build config, why Firecracker's config, PVE overlay
- **[Limitations](docs/limitations.md)** — what doesn't work (yet)
- **[Troubleshooting](docs/troubleshooting.md)** — common issues and fixes
- **[Development](docs/development.md)** — repo structure, building, testing, references

---

## Roadmap

- [x] `qm create/start/stop/destroy` with microvm
- [x] Serial console via `qm terminal` and PVE web UI
- [x] OCI image import and template cloning
- [x] All PVE storage backends (LVM, ZFS, Ceph, NFS)
- [x] Pre-built microvm kernel
- [x] Web UI machine type dropdown
- [x] Balloon device for memory reporting
- [ ] vzdump backup validation
- [ ] dpkg trigger for auto-repatching after upgrades
- [ ] Performance benchmarking
- [ ] Upstream proposal to Proxmox

---

## License

[Apache-2.0](LICENSE)
