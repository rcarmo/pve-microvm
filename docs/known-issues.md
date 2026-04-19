# Known Issues

## Kernel config (RESOLVED in v0.1.18)

The Firecracker 6.1 config had broken virtio probing on kernel 6.12.
Fixed by using the native `x86_64_defconfig` as the base.

## Serial console (RESOLVED in v0.1.20)

The stock `serial-getty@ttyS0` requires `dev-ttyS0.device` which needs
udev events that devtmpfs from initrd doesn't generate (90s timeout).
Fixed with a custom `microvm-console.service` using agetty directly.

## Guest agent startup delay

`qemu-ga` may fail on first attempt if `/dev/vport1p1` isn't ready.
The systemd override uses `--retry-path` and `Restart=always` so it
retries automatically. Typically works within 3-6 seconds.

## Serial console buffering

QEMU's serial chardev socket does not buffer output when no client is
connected. Boot messages are lost. Connect via `qm terminal` after boot.

## z83ii performance

Template builds take 5+ minutes on the Atom. OCI pulls may time out.
All features confirmed working despite the slow hardware.
