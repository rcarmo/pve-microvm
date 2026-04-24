# Architecture

## How it works

```
qm create 900 --machine microvm ...
         │
         ▼
PVE::QemuServer::Machine (Machine.pm) [PATCHED]
  ─ regex accepts 'microvm'
  ─ machine_base_type() → 'microvm'
  ─ get_vm_machine() → 'microvm' (no +pve0 suffix)
         │
         ▼
PVE::QemuServer (QemuServer.pm) [PATCHED]
  ─ config_to_command() detects microvm
  ─ delegates to MicroVM module
         │
         ▼
PVE::QemuServer::MicroVM (MicroVM.pm) [NEW]
  ─ validates config
  ─ generates QEMU command with PCIe devices
         │
         ▼
/usr/bin/qemu-system-x86_64
  -M microvm,...,pcie=on,acpi=on
  -kernel vmlinuz -initrd initrd
  -device virtio-blk-pci-non-transitional
  -device virtio-net-pci-non-transitional
  -device virtio-serial-pci-non-transitional
  -device virtio-balloon-pci-non-transitional
  -device vhost-vsock-pci-non-transitional
```

## Boot flow

1. QEMU loads kernel + initrd directly (no BIOS/UEFI)
2. Initrd `/init` loads virtio modules (blk, net, console, balloon)
3. Initrd mounts devtmpfs in new root, mounts `/dev/vda`
4. `switch_root` to real rootfs, systemd takes over
5. systemd-networkd brings up eth0 (DHCP via cloud-init)
6. Guest agent starts on `/dev/vport1p1`
7. Serial console via custom `microvm-console.service`

## Device transport

microvm with `pcie=on` uses PCI non-transitional devices:

| Device | QEMU type | Guest sees |
|---|---|---|
| Block | `virtio-blk-pci-non-transitional` | `/dev/vda` |
| Network | `virtio-net-pci-non-transitional` | `eth0` |
| Serial/Agent | `virtio-serial-pci-non-transitional` | `/dev/vport1p1` |
| Balloon | `virtio-balloon-pci-non-transitional` | memory reporting |
| vsock | `vhost-vsock-pci-non-transitional` | `/dev/vsock` (CID=VMID+1000) |
| virtiofs | `vhost-user-fs-pci` | `mount -t virtiofs shared /mnt` |
| Console | ISA serial (`isa-serial=on`) | `/dev/ttyS0` |

## Storage support

All PVE storage backends work:

| Storage | Path QEMU sees | Format |
|---|---|---|
| LVM / LVM-thin | `/dev/<vg>/vm-<vmid>-disk-0` | raw |
| ZFS | `/dev/zvol/<pool>/vm-<vmid>-disk-0` | raw |
| Ceph/RBD | `rbd:<pool>/vm-<vmid>-disk-0` | rbd |
| NFS/CIFS | `/mnt/pve/<store>/images/<vmid>/...` | qcow2/raw |
| Local dir | `/var/lib/vz/images/<vmid>/...` | qcow2/raw |

## Patch management

```bash
pve-microvm-patch status   # check
pve-microvm-patch apply    # apply (done on install)
pve-microvm-patch revert   # revert (done on removal)
```

- Originals backed up to `/usr/share/pve-microvm/backup/`
- dpkg trigger auto-reapplies after `qemu-server` upgrades

## Web UI integration

The `pve-microvm.js` extension (injected into `index.html.tpl`):

- Adds `microvm` to the machine type dropdown
- Hides unsupported fields in create wizard and hardware view
- Filters USB/PCI/BIOS/EFI/TPM rows from hardware panel
- Disables unsupported "Add hardware" menu items
- Shows ⚡ bolt icon for microvm-tagged VMs
- Adds "⚡ Clone microvm" context menu on templates

## Test infrastructure

| Node | CPU | RAM | Role |
|---|---|---|---|
| **z83ii** | Intel Atom x5-Z8350, 4 cores @ 1.44 GHz | 2 GB | Stability testing on worst-case hardware |
| **borg** | Intel Core i7-12700, 20 cores @ 4.9 GHz | 128 GB | Performance reference and multi-node testing |

Both nodes run PVE 9.1.7–9.1.9 with QEMU 10.1.2 and kernel 6.17.13-2-pve.
The z83ii is deliberately used as the primary test node — if microvms
work well on a 2 GB Atom, they'll work anywhere.
