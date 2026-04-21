# Limitations

## No display

No VGA, QXL, or virtio-gpu. No VNC/noVNC/SPICE. Serial console only
(`qm terminal` or xterm.js via `vga: serial0`).

## No PCI bus

No PCI topology — no PCI passthrough, no PCI-attached devices. Everything
uses virtio-mmio. Max ~32 mmio devices depending on QEMU version.

## No ACPI

No ACPI power button. `qm shutdown` requires the guest agent.
Use `qm stop` for force shutdown.

## No USB

No USB controllers. No USB passthrough.

## No UEFI / Secure Boot

Direct kernel boot only. No firmware, no EFI variables.

## Kernel required

Unlike standard VMs, microvm always needs `-kernel` in `args`.
The kernel must be on the Proxmox host filesystem.

## No CD-ROM / ISO boot

Cannot boot from ISO. Use `pve-oci-import` or prepare disk images directly.

## Migration untested

Live migration has not been tested. The reduced device model may simplify
state transfer but this is unverified.

## Backup (vzdump)

Not yet validated. Guest agent fsfreeze should work if agent is installed.

## Limited NICs

Current implementation supports up to 6 network interfaces per guest.
Can be increased in `MicroVM.pm`.

## Serial buffer

QEMU's serial chardev socket does not buffer output when no client is
connected. Boot messages may be lost. Connect via `qm terminal` after boot
to get an interactive shell.

## Kernel config drift

The Firecracker 6.1 base kernel config may silently lose drivers when
built on newer kernel versions (e.g., 6.12). The PVE overlay forces
critical drivers (`virtio_net`, `virtio_balloon`, `virtio_console`) to
`=y`. Always verify the final `.config` after `make olddefconfig`.

## 9Front / Plan 9 (experimental)

9Front template support is experimental and intended as a quick way to test
non-Linux microvms. It demonstrates the platform's ability to host alternative
operating systems before tackling specialist microkernels such as:

- **PikeOS** / **QNX** — safety-certified RTOS for telco and automotive
- **seL4** — formally verified microkernel
- **Zephyr** — real-time OS for embedded and edge
- **Unikraft** — unikernel framework for single-application VMs

9Front uses q35 (not microvm machine type) since Plan 9 boots from disk
via BIOS. The serial console requires typing `console=0` at the boot prompt
or editing `plan9.ini` inside the guest.
