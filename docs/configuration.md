# Configuration Reference

## Supported options

| Option | Notes |
|---|---|
| `machine` | Must be `microvm` |
| `memory` | Static allocation (MiB) |
| `cores` | vCPUs per socket |
| `sockets` | CPU sockets |
| `cpu` | CPU model (default: `host`) |
| `name` | Guest name |
| `args` | **Required** — must include `-kernel` and `-initrd` |
| `kvm` | Hardware virtualization (default: on) |
| `agent` | Guest agent (recommended) |
| `serial0` | Set to `socket` for `qm terminal` |
| `vga` | Set to `serial0` for PVE web console |
| `net0`–`net5` | virtio only; bridge, MAC, VLAN |
| `scsi0`–`scsi30` | Block devices (virtio-blk-pci on PCIe) |
| `affinity` | CPU pinning |
| `onboot` | Start on host boot |
| `tags` | Metadata (use `microvm` for ⚡ icon) |
| `protection` | Prevent accidental removal |
| `ciuser` | Cloud-init user |
| `cipassword` | Cloud-init password |
| `ipconfig0` | Cloud-init network (e.g. `ip=dhcp`) |
| `sshkeys` | Cloud-init SSH public keys |

## Unsupported options

| Option | Reason |
|---|---|
| `bios` | No BIOS/UEFI — direct kernel boot |
| `efidisk0` | No UEFI |
| `tablet` | No USB bus |
| `audio0` | No audio hardware |
| `usb0`–`usb9` | No USB bus |
| `hostpci0`–`hostpci3` | No PCI passthrough (PCIe is used internally) |
| `tpmstate0` | No TPM |
| `rng0` | Use virtio-rng instead |
| `parallel0`–`parallel2` | No ISA parallel port |

`vmgenid` and `smbios1` are auto-set by `qm create` but silently ignored.

These options are **automatically hidden** in the PVE web UI when
`machine: microvm` is selected.

## Example config

`/etc/pve/qemu-server/900.conf`:

```ini
agent: 1
args: -kernel /usr/share/pve-microvm/vmlinuz -initrd /usr/share/pve-microvm/initrd -append "console=ttyS0 root=/dev/vda rw quiet"
ciuser: root
cores: 2
ipconfig0: ip=dhcp
machine: microvm
memory: 512
name: my-sandbox
net0: virtio=BC:24:11:00:00:01,bridge=vmbr0
scsi0: local-lvm:vm-900-disk-0,size=2G
scsi1: local-lvm:vm-900-cloudinit,media=cdrom
serial0: socket
tags: microvm
vga: serial0
```

## Automatic features

When `machine: microvm` is detected, `MicroVM.pm` automatically:

- Uses PCIe with `pcie=on` and non-transitional virtio devices
- Adds `virtio-balloon-pci-non-transitional` for memory reporting
- Adds `vhost-vsock-pci-non-transitional` with CID = VMID + 1000 (if `/dev/vhost-vsock` exists)
- Adds virtiofs device (if `pve-microvm-share` started a virtiofsd for this VM)
- Adds 9p share devices (if `pve-microvm-9p` configured shares for this VM)
- Injects `-initrd` automatically when using the shipped kernel
- Strips `vmgenid` and `smbios1` from config
- Sets `serial0: socket` if not already set
