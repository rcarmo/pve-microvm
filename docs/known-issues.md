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

The guest agent takes 30-120 seconds to start on slow hardware (e.g. z83ii).
The systemd override uses `Restart=always` with `RestartSec=5`.
`qm agent <vmid> ping` succeeds once the agent connects to `/dev/vport1p1`.

## Serial console

Uses a custom `microvm-console.service` with `agetty --autologin root`
instead of the stock `serial-getty@ttyS0` which requires udev device
events that devtmpfs from initrd doesn't generate.

## Serial buffering

QEMU's serial chardev socket doesn't buffer when no client is connected.
Boot messages may be lost. Connect via `qm terminal` or the web UI Console.

## PCI: Fatal: No config space access function found

Harmless warning from the microvm boot. The guest kernel tries standard
PCI config space probing before the PCIe ECAM from microvm is initialized.
Does not affect device functionality — all virtio devices bind correctly.

## Cloud-init Perl warning (FIXED in qemu-server 9.1.8)

```
Use of uninitialized value in split at /usr/share/perl5/PVE/QemuServer/Cloudinit.pm line 115.
```

Harmless PVE warning when generating cloud-init ISO for microvms.
Cloud-init data is injected correctly despite the warning.

**Fixed**: This warning is resolved in `qemu-server` 9.1.8+.

## HA relocate (not live)

HA relocate works but performs stop→migrate→start (not live migration).
Expect 2-10 seconds of downtime during relocate depending on hardware.

## Cloud-init drive order (FIXED in v0.3.3)

On `qemu-server` < 9.1.8, the cloud-init ISO (`scsi1`) could appear as
`/dev/vda` before the root disk, breaking `root=/dev/vda` in the kernel
args.

**Root cause**: Three issues combined:
1. `PVE::QemuServer::Drive::valid_drive_names()` returns 0 items at
   runtime inside `config_to_command` on qemu-server 9.1.6
2. `is_microvm()` relied on `Machine::parse_machine()` which could fail
   on older qemu-server versions
3. Drive iteration order was not guaranteed

**Fix** (v0.3.3):
1. `is_microvm()` falls back to raw string match if parse fails
2. Drive loop iterates `keys %$conf` (not `valid_drive_names()`)
3. Sort guarantees scsi0 is always emitted first (`/dev/vda` = root)
4. Cloud-init ISO included as `/dev/vdb` (needed for config delivery)
5. Root filesystem labelled `microvm-root` for future LABEL= boot
