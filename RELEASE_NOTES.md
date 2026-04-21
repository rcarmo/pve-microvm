# pve-microvm v0.2.0

Major milestone: 34 roadmap items shipped, all core features working end-to-end.

## Highlights

- **Full end-to-end** on z83ii (Intel Atom, 2GB RAM, PVE 9.1.7, QEMU 10.1.2)
- **Ephemeral VMs** — `pve-microvm-run -- uname -a` (auto-cleanup)
- **9Front / Plan 9** — boots from pre-built qcow2, sub-3s on Atom
- **Alpine templates** — apk-based chroot with full package support
- **All storage types** — LVM, LVM-thin, ZFS, dir, NFS/CIFS
- **virtiofs + vsock** — host directory sharing and SSH agent forwarding
- **GUI** — panel hiding, one-click clone, ⚡ icon
- **Reliable networking** — dhclient fallback for Trixie's networkd issues
- **Guest agent** — custom service with retry, works on all images

## Tools shipped

| Tool | Purpose |
|---|---|
| `pve-microvm-template` | Create templates from OCI images or 9Front |
| `pve-oci-import` | Import any OCI image as a microvm disk |
| `pve-microvm-run` | Ephemeral VMs (run-and-destroy) |
| `pve-microvm-share` | Share host directories via virtiofs |
| `pve-microvm-ssh-agent` | Forward SSH agent via vsock |
| `pve-microvm-bench` | Boot time and resource benchmarking |
| `pve-microvm-patch` | Safe apply/revert of qemu-server patches |

## Supported guest images

- `debian:trixie-slim` (default, 28 MB)
- `alpine:latest` (5 MB, static busybox)
- `9front` (Plan 9 / 9Front, 511 MB qcow2)
- Any OCI image from Docker Hub, ghcr.io, quay.io

## Upgrade

```bash
curl -sL https://github.com/rcarmo/pve-microvm/releases/download/v0.2.0/pve-microvm_0.2.0-1_all.deb -o /tmp/pve-microvm.deb
dpkg -i /tmp/pve-microvm.deb
```
