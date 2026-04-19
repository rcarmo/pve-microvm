# Known Issues

## Guest agent startup delay

The guest agent takes 30-120 seconds to start on slow hardware (z83ii Atom).
The systemd override uses `Restart=always` with `RestartSec=5` for
automatic retry. `qm agent <vmid> ping` will succeed once ready.

## Serial console

Uses a custom `microvm-console.service` with `agetty --autologin root`
instead of the stock `serial-getty@ttyS0` which requires udev device
events that devtmpfs from initrd doesn't generate.

## Serial buffering

QEMU's serial chardev socket doesn't buffer when no client is connected.
Connect via `qm terminal` after boot for interactive access.

## DHCP timing on slow hardware

On z83ii (Intel Atom), DHCP may take 30-60 seconds after boot.
Cloud-init configures networkd; the lease is obtained once the network
stage completes.

## Template build time

On z83ii, OCI pulls and chroot package installation take 5+ minutes.
All features are confirmed working despite the slow hardware.
