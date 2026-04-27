# Changelog

## v0.3.5 (2026-04-27)

50 shipped features, 21 guest OS types.

### Features

- `qm create/start/stop/destroy` with microvm
- Serial console via `qm terminal` and PVE web UI (xterm.js)
- OCI image import and template cloning
- All PVE storage backends (LVM, LVM-thin, ZFS, Ceph, NFS)
- Pre-built microvm kernel (6.12.22 from defconfig)
- Web UI machine type dropdown + Create µVM dialog
- Balloon device for memory reporting
- Guest agent (virtio-serial, auto-retry)
- Networking (tap, bridge, VLAN, DHCP via cloud-init)
- `microvm-init` for minimal OCI images
- GitHub Actions CI/CD with kernel + initrd build
- Cloud-init / user-data — SSH keys, hostname, network config
- Linked clones — instant LVM snapshot cloning
- dpkg trigger — auto-reapply patches on `qemu-server` upgrades
- SSH agent forwarding via vsock (`pve-microvm-ssh-agent`)
- vsock host↔guest sockets (CID = VMID + 1000)
- virtiofs shared folders (`pve-microvm-share`)
- 9p filesystem sharing (`pve-microvm-9p`, no daemon needed)
- `qm shutdown` — graceful shutdown via guest agent
- Disk resize (`qm disk resize`)
- vzdump backup (stop-mode)
- Offline migration between nodes (shared storage, 2s on CIFS)
- HA support (ha-manager add/relocate, stop-migrate-start cycle)
- Snapshots (`qm snapshot`)
- Firewall integration (tap on vmbr0)
- Resource accounting (cluster resources)
- `onboot` / startup order
- Nested virtualization (KVM passthrough)
- Template profiles (minimal/standard/full, --no-docker, --no-ssh, --no-agent)
- Performance benchmarking (`pve-microvm-bench`)
- Ephemeral VMs (`pve-microvm-run`)

### Guest OS (21 types)

- 13 Linux: Debian, Ubuntu, Alpine, Fedora, Rocky, Alma, Amazon, Oracle, UBI, Photon, Azure Linux
- SmolBSD (NetBSD, 307ms boot, virtio-mmio)
- OpenWrt (router OS, 13 MB)
- OPNsense (FreeBSD firewall, 500 MB)
- 9Front (Plan 9)
- OSv (unikernel)
- gokrazy (Go appliance)
- Firecracker rootfs (ext4 import)

### Web UI

- Create µVM dialog with OCI image picker
- ⚡ amber bolt icon for microvm VMs
- xterm.js console (auto-selected for microvm)
- Panel hiding (BIOS/EFI/USB/PCI/TPM hidden)
- One-click clone from templates
- Context menu: serial console + clone
- Dark mode support

### Bug fixes (v0.3.1–v0.3.5)

- Cloud-init drive order: scsi0 always first (/dev/vda)
- `valid_drive_names()` returns 0 at runtime on qemu-server 9.1.6
- `drive_is_cdrom($drive, 1)` excluded cloud-init from detection
- dpkg trigger loop (interest-noawait)
- postinst now always reverts+reapplies on upgrade
