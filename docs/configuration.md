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
| `args` | **Required** — must include `-kernel` |
| `kvm` | Hardware virtualization (default: on) |
| `agent` | Guest agent |
| `serial0` | Set to `socket` for `qm terminal` |
| `vga` | Set to `serial0` for PVE web console |
| `net0`–`net5` | virtio only; bridge, MAC, VLAN |
| `scsi0`–`scsi30` | Block devices (virtio-blk-device on mmio) |
| `affinity` | CPU pinning |
| `onboot` | Start on host boot |
| `tags` | Metadata tags |
| `protection` | Prevent accidental removal |

## Unsupported options

| Option | Reason |
|---|---|
| `bios` | No BIOS/UEFI — direct kernel boot |
| `efidisk0` | No UEFI |
| `tablet` | No USB bus |
| `audio0` | No audio hardware |
| `usb0`–`usb9` | No USB bus |
| `hostpci0`–`hostpci3` | No PCI bus |
| `tpmstate0` | No TPM |
| `rng0` | No PCI for virtio-rng-pci |
| `parallel0`–`parallel2` | No ISA parallel port |

`vmgenid` and `smbios1` are auto-set by `qm create` but silently ignored.

## Example config

`/etc/pve/qemu-server/900.conf`:

```ini
machine: microvm
name: my-sandbox
memory: 256
cores: 2
kvm: 1
serial0: socket
vga: serial0
net0: virtio=BC:24:11:00:00:01,bridge=vmbr0
scsi0: local-lvm:vm-900-disk-0,size=2G
tags: microvm
args: -kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw quiet"
```
