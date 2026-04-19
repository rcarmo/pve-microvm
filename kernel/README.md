# pve-microvm kernel

This directory contains the kernel configuration and build tooling for
pve-microvm guests.

## Choice of base config

We use the **Firecracker `microvm-kernel-ci-x86_64-6.1` config** as the base,
targeting **kernel 6.12 LTS** for builds (forward-compatible with PVE 9's
host kernel 6.14).

### Why Firecracker's config?

| Criterion | Alpine `linux-virt` | Firecracker CI | Custom `tinyconfig` |
|---|---|---|---|
| virtio-mmio | ✅ built-in | ✅ built-in | needs manual setup |
| virtio-blk | ⚠️ module | ✅ built-in | needs manual setup |
| virtio-net | ⚠️ module | ✅ built-in | needs manual setup |
| virtio-console | ✅ built-in | ✅ built-in | needs manual setup |
| ext4 | ⚠️ module | ✅ built-in | needs manual setup |
| Direct boot (no initrd) | ❌ needs initrd | ✅ works | ✅ works |
| Serial console | ✅ | ✅ | needs manual setup |
| Namespaces | ✅ | ✅ all 6 | needs manual setup |
| Cgroups | ✅ | ✅ | needs manual setup |
| Seccomp | ✅ | ✅ | needs manual setup |
| OverlayFS | ⚠️ module | ✅ built-in | needs manual setup |
| FUSE | ⚠️ module | ✅ built-in | needs manual setup |
| IPv6 | ✅ | ✅ | needs manual setup |
| Netfilter | ✅ | ✅ | needs manual setup |
| Kernel size | ~12 MB | ~6–8 MB | ~2–4 MB |
| Maintenance | Alpine team | AWS/Firecracker | you |

**The critical advantage**: Firecracker's config has all virtio drivers,
filesystems, and networking **built-in** (`=y`), not as modules (`=m`).
This means microvm guests can boot with just `-kernel vmlinuz` — no initrd
or module loading infrastructure needed.

Alpine's `linux-virt` is excellent but ships virtio-blk, virtio-net, and ext4
as modules, which means you **must** also provide an initramfs. For a
"just works" microvm experience, built-in drivers are essential.

## PVE overlay

On top of the Firecracker base, we apply `pve-microvm-overlay.config` which adds:

| Feature | Config | Why |
|---|---|---|
| VLAN 802.1Q | `CONFIG_VLAN_8021Q=y` | Proxmox bridges use VLAN tags |
| cgroup controllers | `CONFIG_MEMCG=y`, `CGROUP_PIDS`, etc. | systemd guests, container workloads |
| iptables/nftables | `CONFIG_NF_CONNTRACK=y`, etc. | Firewall/NAT inside guests |
| XFS | `CONFIG_XFS_FS=y` | Alternative rootfs filesystem |
| Loop device | `CONFIG_BLK_DEV_LOOP=y` | Mount images inside guest |
| Watchdog | `CONFIG_SOFT_WATCHDOG=y` | Guest health monitoring |

## Feature audit

### ✅ Supported (built-in)

- virtio-mmio transport
- virtio-blk (block devices)
- virtio-net (networking)
- virtio-console (guest agent channel)
- virtio-balloon (memory management)
- virtio-rng (hardware RNG)
- virtio-vsock (host↔guest sockets)
- Serial 8250 + console
- ext4, OverlayFS, FUSE, SquashFS, XFS
- devtmpfs (auto-mount)
- Full IPv4 + IPv6 networking
- Netfilter + conntrack + NAT
- All 6 Linux namespaces (user, pid, net, uts, ipc, mount)
- Cgroups v1 + v2
- Seccomp + BPF
- inotify, epoll, signalfd, timerfd, eventfd
- ELF + script binary formats

### ❌ Not included (by design)

- PCI bus / PCIe (not used by microvm)
- VGA / framebuffer / DRM
- USB / HID
- Sound / audio
- ACPI (microvm has no ACPI)
- Wireless networking
- Bluetooth
- Filesystem: NTFS, FAT (add if needed)
- Kernel module loading (everything is built-in)

## Building

### Prerequisites

```bash
apt install build-essential flex bison libelf-dev bc libssl-dev wget
```

### Build

```bash
cd kernel/
./build-kernel.sh

# Or with a specific kernel version:
./build-kernel.sh --version 6.12.22 --output ./vmlinuz-microvm
```

### Install on Proxmox node

```bash
scp vmlinuz-microvm root@pve-node:/usr/share/pve-microvm/vmlinuz
```

### Use with a microvm guest

```bash
qm set 900 --args '-kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw quiet"'
```

## Files

| File | Description |
|---|---|
| `base-x86_64-6.1.config` | Firecracker's microvm CI kernel config (6.1 LTS, x86_64) |
| `pve-microvm-overlay.config` | PVE-specific additions (VLAN, cgroups, iptables, XFS) |
| `build-kernel.sh` | Automated kernel download + build script |

## Updating the base config

When Firecracker updates their kernel config (e.g., for a new LTS series):

1. Download the new config from
   `https://github.com/firecracker-microvm/firecracker/tree/main/resources/guest_configs`
2. Replace `base-x86_64-6.1.config`
3. Verify the overlay still applies cleanly
4. Rebuild and test

## Known issue: Firecracker 6.1 config on kernel 6.12

`make olddefconfig` on kernel 6.12 sources with the Firecracker 6.1 base
config **silently drops** `CONFIG_VIRTIO_NET`, `CONFIG_VIRTIO_BALLOON`, and
`CONFIG_VIRTIO_CONSOLE` due to changed Kconfig dependencies.

The PVE overlay explicitly forces these back to `=y`. If you update the
base config or kernel version, always verify these are present in the
final `.config` after `olddefconfig`.
