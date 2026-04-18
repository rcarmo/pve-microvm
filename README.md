# pve-microvm

Add QEMU `microvm` machine type support to Proxmox VE as a Debian package.

## Goal

Ship a `.deb` that patches or extends `qemu-server` so that Proxmox can create,
start, stop, and manage lightweight QEMU microVMs as first-class guests —
visible in the UI, manageable via `qm`, and using the existing KVM/QEMU stack.

## Prior art

**Nobody has done this yet.** Research found:

- **No Proxmox patches, PRs, or mailing list threads** for `microvm` machine type support
- **No Debian packages** that add `microvm` guest type to PVE
- **No GitHub repos** implementing this integration
- **Ubuntu** ships a separate `qemu-system-x86-microvm` binary (stripped QEMU build), but it's not a Proxmox integration
- **`linuxdevel/firecracker-farm`** (★0) — shell scripts for Firecracker microVMs on Proxmox hosts, but it's a sidecar tool, not a PVE guest type
- **Proxmox `qemu-server`** explicitly blocks `microvm` in its machine type regex

## Why `microvm`

- Already in QEMU on every Proxmox node — no new binary
- Sub-200ms boot (no BIOS, no ACPI, no PCI scan)
- virtio-mmio devices — minimal attack surface
- Same KVM isolation as regular VMs
- OCI images can be converted to bootable rootfs disks

## Architecture

### What needs to change in `qemu-server`

1. **Machine type regex** — allow `microvm` alongside `pc`/`q35`/`virt`
2. **Command builder** (`Cfg2Cmd.pm`) — stripped-down path that:
   - skips PCI bus, VGA, ACPI, SMBIOS, USB
   - uses `-device virtio-blk-device` / `-device virtio-net-device` (mmio)
   - uses `-serial stdio` or virtio-console
   - passes `-M microvm,x-option-roms=off,pit=off,pic=off,rtc=on`
3. **Config validation** — reject incompatible options (PCI passthrough, VGA, USB, EFI)
4. **Status/monitoring** — QMP still works, so `qm status`/`qm monitor` should be fine

### What needs to change in `pve-manager` (UI)

5. Add `microvm` to machine type dropdown
6. Conditionally hide unsupported panels (VGA, USB, PCI, EFI)

### Helper tooling

7. **`pve-oci-import`** — convert OCI images to bootable microvm disk images:
   - `skopeo copy` → `umoci unpack` → `virt-make-fs` → `.qcow2`
   - ship a stock microvm-compatible kernel (`vmlinuz`)
8. **Microvm kernel package** — minimal kernel config for fast boot

## Package structure

```
pve-microvm/
├── debian/
│   ├── control
│   ├── rules
│   ├── changelog
│   ├── compat
│   └── patches/
│       ├── series
│       ├── 01-machine-type-regex.patch
│       ├── 02-microvm-cmd-builder.patch
│       ├── 03-microvm-config-validation.patch
│       └── 04-ui-microvm-support.patch
├── tools/
│   └── pve-oci-import          # OCI → microvm disk converter
├── kernel/
│   └── microvm-kernel.config   # minimal kernel config
├── Makefile
└── README.md
```

## Scope

### v0.1 — MVP
- [ ] Patch `qemu-server` machine type regex
- [ ] Microvm-aware command builder (minimal device set)
- [ ] Config validation (reject incompatible options)
- [ ] `qm create/start/stop/destroy` working
- [ ] Serial console access via `qm terminal`
- [ ] Basic `pve-oci-import` script
- [ ] `.deb` package that applies patches on install

### v0.2 — UI + polish
- [ ] `pve-manager` UI patches
- [ ] Machine type dropdown includes `microvm`
- [ ] Conditional panel hiding
- [ ] Cloud-init or Ignition support for microvm guests

### v0.3 — Production hardening
- [ ] Microvm kernel package
- [ ] vzdump/backup support assessment
- [ ] Resource accounting / cgroup integration
- [ ] Documentation

## Limitations (known)

- No VNC/noVNC console (serial only)
- No PCI passthrough
- No USB passthrough
- No UEFI/Secure Boot
- No ACPI (no graceful shutdown via ACPI power button — use QMP `system_powerdown` or agent)
- Live migration — untested, likely needs work
- vzdump snapshots — untested

## References

- [QEMU microvm docs](https://www.qemu.org/docs/master/system/i386/microvm.html)
- [Ubuntu microvm docs](https://ubuntu.com/server/docs/explanation/virtualisation/qemu-microvm/)
- [Proxmox `qemu-server` source](https://git.proxmox.com/git/qemu-server.git)
- [Proxmox `pve-manager` source](https://git.proxmox.com/git/pve-manager.git)
- [Proxmox Developer Documentation](https://pve.proxmox.com/wiki/Developer_Documentation)
