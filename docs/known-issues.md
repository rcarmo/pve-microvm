# Known Issues

## Kernel: 6.12 defconfig build (RESOLVED in v0.1.18)

The original Firecracker 6.1 kernel config had broken virtio device probing
when built on kernel 6.12. Fixed by switching to the native 6.12 `x86_64_defconfig`
as the base config.

All virtio drivers (net, block, balloon, console) are confirmed compiled and
linked in the v0.1.18 kernel. `virtnet_probe`, `virtblk_probe`, `balloon_probe`
are all present in `vmlinux`.

## Initrd: switch_root devtmpfs (RESOLVED in v0.1.18)

The initrd's `/init` script was losing `/dev` during `switch_root`, causing
`/dev/ttyS0` to not exist when systemd started. Fixed by keeping devtmpfs
mounted during switch_root.

## Serial console buffering

QEMU's serial chardev socket (`server=on,wait=off`) does not buffer output
when no client is connected. Boot messages are lost. Connect via
`qm terminal` after boot for an interactive shell.

## z83ii test node performance

The z83ii node (Intel Atom Z83II, 2GB RAM) is very slow for OCI pulls and
template creation. Full template builds take 5+ minutes. Consider testing
on `borg` or `u59` for faster iteration.

## Guest agent device path

The guest agent's default systemd service has `BindsTo=dev-virtio\x2dports-...`
which may time out on microvm. The template creates a systemd override that
removes this binding and lets `qemu-ga` auto-detect its channel.
