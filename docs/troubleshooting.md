# Troubleshooting

## "option 'X' is not supported with microvm machine type"

Remove the unsupported option:

```bash
qm set <vmid> --delete <option>
```

Common: `bios`, `efidisk0`, `usb0`, `hostpci0`.

## "microvm requires a kernel"

Specify a kernel via `--args`:

```bash
qm set <vmid> --args '-kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw"'
```

## No console output

1. Ensure `console=ttyS0` is in the kernel command line
2. Ensure `serial0: socket` and `vga: serial0` are in the VM config
3. Use `qm terminal <vmid>` (not noVNC)
4. Press Enter — the shell may be waiting for input

## Kernel panic: "No working init found"

1. Verify the rootfs has `/sbin/init` (or use `init=/sbin/microvm-init` in append)
2. Verify root device: `root=/dev/vda` matches the actual root disk
3. Verify ext4 is compiled into the kernel (not as a module)
4. Debug: add `rdinit=/bin/sh` to kernel append to get a pre-init shell

## Network not working

1. Check bridge exists: `brctl show`
2. Check tap device: `ip link show tap<vmid>i0`
3. Inside guest: `ip link` — may need DHCP or static config
4. Try: `udhcpc -i eth0` (Alpine) or `dhclient eth0` (Debian)

## "KVM virtualisation configured, but not available"

```bash
ls -la /dev/kvm
modprobe kvm_intel   # or kvm_amd
```

For nested VMs, enable nested virtualization on the outer hypervisor.

## `qm shutdown` or `qm reboot` times out

MicroVMs do not have a conventional ACPI power button. Graceful power operations
therefore require the QEMU guest agent and a working guest shutdown command.

Releases before v0.3.17 also omitted PVE's qmeventd monitor socket. The guest
could power off correctly while QEMU remained in `paused (shutdown)` because it
runs with `-no-shutdown`.

Upgrade `pve-microvm`, restart the VM so the new QEMU command line is used, and
verify the qmeventd monitor is present. Since v0.3.20, package installation also
reloads `pvedaemon`; this is required because its long-lived Perl process would
otherwise keep the previous `MicroVM.pm` for UI, API, `pvesh`, and automation
requests. Fresh `qm` processes do not have that cache.

```bash
qm showcmd <vmid> --pretty | grep -E 'qmp-event|qmeventd.sock'
```

Existing Debian/Ubuntu guests built without D-Bus also need:

```bash
qm guest exec <vmid> -- bash -lc \
  'apt-get update && apt-get install -y dbus && systemctl enable --now dbus'
```

Then verify both lifecycle operations. A reboot must change the guest boot ID;
a shutdown must leave no QEMU process behind:

```bash
qm reboot <vmid>
qm shutdown <vmid> --timeout 60
qm status <vmid>
```

Guests created with `--no-agent` still have no guaranteed graceful shutdown
path; use `qm stop` or install/enable the QEMU guest agent.

## Patches not applied after qemu-server upgrade

Do not restore an old backup before applying patches, because it may belong to
an older qemu-server version. Apply the current patch set directly:

```bash
rm -f /usr/share/pve-microvm/.applied
/usr/share/pve-microvm/pve-microvm-patch apply
systemctl reload pvedaemon
```

## WebUI package update disconnects after patching

Versions 0.3.20 through 0.3.25 fully restarted `pvedaemon` after applying patches.
That can terminate the WebUI terminal and the package update running beneath it.
The `Disconnecting... (Detecting migration...)` banner does not establish that a
VM migrated or that the update completed.

Upgrade to 0.3.26 or later, which uses Proxmox's graceful reload action. When
recovering from an interrupted update, connect over SSH and first check whether
an `apt` or `dpkg` process is still running. Do not remove lock files or start a
second package manager while one is active. Once it has stopped, inspect
`dpkg --audit` and `/var/log/apt/term.log`; use `dpkg --configure -a` to finish
pending configuration if needed, then retry the upgrade over SSH.

See [the #20 RCA](rca-issue-20.md) for the process lifecycle and canary tests.

## pve-oci-import fails: "required tool not found"

```bash
apt update && apt install skopeo umoci qemu-utils
```

## pve-oci-import fails: "failed to import disk"

The VM must exist first:

```bash
qm create <vmid> --machine microvm --memory 256
pve-oci-import --image alpine:3.21 --vmid <vmid>
```

## Linked qcow2 clone drops into the initrd or BusyBox

Check the format passed to QEMU:

```bash
qm showcmd <vmid> --pretty | grep 'drive-scsi0'
```

A file-backed qcow2 clone must include `format=qcow2`; LVM-thin and ZFS block
volumes normally use `format=raw`. Releases before v0.3.23 could call a
nonexistent PVE format API, swallow the error, and pass a qcow2 overlay as raw.
Do not rename the image or change `root=/dev/vda` as a workaround.

With cloud-init, the supported order is:

```text
scsi0 -> /dev/vda  root filesystem
scsi1 -> /dev/vdb  cloud-init data
```

Collect `qm config`, `qm showcmd --pretty`, `pvesm status`, and
`PVE::Storage::parse_volname()` output when diagnosing a backend-specific
format mismatch.

## No network / no guest agent / no balloon

Check the QEMU devices, guest character devices, and release build log rather
than searching compressed `vmlinuz` strings:

```bash
qm showcmd <vmid> --pretty | grep -E 'virtio-(net|serial|balloon)'
ls -l /dev/vport* /dev/virtio-ports/*
```

`/dev/vport1p1` proves that the virtio-console driver is active. The named
`/dev/virtio-ports/org.qemu.guest_agent.0` symlink additionally depends on guest
udev processing and may be absent even when the kernel driver works.

Since v0.3.24, generated systemd guests use one replacement unit named
`qemu-guest-agent.service`. It waits for `/dev/vport1p1` and starts the packaged
agent directly, avoiding both the missing-symlink failure and the older
competing-agent restart loop. Diagnose existing guests with:

```bash
systemctl status qemu-guest-agent.service microvm-agent.service --no-pager
ps -ef | grep '[q]emu-ga'
ls -l /dev/vport* /dev/virtio-ports/*
```

There must be exactly one `qemu-ga` process. See `docs/known-issues.md` for the
existing-guest replacement unit and EL binary-path note.

The release workflow prints the final values of `CONFIG_VIRTIO_NET`,
`CONFIG_VIRTIO_CONSOLE`, and `CONFIG_VIRTIO_BALLOON` after `olddefconfig`; all
must be `=y`. The overlay is in `kernel/pve-microvm-overlay.config`.

## Full clone from a running microVM fails in the version check

Versions through 0.3.28 could pass the unversioned `microvm` machine string into
PVE's block-job machine-version check before mirroring started. Depending on
PVE version the task can report `unable to parse ... machine version` or
`cannot check version of invalid string '10'`. The source guest can keep running
while the failed clone is cleaned up.

Upgrade to 0.3.29 or later. Its `BlockJob.pm` guard selects the existing drive
mirror for exact `microvm`, matching the command builder's `-drive` devices.
Versioned conventional machines retain their previous selection. Collect the
clone task log and package versions if failure recurs; do not treat every disk
copy error as this version-parser bug.
