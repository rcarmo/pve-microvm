# Frequently Asked Questions

## General

### What is pve-microvm?

A Debian package that adds QEMU's `microvm` machine type as a managed guest type in Proxmox VE. It lets you create lightweight, hardware-isolated VMs that boot in under a second, managed through the same `qm` CLI and web UI you already use for regular VMs and containers.

### Can I use this in production?

Not yet. This is highly experimental. It patches `qemu-server` internals and has been tested on a single node (z83ii, Intel Atom). The patches are reversible and the architecture is sound, but it needs broader testing before production use. Back up your Proxmox configuration before installing.

### What's the boot time?

We deliberately test on the slowest node in the cluster — an Intel Atom
x5-Z8350 — to make sure performance is acceptable everywhere.

**z83ii** (Intel Atom x5-Z8350 @ 1.44 GHz, 2 GB RAM):

| Stage | Busybox (Alpine) | Debian trixie-slim |
|---|---|---|
| QEMU start → serial socket | ~200 ms | ~200 ms |
| Kernel + initrd → shell prompt | ~2 s | ~8 s |
| + DHCP networking ready | ~4 s | ~15 s |
| + DHCP + guest agent responding | ~8 s | ~30 s |

**borg** (Intel Core i7-12700 @ 4.9 GHz, 20 cores, 125 GB RAM):

| Stage | Busybox (Alpine) | Debian trixie-slim |
|---|---|---|
| QEMU start → serial socket | <50 ms | <50 ms |
| Kernel + initrd → shell prompt | <500 ms | ~2 s |
| + DHCP networking ready | ~1 s | ~5 s |
| + DHCP + guest agent responding | ~2 s | ~10 s |

## Comparison with other approaches

### How is this different from a regular QEMU/KVM VM?

A standard Proxmox VM emulates a full PC: BIOS/UEFI firmware, PCI buses, VGA display, USB controllers, ACPI tables. That takes 2–10 seconds to boot and consumes resources even when idle.

A microvm strips all of that away. No BIOS scan, no PCI topology, no display. Just a kernel, virtio devices, and a serial console. The result: sub-second boot, minimal memory overhead, and a much smaller attack surface — while keeping the same KVM hardware isolation.

### How is this different from an LXC container?

LXC containers share the host kernel. A compromised container process has the same kernel attack surface as every other container on the node. This is fine for trusted workloads but risky for things like coding agents that routinely `curl | bash` arbitrary code.

A microvm runs its own kernel inside a hardware-isolated VM. The host kernel is never exposed to the guest. You get container-like speed with VM-level isolation.

### Why not just use Firecracker or Cloud Hypervisor?

Firecracker and Cloud Hypervisor are standalone VMMs — separate binaries with their own APIs, lifecycle models, and tooling. They don't integrate with Proxmox's VM management, storage, networking, backup, or web UI.

pve-microvm uses the QEMU that's already on every Proxmox node. Your microvms show up in the PVE web UI, use PVE storage, get PVE firewall rules, and work with `qm`, `vzdump`, `qm snapshot`, etc. No new runtime to install or manage.

### Why not use smolvm?

smolvm is a great standalone tool for running microVMs locally. It uses libkrun (not QEMU) and targets developer workstations and CI runners.

pve-microvm targets Proxmox clusters. If you're already running PVE for your infrastructure, pve-microvm lets you add microvm workloads without introducing a separate runtime. The two projects solve different problems at different layers.

### How does this compare to kata-containers?

Kata Containers wraps each container in a lightweight VM for Kubernetes/CRI workloads. It requires containerd and a CRI runtime.

pve-microvm is for Proxmox — it makes microvms a native PVE guest type managed through the same tools as regular VMs. No Kubernetes, no containerd, no extra runtime stack.

## Installation and maintenance

### Does this modify Proxmox itself?

Yes — it patches two Perl files in `qemu-server` to allow the `microvm` machine type and delegate command generation to a new module. It also injects a small JavaScript file into the PVE web UI for the machine type dropdown and panel hiding.

All changes are fully reversible. Uninstalling the package restores the original files from backup.

### Can I undo the installation?

Yes. `apt remove pve-microvm` reverts all patches and restores the original `qemu-server` files. No VMs, configs, or data are affected.

### What happens when Proxmox upgrades qemu-server?

The package includes a dpkg trigger that watches for changes to the patched files. When `qemu-server` is upgraded, the trigger automatically re-applies the patches. You can also manually run `/usr/share/pve-microvm/pve-microvm-patch apply` after an upgrade.

### Which storage backends work?

All of them: LVM, LVM-thin, ZFS, dir (local), NFS, CIFS, Ceph/RBD. The tools parse `qm importdisk` output to get the correct volume ID regardless of storage type.

## Technical details

### Why does the kernel need an initrd?

The shipped kernel (6.12.22, built from `x86_64_defconfig`) has virtio drivers compiled as modules rather than built-in. On QEMU 10.x's microvm with PCIe, the modules need to be loaded before the root device appears. The initrd (1.1 MB) loads the virtio modules, mounts the root filesystem, and hands off to the real init.

### Why PCIe instead of virtio-mmio?

QEMU 10.x's microvm mmio transport has a device probing issue where only `virtio-blk` binds — network, serial, and balloon devices don't get claimed by their drivers. PCIe with non-transitional devices works reliably for all device types, and paves the way for future GPU support. The boot time penalty is negligible (~50ms).

### How much RAM does a microvm need?

- **256 MB** is enough for the kernel + busybox (Alpine-style minimal images)
- **512 MB** is comfortable for Debian trixie-slim with systemd + cloud-init
- **1 GB+** if you plan to run Docker or install many packages

The balloon device reports actual usage, so PVE's memory accounting is accurate.

### Why is there no VNC/noVNC console?

Microvm has no VGA hardware. The console is serial-only (ttyS0), accessible via `qm terminal` on the CLI or xterm.js in the PVE web UI (configured automatically when `vga: serial0` is set).

### Why does the guest agent take so long to start?

On slow hardware (e.g., Intel Atom), systemd + cloud-init can take 60–120 seconds to fully initialize. The guest agent service retries automatically (`Restart=always, RestartSec=5`). On faster hardware, the agent is typically ready in 10–30 seconds, but realistically most microVM workloads don't need the agent--we just added it because it provides better observability, and the trade-off is acceptable in the long run.

## Guest capabilities

### Can I run Docker inside a microvm?

Yes. The template's current first-boot setup actually installs Docker CE because that is a key part of our workflow, but there will be an option to disable that by default. The kernel supports nested namespaces and cgroups. KVM passthrough (`-cpu host`) means Docker works at native speed.

### Can I SSH into a microvm?

Yes. The current template installs OpenSSH server by detault and `cloud-init` configures it. Set your SSH key via `qm set <vmid> --sshkeys ~/.ssh/authorized_keys` before first boot.

### How do I share files between host and guest?

Use `pve-microvm-share`:

```bash
pve-microvm-share <vmid> /path/to/host/directory
# Inside guest: mount -t virtiofs shared /mnt/shared
```

This uses virtiofs (via virtiofsd) for near-native filesystem performance without networking.

### How do I forward my SSH keys into the guest?

Use `pve-microvm-ssh-agent`:

```bash
pve-microvm-ssh-agent <vmid>
# Inside guest: socat UNIX-LISTEN:/tmp/agent.sock,fork VSOCK-CONNECT:2:2222 &
# SSH_AUTH_SOCK=/tmp/agent.sock git clone git@github.com:...
```

Private keys never enter the guest — only the SSH agent protocol is forwarded over vsock.

### Can I boot non-Linux guests?

Yes — experimentally. 9Front (Plan 9) is supported as a template:

```bash
pve-microvm-template --image 9front --vmid 9002
```

This is a proof-of-concept for running non-Linux microvms, and a stepping stone toward specialist microkernels used in telco (PikeOS, QNX), real-time systems (Zephyr, seL4), and unikernel frameworks (Unikraft). Because I'm weird that way.

## Future plans

### Will this work on ARM64 / Raspberry Pi?

Not yet. The current implementation is x86_64 only. ARM64 support would need a different QEMU machine type (`virt` instead of `microvm`), a different kernel config, and testing on ARM64 PVE hosts. It's on the roadmap as a low-priority exploratory item, but since we run PVE on ARM64 already, it might get done sooner than later.

### Can I migrate microvms between nodes?

Not tested. Live migration of microvm guests may work since the PCIe device model is simpler than a full q35 VM, but this hasn't been validated. It's on the roadmap.

### Can I use Firecracker rootfs images?

Yes. Firecracker rootfs images are raw ext4 filesystem files — the same
format our tools produce. Import them directly:

```bash
qm create 900 --machine microvm --memory 256 --serial0 socket --vga serial0
qm importdisk 900 /path/to/firecracker-rootfs.ext4 local-lvm
qm set 900 --scsi0 local-lvm:vm-900-disk-0
qm set 900 --args '-kernel /usr/share/pve-microvm/vmlinuz -initrd /usr/share/pve-microvm/initrd -append "console=ttyS0 root=/dev/vda rw"'
```

You use our kernel (not Firecracker's vmlinux) but the rootfs is
interchangeable. There's no separate "Firecracker registry" — any ext4
rootfs works, whether built for Firecracker, Docker-exported, or
created by `pve-oci-import`.
