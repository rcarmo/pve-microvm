# Architecture

## How it works

pve-microvm patches two files in `qemu-server` and adds one new Perl module:

```
qm create 900 --machine microvm ...
         │
         ▼
PVE::QemuServer::Machine (Machine.pm)
  ─ regex now accepts 'microvm'
  ─ machine_base_type() returns 'microvm'
  ─ get_vm_machine() returns 'microvm' without +pve0
         │
         ▼
PVE::QemuServer (QemuServer.pm)
  ─ config_to_command() detects microvm
  ─ delegates to MicroVM module
         │
         ▼
PVE::QemuServer::MicroVM (MicroVM.pm)  ← NEW
  ─ validates config (rejects unsupported options)
  ─ generates stripped-down QEMU command line
         │
         ▼
/usr/bin/qemu-system-x86_64 -M microvm ...
```

## Files modified

| File | Change |
|---|---|
| `Machine.pm` | Regex + `machine_base_type()` + `get_vm_machine()` + flags |
| `QemuServer.pm` | `use` statement + delegation in `config_to_command()` |
| `MicroVM.pm` | New file (installed, not patched) |

## QEMU command line

Generated for a typical microvm guest:

```bash
qemu-system-x86_64 \
  -M microvm,x-option-roms=off,pit=off,pic=off,isa-serial=on,rtc=on \
  -enable-kvm -cpu host -m 256M \
  -nodefaults -no-user-config -nographic \
  -device virtio-balloon-device,id=balloon0 \
  -device virtio-blk-device,drive=drive-scsi0 \
  -device virtio-net-device,netdev=netdev0,mac=BC:24:11:... \
  -serial chardev:serial0 \
  -kernel /usr/share/pve-microvm/vmlinuz \
  -append "console=ttyS0 root=/dev/vda rw quiet"
```

## Comparison with standard VMs

| Feature | Standard VM | microvm |
|---|---|---|
| Machine | `pc-i440fx-*` or `pc-q35-*` | `microvm` |
| Boot | SeaBIOS/OVMF from disk | `-kernel` direct |
| Block devices | `virtio-blk-pci` | `virtio-blk-device` (mmio) |
| Network | `virtio-net-pci` | `virtio-net-device` (mmio) |
| Display | VNC | serial only |
| ACPI | yes | no |
| USB | yes | no |
| PCI | full topology | none |
| Balloon | `virtio-balloon-pci` | `virtio-balloon-device` (mmio) |
| Guest agent | `virtio-serial` (PCI) | `virtio-serial-device` (mmio) |

## Storage support

All PVE storage backends work:

| Storage | Path QEMU sees | Format |
|---|---|---|
| LVM | `/dev/<vg>/vm-<vmid>-disk-0` | raw |
| LVM-thin | `/dev/<vg>/vm-<vmid>-disk-0` | raw |
| ZFS | `/dev/zvol/<pool>/vm-<vmid>-disk-0` | raw |
| Ceph/RBD | `rbd:<pool>/vm-<vmid>-disk-0` | rbd |
| NFS/CIFS | `/mnt/pve/<store>/images/<vmid>/...` | qcow2/raw |
| Local dir | `/var/lib/vz/images/<vmid>/...` | qcow2/raw |

## Patch management

```bash
/usr/share/pve-microvm/pve-microvm-patch status   # check
/usr/share/pve-microvm/pve-microvm-patch apply     # apply (done on install)
/usr/share/pve-microvm/pve-microvm-patch revert    # revert (done on removal)
```

- Originals backed up to `/usr/share/pve-microvm/backup/`
- Idempotent — safe to run multiple times
- After `qemu-server` upgrades: re-run `revert` then `apply`
