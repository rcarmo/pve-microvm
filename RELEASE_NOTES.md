# pve-microvm v0.1.1

Bugfix release — the v0.1.0 .deb was missing the kernel binary and had a
broken regex patch. Both are fixed.

## Fixes since v0.1.0

- **Kernel now included in .deb** — `make clean` was deleting `kernel/vmlinuz-microvm`
  before `dpkg-buildpackage` could include it. Fixed.
- **Regex patch rewritten in Python** — the Perl-based patcher produced an
  unmatched `)` in `Machine.pm`, causing `qm create --machine microvm` to fail.
  Rewritten with exact string replacement. Tested on live PVE 9 node.

## Tested on

- **z83ii** — PVE 9.1.7, kernel 6.17.13-2-pve, QEMU 10.1.2
- `qm create 999 --machine microvm --memory 128` ✅
- `qm destroy 999` ✅
- Patch apply/revert cycle ✅

## What this is

A Debian package that adds QEMU `microvm` machine type support to Proxmox VE 9.0.
microvm guests provide full KVM hardware isolation with container-like boot times
(< 200 ms), targeting coding agents and semi-trusted workloads that need more
isolation than LXC but less overhead than a standard VM.

**Nobody has done this before** — there are no existing Proxmox patches, packages,
or integrations for the QEMU microvm machine type.

## What's included

### Debian package (`pve-microvm_0.1.0-1_all.deb`)
- **`PVE::QemuServer::MicroVM`** — Perl module for microvm QEMU command generation
  - Stripped-down command builder: no PCI, VGA, ACPI, USB, BIOS
  - virtio-mmio devices (virtio-blk-device, virtio-net-device)
  - Serial console, guest agent, direct kernel boot
  - Full PVE storage backend support: LVM, LVM-thin, ZFS, Ceph/RBD, NFS/CIFS
  - I/O throttling, per-storage cache and AIO settings
- **`pve-microvm-patch`** — safe apply/revert tool for qemu-server patches
  - Backs up originals before patching
  - Fully reversible on package removal
- **`pve-oci-import`** — convert OCI container images into bootable microvm disks
  - Pulls from Docker Hub, ghcr.io, quay.io, or any OCI registry
  - Extracts rootfs, prepares init, creates ext4 qcow2 disk
  - Imports into PVE storage via `qm importdisk`
- **Custom UI icon** — tag-based ⚡ icon for microvm guests in the Proxmox tree
- **Kernel build tooling** — config and build script for a minimal microvm kernel

### Pre-built kernel (`vmlinuz-microvm`)
- Based on **Firecracker microvm-kernel-ci-x86_64-6.1** config
- Built against **Linux 6.12.22 LTS**
- All virtio drivers, ext4, networking, namespaces, cgroups, seccomp **built-in** (`=y`)
- PVE overlay adds: VLAN 802.1Q, cgroup controllers, iptables/nftables, XFS
- Direct kernel boot — no initrd required
- ~9 MB compressed

## Tested against

| Component | Version |
|---|---|
| Proxmox VE | 9.0 |
| Debian | Trixie (13) |
| qemu-server | 9.1.6 |
| pve-qemu-kvm | 10.2.1 (QEMU 10.2) |
| Host kernel | 6.14.x |

## Quick start

```bash
# Install
dpkg -i pve-microvm_0.1.0-1_all.deb
apt-get install -f

# Create a microvm guest from an OCI image
qm create 900 --machine microvm --memory 256 --cores 1 --name alpine-sandbox --net0 virtio,bridge=vmbr0
pve-oci-import --image alpine:latest --vmid 900 --configure

# Boot (< 200 ms) and connect
qm start 900
qm terminal 900
```

## Limitations

- Serial console only (no VNC/noVNC/SPICE)
- No PCI/USB passthrough
- No UEFI/Secure Boot
- No ACPI (use guest agent or `qm stop` for shutdown)
- Live migration and vzdump untested
- Patches must be re-applied after `qemu-server` upgrades

## What's next

- v0.2: Proxmox web UI patches (machine type dropdown, conditional panels)
- v0.3: vzdump backup validation, dpkg triggers for auto-repatching
