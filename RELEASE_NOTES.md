# pve-microvm v0.1.5

Docs restructure, GUI extension, proper init, balloon device.

## Highlights

- **Demo GIF in README** — concise README with all detail moved to `docs/`
- **GUI extension** — `microvm` in machine type dropdown, auto-sets serial/vga
- **`microvm-init`** — shipped init for minimal OCI images (debian:trixie-slim)
  with `agetty --autologin root` on ttyS0
- **Balloon device** — `virtio-balloon-device` on mmio suppresses PVE warning
- **Default: `debian:trixie-slim`** (28 MB) — same Debian as PVE 9 host

## End-to-end tested

```
pve-microvm-template → qm clone → qm start → qm terminal → root@microvm:~#
```

On z83ii: PVE 9.1.7, QEMU 10.1.2, LVM-thin.

## All changes since v0.1.4

- Restructured docs into `docs/` (installation, usage, config, architecture,
  limitations, troubleshooting, development)
- Ship `microvm-init` for images without `/sbin/init`
- Add `virtio-balloon-device` to QEMU command
- Fix OCI import init detection (systemd vs busybox vs minimal)
- GUI: machine dropdown, auto-set serial0/vga, hide unsupported fields
