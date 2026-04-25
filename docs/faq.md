# Frequently Asked Questions

## General

### What is pve-microvm?

A Debian package that adds QEMU's `microvm` machine type as a managed
guest type in Proxmox VE. It lets you create lightweight,
hardware-isolated VMs that boot in under a second, managed through the
same `qm` CLI and web UI you already use for regular VMs and containers.

### What Linux distributions are supported?

All 12 tested distros create templates and boot on both z83ii (Atom,
2 GB) and borg (i7-12700, 128 GB). The `pve-microvm-template` tool
auto-detects the package manager and installs base services.

| Image | Size | Pkg mgr |
|---|---|---|
| `alpine:3.21` | 3 MB | apk |
| `redhat/ubi9-micro` | 6 MB | microdnf |
| `photon:5.0` | 15 MB | tdnf |
| `debian:trixie-slim` | 28 MB | apt |
| `ubuntu:24.04` | 28 MB | apt |
| `mcr.microsoft.com/azurelinux/base/core:3.0` | 30 MB | tdnf |
| `almalinux:9-minimal` | 34 MB | dnf |
| `redhat/ubi9-minimal` | 38 MB | microdnf |
| `rockylinux:9-minimal` | 44 MB | dnf |
| `oraclelinux:9-slim` | 45 MB | dnf |
| `amazonlinux:2023` | 52 MB | dnf |
| `fedora:41` | 57 MB | dnf |

Any OCI image with a supported package manager (apt, apk, dnf, microdnf,
tdnf, yum) should work. You can also pass `--profile minimal` to skip
package installation entirely and use the image as-is with our
`microvm-init`.

### What about non-Linux guests?

| Image | Type | Notes |
|---|---|---|
| `9front` | Plan 9 | Boots via q35/BIOS, experimental |
| `osv` | Unikernel | ELF loader via q35, needs app image |
| `gokrazy` | Go appliance | Prints `gok` CLI build instructions |
| Firecracker rootfs | ext4 | Direct import via `qm importdisk` |

See [Firecracker Compatibility](firecracker.md) for details on importing
Firecracker rootfs images.

### Can I use this in production?

Not yet. This is experimental. It patches `qemu-server` internals and
has been tested on a 4-node cluster (Atom to i7-12700). The patches are
fully reversible and the architecture is sound, but it needs broader
testing before production use. Back up your Proxmox configuration before
installing.

### What's the boot time?

We test on the slowest node in the cluster — an Intel Atom x5-Z8350 —
to make sure performance is acceptable everywhere.

**z83ii** (Intel Atom x5-Z8350 @ 1.44 GHz, 2 GB RAM):

| Stage | Alpine (busybox) | Debian trixie-slim |
|---|---|---|
| QEMU start → serial socket | ~200 ms | ~200 ms |
| Kernel + initrd → shell prompt | ~2 s | ~8 s |
| + DHCP networking ready | ~4 s | ~15 s |
| + DHCP + guest agent responding | ~8 s | ~30 s |

On faster hardware (borg, i7-12700), boot times are roughly 3–5× faster.
Use `pve-microvm-bench` to measure on your own hardware.

## Comparison with other approaches

### How is this different from a regular QEMU/KVM VM?

A standard Proxmox VM emulates a full PC: BIOS/UEFI firmware, PCI buses,
VGA display, USB controllers, ACPI tables. That takes 2–10 seconds to
boot and consumes resources even when idle.

A microvm strips all of that away. No BIOS scan, no PCI topology, no
display. Just a kernel, virtio devices, and a serial console. The result:
sub-second boot, minimal memory overhead, and a much smaller attack
surface — while keeping the same KVM hardware isolation.

### How is this different from an LXC container?

LXC containers share the host kernel. A compromised container process has
the same kernel attack surface as every other container on the node. This
is fine for trusted workloads but risky for untrusted code.

A microvm runs its own kernel inside a hardware-isolated VM. The host
kernel is never exposed to the guest. You get container-like speed with
VM-level isolation.

### Why not just use Firecracker or Cloud Hypervisor?

Firecracker and Cloud Hypervisor are standalone VMMs — separate binaries
with their own APIs, lifecycle models, and tooling. They don't integrate
with Proxmox's VM management, storage, networking, backup, or web UI.

pve-microvm uses the QEMU that's already on every Proxmox node. Your
microvms show up in the PVE web UI, use PVE storage, get PVE firewall
rules, and work with `qm`, `vzdump`, `qm snapshot`, etc. No new runtime
to install or manage.

### Why not use smolvm?

smolvm is a standalone tool for running microVMs locally using libkrun
(not QEMU), targeting developer workstations and CI runners.

pve-microvm targets Proxmox clusters. If you're already running PVE for
your infrastructure, pve-microvm lets you add microvm workloads without
introducing a separate runtime. The two projects solve different problems
at different layers.

### How does this compare to kata-containers?

Kata Containers wraps each container in a lightweight VM for
Kubernetes/CRI workloads. It requires containerd and a CRI runtime.

pve-microvm is for Proxmox — it makes microvms a native PVE guest type
managed through the same tools as regular VMs. No Kubernetes, no
containerd, no extra runtime stack.

## Installation and maintenance

### Does this modify Proxmox itself?

Yes — it patches two Perl files in `qemu-server` to allow the `microvm`
machine type and delegate command generation to a new module. It also
injects a JavaScript file and CSS into the PVE web UI for the ⚡ icon,
Create µVM dialog, and panel hiding.

All changes are fully reversible. Uninstalling the package restores the
original files from backup.

### Can I undo the installation?

Yes. `apt remove pve-microvm` reverts all patches and restores the
original `qemu-server` files. No VMs, configs, or data are affected.

### What happens when Proxmox upgrades qemu-server?

The package includes a dpkg trigger that watches for changes to the
patched files. When `qemu-server` is upgraded, the trigger automatically
re-applies the patches. Tested with the qemu-server 9.1.6 → 9.1.8
upgrade — patches reapply cleanly and all 12 distros continue to work.

You can also manually re-apply with:

```bash
/usr/share/pve-microvm/pve-microvm-patch revert
/usr/share/pve-microvm/pve-microvm-patch apply
```

### Which storage backends work?

All of them: LVM, LVM-thin, ZFS, dir (local), NFS, CIFS, Ceph/RBD. The
tools parse `qm importdisk` output to get the correct volume ID
regardless of storage type.

## Technical details

### Why does the kernel need an initrd?

The shipped kernel (6.12.22, built from `x86_64_defconfig`) has virtio
drivers compiled as modules. On QEMU 10.x's microvm with PCIe, the
modules need to be loaded before the root device appears. The initrd
(1.1 MB) loads the virtio modules, mounts the root filesystem, and
hands off to the real init.

### Why PCIe instead of virtio-mmio?

QEMU 10.x's microvm mmio transport has a device probing issue where only
`virtio-blk` binds — network, serial, and balloon devices don't get
claimed by their drivers. PCIe with non-transitional devices works
reliably for all device types. The boot time penalty is negligible
(~50 ms).

### How much RAM does a microvm need?

- **128 MB** minimum — kernel + busybox (Alpine `--profile minimal`)
- **256 MB** comfortable for Debian/Ubuntu with systemd + cloud-init
- **512 MB+** for Docker or package-heavy workloads

The balloon device reports actual usage, so PVE's memory accounting is
accurate.

### Why is there no VNC/SPICE console?

Microvm has no VGA hardware. The console is serial-only (ttyS0). The PVE
web UI automatically uses xterm.js for microvm VMs (instead of noVNC),
and the Console tab shows a ⚡ bolt icon. You can also use `qm terminal`
from the CLI.

### Why does the guest agent take so long to start?

On slow hardware (e.g., Intel Atom), systemd + cloud-init can take
60–120 seconds to fully initialize. The guest agent service retries
automatically (`Restart=always, RestartSec=5`). On faster hardware, the
agent is typically ready in 10–30 seconds.

Most microvm workloads don't strictly need the agent — it's included for
PVE integration (graceful shutdown, IP reporting, fsfreeze for backups).

## Guest capabilities

### Can I run Docker inside a microvm?

Yes, with `--profile full`:

```bash
pve-microvm-template --image debian:trixie-slim --vmid 9000 --profile full
```

The `full` profile installs Docker CE on first boot. The `standard`
profile (default) does not install Docker. The kernel supports nested
namespaces and cgroups, and KVM passthrough (`-cpu host`) means Docker
runs at native speed.

### Can I SSH into a microvm?

Yes. The `standard` and `full` profiles install OpenSSH server and
configure it via cloud-init. The `minimal` profile does not install SSH.

Set your SSH key before first boot:

```bash
qm set <vmid> --sshkeys ~/.ssh/authorized_keys
```

### How do I share files between host and guest?

Two options:

**virtiofs** (higher performance, needs virtiofsd daemon):
```bash
pve-microvm-share <vmid> /path/to/host/directory
# Inside guest: mount -t virtiofs shared /mnt/shared
```

**9p** (simpler, no daemon needed):
```bash
pve-microvm-9p <vmid> /path/to/host/directory mytag
# Inside guest: mount -t 9p mytag /mnt/mytag -o trans=virtio,version=9p2000.L
```

> **Note**: 9p requires the next kernel build (CONFIG_9P_FS=y is in the
> overlay but not yet in the shipped kernel).

### How do I forward my SSH agent into the guest?

Use `pve-microvm-ssh-agent`:

```bash
pve-microvm-ssh-agent <vmid>
# Inside guest:
socat UNIX-LISTEN:/tmp/agent.sock,fork VSOCK-CONNECT:2:2222 &
SSH_AUTH_SOCK=/tmp/agent.sock git clone git@github.com:...
```

Private keys never enter the guest — only the SSH agent protocol is
forwarded over vsock.

### Can I boot non-Linux guests?

Yes, experimentally:

```bash
# Plan 9 / 9Front
pve-microvm-template --image 9front --vmid 9002

# OSv unikernel
pve-microvm-template --image osv --vmid 9003

# gokrazy (prints build instructions)
pve-microvm-template --image gokrazy --vmid 9004
```

9Front and OSv use q35 (not microvm) since they need disk/BIOS boot or
direct kernel loading. They serve as proof-of-concept for non-Linux
guest support.

## Migration and HA

### Can I migrate microvms between nodes?

Yes — **offline migration** works and has been tested between z83ii and
borg. Migration takes about 2 seconds on shared CIFS storage.

**Live migration** (`qm migrate --online`) is not supported — the QEMU
microvm machine type does not implement it.

### Does HA work?

Yes. Tested with `ha-manager`:

```bash
# VM must be on shared storage (CIFS, NFS, etc.)
ha-manager add vm:9010 --group Intel --state started
ha-manager relocate vm:9010 borg
```

HA relocate performs a stop → migrate → start cycle automatically.
Expect 2–10 seconds of downtime during relocate.

### Can I use Firecracker rootfs images?

Yes. Firecracker rootfs images are raw ext4 filesystem files — the same
format our tools produce. Import them directly:

```bash
qm create 900 --machine microvm --memory 256 --serial0 socket --vga serial0
qm importdisk 900 /path/to/firecracker-rootfs.ext4 local-lvm
qm set 900 --scsi0 local-lvm:vm-900-disk-0
qm set 900 --args '-kernel /usr/share/pve-microvm/vmlinuz \
  -initrd /usr/share/pve-microvm/initrd \
  -append "console=ttyS0 root=LABEL=microvm-root rw"'
```

You use our kernel (not Firecracker's vmlinux) but the rootfs is
interchangeable. See [Firecracker Compatibility](firecracker.md) for the
full guide.

## Future plans

### Will this work on ARM64?

Not yet. The current implementation is x86_64 only. ARM64 support would
need a different QEMU machine type (`virt` instead of `microvm`), a
different kernel config, and testing on ARM64 PVE hosts. It's on the
roadmap.

### What's on the roadmap?

See the [README](../README.md#roadmap) for the full list. Key remaining
items:

- Network off by default
- Egress allow-list (nftables)
- CPU/memory hotplug
- Declarative VM config (TOML)
- Upstream RFC for Proxmox pve-devel
