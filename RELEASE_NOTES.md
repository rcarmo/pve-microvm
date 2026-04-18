# pve-microvm v0.1.4

End-to-end tested release. The PVE web UI now opens the serial console
correctly when you click "Console" on a microvm guest.

## What's new

- **Serial console works in PVE web UI** — `vga: serial0` tells PVE to use
  xterm.js serial console instead of noVNC. All tools set this automatically.
- **Default image: `debian:trixie-slim`** (28 MB) — same Debian as PVE 9 host.
- **systemd image support** — serial-getty@ttyS0 enabled, empty root password.
- **`pve-microvm-template`** — one-command golden image creation with instant cloning.
- **Clean VM config** — tools auto-delete `vmgenid`/`smbios1` (unsupported on microvm).

## All fixes since v0.1.0

- Fix regex patcher (rewrote in Python)
- Fix bridge script path (`/usr/libexec/qemu-server/`)
- Fix Perl module imports (`Network.pm`, `Agent.pm`)
- Fix `-append` args quoting (respect double-quoted strings)
- Fix `get_vm_machine()` appending `+pve0` to microvm
- Fix kernel inclusion in .deb (`dh_auto_clean` override)
- Fix `.deb` upload in CI (`upload-artifact` path)
- Publish to GitHub Packages (ghcr.io)

## Tested on

- **z83ii** — PVE 9.1.7, kernel 6.17.13-2-pve, QEMU 10.1.2, LVM-thin
- Full lifecycle: install → create → start → console → stop → destroy ✅
- Network: tap device on vmbr0 ✅
- Storage: LVM-thin ✅
- Kernel: 6.12.22 boots, mounts ext4 rootfs ✅
