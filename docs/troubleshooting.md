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

## Patches not applied after qemu-server upgrade

```bash
/usr/share/pve-microvm/pve-microvm-patch revert
/usr/share/pve-microvm/pve-microvm-patch apply
```

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

## No network / no guest agent / no balloon

If `virtio_net`, `virtio_console`, or `virtio_balloon` aren't probing,
the kernel may have been built without these drivers. Check:

```bash
strings /usr/share/pve-microvm/vmlinuz | grep -c virtio_net
# Should be > 0
```

If zero, rebuild the kernel — the PVE overlay in
`kernel/pve-microvm-overlay.config` forces these to `=y`.
