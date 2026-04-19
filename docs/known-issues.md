# Known Issues

## Kernel: 6.12 defconfig build (RESOLVED in v0.1.18)

The Firecracker 6.1 kernel config had broken virtio device probing on 6.12.
Fixed by switching to the native `x86_64_defconfig` as the base config.

All virtio drivers probe correctly with PCIe transport:
- `virtio_blk` → `/dev/vda`
- `virtio_net` → `eth0`
- `virtio_console` → `/dev/vport1p1` (guest agent channel)
- `virtio_balloon` → memory reporting

## Initrd required

The kernel uses an initrd (1.2 MB) to load virtio modules before mounting
root. Without the initrd, the kernel can't find `/dev/vda`. The template
tool and MicroVM.pm handle this automatically.

## Serial console buffering

QEMU's serial chardev socket does not buffer output when no client is
connected. Boot messages may be lost. Connect via `qm terminal` after boot
for an interactive shell.

## Rootfs requires static busybox

The OCI rootfs must contain either a static init binary or a full init
system (systemd). The host's dynamic busybox won't work inside the microvm.
The `pve-microvm-template` tool handles this by installing packages via
chroot during template creation.

## z83ii performance

The z83ii test node (Intel Atom, 2GB RAM) is slow. OCI pulls may time out.
Template builds take 5+ minutes. For faster testing, use `borg` or `u59`.
