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

### Shipped

- [x] `qm create/start/stop/destroy` with microvm
- [x] Serial console via `qm terminal` and PVE web UI
- [x] OCI image import and template cloning
- [x] All PVE storage backends (LVM, ZFS, Ceph, NFS)
- [x] Pre-built microvm kernel (6.12 LTS)
- [x] Web UI machine type dropdown
- [x] Balloon device for memory reporting
- [x] Guest agent channel (virtio-serial-device)
- [x] Networking (tap, bridge, VLAN)
- [x] `microvm-init` for minimal OCI images
- [x] GitHub Actions CI/CD with kernel build

### Planned

| | Feature | Priority | Impact | Effort |
|---|---|---|---|---|
| [x] | **Cloud-init / user-data** — inject SSH keys, hostname, network config at clone time | Critical | High | Medium |
| [ ] | **Linked clones** — verify LVM snapshot clones work for instant VM creation | Critical | High | Low |
| [ ] | **dpkg trigger** — auto-reapply patches after `qemu-server` upgrades | Critical | High | Low |
| [ ] | **SSH agent forwarding** — forward host SSH agent into guest via vsock (git clone without exposing keys) | High | High | Medium |
| [ ] | **vsock (host↔guest sockets)** — fast communication without networking | High | High | Medium |
| [ ] | **virtiofs (shared folders)** — mount host workspace into guest without network | High | High | High |
| [ ] | **`qm shutdown` without agent** — lightweight shutdown via QMP or serial | High | Medium | Low |
| [ ] | **Disk resize** — verify `qm disk resize` + guest `resize2fs` | High | Medium | Low |
| [ ] | **vzdump backup** — validate snapshot and agent-based backup | High | Medium | Medium |
| [ ] | **Firewall integration** — verify PVE firewall rules on microvm tap devices | High | Medium | Low |
| [ ] | **Network off by default** — microvm boots with no network unless explicitly enabled (safer for sandboxes) | Medium | Medium | Low |
| [ ] | **Egress allow-list** — restrict outbound network to specific hosts via PVE firewall or guest nftables | Medium | Medium | Medium |
| [ ] | **Suppress SeaBIOS banner** — use `bios-microvm.bin` or qboot for cleaner boot | Medium | Low | Low |
| [ ] | **GUI: conditional panel hiding** — hide BIOS/EFI/USB/PCI tabs for microvm | Medium | Medium | Medium |
| [ ] | **GUI: kernel path field** — dedicated field instead of raw `args` | Medium | Medium | Medium |
| [ ] | **GUI: one-click clone** — "Create microvm" button that clones from template | Medium | Medium | Medium |
| [ ] | **Snapshots** — verify `qm snapshot` with microvm guests | Medium | Medium | Medium |
| [ ] | **Migration** — test live migration with reduced device model | Medium | Medium | Medium |
| [ ] | **HA (High Availability)** — test with PVE HA manager | Medium | Medium | Medium |
| [ ] | **Resource accounting** — verify I/O metrics report correctly | Medium | Low | Low |
| [ ] | **`onboot` / startup order** — verify PVE boot ordering works | Medium | Low | Low |
| [ ] | **Nested virtualization** — run Docker/containers inside microvm | Medium | Medium | Low |
| [ ] | **GPU passthrough (exploratory)** — investigate virtio-gpu on mmio for ML workloads | Low | Medium | High |
| [ ] | **Ephemeral VMs** — single-command run-and-destroy workflow like `smolvm machine run` | Medium | High | Medium |
| [ ] | **Volume mounts** — attach host directories into guest at create time (virtiofs or 9p) | High | High | High |
| [ ] | **Pre-baked images** — ship ready-to-boot qcow2 templates (avoid chroot build at install) | Medium | Medium | Medium |
| [x] | **systemd-networkd auto-enable** — ensure DHCP works on first boot without manual config | High | High | Low |
| [x] | **Guest agent on virtio-mmio** — fix udev/device path for qemu-ga on mmio bus | High | High | Low |
| [ ] | **9p filesystem sharing** — alternative to virtiofs for host↔guest files | Low | Medium | Medium |
| [ ] | **CPU/memory hotplug** — dynamic scaling for agent workloads | Low | Medium | Medium |
| [ ] | **Multiple kernel management** — ship/manage multiple kernel versions | Low | Low | Low |
| [ ] | **Custom icon persistence** — ensure ⚡ icon works across all browsers/reloads | Low | Low | Low |
| [ ] | **Performance benchmarking** — document boot time, memory overhead, I/O throughput | Low | Medium | Medium |
| [ ] | **Upstream proposal** — RFC patch series for Proxmox pve-devel mailing list | Low | High | High |
| [ ] | **Declarative VM config (Smolfile-style)** — TOML file describing image, resources, mounts, network for reproducible VMs | Low | Medium | Medium |
| [ ] | **Plan 9 / 9Front microVM** — boot Plan 9 or 9Front as a microvm guest (different kernel, virtio drivers, console) | Low | Low | High |
| [ ] | **AArch64 guest support** — microvm on ARM64 PVE hosts (different machine type, kernel config, virtio transport) | Low | Medium | High |

---

## License

[Apache-2.0](LICENSE)
