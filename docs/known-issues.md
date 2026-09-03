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

## Guest-agent port discovery (FIXED in v0.3.24)

The shipped kernel includes `CONFIG_VIRTIO_CONSOLE=y` and creates
`/dev/vport1p1`, but minimal guests may not replay the udev event that creates
`/dev/virtio-ports/org.qemu.guest_agent.0` after the initrd hand-off. The
vendor `qemu-guest-agent.service` waits for that named device and stays
inactive even though the driver and direct port work.

Older templates worked around this with a separate `microvm-agent.service`.
If the vendor unit later started too, both processes competed for
`/dev/vport1p1` and the custom service restarted forever.

Current templates keep exactly one service named `qemu-guest-agent.service`.
A microVM-specific replacement unit waits up to 60 seconds for
`/dev/vport1p1`, runs the packaged `qemu-ga` binary against that path, and uses
`Restart=always` without depending on the named udev symlink.

For an existing Debian/Ubuntu guest, remove the legacy and vendor-device
assumptions by copying the replacement unit from a newly generated template or
create this equivalent unit with the correct `qemu-ga` path:

```ini
[Unit]
Description=QEMU Guest Agent for microVM
After=local-fs.target

[Service]
Type=simple
ExecStart=/bin/sh -c 'i=0; while test $i -lt 60; do test -c /dev/vport1p1 && exec /usr/sbin/qemu-ga --method=virtio-serial --path=/dev/vport1p1; i=$((i + 1)); sleep 1; done; exit 1'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Then run:

```bash
systemctl disable --now microvm-agent.service 2>/dev/null || true
rm -f /etc/systemd/system/microvm-agent.service
rm -rf /etc/systemd/system/qemu-guest-agent.service.d
systemctl daemon-reload
systemctl enable --now qemu-guest-agent.service
```

Enterprise Linux commonly installs the binary as `/usr/bin/qemu-ga`; verify
with `command -v qemu-ga` before writing the unit.

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

Cloud-init does not move the root disk in current releases. Keep
`root=/dev/vda`; the data disk is `/dev/vdb`.

## File-backed linked clone detected as raw (FIXED in v0.3.23)

Releases through v0.3.22 called a nonexistent `PVE::Storage::volume_format()`
function. Because the call was inside `eval`, the failure was hidden and the
command builder defaulted to raw. A file-backed qcow2 linked clone was then
passed to QEMU as `format=raw` and failed to boot.

The command builder now reads the seventh value from
`PVE::Storage::parse_volname()`, which is PVE's actual volume format metadata.
Unknown formats and parser failures stop command generation instead of risking
writes through the wrong block driver. Explicit drive formats still take
priority, and RBD continues to use `format=rbd`.

## Docker containers fail: bpf_prog_query not implemented (FIXED in v0.3.9)

Docker's runc requires BPF cgroup device controller support:

```
bpf_prog_query(BPF_CGROUP_DEVICE) failed: function not implemented
```

**Root cause**: The microvm kernel overlay had `CONFIG_CGROUP_BPF=y` but
not `CONFIG_BPF_SYSCALL=y`, so `CGROUP_BPF` was silently disabled by
`make olddefconfig`.

**Fix** (v0.3.9): Added `CONFIG_BPF_SYSCALL`, `CONFIG_BPF_JIT`,
`CONFIG_BPF_JIT_ALWAYS_ON` to the overlay. Requires kernel rebuild.

**Workaround**: Use the Debian stock kernel for Docker workloads:

```bash
# Inside the microvm, install the Debian kernel:
apt-get install -y linux-image-amd64

# On the host, extract and switch:
# (see virtualdsm/archivebox examples in the docs)
qm set <vmid> --args "-kernel /usr/share/pve-microvm/vmlinuz-docker ..."
```
