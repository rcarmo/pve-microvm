# Known Issues

## virtio-mmio device discovery (v0.1.x)

The pre-built kernel (6.12.22 from Firecracker 6.1 config) has all virtio
drivers compiled in, but **only `virtio_blk` probes** on the microvm mmio bus.
`virtio_net`, `virtio_console`, and `virtio_balloon` are linked into the
kernel but don't bind to their devices.

**Root cause**: Under investigation. The QEMU 10.x microvm mmio device
registration path differs from Firecracker's libkrun, and the kernel's
`virtio_mmio` driver doesn't discover all devices.

### Workarounds

1. **Use the PVE host kernel + initrd** (recommended until fixed):
   ```
   args: -kernel /boot/vmlinuz-$(uname -r) -initrd /boot/initrd.img-$(uname -r) -append "console=ttyS0 root=/dev/vda rw"
   ```
   This uses modules from the initramfs and all devices work.

2. **Use `pcie=on`** in the machine flags (adds ~100ms boot time):
   Requires fixing the I/O BAR assignment issue on microvm's minimal PCI bridge.

## Serial console buffering

QEMU's serial chardev socket (`server=on,wait=off`) does not buffer output
when no client is connected. Boot messages are lost. Connect via
`qm terminal` after boot to get an interactive shell.
