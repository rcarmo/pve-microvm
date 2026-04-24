# Limitations

## No display

No VGA, QXL, or virtio-gpu. No VNC/SPICE. Serial console only via xterm.js
(PVE web UI auto-selects xterm.js for microvm, or use `qm terminal`).

## No PCI passthrough

The microvm machine type uses a minimal PCIe bus (`pcie=on`) for virtio
device transport. PCI passthrough of host devices (GPUs, NICs, etc.)
is not supported.

## No USB

No USB controllers. No USB passthrough.

## No UEFI / Secure Boot

Direct kernel boot only. No firmware, no EFI variables.

## Kernel required

Unlike standard VMs, microvm always needs `-kernel` in `args`.
The kernel and initrd must be on the Proxmox host filesystem
(installed to `/usr/share/pve-microvm/` by the package).

## No CD-ROM / ISO boot

Cannot boot from ISO. Use `pve-microvm-template` to build from OCI images,
or import ext4/raw disk images directly with `qm importdisk`.

## No live migration

Live migration (`qm migrate --online`) is not supported for the microvm
machine type. Offline migration works — HA relocate performs a
stop→migrate→start cycle automatically (tested z83ii↔borg, ~2 seconds).

## No ACPI power button

No ACPI power button. `qm shutdown` requires the guest agent.
Use `qm stop` for force shutdown.

## Limited NICs

Current implementation supports up to 6 network interfaces per guest.
Can be increased in `MicroVM.pm`.

## Serial buffer

QEMU's serial chardev socket does not buffer output when no client is
connected. Boot messages may be lost. Connect via `qm terminal` after boot
to get an interactive shell.

## Kernel config

Uses `x86_64_defconfig` with an overlay for virtio, vsock, and virtiofs.
The Firecracker 6.1 kernel config is NOT compatible — it has broken virtio
device ID tables on kernel 6.12+. Always use the shipped kernel.

## 9Front / Plan 9 (experimental)

Uses q35 (not microvm machine type) since Plan 9 boots from disk via BIOS.
Serial console requires `console=0` at boot or editing `plan9.ini`.

## OSv (experimental)

Uses q35 with `-kernel` boot. The loader image needs a separate application
image (built with `capstan` or `ops`) attached as a disk.
