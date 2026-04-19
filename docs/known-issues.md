# Known Issues

## Virtio driver binding on QEMU 10.x microvm (v0.1.x)

**Status**: Under investigation. Affects the shipped 6.12.22 custom kernel.

The pre-built kernel has all virtio drivers compiled in (`=y`), but only
`virtio_blk` binds to devices — both on mmio and PCIe transport. The
`virtio_net`, `virtio_console`, and `virtio_balloon` drivers are present in
the kernel binary but their probe functions never fire.

This affects:
- **Networking**: no eth0 interface
- **Guest agent**: no virtio-serial port, qemu-ga can't start
- **Memory ballooning**: no balloon device

The same behavior occurs with:
- virtio-mmio transport (no PCI)
- PCIe with transitional devices
- PCIe with non-transitional devices
- Drivers built-in (`=y`) or as modules (`=m`)

### Root cause hypothesis

The Firecracker 6.1 kernel config, when processed by `make olddefconfig` on
kernel 6.12, silently changes a Kconfig dependency that prevents non-block
virtio PCI device IDs from being registered. The `virtio_blk` driver works
because its device ID table is populated differently.

### Workaround: use PVE host kernel

```
args: -kernel /boot/vmlinuz-$(uname -r) -initrd /boot/initrd.img-$(uname -r) -append "console=ttyS0 root=/dev/vda rw"
```

Requires 1GB+ RAM due to the large PVE initrd (78 MB).

### Future fix

- Build a kernel config from scratch for 6.12 (not based on Firecracker 6.1)
- Or debug the exact Kconfig dependency causing the driver ID table issue
- Or use the PVE kernel with a minimal initrd containing only virtio modules

## Serial console buffering

QEMU's serial chardev socket (`server=on,wait=off`) does not buffer output
when no client is connected. Boot messages are lost. Connect via
`qm terminal` after boot to get an interactive shell.
