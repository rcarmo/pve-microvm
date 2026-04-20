# Known Issues

## systemd-networkd config matching (WORKAROUND in v0.1.21+)

systemd-networkd on Trixie doesn't match `.network` config files for eth0
after the initrd switch_root. `networkctl status eth0` shows
`Network File: n/a` despite correct file permissions and matching criteria.

**Root cause**: The initrd's devtmpfs doesn't generate udev events that
networkd uses for link matching. The interface is UP with carrier but
networkd never claims it.

**Workaround**: A `microvm-dhcp.service` runs `dhclient -4 eth0` at boot
as a reliable fallback. DHCP works instantly via dhclient.

## Guest agent startup delay

The guest agent takes 30-120 seconds to start on slow hardware.
The systemd override uses `Restart=always` with `RestartSec=5`.
`qm agent <vmid> ping` succeeds once the agent connects to `/dev/vport1p1`.

## Serial console

Uses a custom `microvm-console.service` with `agetty --autologin root`
instead of the stock `serial-getty@ttyS0` which requires udev device
events that devtmpfs from initrd doesn't generate.

## Serial buffering

QEMU's serial chardev socket doesn't buffer when no client is connected.
Boot messages may be lost. Connect via `qm terminal` or the web UI Console.

## VM shutdown state

After `qm shutdown`, QEMU stays alive in "shutdown" state due to
`-no-shutdown`. The PVE web UI may show the VM as stopped but the process
persists. Use `qm stop` to fully terminate, or `qm start` will restart cleanly.
EOF
